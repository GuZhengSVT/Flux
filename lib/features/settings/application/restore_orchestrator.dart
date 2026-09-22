// 恢复编排用例（T048；架构 5.3 的恢复段）。
//
// T046 交付「恢复到新目录并校验通过」，本用例把剩下的半自动部分接起来：
//
//   pendingRestart ──（重启时）──► switched ──（用户确认）──► cleaned
//
// 三条不变量：
//   1) **切换失败必须回退**，且回退后当前数据目录仍是切换前的那一份（用户不会因为一次恢复而
//      失去可用数据）。回退失败是一种必须被报告出来的状态（不能静默停在停放位置）。
//   2) **任何一步失败都不清标记**（除了「标记本身指向一个不可用的目录」那一种），因此下一次
//      启动还会重试或至少让用户看到问题。
//   3) **删除旧目录必须由用户确认**：切换之后旧目录还留着，用户可能想先打开看一眼再删。
library;

import 'package:flux/core/core.dart';

import 'maintenance_ports.dart';

/// 恢复编排用例。
final class RestoreOrchestrator {
  /// 构造用例。
  const RestoreOrchestrator({
    required this.port,
    this.diagnostics = const NoopDiagnosticSink(),
    this.clock = const SystemClock(),
  });

  /// 编排端口。
  final RestoreOrchestrationPort port;

  /// 诊断记录（只记类别与阶段，不记路径与内容）。
  final DiagnosticSink diagnostics;

  /// 时钟（标记的时刻；不参与任何判定）。
  final Clock clock;

  /// 记下一次「已恢复到新目录、等重启切换」。
  ///
  /// 由 T046 的恢复成功路径调用。之所以是**独立一步**而不是让恢复用例自己写标记：标记的字段
  /// 与语义属于编排（阶段机），而恢复用例只该知道「写到哪里、写什么版本」。
  Future<Result<void>> markPendingRestart({
    required String restoredDirectory,
    int? schemaVersion,
  }) async {
    final Result<void> written = await port.writeMarker(
      RestoreMarker(
        phase: RestorePhase.pendingRestart,
        restoredDirectory: restoredDirectory,
        restoredAt: clock.now().toUtc(),
        schemaVersion: schemaVersion,
      ),
    );
    if (written.isOk) {
      diagnostics.info(
        '恢复已就绪，等待重启切换（阶段 pendingRestart）',
        tag: 'restore.marker',
      );
    }
    return written;
  }

  /// 读当前编排状态（界面展示；**不做任何变更**）。
  Future<Result<RestoreOrchestrationState>> readState() async {
    final Result<RestoreMarker?> read = await port.readMarker();
    if (read.isErr) {
      return Err<RestoreOrchestrationState>(read.errorOrNull!);
    }
    final RestoreMarker? marker = read.valueOrNull;
    if (marker == null) {
      return const Ok<RestoreOrchestrationState>(
        RestoreOrchestrationState.idle,
      );
    }
    return Ok<RestoreOrchestrationState>(
      RestoreOrchestrationState(
        phase: marker.phase,
        restoredDirectory: marker.restoredDirectory,
        supersededDirectory: marker.supersededDirectory,
        restoredAt: marker.restoredAt,
      ),
    );
  }

  /// 启动时执行编排（bootstrap 在打开数据库**之前**调用）。
  ///
  /// 返回实际发生的动作，供启动路径决定「这一轮用的是哪个数据目录」并如实告知用户。
  ///
  /// 顺序之所以重要：这一步必须在打开数据库之前完成，否则应用会先打开**旧**库（把连接建在
  /// 旧目录上），而接下来的切换在中途失败——那时数据库已经在使用一个正在被搬动的文件。
  Future<Result<RestoreAction>> runOnStartup() async {
    final Result<RestoreMarker?> read = await port.readMarker();
    if (read.isErr) {
      return Err<RestoreAction>(read.errorOrNull!);
    }
    final RestoreMarker? marker = read.valueOrNull;
    final String? current = port.currentDataDirectoryPath;
    if (marker == null) {
      return const Ok<RestoreAction>(RestoreAction.nothingToDo);
    }
    if (current == null) {
      // 数据目录不可解析：这一轮什么都不能做。**不清标记**——下一次能解析出目录时还要处理它。
      diagnostics.warning('数据目录不可用，本次启动跳过恢复编排', tag: 'restore');
      return const Ok<RestoreAction>(RestoreAction.nothingToDo);
    }

    final bool restoredExists = await port.directoryExists(
      marker.restoredDirectory,
    );
    final bool usable = restoredExists
        ? await port.databaseUsable(marker.restoredDirectory)
        : false;
    final RestoreAction action = decideRestoreAction(
      marker: marker,
      currentDataDirectory: current,
      restoredDirectoryExists: restoredExists,
      restoredDatabaseUsable: usable,
    );
    switch (action) {
      case RestoreAction.nothingToDo:
        // `cleaned` 残留标记在这里被清掉（没有待办事项）；`pendingRestart` 但恢复目录就是当前
        // 目录时也走这里。两种都不该让用户再看到一条恢复提示。
        await port.clearMarker();
        return const Ok<RestoreAction>(RestoreAction.nothingToDo);
      case RestoreAction.awaitCleanupConfirmation:
        return const Ok<RestoreAction>(RestoreAction.awaitCleanupConfirmation);
      case RestoreAction.dropMarkerAndReport:
        // 恢复目录不可用：丢弃标记并**保持当前数据目录不变**。这是唯一会清标记的失败分支——
        // 留着它会让每次启动都重复报告同一个已经无法完成的任务。
        final String reason = !restoredExists
            ? RestoreFailureKind.restoredDirectoryMissing
            : RestoreFailureKind.restoredDatabaseUnusable;
        await port.clearMarker();
        diagnostics.error('恢复目标不可用，已丢弃标记：$reason', tag: 'restore');
        return const Ok<RestoreAction>(RestoreAction.dropMarkerAndReport);
      case RestoreAction.switchToRestored:
        final Result<RestoreSwitchOutcome> switched = await _switch(
          marker: marker,
          current: current,
        );
        if (switched.isErr) {
          return Err<RestoreAction>(switched.errorOrNull!);
        }
        return const Ok<RestoreAction>(RestoreAction.switchToRestored);
    }
  }

  /// 执行切换：停放旧目录 → 启用新目录；第 2 步失败则**搬回来**。
  ///
  /// 为什么用「停放 + 启用」而不是「删除旧目录 + 改名」：改名失败时旧目录还在（可回退）；
  /// 而删除不可撤销。停放目录的名字与数据目录并列并带 `superseded` 标记，因此人工排查时一眼
  /// 能看出它的身份。
  Future<Result<RestoreSwitchOutcome>> _switch({
    required RestoreMarker marker,
    required String current,
  }) async {
    final String parked = port.newParkedDirectoryName(
      clock.now().toUtc().millisecondsSinceEpoch.toString(),
    );
    final Result<void> park = await port.moveDirectory(
      from: current,
      to: parked,
    );
    if (park.isErr) {
      diagnostics.error(
        '恢复切换失败（停放旧目录）：${park.errorOrNull!.kind}',
        tag: 'restore',
      );
      return const Ok<RestoreSwitchOutcome>(RestoreSwitchOutcome.rolledBack);
    }
    final Result<void> activate = await port.moveDirectory(
      from: marker.restoredDirectory,
      to: current,
    );
    if (activate.isOk) {
      await port.writeMarker(
        marker.copyWith(
          phase: RestorePhase.switched,
          supersededDirectory: parked,
        ),
      );
      diagnostics.info('恢复切换完成（阶段 switched）', tag: 'restore');
      return const Ok<RestoreSwitchOutcome>(RestoreSwitchOutcome.switched);
    }

    // 启用失败：把旧目录搬回原位。这一步失败意味着数据目录停在停放位置，必须**明确报告**
    // （静默留下会让用户下次启动看到「什么都没有」而不知道去哪里找）。
    final Result<void> rollback = await port.moveDirectory(
      from: parked,
      to: current,
    );
    if (rollback.isErr) {
      diagnostics.error(
        '恢复切换失败且回退失败：${RestoreFailureKind.rollbackFailed}',
        tag: 'restore',
      );
      return Err<RestoreSwitchOutcome>(
        StorageError(
          operation: 'restore.switch',
          detail: RestoreFailureKind.rollbackFailed,
          cause: rollback.errorOrNull,
        ),
      );
    }
    // 回退成功：标记保持 pendingRestart（下次启动可重试），并留一条诊断。
    diagnostics.error(
      '恢复切换失败，已回退到原数据目录：${activate.errorOrNull!.kind}',
      tag: 'restore',
    );
    return const Ok<RestoreSwitchOutcome>(RestoreSwitchOutcome.rolledBack);
  }

  /// 完成清理：删除被顶替的旧目录并清标记。
  ///
  /// 只有 `switched` 阶段可调用（其它阶段没有「被顶替的目录」这个概念）。返回 `Ok(null)` 表示
  /// 「当前阶段不需要清理」，而不是失败。
  Future<Result<String?>> completeCleanup() async {
    final Result<RestoreMarker?> read = await port.readMarker();
    if (read.isErr) {
      return Err<String?>(read.errorOrNull!);
    }
    final RestoreMarker? marker = read.valueOrNull;
    if (marker == null || marker.phase != RestorePhase.switched) {
      return const Ok<String?>(null);
    }
    final String? superseded = marker.supersededDirectory;
    if (superseded == null) {
      // 阶段是 switched 但没有停放目录：这是一个内部不一致的标记（不该由本用例产生）。
      // 丢掉标记而不是编一个要删的路径——猜错路径会把用户的数据删掉。
      await port.clearMarker();
      return const Ok<String?>(null);
    }
    final Result<void> deleted = await port.deleteDirectory(superseded);
    if (deleted.isErr) {
      // 删不掉（被占用、权限）时**保留标记**：用户还能在下一次尝试里完成清理，
      // 而丢掉标记会让那个旧目录变成一个没有任何线索的孤儿（占着磁盘且用户不知道它是什么）。
      return Err<String?>(deleted.errorOrNull!);
    }
    await port.writeMarker(marker.copyWith(phase: RestorePhase.cleaned));
    await port.clearMarker();
    diagnostics.info('旧数据目录已清理（阶段 cleaned）', tag: 'restore');
    return Ok<String?>(superseded);
  }

  /// 放弃这次恢复（用户决定不切了）。
  ///
  /// 只清标记，**不删**恢复出来的目录：那个目录里是一份完整可用的数据，删它是破坏性动作，
  /// 应当由用户在文件系统里自己做，或走一次显式的清理确认。
  Future<Result<void>> abandon() async {
    final Result<void> cleared = await port.clearMarker();
    if (cleared.isOk) {
      diagnostics.info('用户放弃了这次恢复（标记已清，恢复目录保留）', tag: 'restore');
    }
    return cleared;
  }
}
