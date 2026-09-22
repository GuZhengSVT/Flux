// 同步管理器：触发来源、串行排队与首次合并（T044；SET-072/073/075、架构 5.2）。
//
// 这个文件回答「什么时候同步、同一时刻只跑几次、第一次连上远端时先做什么」。它**不**做
// 合并（T043 的纯函数）、不做协议动作（T042/T043 的传输端口）、不碰 Keychain（注入的端口）。
//
// 五条刻意的设计：
//
//   1) **同机不并发**。四个触发来源（启动 / 定时 / 变更防抖 / 手动）都走同一个 [request]
//      入口，而入口在已有一次运行在途时只**记下一个待跑标记**，不再开第二轮：并发两次同步
//      会让它们读到同一个父版本、各自上传，其中一次的 412 重试白跑一轮，而更糟的是
//      「谁最后写」变得不可预测。触发被合并而不是排队成 N 次：用户连点五次「立即同步」
//      应该只产生一次同步，而不是把同一份内容传五遍。
//   2) **防抖 5 秒（SET-072 的 changeDebounceSeconds）**：变更触发的计时器每次收到新变更
//      都重新计时，因此「连续改了十个字段」只在上次改动静默满 5 秒后产生一次同步。
//   3) **首次同步先预览（SET-075 的 firstSyncPreview）**：没有共同基线时**不自动发布**，
//      而是把远端内容与差异列给用户，默认策略是**不覆盖本地**。用户确认后才建立基线。
//   4) **冲突必须由用户选版**：manual 策略下引擎不发布，管理器把冲突列表暴露给界面。
//   5) **状态是单一来源**：[SyncStatusSnapshot] 由管理器唯一写出，界面读它而不是自己拼。
library;

import 'dart:async';

import 'package:flux/core/core.dart';

import 'sync_engine.dart';
import 'sync_settings.dart';

/// 一次同步的触发来源（诊断与界面提示的区分）。
enum SyncTrigger {
  /// 应用启动时（SET-072 的 syncOnStart）。
  launch,

  /// 定时（SET-073 的 intervalMinutes）。
  scheduled,

  /// 本地变更后的防抖触发（SET-072 的 syncOnChange）。
  change,

  /// 用户手动点击。
  manual,

  /// 冲突选版 / 首次合并确认之后的续跑。
  conflictResolution;

  /// 诊断标签。
  String get tag => switch (this) {
    SyncTrigger.launch => 'sync.launch',
    SyncTrigger.scheduled => 'sync.scheduled',
    SyncTrigger.change => 'sync.change',
    SyncTrigger.manual => 'sync.manual',
    SyncTrigger.conflictResolution => 'sync.conflictResolution',
  };
}

/// 读一次凭据的动作（用户名 + 密码；密码只在本次调用期间存在）。
typedef SyncCredentialLoader = Future<Result<SyncCredentials>> Function(
  SyncSettings settings,
);

/// 同步的界面状态快照（设置页与冲突页读同一份）。
final class SyncStatusSnapshot {
  /// 构造状态。
  const SyncStatusSnapshot({
    this.enabled = false,
    this.running = false,
    this.queued = false,
    this.capability = WebDavWriteCapability.unknown,
    this.lastTrigger,
    this.lastStatus,
    this.lastErrorReason,
    this.lastSyncedAt,
    this.lastVersion,
    this.conflicts = const <SyncMergeConflict>[],
    this.pendingRemoteDeletions = const <SyncDeletion>[],
    this.pendingChangeCount = 0,
    this.firstMergePreview,
  });

  /// SET-072 的总开关。
  final bool enabled;

  /// 是否正在运行。
  final bool running;

  /// 是否有一次触发被合并成「等待运行」（同机不并发的证据）。
  final bool queued;

  /// 服务器能力（T042 的探测结论）。
  final WebDavWriteCapability capability;

  /// 最近一次触发的来源。
  final SyncTrigger? lastTrigger;

  /// 最近一次的结论。
  final SyncRunStatus? lastStatus;

  /// 失败原因的结构性标识（不含地址与凭据）。
  final String? lastErrorReason;

  /// 上次成功同步的时刻（UTC）。
  final DateTime? lastSyncedAt;

  /// 上次成功发布的版本。
  final String? lastVersion;

  /// 待用户选版的冲突（manual 策略下非空）。
  final List<SyncMergeConflict> conflicts;

  /// 远端提出、本机未确认的破坏性删除（**尚未应用**）。
  final List<SyncDeletion> pendingRemoteDeletions;

  /// 待同步的本机变更数。
  final int pendingChangeCount;

  /// 首次同步预览；非空表示**尚未建立基线**且用户还没确认。
  final SyncFirstMergePreview? firstMergePreview;

  /// 是否处于降级模式（服务器不支持可靠条件写）。
  bool get degraded => capability == WebDavWriteCapability.readOnlyPull;

  /// 是否需要用户介入（冲突选版 / 破坏性删除确认 / 首次合并确认）。
  bool get needsUserAction =>
      conflicts.isNotEmpty ||
      pendingRemoteDeletions.isNotEmpty ||
      firstMergePreview != null;

  /// 复制并覆盖部分字段（只有管理器与状态读取端口构造状态）。
  SyncStatusSnapshot copyWith({
    bool? enabled,
    bool? running,
    bool? queued,
    WebDavWriteCapability? capability,
    SyncTrigger? lastTrigger,
    SyncRunStatus? lastStatus,
    String? lastErrorReason,
    bool clearLastError = false,
    DateTime? lastSyncedAt,
    String? lastVersion,
    List<SyncMergeConflict>? conflicts,
    List<SyncDeletion>? pendingRemoteDeletions,
    int? pendingChangeCount,
    SyncFirstMergePreview? firstMergePreview,
    bool clearFirstMergePreview = false,
  }) => SyncStatusSnapshot(
    enabled: enabled ?? this.enabled,
    running: running ?? this.running,
    queued: queued ?? this.queued,
    capability: capability ?? this.capability,
    lastTrigger: lastTrigger ?? this.lastTrigger,
    lastStatus: lastStatus ?? this.lastStatus,
    lastErrorReason: clearLastError
        ? null
        : (lastErrorReason ?? this.lastErrorReason),
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    lastVersion: lastVersion ?? this.lastVersion,
    conflicts: conflicts ?? this.conflicts,
    pendingRemoteDeletions:
        pendingRemoteDeletions ?? this.pendingRemoteDeletions,
    pendingChangeCount: pendingChangeCount ?? this.pendingChangeCount,
    firstMergePreview: clearFirstMergePreview
        ? null
        : (firstMergePreview ?? this.firstMergePreview),
  );
}

/// 同步管理器。
///
/// 依赖全部是窄能力：读设置、读初始状态、造引擎、探测能力、读凭据。因此「启动/定时/防抖/
/// 手动串行不重复排队」「首次预览不覆盖本地」「冲突可选版」都能用替身逐条断言，而不需要
/// 真实服务器（真实服务器验证按手册 7.3 记 NOT_RUN）。
final class SyncManager {
  /// 构造管理器。
  SyncManager({
    required this.readSettings,
    required this.readStatusBaseline,
    required this.buildEngine,
    required this.probeCapability,
    required this.loadCredentials,
    required this.readLocalContentSnapshot,
    this.onStatus,
    this.diagnostics = const NoopDiagnosticSink(),
    this.clock = const SystemClock(),
  });

  /// 读同步设置（SET-070–075）。
  final Future<Result<SyncSettings>> Function() readSettings;

  /// 读初始状态（基线/能力/上次成功/待同步数；**不发网络请求**）。
  ///
  /// 返回的是存储层能诚实回答的那部分（[SyncStatusBaseline]）而不是界面快照：冲突列表与
  /// 首次合并预览是「一次合并的结论」，本机存储里没有它们，硬塞进存储层只会让存储层编造
  /// 两个它并不知道的数字。
  final Future<Result<SyncStatusBaseline>> Function() readStatusBaseline;

  /// 造一个引擎（每轮现造：设置可以在两轮之间被改，复用会让新地址与旧连接混在一起）。
  ///
  /// 返回 **null** 表示「这一轮无法构造引擎」（例如数据库不可用的降级启动）：管理器会
  /// 如实报一处 storage 失败，而不是抛出一个没人处理的异常。
  final SyncEngine? Function(SyncSettings settings, SyncCredentials credentials)
  buildEngine;

  /// 探测服务器能力（T042 的四步探测；只在需要时调用）。
  final Future<Result<WebDavWriteCapability>> Function(
    SyncSettings settings,
    SyncCredentials credentials,
  )
  probeCapability;

  /// 读一次凭据（从 Keychain 取，**不落库、不缓存**）。
  final SyncCredentialLoader loadCredentials;

  /// 读**本机当前内容快照**（首次合并预览要拿它跟远端比差异）。
  final Future<Result<SyncSnapshot>> Function() readLocalContentSnapshot;

  /// 状态变更回调（界面据此刷新）。
  final void Function(SyncStatusSnapshot status)? onStatus;

  /// 诊断记录。
  final DiagnosticSink diagnostics;

  /// 时钟（只用于防抖计时与诊断；**不参与合并判定**）。
  final Clock clock;

  Timer? _debounce;
  Timer? _interval;
  bool _running = false;
  bool _pending = false;
  SyncTrigger? _pendingTrigger;
  bool _disposed = false;
  bool _firstMergeConfirmed = false;
  SyncStatusSnapshot _status = const SyncStatusSnapshot();

  /// 当前状态。
  SyncStatusSnapshot get status => _status;

  /// 是否正在运行。
  bool get isRunning => _running;

  /// 是否有一次触发被合并成「等待运行」（用于断言「不重复排队」）。
  bool get hasQueuedTrigger => _pending;

  /// 应用启动：读初始状态、按 SET-072/073 决定是否立即同步与起定时。
  Future<void> onLaunch() async {
    if (_disposed) {
      return;
    }
    final Result<SyncSettings> settingsRead = await readSettings();
    if (settingsRead.isErr) {
      _publish(
        _status.copyWith(
          running: false,
          lastErrorReason: settingsRead.errorOrNull!.kind,
        ),
      );
      return;
    }
    final SyncSettings settings = settingsRead.unwrap();
    _publish(await _statusFromStore(enabled: settings.enabled));
    if (!settings.enabled || !settings.hasEndpointConfig) {
      // 未配置或已关闭：**不探测、不同步、不起定时**。这一条同时保证「未配置的设备
      // 一个请求都不发」。
      return;
    }
    if (settings.syncOnStart) {
      await request(SyncTrigger.launch);
    }
    startIntervalTimer();
  }

  /// 起自动同步的定时器（SET-073；manualOnly 时不起）。
  void startIntervalTimer() {
    if (_disposed) {
      return;
    }
    _interval?.cancel();
    _interval = null;
    unawaited(
      readSettings().then((Result<SyncSettings> settings) {
        if (_disposed || settings.isErr) {
          return;
        }
        final SyncSettings value = settings.unwrap();
        if (!value.enabled || value.manualOnly) {
          return;
        }
        _interval = Timer.periodic(value.interval, (Timer _) {
          unawaited(request(SyncTrigger.scheduled));
        });
      }),
    );
  }

  /// 本地变更后的触发（SET-072 的防抖）。
  ///
  /// 每次调用**重新计时**：连续改动只在上次改动静默满防抖时长之后产生一次同步。
  void notifyLocalChange() {
    if (_disposed) {
      return;
    }
    unawaited(
      readSettings().then((Result<SyncSettings> settings) {
        if (_disposed || settings.isErr) {
          return;
        }
        final SyncSettings value = settings.unwrap();
        if (!value.enabled || !value.syncOnChange) {
          return;
        }
        _debounce?.cancel();
        _debounce = Timer(value.changeDebounce, () {
          unawaited(request(SyncTrigger.change));
        });
      }),
    );
  }

  /// 是否有防抖计时器在等待（诊断与用例观察用）。
  bool get hasPendingDebounce => _debounce?.isActive ?? false;

  /// 请求一次同步（四个触发来源的唯一入口）。
  ///
  /// 返回 null 表示这次请求被合并进一次已在途/已排队的运行（同机不并发）。
  Future<SyncRunResult?> request(SyncTrigger trigger) async {
    if (_disposed) {
      return null;
    }
    if (_running) {
      // 只记下「还有一个触发等着」，不排队成 N 次。
      _pending = true;
      _pendingTrigger = trigger;
      _publish(_status.copyWith(queued: true, running: true));
      return null;
    }
    _running = true;
    _publish(
      _status.copyWith(
        running: true,
        lastTrigger: trigger,
        clearLastError: true,
      ),
    );
    SyncRunResult? result;
    try {
      result = await _runOnce(trigger: trigger);
      return result;
    } finally {
      _running = false;
      final SyncTrigger? queued = _pending ? _pendingTrigger : null;
      _pending = false;
      _pendingTrigger = null;
      if (queued != null) {
        // 串行续跑：这一轮结束之后再跑那次被合并的触发（不并行、不丢触发）。
        _publish(_status.copyWith(running: false, queued: false));
        unawaited(request(queued));
      } else {
        _publish(_status.copyWith(running: false, queued: false));
      }
    }
  }

  /// 冲突选版 / 首次合并确认之后的续跑（T044 的界面回填）。
  Future<SyncRunResult?> resolveConflicts(
    Map<String, SyncConflictChoice> choices, {
    SyncConflictPolicy? policy,
  }) async {
    if (_disposed) {
      return null;
    }
    if (_running) {
      _pending = true;
      _pendingTrigger = SyncTrigger.conflictResolution;
      _publish(_status.copyWith(queued: true, running: true));
      return null;
    }
    _running = true;
    _publish(
      _status.copyWith(
        running: true,
        lastTrigger: SyncTrigger.conflictResolution,
        clearLastError: true,
      ),
    );
    try {
      return await _runOnce(
        trigger: SyncTrigger.conflictResolution,
        choices: choices,
        policyOverride: policy,
      );
    } finally {
      _running = false;
      _publish(_status.copyWith(running: false, queued: false));
    }
  }

  /// 用户确认首次合并（T044 的首次合并预览回填）。
  ///
  /// [policy] 是用户选的合并策略；界面默认 [SyncConflictPolicy.preferLocal]（**不覆盖本地**）。
  Future<SyncRunResult?> confirmFirstMerge({
    required SyncConflictPolicy policy,
    Map<String, SyncConflictChoice> choices =
        const <String, SyncConflictChoice>{},
  }) async {
    _firstMergeConfirmed = true;
    final SyncRunResult? result = await resolveConflicts(
      choices,
      policy: policy,
    );
    if (result != null && result.status != SyncRunStatus.failed) {
      // 确认之后基线就建立了，预览不再需要显示。
      _publish(_status.copyWith(clearFirstMergePreview: true));
    }
    return result;
  }

  /// 停止定时器与防抖（应用退出/设置页销毁时调用）。
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _debounce = null;
    _interval?.cancel();
    _interval = null;
  }

  // -------------------------------------------------------------------------
  // 内部
  // -------------------------------------------------------------------------

  Future<SyncRunResult?> _runOnce({
    required SyncTrigger trigger,
    Map<String, SyncConflictChoice> choices =
        const <String, SyncConflictChoice>{},
    SyncConflictPolicy? policyOverride,
  }) async {
    final Result<SyncSettings> settingsRead = await readSettings();
    if (settingsRead.isErr) {
      return _fail(settingsRead.errorOrNull!.kind);
    }
    final SyncSettings settings = settingsRead.unwrap();
    if (!settings.enabled) {
      // 关闭时**一个请求都不发**：手动触发也一样（用户关了同步还点按钮时，如实说明
      // 「同步已关闭」比偷偷跑一次更符合预期）。
      _publish(
        _status.copyWith(
          running: false,
          enabled: false,
          lastStatus: SyncRunStatus.readonlyPull,
          lastErrorReason: 'syncDisabled',
        ),
      );
      return null;
    }
    final Uri? remoteRoot = settings.remoteRoot;
    if (remoteRoot == null) {
      return _fail('endpointNotConfigured');
    }

    final Result<SyncCredentials> credentials = await loadCredentials(settings);
    if (credentials.isErr) {
      return _fail(credentials.errorOrNull!.kind);
    }

    // 能力：未知时先探测（T042 的四步），已探测过则直接用状态里的结论（不重复探测）。
    WebDavWriteCapability capability = _status.capability;
    if (capability == WebDavWriteCapability.unknown) {
      final Result<WebDavWriteCapability> probed = await probeCapability(
        settings,
        credentials.unwrap(),
      );
      if (probed.isErr) {
        return _fail(probed.errorOrNull!.kind);
      }
      capability = probed.unwrap();
    }

    // 首次合并预览（SET-075）：没有共同基线、且用户还没确认过时，**先预览再合并**。
    // 预览不写任何东西：它只读远端与本机两份内容算差异。
    if (settings.firstSyncPreview && !_firstMergeConfirmed) {
      final SyncFirstMergePreview? preview = await _buildPreviewIfFirstRun(
        settings: settings,
        credentials: credentials.unwrap(),
        capability: capability,
        remoteRoot: remoteRoot,
      );
      if (preview != null) {
        _publish(
          _status.copyWith(
            running: false,
            capability: capability,
            lastTrigger: trigger,
            firstMergePreview: preview,
            conflicts: const <SyncMergeConflict>[],
            pendingRemoteDeletions: preview.remoteDeletionCount > 0
                ? _status.pendingRemoteDeletions
                : const <SyncDeletion>[],
            pendingChangeCount: await _pendingCountFor(settings),
            lastStatus: SyncRunStatus.waitingConflictChoice,
            lastErrorReason: 'firstMergePreviewRequired',
          ),
        );
        return null;
      }
    }

    final SyncEngine? engine = buildEngine(settings, credentials.unwrap());
    if (engine == null) {
      return _fail('storage');
    }
    final SyncRunResult result = await engine.run(
      capability: capability,
      conflictPolicy: policyOverride ?? settings.conflictPolicy,
      choices: choices,
    );
    _publishFromRun(result, capability: capability);
    return result;
  }

  /// 没有共同基线时算一次预览；已有基线或幂等路径则返回 null（走正常合并）。
  Future<SyncFirstMergePreview?> _buildPreviewIfFirstRun({
    required SyncSettings settings,
    required SyncCredentials credentials,
    required WebDavWriteCapability capability,
    required Uri remoteRoot,
  }) async {
    final Result<SyncStatusBaseline> baseline = await readStatusBaseline();
    final String? baseVersion = baseline.valueOrNull?.baseVersion;
    if (baseVersion != null) {
      return null;
    }
    // 降级服务器：只读拉取本来就不写，预览没有意义（引擎会返回 pulledSnapshot 供导入）。
    if (capability != WebDavWriteCapability.conditionalWrite) {
      return null;
    }
    final SyncEngine? engine = buildEngine(settings, credentials);
    if (engine == null) {
      return null;
    }
    // 用引擎的读能力取远端快照：复用同一条读取路径（含「读不懂就明确失败」的规则），
    // 而不是在这里另写一份 HTTP 代码。
    final Result<SyncSnapshot?> remoteRead = await engine
        .readRemoteSnapshotOnly();
    if (remoteRead.isErr) {
      return null;
    }
    final SyncSnapshot? remote = remoteRead.unwrap();
    if (remote == null || remote.isEmpty) {
      // 远端还没有内容：首次发布不需要用户确认（没有可覆盖的东西）。
      return null;
    }
    final Result<SyncSnapshot> local = await readLocalContentSnapshot();
    if (local.isErr) {
      return null;
    }
    return buildFirstMergePreview(local: local.unwrap(), remote: remote);
  }

  Future<int> _pendingCountFor(SyncSettings settings) async {
    final Result<SyncStatusBaseline> baseline = await readStatusBaseline();
    return baseline.valueOrNull?.pendingChangeCount ?? 0;
  }

  /// 由存储层读到的那部分状态拼出界面快照（内存里的冲突列表保持不变）。
  Future<SyncStatusSnapshot> _statusFromStore({required bool enabled}) async {
    final Result<SyncStatusBaseline> baseline = await readStatusBaseline();
    final SyncStatusBaseline? value = baseline.valueOrNull;
    return _status.copyWith(
      enabled: enabled,
      capability: value?.capability ?? WebDavWriteCapability.unknown,
      lastSyncedAt: value?.lastSyncedAt,
      lastVersion: value?.baseVersion,
      pendingChangeCount: value?.pendingChangeCount ?? 0,
    );
  }

  SyncRunResult? _fail(String reason) {
    _publish(
      _status.copyWith(
        running: false,
        lastStatus: SyncRunStatus.failed,
        lastErrorReason: reason,
      ),
    );
    return null;
  }

  void _publishFromRun(
    SyncRunResult result, {
    required WebDavWriteCapability capability,
  }) {
    _publish(
      _status.copyWith(
        running: false,
        capability: capability,
        lastStatus: result.status,
        lastErrorReason: result.reason,
        lastSyncedAt: result.isSuccess && !result.recoveredWithoutUpload
            ? clock.now().toUtc()
            : null,
        lastVersion: result.publishedVersion,
        // 冲突只在**等待用户选版**时留在状态里。
        //
        // 引擎即使已经按选择解决了冲突，也会把「这次确实发生过哪条冲突」记在结果里（那是
        // 事实，不该被抹掉）；但界面读的是「还有多少事要用户做」，而一次成功的发布之后
        // 答案是零——照搬引擎的冲突列表会让提示条永远挂在设置页上，而用户已经选完了。
        conflicts: result.status == SyncRunStatus.waitingConflictChoice
            ? result.conflicts
            : const <SyncMergeConflict>[],
        pendingRemoteDeletions: result.pendingRemoteDeletions,
        // 首次合并若已经形成并发布成功，预览就该消失。
        clearFirstMergePreview: result.isSuccess,
      ),
    );
  }

  void _publish(SyncStatusSnapshot status) {
    _status = status;
    onStatus?.call(status);
  }
}
