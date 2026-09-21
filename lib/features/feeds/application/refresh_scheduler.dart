// 刷新调度（T016；架构 4.1「刷新有条件请求、取消、限并发，区分 304、没有新文章、
// 部分解析失败和网络失败；保留旧内容」；SET-013、SET-020、SET-021、SET-022、SET-028）。
//
// 本文件解决的是**什么时候刷新、刷新哪些源、同时跑几个、重复触发怎么办**，而
// 「一次刷新内部怎么走」已经在 T013 的 RefreshFeedUseCase 里定义好了。这条分工
// 是刻意的：调度不认识 XML、也不认识文章表，它只做派发与结果汇总。
//
// 四条规则，各自对应一处文档要求：
//
//   1) **触发合并**。启动触发（SET-021）+ 定时触发（SET-020）+ 用户点「刷新」可能
//      在同一时刻发生。合并的粒度是**源**：同一个源已经在队列里就不再入队。
//      为什么不整体丢弃后到的触发：那两个触发覆盖的源集合可能不同（定时只跑
//      「间隔到了」的源，手动是全部），整体丢弃会让手动刷新在定时刚启动时被静默
//      吃掉，用户会以为按钮坏了。
//
//   2) **并发 4**（SET-028）。用**串行派发 + 限定在途数**实现，而不是 Future.wait
//      一批：一批里最慢的源会拖住整批，而且中途新入队的源要等下一批才开始。限定
//      在途数可以让空出来的槽立刻接下一个。真正的并发上限还有第二层保障：抓取器
//      内部的信号量（同一个实例内共享），因此即使调度被绕过也不会超。
//
//   3) **失败隔离**。一个源失败不中断其他源。[RefreshFeedUseCase] 本身永不抛
//      异常，这里再兜一层：调度是长期存活的对象，一次未预期异常不能让后续所有
//      触发都不再执行。
//
//   4) **离线与计费网络在上网之前拦下**（SET-013 默认关）。守卫命中时**不发出任何
//      请求**，但仍然如实记录 waitingNetwork / skippedMetered，并**不推进**上次检查
//      时间——否则用户切回网络后会因为「刚检查过」而白等一个间隔。
//
// 时间来源是 [Clock]（测试注入 FakeClock），因此「定时触发窗口」这种规则不需要
// 真实等待就能验证。
library;

import 'dart:async';

import 'package:flux/core/core.dart';

import '../domain/feed_interval.dart';

import 'refresh_feed.dart';

/// 一次触发刷新的来源（用于诊断与界面提示的区分）。
enum RefreshTrigger {
  /// 启动触发（SET-021）。
  launch,

  /// 定时触发（SET-020）。
  scheduled,

  /// 用户手动点「刷新」。
  manual;

  /// 诊断标签。
  String get tag => switch (this) {
    RefreshTrigger.launch => 'refresh.trigger.launch',
    RefreshTrigger.scheduled => 'refresh.trigger.scheduled',
    RefreshTrigger.manual => 'refresh.trigger.manual',
  };
}

/// 调度策略（来自 SET-020/021/013 与单源 SET-022）。
class RefreshSchedulePolicy {
  /// 构造策略。
  const RefreshSchedulePolicy({
    required this.autoRefreshEnabled,
    required this.intervalSetting,
    required this.refreshOnLaunch,
    required this.allowMeteredNetwork,
    this.maxConcurrency = 4,
  }) : assert(maxConcurrency >= 1, '并发上限至少为 1');

  /// SET-020 的全局开关。
  final bool autoRefreshEnabled;

  /// SET-020 的间隔取值（'manual' / '15' / '30' / '60' / '120'）。
  ///
  /// 保存字符串而不是 int：'manual' 与「0 分钟」在注册表里是两个不同的语义
  /// （前者是「不自动跑」），提前转成 int 会把这个区别抹掉。
  final String intervalSetting;

  /// SET-021 启动时刷新。
  final bool refreshOnLaunch;

  /// SET-013 允许计费网络（默认 false）。
  final bool allowMeteredNetwork;

  /// 在途刷新上限（SET-028 默认 4）。
  final int maxConcurrency;

  /// 全局定时间隔；'manual' 时为 null（不做定时刷新）。
  Duration? get globalInterval => intervalFromSetting(intervalSetting);

  /// 复制并覆盖部分字段。
  RefreshSchedulePolicy copyWith({
    bool? autoRefreshEnabled,
    String? intervalSetting,
    bool? refreshOnLaunch,
    bool? allowMeteredNetwork,
    int? maxConcurrency,
  }) => RefreshSchedulePolicy(
    autoRefreshEnabled: autoRefreshEnabled ?? this.autoRefreshEnabled,
    intervalSetting: intervalSetting ?? this.intervalSetting,
    refreshOnLaunch: refreshOnLaunch ?? this.refreshOnLaunch,
    allowMeteredNetwork: allowMeteredNetwork ?? this.allowMeteredNetwork,
    maxConcurrency: maxConcurrency ?? this.maxConcurrency,
  );
}

/// 一个源在一次调度里被跳过的记录。
class FeedRefreshSkip {
  /// 构造记录。
  const FeedRefreshSkip({
    required this.feedId,
    required this.feedName,
    required this.reason,
    this.deferral,
  });

  /// 源 id。
  final int feedId;

  /// 源显示名（提示文案需要它，而此时界面可能已经重读了列表）。
  final String feedName;

  /// 跳过原因（稳定的英文类别名，不进 UI）。
  final String reason;

  /// 因网络守卫而延迟时的原因；其它跳过为 null。
  final FeedRefreshDeferral? deferral;
}

/// 一轮调度的结果汇总。
class RefreshRunReport {
  /// 构造汇总。
  const RefreshRunReport({
    required this.trigger,
    required this.attempted,
    required this.outcomes,
    this.skipped = const <FeedRefreshSkip>[],
    this.mergedTriggers = 0,
  });

  /// 本次触发来源。
  final RefreshTrigger trigger;

  /// 实际发起（或被守卫拦下）的源数量。
  final int attempted;

  /// 每个源的结果（键为 feed id）。
  final Map<int, FeedRefreshResult> outcomes;

  /// 被跳过的源（禁用、间隔未到、守卫等）。
  final List<FeedRefreshSkip> skipped;

  /// 并入本轮而**没有重复入队**的触发次数（验证合并行为）。
  final int mergedTriggers;

  /// 有多少个源真的拿到了新内容。
  int get updatedCount => outcomes.values
      .where((FeedRefreshResult r) => r.outcome.hasNewContent)
      .length;

  /// 有多少个源命中 304。
  int get notModifiedCount => outcomes.values
      .where(
        (FeedRefreshResult r) => r.outcome == FeedRefreshOutcome.notModified,
      )
      .length;

  /// 失败（网络/解析）的源数量。
  int get failedCount => outcomes.values
      .where((FeedRefreshResult r) => r.outcome.isFailure)
      .length;

  /// 因未联网而延迟的源数量。
  int get deferredCount => outcomes.values
      .where((FeedRefreshResult r) => r.outcome.isDeferred)
      .length;

  /// 新插入文章总数。
  int get insertedTotal => outcomes.values.fold(
    0,
    (int sum, FeedRefreshResult r) => sum + r.inserted,
  );
}

/// 刷新调度器。
///
/// 生命周期由持有者管理（应用壳与测试各自负责 [dispose]）。本类**不是** widget，
/// 也不直接读设置注册表：策略与源列表由调用方传入，使调度规则可以用纯 Dart 测试
/// 验证，不依赖 Riverpod 容器。
final class RefreshScheduler {
  /// 构造调度器。
  RefreshScheduler({
    required this.listFeeds,
    required this.refreshFeed,
    required this.recordDeferral,
    this.networkConditions = const PermissiveNetworkConditions(),
    this.diagnostics = const NoopDiagnosticSink(),
    this.clock = const SystemClock(),
  });

  /// 读取待刷新的源（由组合根接到订阅仓储）。
  ///
  /// 用函数而不是端口对象：调度只需要「给我一份源列表」，一个函数比一个接口更
  /// 小、更容易在测试里替换。
  final Future<Result<List<FeedRecord>>> Function() listFeeds;

  /// 刷新单个源的用例（T013）。
  final RefreshFeedUseCase refreshFeed;

  /// 记录一次「被守卫拦下」的结果（写 feeds.lastRefreshResult / 错误类别）。
  ///
  /// 为什么必须记录：守卫命中时没有发起请求，如果不写任何东西，界面上的「上次检查」
  /// 会一直停在上一次，用户无从判断调度是在跑还是坏了。这一条由组合根接到
  /// DriftFeedArticleStore.recordRefreshOutcome 上。
  ///
  /// 接的是 [FeedArticleStore.recordDeferredOutcome] 而不是 recordRefreshOutcome：
  /// 后者会推进 lastCheckedAt，而这里一个字节都没发出去，推进时间会让用户切回网络
  /// 后白等一个间隔（见文件头第 4 条）。
  final Future<Result<void>> Function({
    required int feedId,
    required FeedRefreshOutcome outcome,
    String? errorKind,
  })
  recordDeferral;

  /// 网络状况端口（计费/离线判定）。
  final NetworkConditionPort networkConditions;

  /// 诊断记录。
  final DiagnosticSink diagnostics;

  /// 时钟（定时窗口判定与「检查过」的时间戳）。
  final Clock clock;

  /// 已在队列中的源 id（合并重复触发的依据）。
  final Set<int> _queued = <int>{};

  /// 在途数量（并发上限的计数器）。
  int _inFlight = 0;

  /// 等待派发的触发。
  final List<_PendingTrigger> _pending = <_PendingTrigger>[];

  /// 每个源最近一次完成调度的时间（定时窗口判定用）。
  final Map<int, DateTime> _lastCompletedAt = <int, DateTime>{};

  /// 并入的重复触发累计次数。
  int _mergedTotal = 0;

  /// 是否已释放（释放后再触发只记录一条诊断，不执行）。
  bool _disposed = false;

  /// 并发上限（来自策略）。
  int _maxConcurrency = 4;

  /// SET-013 的允许开关（默认**不允许**：与注册表默认值 false 一致）。
  bool _policyAllowsMetered = false;

  /// 最近一次套用的策略（定时窗口判定用）。
  RefreshSchedulePolicy _currentPolicy = const RefreshSchedulePolicy(
    autoRefreshEnabled: true,
    intervalSetting: '60',
    refreshOnLaunch: true,
    allowMeteredNetwork: false,
  );

  /// 是否有工作在进行（界面据此显示进度，而不是靠猜）。
  bool get isRunning => _inFlight > 0 || _pending.isNotEmpty;

  /// 当前在途数量（测试断言并发上限用）。
  int get inFlightCount => _inFlight;

  /// 已入队但尚未完成的源 id 快照（测试断言合并用）。
  Set<int> get queuedFeedIds => Set<int>.unmodifiable(_queued);

  /// 并入的重复触发累计次数（诊断与测试用）。
  int get mergedTriggerTotal => _mergedTotal;

  /// 套用一份策略（并发上限、SET-013 开关、定时间隔口径）。
  void applyPolicy(RefreshSchedulePolicy policy) {
    _currentPolicy = policy;
    _maxConcurrency = policy.maxConcurrency;
    _policyAllowsMetered = policy.allowMeteredNetwork;
  }

  /// 手动全量刷新：所有**启用**的源，忽略间隔（用户明确要求现在就检查）。
  Future<RefreshRunReport> refreshAll({
    RefreshTrigger trigger = RefreshTrigger.manual,
  }) => _enqueue(trigger: trigger, onlyDue: false);

  /// 启动触发（SET-021）。
  ///
  /// 开关判断留在调用方（它同时要读设置并决定「启动时是否真的触发」），因为
  /// 调度的职责是「怎么跑」，不是「要不要跑」。
  Future<RefreshRunReport> refreshOnLaunch() =>
      _enqueue(trigger: RefreshTrigger.launch, onlyDue: false);

  /// 定时触发（SET-020）：按**各源自己的间隔**筛出到期的源。
  Future<RefreshRunReport> refreshDueScheduled() =>
      _enqueue(trigger: RefreshTrigger.scheduled, onlyDue: true);

  /// 释放调度器：不再接受新的触发，等待在途任务自然结束后停止。
  ///
  /// 刻意**不**强制中断在途请求：中断一个已经发出并可能计费的请求，会让「这次
  /// 刷新到底成没成」变得不确定（架构第 8 节不允许把不确定说成已取消）。
  void dispose() {
    _disposed = true;
    _pending.clear();
  }

  /// 某个源的间隔（本机覆盖优先，其次全局）；null 表示不自动刷新。
  Duration? intervalFor(FeedRecord feed, RefreshSchedulePolicy policy) {
    final int? override = feed.refreshIntervalMinutes;
    if (override != null) {
      // 0 表示「手动」：该源不参与定时刷新（SET-022）。
      return override == 0 ? null : Duration(minutes: override);
    }
    return policy.autoRefreshEnabled ? policy.globalInterval : null;
  }

  /// 某个源本次定时触发是否到期。
  ///
  /// 「从未检查过」视为到期（否则新订阅要等一个完整间隔才会首次自动抓取，
  /// 而用户刚添加完正期待看到内容）。
  bool isFeedDue({
    required FeedRecord feed,
    required DateTime now,
    DateTime? lastRun,
  }) {
    if (!feed.enabled) {
      return false;
    }
    // 调度进程内的记录优先（本次会话确实跑过）；否则回落到库里的上次检查时间——
    // 否则每次重启都会立刻全量刷新一遍，把「默认开但按时区运行」变成「每次启动都跑」。
    final DateTime? reference = lastRun ?? feed.lastCheckedAt;
    final Duration? interval = intervalFor(feed, _currentPolicy);
    if (interval == null) {
      return false;
    }
    if (reference == null) {
      return true;
    }
    return now.difference(reference) >= interval;
  }

  /// 入队一轮触发。
  Future<RefreshRunReport> _enqueue({
    required RefreshTrigger trigger,
    required bool onlyDue,
  }) async {
    if (_disposed) {
      diagnostics.warning('调度器已释放，忽略 ${trigger.name} 触发', tag: trigger.tag);
      return RefreshRunReport(
        trigger: trigger,
        attempted: 0,
        outcomes: const <int, FeedRefreshResult>{},
      );
    }

    final Result<List<FeedRecord>> feeds = await listFeeds();
    if (feeds.isErr) {
      diagnostics.error('读取订阅清单失败，本轮 ${trigger.name} 刷新不执行', tag: trigger.tag);
      return RefreshRunReport(
        trigger: trigger,
        attempted: 0,
        outcomes: const <int, FeedRefreshResult>{},
      );
    }

    final DateTime now = clock.now();
    final List<FeedRecord> candidates = <FeedRecord>[];
    final List<FeedRefreshSkip> skipped = <FeedRefreshSkip>[];
    int merged = 0;

    for (final FeedRecord feed in feeds.valueOrNull!) {
      // 1) 禁用源不参与刷新（SET-022）。
      if (!feed.enabled) {
        skipped.add(
          FeedRefreshSkip(
            feedId: feed.id,
            feedName: feed.name,
            reason: 'disabled',
          ),
        );
        continue;
      }

      // 2) 只有定时触发看间隔；手动/启动是「用户/系统明确要求现在检查」。
      if (onlyDue &&
          !isFeedDue(
            feed: feed,
            now: now,
            lastRun: _lastCompletedAt[feed.id],
          )) {
        skipped.add(
          FeedRefreshSkip(
            feedId: feed.id,
            feedName: feed.name,
            reason: 'intervalNotReached',
          ),
        );
        continue;
      }

      // 3) 合并重复触发：已在队列中的源不再入队。
      if (_queued.contains(feed.id)) {
        merged++;
        continue;
      }

      candidates.add(feed);
    }

    _mergedTotal += merged;

    if (candidates.isEmpty) {
      diagnostics.info(
        '本轮 ${trigger.name} 刷新没有需要执行的源（并入 $merged 次重复触发）',
        tag: trigger.tag,
      );
      return RefreshRunReport(
        trigger: trigger,
        attempted: 0,
        outcomes: const <int, FeedRefreshResult>{},
        skipped: skipped,
        mergedTriggers: merged,
      );
    }

    // 网络守卫在**派发之前**判定一次：整轮触发共享同一次判定，避免每个源各探一次
    // 得到互相矛盾的结果（网络状态在一次刷新周期内变化会让部分源跑、部分源不跑，
    // 用户看到的是「有的刷新了有的没刷」而没有任何解释）。
    final FeedRefreshDeferral? deferral = await _guard();

    final _PendingTrigger pending = _PendingTrigger(
      trigger: trigger,
      feeds: candidates,
      deferral: deferral,
      skipped: skipped,
      mergedTriggers: merged,
    );
    _pending.add(pending);
    for (final FeedRecord feed in candidates) {
      _queued.add(feed.id);
    }
    unawaited(_drain());
    return pending.completer.future;
  }

  /// 上游守卫：返回拦下整轮的原因；放行时为 null。
  Future<FeedRefreshDeferral?> _guard() async {
    // 计费网络（SET-013 默认关）：**先于**任何请求判定，命中就一个字节都不发。
    // 判定顺序是「先计费后离线」：计费网络通常同时也是有网状态，先判计费能让
    // 提示文案说对原因（用户需要知道的是「你关掉了计费网络下载」）。
    if (!_policyAllowsMetered && await networkConditions.isMetered()) {
      return FeedRefreshDeferral.meteredNetwork;
    }
    if (await networkConditions.isOffline()) {
      return FeedRefreshDeferral.offline;
    }
    return null;
  }

  /// 按并发上限派发队列。
  Future<void> _drain() async {
    while (true) {
      if (_pending.isEmpty) {
        return;
      }
      if (_inFlight >= _maxConcurrency) {
        // 槽位已满：等一次在途任务结束时由它再次调用 _drain（见 _runOne 的 finally）。
        return;
      }
      final _PendingTrigger current = _pending.first;
      if (current.feeds.isEmpty) {
        // 没有待派发的源了，但可能还有**在途**的源：此时这一轮还没结束。
        // 之前的实现只判断「待派发为空」就结束整轮，会在请求还在飞的时候就把
        // 结果汇总发出去（attempted 恒为 0）。必须同时看 outstanding。
        if (current.outstanding == 0) {
          _pending.removeAt(0);
          _finish(current);
          continue;
        }
        return;
      }
      final FeedRecord feed = current.feeds.removeAt(0);
      _inFlight++;
      current.outstanding++;
      unawaited(_runOne(current: current, feed: feed));
    }
  }

  /// 执行单个源。
  Future<void> _runOne({
    required _PendingTrigger current,
    required FeedRecord feed,
  }) async {
    try {
      final FeedRefreshDeferral? deferral = current.deferral;
      if (deferral != null) {
        // 守卫命中：不联网，但必须如实记录结果（且不推进「上次检查」）。
        final Result<void> recorded = await recordDeferral(
          feedId: feed.id,
          outcome: deferral.outcome,
          errorKind: deferral.errorKind,
        );
        if (recorded.isErr) {
          diagnostics.warning('记录「未联网跳过」失败：${feed.name}', tag: 'refresh.guard');
        }
        current.outcomes[feed.id] = FeedRefreshResult(
          outcome: deferral.outcome,
        );
        current.skipped.add(
          FeedRefreshSkip(
            feedId: feed.id,
            feedName: feed.name,
            reason: deferral.errorKind,
            deferral: deferral,
          ),
        );
        return;
      }

      final FeedRefreshResult result = await refreshFeed(
        FeedRefreshRequest(
          feedId: feed.id,
          url: Uri.parse(feed.normalizedUrl),
          feedName: feed.name,
          etag: feed.httpEtag,
          lastModified: feed.httpLastModified,
          now: clock.now(),
        ),
      );
      current.outcomes[feed.id] = result;
      if (!result.outcome.isDeferred) {
        _lastCompletedAt[feed.id] = clock.now();
      }
    } on Exception catch (error) {
      // 调度是长期存活对象：一次未预期异常不能让后续所有触发都不再执行。
      // 这里记录「失败但保留旧内容」的语义（用例层没有写入任何东西）。
      diagnostics.error(
        '刷新源时发生未预期异常：${feed.name} — ${error.runtimeType}',
        tag: 'refresh.scheduler',
      );
      current.outcomes[feed.id] = FeedRefreshResult(
        outcome: FeedRefreshOutcome.networkFailed,
        error: NetworkError(
          uri: SecretRedaction.sanitizeUrlString(feed.normalizedUrl),
          reason: '刷新流程异常（${error.runtimeType}）',
          cause: error,
        ),
      );
    } finally {
      _inFlight--;
      current.outstanding--;
      _queued.remove(feed.id);
      if (current.feeds.isEmpty && current.outstanding == 0) {
        _pending.remove(current);
        _finish(current);
      }
      // 释放一个槽位后继续派发；这里不等待它完成（完成信号走 completer）。
      unawaited(_drain());
    }
  }

  /// 结束一轮触发。
  void _finish(_PendingTrigger current) {
    final RefreshRunReport report = RefreshRunReport(
      trigger: current.trigger,
      attempted: current.outcomes.length,
      outcomes: Map<int, FeedRefreshResult>.unmodifiable(current.outcomes),
      skipped: List<FeedRefreshSkip>.unmodifiable(current.skipped),
      mergedTriggers: current.mergedTriggers,
    );
    diagnostics.info(
      '${current.trigger.name} 刷新完成：${report.attempted} 个源，新增 ${report.insertedTotal} 篇，'
      '失败 ${report.failedCount} 个，304 ${report.notModifiedCount} 个，延迟 ${report.deferredCount} 个',
      tag: current.trigger.tag,
    );
    current.completer.complete(report);
  }
}

/// 一轮待派发的触发。
final class _PendingTrigger {
  /// 构造触发。
  _PendingTrigger({
    required this.trigger,
    required this.feeds,
    required this.deferral,
    required this.skipped,
    required this.mergedTriggers,
  });

  /// 触发来源。
  final RefreshTrigger trigger;

  /// 尚未派发的源（派发时逐个移出）。
  final List<FeedRecord> feeds;

  /// 整轮被守卫拦下的原因；null 表示正常派发。
  final FeedRefreshDeferral? deferral;

  /// 已被跳过的源（禁用、间隔未到）。
  final List<FeedRefreshSkip> skipped;

  /// 并入本轮的重复触发次数。
  final int mergedTriggers;

  /// 结果累积。
  final Map<int, FeedRefreshResult> outcomes = <int, FeedRefreshResult>{};

  /// 已派发但**尚未完成**的源数量。
  ///
  /// 必须与 [feeds] 分开计数：只判断 [feeds] 为空会把「请求还在飞」误判成
  /// 「这一轮已经做完」，汇总里会一个源都没有。
  int outstanding = 0;

  /// 完成信号。
  final Completer<RefreshRunReport> completer = Completer<RefreshRunReport>();
}
