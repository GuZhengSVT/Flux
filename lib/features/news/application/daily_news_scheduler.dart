// 默认开启的每日定时总结（T040；架构 4.4「定时默认每天设备当地时间 20:00、启用开关默认开；
// 后台尽力执行，不要求系统精确定时；错过计划后在下一次可运行时仅补当日一次；当天成功版本
// 存在则不重复自动收费」、D-08、SET-056/057、手册 6.3「定时」节）。
//
// 时间规则本身在 core/domain/news_schedule.dart 的纯函数里（到点/错过/跨日/换时区都能用假时钟
// 逐条断言）。本文件负责**把规则接到真实世界**：读设置、判断配置是否齐备、按分钟检查、跑一次
// 任务、并把「等待配置」这个不动网络的状态如实暴露给界面。
//
// 四条刻意的设计：
//
//   1) **等待配置是不发请求的状态，不是一次失败的运行**（D-08）。判定顺序是「总开关 → 配置
//      齐备 → 今日已成功 → 是否到点」：未配置时连到没到点都不看，因此界面从早到晚都显示
//      「等待配置」，而不是 20:00 之前显示「按计划运行」、到点那一刻才变成缺配置。
//   2) **补跑只补当天一次，跨日不补**。这不是一条额外的判断：昨天错过的机会随着日期键翻页就
//      消失了，今天的判定只看「今天是否已成功 + 今天是否已过点」。因此关掉应用三天后再打开，
//      只会补今天这一次，不会连补三次并连收三次费用。
//   3) **绝不自动重放被终止的任务**。启动时把上次留下的 `running` 行标成 `interrupted`（沿用
//      T030 的口径），补跑走的是**新任务与新版本号**——把一条不确定是否计费的旧任务重发一次，
//      代价是用户为同一份内容付两次费。macOS 没有后台执行的保证，这里的取舍写在文档里，
//      不伪称「后台一定能跑完」。
//   4) **并发闸门只有一个**：应用启动检查与每分钟检查都经过 [runIfDue]，而它在运行期间直接
//      返回 null。两处各判一次「有没有在跑」会让同一分钟内两次触发同时进入（定时器与用户手动
//      重新生成也会互相覆盖版本号）。
library;

import 'dart:async';

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/domain/ai_message.dart';

import 'news_run_service.dart';

/// 一次定时运行的触发来源（诊断与界面提示的区分）。
enum DailyNewsTrigger {
  /// 应用启动时的检查（含「补跑当天错过的时点」）。
  launch,

  /// 运行期间每分钟的到点检查。
  scheduled;

  /// 诊断标签。
  String get tag => switch (this) {
    DailyNewsTrigger.launch => 'news.daily.launch',
    DailyNewsTrigger.scheduled => 'news.daily.scheduled',
  };
}

/// 配置齐备性的结论（决定是否进入 `waitingConfiguration`）。
final class DailyNewsReadiness {
  /// 构造结论。
  const DailyNewsReadiness({required this.ready, this.reason});

  /// 齐备时用这个常量。
  static const DailyNewsReadiness ok = DailyNewsReadiness(ready: true);

  /// 是否齐备。
  final bool ready;

  /// 缺失的原因（结构标识：`noModel` / `noModelCredential` / `noSearch` / `costNotice`）。
  final String? reason;

  @override
  String toString() => 'DailyNewsReadiness(ready=$ready, reason=$reason)';
}

/// 定时状态的界面快照（设置页与今日页都读它，不在别处重算时间）。
final class DailyNewsStatus {
  /// 构造状态。
  const DailyNewsStatus({
    required this.kind,
    required this.enabled,
    required this.timeOfDay,
    required this.timeZone,
    required this.localDate,
    this.nextRunUtc,
    this.scheduledAtUtc,
    this.waitingReason,
    this.completedLocalDate,
    this.running = false,
    this.lastAttemptUtc,
    this.lastCatchUp = false,
    this.lastErrorKind,
  });

  /// 结论（到点/等待配置/已成功/未到点/关闭）。
  final DailyNewsDueKind kind;

  /// SET-056 的开关。
  final bool enabled;

  /// SET-057 的执行时间（`HH:mm`）。
  final String timeOfDay;

  /// 评估时的设备时区。
  final String timeZone;

  /// 评估时的本地日期键。
  final String localDate;

  /// 下一次应当运行的时刻（UTC）。
  final DateTime? nextRunUtc;

  /// 今天的计划时刻（UTC）。
  final DateTime? scheduledAtUtc;

  /// 等待配置的原因（结构标识）。
  final String? waitingReason;

  /// 今天已有成功版本的日期键（等于 [localDate] 时界面说「今日已完成」）。
  final String? completedLocalDate;

  /// 是否正在运行。
  final bool running;

  /// 最近一次尝试的时刻（UTC）。
  final DateTime? lastAttemptUtc;

  /// 最近一次运行是否为补跑。
  final bool lastCatchUp;

  /// 最近一次运行的失败类别（结构标识）。
  final String? lastErrorKind;

  /// 今天是否已经生成成功。
  bool get completedToday =>
      completedLocalDate != null && completedLocalDate == localDate;

  /// 复制并覆盖部分字段。
  DailyNewsStatus copyWith({
    DailyNewsDueKind? kind,
    bool? enabled,
    String? timeOfDay,
    String? timeZone,
    String? localDate,
    DateTime? nextRunUtc,
    DateTime? scheduledAtUtc,
    String? waitingReason,
    bool clearWaitingReason = false,
    String? completedLocalDate,
    bool clearCompleted = false,
    bool? running,
    DateTime? lastAttemptUtc,
    bool? lastCatchUp,
    String? lastErrorKind,
    bool clearLastError = false,
  }) => DailyNewsStatus(
    kind: kind ?? this.kind,
    enabled: enabled ?? this.enabled,
    timeOfDay: timeOfDay ?? this.timeOfDay,
    timeZone: timeZone ?? this.timeZone,
    localDate: localDate ?? this.localDate,
    nextRunUtc: nextRunUtc ?? this.nextRunUtc,
    scheduledAtUtc: scheduledAtUtc ?? this.scheduledAtUtc,
    waitingReason: clearWaitingReason
        ? null
        : (waitingReason ?? this.waitingReason),
    completedLocalDate: clearCompleted
        ? null
        : (completedLocalDate ?? this.completedLocalDate),
    running: running ?? this.running,
    lastAttemptUtc: lastAttemptUtc ?? this.lastAttemptUtc,
    lastCatchUp: lastCatchUp ?? this.lastCatchUp,
    lastErrorKind: clearLastError
        ? null
        : (lastErrorKind ?? this.lastErrorKind),
  );
}

/// 一次定时运行的产出（界面提示与诊断用）。
final class DailyNewsRunReport {
  /// 构造产出。
  const DailyNewsRunReport({
    required this.trigger,
    required this.localDate,
    required this.catchUp,
    required this.outcome,
  });

  /// 触发来源。
  final DailyNewsTrigger trigger;

  /// 运行归属的本地日期。
  final String localDate;

  /// 是否为补跑。
  final bool catchUp;

  /// 编排层的产出（状态、版本、错误都在里面）。
  final NewsRunOutcome outcome;
}

/// 一次定时运行需要的东西（由组合根提供；全部是**纯数据之外的窄能力**）。
///
/// 与 daily_news_run.dart 的 [DailyNewsRunner]（带占位行的执行器）不是同一件事：这个是
/// 「怎么跑一次」的函数形状，调度器只认它，因此时间规则可以用最简的替身验证。
typedef DailyNewsRunAction = Future<NewsRunOutcome> Function({
  required String localDate,
  required SessionLocalZone zone,
  required AiCancellation cancellation,
});

/// 默认开启的每日定时总结调度器。
///
/// 生命周期由持有者管理（界面宿主或测试各自负责 [dispose]）。本类不读 Riverpod、不建
/// HTTP 客户端：策略、齐备性与「跑一次」都由调用方注入，因此「到点触发 / 错过补跑一次 /
/// 次日不补 / 今日已成功不重复 / 等待配置零请求」这些验收项都可以用假时钟逐条断言。
final class DailyNewsScheduler {
  /// 构造调度器。
  DailyNewsScheduler({
    required this.readPolicy,
    required this.readReadiness,
    required this.successDateLoader,
    required this.runNews,
    required this.markInterruptedOnStartup,
    this.clock = const SystemClock(),
    this.diagnostics = const NoopDiagnosticSink(),
    this.onStatus,
    this.checkInterval = const Duration(minutes: 1),
  });

  /// 读策略（SET-056/057 + 当前设备时区）。
  final Future<Result<DailyNewsPolicy>> Function() readPolicy;

  /// 读配置齐备性（模型、凭据、搜索、费用告知）。
  ///
  /// **只在需要时调用**：它要读模型列表、凭据与搜索服务（各一次往返），而每次评估都读一遍
  /// 会把一分钟一次的检查变成一分钟三次数据库往返。
  final Future<DailyNewsReadiness> Function() readReadiness;

  /// 读某一天某时区**最近一次成功版本**的日期键（没有成功版本时返回 null）。
  final Future<String?> Function({
    required String localDate,
    required String timeZone,
  })
  successDateLoader;

  /// 跑一次任务。
  final DailyNewsRunAction runNews;

  /// 启动时把上次留下的 `running` 标成 `interrupted`（返回被标记的条数）。
  final Future<Result<int>> Function() markInterruptedOnStartup;

  /// 时钟（测试注入假时钟）。
  final Clock clock;

  /// 诊断记录。
  final DiagnosticSink diagnostics;

  /// 状态变更回调（界面据此刷新）。
  final void Function(DailyNewsStatus status)? onStatus;

  /// 检查周期（默认每分钟，架构 4.4「运行中每分钟检查到点」）。
  final Duration checkInterval;

  Timer? _timer;
  bool _running = false;
  bool _disposed = false;
  DateTime? _lastAttemptUtc;
  bool _lastCatchUp = false;
  String? _lastErrorKind;
  DailyNewsStatus? _status;
  bool _startupChecked = false;

  /// 最近一次评估的状态（界面读它；未评估过时为 null）。
  DailyNewsStatus? get status => _status;

  /// 是否有一次运行在进行中。
  bool get isRunning => _running;

  /// 应用启动时检查一次：标中断（不重放）+ 到点则（补）跑今天这一次。
  ///
  /// 「标中断」与「补跑」是两件事，因此顺序固定：先标中断（把上次的遗留状态说清楚），再看
  /// 今天是否到点。反过来会让一次补跑与一条旧的中断记录在同一时刻产生，界面上分不清哪个
  /// 是刚发生的。
  Future<void> onLaunch() async {
    if (_disposed) {
      return;
    }
    if (!_startupChecked) {
      _startupChecked = true;
      final Result<int> marked = await markInterruptedOnStartup();
      if (marked.isErr) {
        // 读不到不算致命：启动时的中断标记只影响历史记录的说清程度，不影响这次是否该跑。
        diagnostics.warning(
          '启动时标记未完成任务失败 kind=${marked.errorOrNull!.kind}',
          tag: 'news.daily.launch',
        );
      }
    }
    await runIfDue(trigger: DailyNewsTrigger.launch);
  }

  /// 启动每分钟的到点检查。
  ///
  /// 用「每分钟复查一次当前策略」而不是「按第一次读到的时间定一个一次性计时器」：用户改了
  /// 执行时间或换了时区之后，下一次检查就按新值算，不需要重启应用。
  void start() {
    if (_disposed || _timer != null) {
      return;
    }
    _timer = Timer.periodic(checkInterval, (Timer _) {
      unawaited(runIfDue(trigger: DailyNewsTrigger.scheduled));
    });
  }

  /// 停止检查。
  ///
  /// 刻意**不**取消正在进行的一次运行：取消一次可能已经发出并计费的请求，会让「这次到底
  /// 成没成」变得不确定（架构第 8 节不允许把不确定说成已取消）。正在跑的任务由进程终止
  /// 这一事实表达，下一次启动时被标成 `interrupted`。
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }

  /// 评估并按需运行一次。
  ///
  /// [force] 只在测试与「用户手动要求立刻检查」时使用：正常路径一律走策略判定。
  Future<DailyNewsRunReport?> runIfDue({
    required DailyNewsTrigger trigger,
    bool force = false,
  }) async {
    if (_disposed) {
      return null;
    }
    // 单一并发闸门：启动检查与每分钟检查走同一条路径，运行期间直接返回。
    if (_running) {
      diagnostics.info(
        '定时总结已有一次运行在进行中，忽略 ${trigger.name} 触发',
        tag: trigger.tag,
      );
      return null;
    }
    final Result<DailyNewsPolicy> policyResult = await readPolicy();
    if (policyResult.isErr) {
      diagnostics.warning(
        '读取定时策略失败 kind=${policyResult.errorOrNull!.kind}',
        tag: trigger.tag,
      );
      return null;
    }
    final DailyNewsPolicy policy = policyResult.valueOrNull!;
    final DateTime now = clock.now().toUtc();
    if (!policy.enabled) {
      _publishDue(
        _evaluate(
          policy: policy,
          nowUtc: now,
          readiness: const DailyNewsReadiness(ready: false, reason: 'disabled'),
          completedLocalDate: null,
        ),
      );
      return null;
    }
    // 齐备性只在**可能真的运行**时才读（到点或启动补跑），避免每分钟三次往返。
    final DailyNewsReadiness readiness = await readReadiness();
    final DailyNewsDue due = _evaluate(
      policy: policy,
      nowUtc: now,
      readiness: readiness,
      completedLocalDate: await successDateLoader(
        localDate: _localDateOf(policy, now),
        timeZone: policy.zone.ianaName,
      ),
    );
    _publishDue(due);
    if (!force && !due.kind.shouldRun) {
      if (due.kind == DailyNewsDueKind.waitingConfiguration) {
        // 诊断只记结构事实（原因类别与本地日期），不记配置内容。
        diagnostics.info(
          '定时总结等待配置 reason=${due.waitingReason ?? 'unknown'} '
          'date=${due.localDate}',
          tag: trigger.tag,
        );
      }
      return null;
    }
    return _run(
      trigger: trigger,
      policy: policy,
      localDate: due.localDate,
      catchUp: due.catchUp,
      due: due,
    );
  }

  /// 只评估并发布状态，**不运行**（设置页用它显示「下次什么时候跑 / 为什么还没跑」）。
  ///
  /// 为什么需要一条不跑的路径：设置页是**只读观察点**，用户打开设置不应该启动一次付费
  /// 运行。真正的运行由 [onLaunch] 与每分钟的检查负责——那两处是后台行为，与用户是否
  /// 正看着设置页无关。
  ///
  /// 它仍然会读齐备性（缺模型/缺 Key/未确认告知），但读到的只是原因，不会发出任何请求。
  Future<DailyNewsStatus?> refreshStatus() async {
    if (_disposed) {
      return null;
    }
    final Result<DailyNewsPolicy> policyResult = await readPolicy();
    if (policyResult.isErr) {
      return _status;
    }
    final DailyNewsPolicy policy = policyResult.valueOrNull!;
    final DateTime now = clock.now().toUtc();
    if (!policy.enabled) {
      _publishDue(
        _evaluate(
          policy: policy,
          nowUtc: now,
          readiness: const DailyNewsReadiness(ready: false, reason: 'disabled'),
          completedLocalDate: null,
        ),
      );
      return _status;
    }
    final DailyNewsReadiness readiness = await readReadiness();
    _publish(
      _statusFrom(
        _evaluate(
          policy: policy,
          nowUtc: now,
          readiness: readiness,
          completedLocalDate: await _trySuccessDate(policy),
        ),
      ),
    );
    return _status;
  }

  /// 执行一次任务。
  Future<DailyNewsRunReport?> _run({
    required DailyNewsTrigger trigger,
    required DailyNewsPolicy policy,
    required String localDate,
    required bool catchUp,
    DailyNewsDue? due,
  }) async {
    _running = true;
    _lastCatchUp = catchUp;
    _lastAttemptUtc = clock.now().toUtc();
    _lastErrorKind = null;
    _publish(
      _statusFrom(
        _evaluate(
          policy: policy,
          nowUtc: _lastAttemptUtc!,
          readiness: DailyNewsReadiness.ok,
          completedLocalDate: null,
        ),
      ).copyWith(running: true, clearLastError: true, lastCatchUp: catchUp),
    );
    diagnostics.info(
      '定时总结开始 trigger=${trigger.name} date=$localDate catchUp=$catchUp '
      'at=${policy.timeOfDayLabel} tz=${policy.zone.ianaName}',
      tag: trigger.tag,
    );
    final AiCancellation cancellation = AiCancellation();
    try {
      final NewsRunOutcome outcome = await runNews(
        localDate: localDate,
        zone: policy.zone,
        cancellation: cancellation,
      );
      _lastErrorKind = outcome.ok ? null : outcome.error?.kind;
      diagnostics.info(
        '定时总结结束 date=$localDate status=${outcome.status.name} '
        'items=${outcome.record?.items.length ?? 0}',
        tag: trigger.tag,
      );
      return DailyNewsRunReport(
        trigger: trigger,
        localDate: localDate,
        catchUp: catchUp,
        outcome: outcome,
      );
    } on Object catch (error) {
      // 调度器是长期存活对象：一次未预期异常不能让后续所有触发都不再执行。
      _lastErrorKind = 'schedulerException';
      diagnostics.error(
        '定时总结抛出未预期异常 type=${error.runtimeType}',
        tag: trigger.tag,
      );
      return null;
    } finally {
      _running = false;
      final DailyNewsPolicy? latestPolicy = await _tryReadPolicy();
      final DailyNewsPolicy effective = latestPolicy ?? policy;
      final String effectiveLocalDate = _localDateOf(
        effective,
        clock.now().toUtc(),
      );
      _publish(
        _statusFrom(
          _evaluate(
            policy: effective,
            nowUtc: clock.now().toUtc(),
            readiness: DailyNewsReadiness.ok,
            completedLocalDate: await _trySuccessDate(effective),
          ),
        ).copyWith(
          running: false,
          lastAttemptUtc: _lastAttemptUtc,
          lastCatchUp: _lastCatchUp,
          lastErrorKind: _lastErrorKind,
          localDate: effectiveLocalDate,
        ),
      );
    }
  }

  /// 评估一次（纯计算 + 一次成功日期读取的结果）。
  ///
  /// 顺带记住本次策略的时分：状态快照里的 `timeOfDay` 用它，因此界面显示的永远是**刚刚
  /// 评估过的那份策略**，而不是构造时或某次旧读取的值。
  DailyNewsDue _evaluate({
    required DailyNewsPolicy policy,
    required DateTime nowUtc,
    required DailyNewsReadiness readiness,
    required String? completedLocalDate,
  }) {
    _lastPolicyMinutes = policy.timeOfDayMinutes;
    return evaluateDailyNewsDue(
      nowUtc: nowUtc,
      policy: policy,
      ready: readiness.ready,
      waitingReason: readiness.reason,
      completedLocalDate: completedLocalDate,
      lastAttemptUtc: _lastAttemptUtc,
    );
  }

  /// 把一次评估结论变成界面状态。
  ///
  /// `timeOfDay` 取**刚刚评估过的那份策略**（`_lastPolicyMinutes` 在 [_evaluate] 里写入），
  /// 因此界面显示的永远是当前值，而不是构造时或某次旧读取的值。
  DailyNewsStatus _statusFrom(DailyNewsDue due) => DailyNewsStatus(
    kind: due.kind,
    // 关闭态由策略决定；「等待配置」不是关闭（保留默认开启的偏好，只是现在跑不了）。
    enabled: due.kind != DailyNewsDueKind.disabled,
    timeOfDay: formatTimeOfDay(_lastPolicyMinutes ?? 0),
    timeZone: due.timeZone,
    localDate: due.localDate,
    nextRunUtc: due.nextRunUtc,
    scheduledAtUtc: due.scheduledAtUtc,
    waitingReason: due.waitingReason,
    completedLocalDate: due.kind == DailyNewsDueKind.alreadyGeneratedToday
        ? due.localDate
        : null,
    running: _running,
    lastAttemptUtc: _lastAttemptUtc,
    lastCatchUp: _lastCatchUp,
    lastErrorKind: _lastErrorKind,
  );

  void _publish(DailyNewsStatus status) {
    _status = status;
    onStatus?.call(status);
  }

  void _publishDue(DailyNewsDue due) => _publish(_statusFrom(due));

  int? _lastPolicyMinutes;

  String _localDateOf(DailyNewsPolicy policy, DateTime nowUtc) =>
      localDateKey(policy.zone.toLocal(nowUtc));

  Future<DailyNewsPolicy?> _tryReadPolicy() async {
    final Result<DailyNewsPolicy> result = await readPolicy();
    if (result.isErr) {
      return null;
    }
    _lastPolicyMinutes = result.valueOrNull!.timeOfDayMinutes;
    return result.valueOrNull;
  }

  Future<String?> _trySuccessDate(DailyNewsPolicy policy) async {
    try {
      return await successDateLoader(
        localDate: _localDateOf(policy, clock.now().toUtc()),
        timeZone: policy.zone.ianaName,
      );
    } on Object {
      return null;
    }
  }
}

/// 定时总结的**费用告知**确认端口（架构 4.4「首次费用告知未确认时任务为 waitingConfiguration」）。
///
/// 为什么与「手动生成前的确认框」不是同一件事：手动生成时确认框就在眼前，用户点「确认生成」
/// 本身就是知情；定时任务没有任何对话框，因此它必须有一个**持久化**的确认记录，否则一次
/// 后台付费运行会在用户从没被告知的情况下发生。
///
/// 记录存在本机（`device.` 命名空间，与引导标记、视觉发送告知同一做法）：它是本机运行授权
/// 状态，不是可同步的偏好——同步到另一台设备就等于那台设备也自动开跑并付费。
abstract interface class NewsCostNoticeStore {
  /// 是否已确认过费用与数据发送告知。
  Future<bool> isAcknowledged();

  /// 记录一次确认（幂等）。
  Future<Result<void>> acknowledge();
}
