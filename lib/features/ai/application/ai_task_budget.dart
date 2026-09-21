// AI 任务的预算、在途并发与等待调度（T029；SET-035/036/059/062/063、架构 4.5）。
//
// 为什么把预算做成一个显式对象而不是在队列里散着读设置：
//   1) 「到总时限或预算即结束」是**总资源边界**（架构 4.5），它必须能在一次任务开始时
//      被冻结并整体检查——散读会让「总量控制」变成若干处各自判断，漏一处就变成
//      只靠时间兜底（架构明确说「仅靠时间不能控制费用」）；
//   2) 测试要能用**假时钟**逐条验证「先到者终止」，因此预算必须是纯数据，不含 IO；
//   3) 三个上限（时间/次数/Token）的语义各自独立，合成一个对象后调用点无法「只看
//      Token 不看次数」。
//
// 刻意**不做**的事：不实现 2/4/8/16 秒的多次退避风暴（架构 4.5 的退避属将来的重试
// 策略）。T029 只做「429 服从 Retry-After 一次」，第二次 429 就算一次无响应——
// 这既满足「不重复无限收费」，也不引入一个会在真实网络里连打四次的循环。
library;

import 'dart:async';
import 'dart:collection';

import 'package:flux/core/core.dart';

import 'model_manager.dart' show SettingsReader;

/// 一次 AI 任务的资源预算（SET-035/036/059/062/063）。
final class AiTaskBudget {
  /// 构造预算。
  const AiTaskBudget({
    this.totalLimit = const Duration(minutes: 10),
    this.maxHttpAttempts = 30,
    this.tokenBudget = 100000,
    this.concurrency = 2,
    this.attemptHardLimit = const Duration(seconds: 120),
    this.failoverEnabled = true,
  });

  /// 每任务总时限（SET-059：默认 10 分钟；含排队、抓取、模型尝试与保存前校验）。
  final Duration totalLimit;

  /// 模型 HTTP 尝试总次数（SET-062 的 httpAttempts：默认 30，含重试）。
  final int maxHttpAttempts;

  /// 每任务累计输入 + 输出 Token 预算（SET-063：默认 100000 估算上限）。
  final int tokenBudget;

  /// 同任务内最多在途请求数（SET-036 的 concurrency：默认 2）。
  ///
  /// 注意故障转移本身是**串行**的（架构 4.5「先取消上一尝试再重试」）：这个上限约束的是
  /// 「一个任务里允许多少个请求同时在途」（将来 T035/T037 的分段并发），它不把跨模型
  /// 故障转移变成并行竞速——并行会同时计费多次，且「先到者胜」会让选中的模型不确定。
  final int concurrency;

  /// 单次调用的硬时限（架构 4.5：默认 120 秒）。
  ///
  /// 首响应 45s / 停滞 30s 由适配器的流守卫承担（它按「每次有字节到达就重置」计时，
  /// 长输出不会被误杀）；本值是**一次调用不设上限**时的兜底，因此必须由队列层用真实
  /// 计时器实现——流卡住时不会有任何事件到达，只靠假时钟无法打断在途请求。
  final Duration attemptHardLimit;

  /// 是否允许跨模型故障转移（SET-035 的 enabled）。
  ///
  /// 关闭时「五次无响应」只终止任务，不切下一个模型：这一项是用户对「把同一份内容
  /// 发给我们之外的另一个服务商」的明确授权（架构 4.5 的候选来自「用户启用且已告知
  /// 数据去向的排序列表」）。
  final bool failoverEnabled;

  /// 任务总时限耗尽时的 limitKind（用于把「任务超时」与「单次调用超时」区分开）。
  static const String taskDeadlineLimitKind = 'taskTotal';

  /// 单次调用硬时限的 limitKind。
  static const String attemptHardLimitKind = 'aiAttemptHardLimit';

  /// 从设置读取预算；读取失败或结构不符的项回退到注册表默认值。
  ///
  /// 为什么回退默认值而不是让任务失败：预算是**总资源边界**，读不到就按保守默认值
  /// （10 分钟 / 30 次 / 100000 Token / 并发 2）继续，比「因为一次设置读失败就不做任何事」
  /// 更符合用户预期；同时默认值是保守的（不会因为回退而放大消耗）。
  static Future<AiTaskBudget> fromSettingsReader(SettingsReader? reader) async {
    if (reader == null) {
      return const AiTaskBudget();
    }
    final int totalMinutes = await _intSetting(reader, SettingId.set059, null);
    final int httpAttempts = await _intSetting(
      reader,
      SettingId.set062,
      'httpAttempts',
    );
    final int tokens = await _intSetting(reader, SettingId.set063, null);
    final int concurrency = await _intSetting(
      reader,
      SettingId.set036,
      'concurrency',
    );
    final bool failover = await _boolSetting(
      reader,
      SettingId.set035,
      'enabled',
    );
    // 三个上限必须为正：0 或负数会让任务一开始就无法做任何事（次数 0）或
    // 立刻超预算（Token 0）。夹到「至少 1」，注册表的上限语义仍由设置校验保证。
    return AiTaskBudget(
      totalLimit: Duration(minutes: totalMinutes < 1 ? 1 : totalMinutes),
      maxHttpAttempts: httpAttempts < 1 ? 1 : httpAttempts,
      tokenBudget: tokens < 1 ? 1 : tokens,
      concurrency: concurrency < 1 ? 1 : concurrency,
      failoverEnabled: failover,
    );
  }

  /// 读一个整数设置项；[component] 非空表示读复合结构里的某个字段。
  static Future<int> _intSetting(
    SettingsReader reader,
    SettingId id,
    String? component,
  ) async {
    final Object? fallback = _registryDefault(id, component);
    final Result<Object?> read = await reader.readSetting(id);
    final Object? raw = read.isOk ? read.valueOrNull : null;
    final Object? value = component == null ? raw : _component(raw, component);
    if (value is int) {
      return value;
    }
    return fallback is int ? fallback : 0;
  }

  /// 读一个布尔设置项；语义同 [_intSetting]。
  static Future<bool> _boolSetting(
    SettingsReader reader,
    SettingId id,
    String component,
  ) async {
    final Result<Object?> read = await reader.readSetting(id);
    final Object? raw = read.isOk ? read.valueOrNull : null;
    final Object? value = _component(raw, component);
    if (value is bool) {
      return value;
    }
    final Object? fallback = _registryDefault(id, component);
    return fallback is bool ? fallback : true;
  }

  /// 取复合设置里的一个字段（结构不符时返回 null）。
  static Object? _component(Object? raw, String field) {
    if (raw is! Map<Object?, Object?>) {
      return null;
    }
    return raw[field];
  }

  /// 注册表默认值（找不到定义时返回 null）。
  static Object? _registryDefault(SettingId id, String? component) {
    final SettingDefinition? definition = SettingRegistry.findById(id);
    if (definition == null) {
      return null;
    }
    final Object? value = definition.defaultValue;
    return component == null ? value : _component(value, component);
  }
}

/// 在途请求上限（SET-036 的并发）。
///
/// 一次任务里所有发出去的请求都必须先 acquire，结束（成功、失败、超时、取消）都必须
/// release。把它做成显式对象而不是「一个整数计数器 + 调用点自觉」，是因为漏掉释放
/// 会表现为「任务偶尔卡死不返回」，那类缺陷在代码审查里几乎看不见。
final class AiInFlightLimiter {
  /// 以最大在途数构造。
  AiInFlightLimiter(this.maxConcurrent) {
    if (maxConcurrent < 1) {
      throw ArgumentError.value(maxConcurrent, 'maxConcurrent', '必须至少为 1');
    }
  }

  /// 最大在途数。
  final int maxConcurrent;

  int _inFlight = 0;
  int _peak = 0;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  /// 当前在途数。
  int get inFlight => _inFlight;

  /// 曾经达到的最大在途数（用于断言「确实没超过上限」）。
  int get peak => _peak;

  /// 等待中的请求数（超出上限、尚未拿到额度的那些）。
  int get waiting => _waiters.length;

  /// 申请一个在途额度；超出上限时挂起直到有人释放。
  Future<void> acquire() {
    if (_inFlight < maxConcurrent) {
      _inFlight++;
      if (_inFlight > _peak) {
        _peak = _inFlight;
      }
      return Future<void>.value();
    }
    final Completer<void> waiter = Completer<void>();
    _waiters.add(waiter);
    return waiter.future;
  }

  /// 释放一个在途额度并把额度交给最早等待者（若有）。
  void release() {
    if (_inFlight == 0) {
      // 多释放是编程错误：静默忽略会让上限被悄悄放大（额度凭空变多）。
      throw StateError('AiInFlightLimiter.release 调用次数多于 acquire');
    }
    if (_waiters.isEmpty) {
      _inFlight--;
      return;
    }
    // 直接把额度转交：不先减再加，否则等待者被唤醒前会短暂出现「额度空闲」，
    // 又一个 acquire 插队进来就会突破上限。
    _waiters.removeFirst().complete();
  }
}

/// 等待调度（退避与 Retry-After 的等待入口）。
///
/// 为什么把「等待」也做成端口：等待会真实消耗总时限，因此测试必须能确定性地
/// 「让时间过去」而不是真的睡 2 秒；生产实现用真实计时器，两者语义一致
/// （都只是「让这段时间过去」）。
abstract interface class AiDelayScheduler {
  /// 等待 [duration]。
  Future<void> delay(Duration duration);
}

/// 真实等待实现。
final class RealAiDelayScheduler implements AiDelayScheduler {
  /// 构造真实等待实现。
  const RealAiDelayScheduler();

  @override
  Future<void> delay(Duration duration) => duration <= Duration.zero
      ? Future<void>.value()
      : Future<void>.delayed(duration);
}
