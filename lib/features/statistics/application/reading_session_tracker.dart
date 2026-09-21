// 阅读会话追踪（T023；架构 5.3 的统计口径与 SET-015）。
//
// 架构原文：「统计首发本机有效阅读时长：前台可见且活跃时累计，失焦/锁屏/后台暂停，
// 5 分钟无交互暂停；按会话时区跨午夜拆分。」
//
// 三条判定与它们各自解决的具体问题：
//
//   1) **「有效」= 前台可见 且 交互未超阈**。不是「页面开着就算」：把页面留在后台一个
//      下午会让统计变成「应用开启时长」。因此前台状态由页面显式告知，空闲由
//      lastActive + 阈值封顶；
//   2) **封顶是「最多算到 lastActive + 阈值」，不是「超时后清零」**。用户读了 4 分钟
//      放下不管，那 4 分钟是真实阅读，必须留在统计里；只有阈值之后的那段时间不算。
//      这一点由 [idleBoundedEnd] 保证，tracker 只是它的调用方；
//   3) **周期性 flush（默认 30 秒）+ 结束时收尾**。只在结束时写会在崩溃/强杀时丢掉
//      整次阅读；只靠周期写又会让「刚读完的这篇文章」在统计里迟到。两者都要，
//      且都是同一段逻辑（close → 拆日 → 落库），不写两遍。
//
// 不持有 Timer：定时由页面驱动（[tick]），因为「多久 tick 一次」是**界面生命周期**
// 的事（页面销毁时定时器必须一起走），而计时规则是这里的事。分开之后，计时规则可以
// 用假时钟确定性验证，不需要真的等 30 秒。
library;

import 'package:flux/core/core.dart';

import 'package:flux/features/settings/application/settings_store.dart';

/// 一条「这次阅读该记多少」的会话追踪器。
///
/// 生命周期：页面创建 → [start] → （交互 [onInteraction] / 前台变化
/// [onVisibilityChanged] / 周期 [tick]）→ [stop]。
///
/// 所有方法都是**幂等且可重复调用**的：界面事件（特别是生命周期回调）在不同平台上
/// 会重复投递，重入一次不该产生重复时间。
final class ReadingSessionTracker {
  /// 构造追踪器。
  ReadingSessionTracker({
    required this.articleId,
    required this.stats,
    required this.settings,
    required this.clock,
    required this.zone,
    this.flushInterval = const Duration(seconds: 30),
    this.diagnostics = const NoopDiagnosticSink(),
    this.idleThresholdOverride,
  });

  /// 被阅读的文章 id。
  final int articleId;

  /// 统计写入端口。
  final ReadingStatsStore stats;

  /// 设置读写端口（读 SET-015）。
  final SettingsStore settings;

  /// 时间来源（测试注入假时钟）。
  final Clock clock;

  /// 会话时区（统计归属依据）。
  final SessionLocalZone zone;

  /// 周期性落库间隔。
  final Duration flushInterval;

  /// 诊断记录。
  final DiagnosticSink diagnostics;

  /// 空闲阈值覆盖（测试用）；为空时读 SET-015 的取值。
  final Duration? idleThresholdOverride;

  /// SET-015 是否启用统计（[start] 时读取；读取失败按**默认值开**处理）。
  bool _enabled = false;

  /// 是否已经开始（未开始的实例不产生任何写入）。
  bool _started = false;

  /// 应用是否在前台且页面可见。
  bool _visible = false;

  /// 空闲阈值。
  Duration _idleThreshold = const Duration(minutes: 5);

  /// 最后一次交互（UTC）；null 表示本次会话还没有任何交互。
  DateTime? _lastActive;

  /// 当前正在累计的区间起点（UTC）；null 表示当前处于暂停态。
  DateTime? _openFrom;

  /// 已结束但尚未落库的区间。
  final List<ReadingInterval> _pending = <ReadingInterval>[];

  /// 上次落库时刻（UTC）。
  DateTime? _lastFlush;

  /// 是否正在记录（界面据此显示「正在记录阅读时间」）。
  bool get isRecording => _started && _enabled;

  /// 本次会话尚未落库的有效秒数（诊断/测试用）。
  int get pendingSeconds => _pending.fold<int>(
    0,
    (int sum, ReadingInterval interval) => sum + interval.duration.inSeconds,
  );

  /// 开始记录。
  ///
  /// 读 SET-015：关闭时**完全不记录**（不启动任何计时，也不在 stop 时写行）。
  /// 读失败时按注册表默认值（开）处理——统计是可选的辅助功能，一次设置读取失败不该
  /// 让阅读统计整段失效，但也不该把它当成「用户关了」。
  Future<void> start() async {
    if (_started) {
      return;
    }
    _idleThreshold = await _resolveIdleThreshold();
    _enabled = await _resolveEnabled();
    _started = true;
    if (!_enabled) {
      return;
    }
    final DateTime now = clock.now();
    _visible = true;
    // 打开详情页即开始累计：架构的「前台可见且活跃」里，「打开并看着」就是活跃的
    // 起点。若用户什么都不做，5 分钟后由封顶规则自动停住，不会多记。
    _lastActive = now;
    _openFrom = now;
    _lastFlush = now;
  }

  /// 记录一次用户交互（指针/键盘）。
  ///
  /// 交互同时做两件事：刷新「最后活跃」并**从暂停中恢复**（如果之前因空闲停住了）。
  /// 用同一个入口而不是两个方法：真实交互不可能只发生其中一件。
  void onInteraction() {
    if (!isRecording) {
      return;
    }
    final DateTime now = clock.now();
    // 先按**旧的** lastActive 收尾：若这次交互之前已经空闲超阈，那段空白必须被截掉，
    // 否则「离开一小时再回来动一下鼠标」会被算成连续阅读一小时。这一步让规则不依赖
    // tick 的频率（生产环境有秒级心跳，但这一层不该把正确性寄托在调用方的定时精度上）。
    _closeOpenIntervalIfIdleExpired(now);
    _lastActive = now;
    if (_visible && _openFrom == null) {
      _openFrom = now;
    }
  }

  /// 前台/可见性变化。
  ///
  /// [visible] 为 false 时（失焦、锁屏、后台）立即收尾当前区间：那些时间不是阅读
  /// 时间。重新可见时重新开一段，但**不**把离开的那段时间补回来。
  void onVisibilityChanged(bool visible) {
    if (!isRecording) {
      return;
    }
    final DateTime now = clock.now();
    if (!visible) {
      _closeOpenInterval(now);
      _visible = false;
      return;
    }
    _visible = true;
    // 重新可见**同时刷新活跃锚点**：用户刚把窗口切回来，这就是一次活跃（与「打开详情页」
    // 同理）。不刷新的话，离开前那个陈旧的 lastActive 会让新开的段立刻被判为空闲超阈，
    // 于是切回来后的这一分钟阅读被整段丢掉（tracker 用例抓到过）。
    _lastActive = now;
    _openFrom ??= now;
  }

  /// 周期性调用：到点就落库，并把已空闲超阈的区间收尾。
  ///
  /// 返回本次是否真的写入了行（测试与界面据此判断「有没有发生落库」）。
  Future<bool> tick() async {
    if (!isRecording) {
      return false;
    }
    final DateTime now = clock.now();
    // 空闲超阈：先把这一段收到「最后交互 + 阈值」，再决定要不要落库。
    // 收尾必须在 flush 之前：否则一次落库会把不该算的时间也算进去。
    _closeOpenIntervalIfIdleExpired(now);
    final DateTime? last = _lastFlush;
    if (last == null || now.difference(last) < flushInterval) {
      return false;
    }
    return flush();
  }

  /// 立即把已结束的区间落库（会重新开一段继续累计）。
  Future<bool> flush() async {
    if (!isRecording) {
      return false;
    }
    final DateTime now = clock.now();
    _closeOpenInterval(now);
    _lastFlush = now;
    final bool wrote = await _writePending();
    if (_visible && _openFrom == null) {
      _openFrom = now;
    }
    return wrote;
  }

  /// 结束记录：收尾并落库。
  ///
  /// 页面关闭/销毁时调用。返回是否写入了行。
  Future<bool> stop() async {
    if (!isRecording) {
      _started = false;
      return false;
    }
    final DateTime now = clock.now();
    _closeOpenInterval(now);
    final bool wrote = await _writePending();
    _visible = false;
    _openFrom = null;
    _started = false;
    return wrote;
  }

  // -------------------------------------------------------------------------
  // 内部
  // -------------------------------------------------------------------------

  /// 收尾当前区间：结束时间取「now 与 lastActive + 阈值」的较小者。
  void _closeOpenInterval(DateTime now) {
    final DateTime? from = _openFrom;
    if (from == null) {
      return;
    }
    _openFrom = null;
    final DateTime? last = _lastActive;
    if (last == null) {
      // 没有任何活跃锚点：不算这一段。正常路径下 start() 已经锚定了「打开详情页」这个
      // 动作，因此走到这里意味着调用方跳过了 start（编程错误），而不是用户没交互。
      return;
    }
    final DateTime? end = effectiveActiveEnd(
      lastActive: last,
      now: now,
      idleThreshold: _idleThreshold,
    );
    if (end == null || !end.isAfter(from)) {
      return;
    }
    _pending.add(ReadingInterval(start: from, end: end));
  }

  /// 空闲已超阈时把区间收尾（不改变「是否在记录」）。
  void _closeOpenIntervalIfIdleExpired(DateTime now) {
    final DateTime? from = _openFrom;
    final DateTime? last = _lastActive;
    if (from == null || last == null) {
      return;
    }
    final DateTime idleDeadline = last.add(_idleThreshold);
    if (!now.isAfter(idleDeadline)) {
      return;
    }
    // 先收尾（end = idleDeadline），再置空。注意这里**不**马上重开：用户没有交互，
    // 重开只会产出一个立刻被丢弃的空区间。
    _closeOpenInterval(idleDeadline);
  }

  /// 把已结束的区间拆日并落库；没有内容时什么都不做。
  Future<bool> _writePending() async {
    if (_pending.isEmpty) {
      return false;
    }
    final List<ReadingInterval> batch = List<ReadingInterval>.of(_pending);
    _pending.clear();
    final List<ReadingSessionDraft> drafts = buildSessionDrafts(
      articleId: articleId,
      intervals: batch,
      zone: zone,
    );
    if (drafts.isEmpty) {
      return false;
    }
    final Result<int> written = await stats.appendSessions(drafts);
    if (written.isErr) {
      // 写失败**不**把区间塞回 pending：那会在下一次 flush 时把同一段时间重复写入
      // （热力图会凭空多出阅读时间）。如实记诊断，统计是估计值，丢一段比记重复更
      // 诚实。
      diagnostics.warning(
        '阅读会话写入失败：${written.errorOrNull!.message}',
        tag: 'reading.session',
      );
      return false;
    }
    diagnostics.info(
      '阅读会话落库 ${drafts.length} 段（文章 $articleId）',
      tag: 'reading.session',
    );
    return true;
  }

  /// 解析 SET-015 的启用开关。
  Future<bool> _resolveEnabled() async {
    final Result<Object?> value = await settings.readSetting(SettingId.set015);
    final Object? fallback = SettingRegistry.findById(SettingId.set015)
        ?.defaultValue;
    return _readEnabled(value.valueOrNull ?? fallback);
  }

  /// 解析 SET-015 的空闲暂停分钟数。
  Future<Duration> _resolveIdleThreshold() async {
    if (idleThresholdOverride case final Duration override) {
      return override;
    }
    final Result<Object?> value = await settings.readSetting(SettingId.set015);
    final Object? fallback = SettingRegistry.findById(SettingId.set015)
        ?.defaultValue;
    final int minutes = _readIdleMinutes(value.valueOrNull ?? fallback);
    return Duration(minutes: minutes);
  }

  /// 从复合值里取 enabled。
  static bool _readEnabled(Object? raw) {
    if (raw is Map<String, Object?>) {
      final Object? enabled = raw['enabled'];
      if (enabled is bool) {
        return enabled;
      }
    }
    // 形态不符合预期时按注册表口径「开」：统计是可选辅助功能，读不到不该静默关闭。
    return true;
  }

  /// 从复合值里取 idlePauseMinutes，并夹到 1–30（SET-015 的范围）。
  static int _readIdleMinutes(Object? raw) {
    Object? minutes;
    if (raw is Map<String, Object?>) {
      minutes = raw['idlePauseMinutes'];
    }
    final int resolved = minutes is int ? minutes : 5;
    if (resolved < 1) {
      return 1;
    }
    if (resolved > 30) {
      return 30;
    }
    return resolved;
  }
}
