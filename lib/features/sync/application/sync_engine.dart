// 同步引擎（T043；架构 5.2 的「下载共同基线→三方比较→在本机暂存合并结果→上传唯一快照并
// 读回校验→以条件写更新 manifest→本地事务确认成功」，以及 412 重读重合并 ≤3 轮）。
//
// 本文件是**编排**：它把 T041 的协议状态、T041 的本机内容、T042 的传输与 T043 的纯合并规则
// 串成一次同步。它自己不做协议动作（那是传输端口）也不做合并判定（那是纯函数）。
//
// 六条刻意的设计，每一条对应架构原话：
//
//   1) **网络不在数据库事务里**：读快照、上传、条件写都不持有事务；只有一个短事务在最后
//      写回本机内容并确认修订（[SyncLocalStore.applyMergedSnapshot]）。
//   2) **确认按修订号上界**：本轮开始时固定 `confirmedRevision`，上传期间新产生的本地改动
//      （修订号更大）不在清除范围内，因此它们保留为下一轮待同步——「上传期间的新修改不丢失」
//      是一条可断言的规则，而不是「希望用户别在这时候改」。
//   3) **412 → 重读 → 重合并 → 重试 ≤3 轮**：每次重试都基于**新读到的**父版本重新合并，
//      因此第二次尝试发布的是「基于新基线的合并结果」，不是把同一份内容硬塞进去。
//      用尽 3 轮则返回 waitingRetry，不改本机基线、也不动远端 manifest。
//   4) **远端发布成功但本机未确认 → 幂等恢复**：重启后若发现远端当前版本**就是**本机当前
//      内容的那一版（版本号由内容哈希派生，因此这是精确判据），则只补一次本机确认，
//      **不重复上传**（[SyncRunResult.recoveredWithoutUpload]）。
//   5) **降级服务器只读**：能力不是 conditionalWrite 时**一个字节都不写**，只把远端的
//      当前快照读下来供显式导入（架构 5.2「降级为只读拉取或显式快照导入/导出，不开启
//      不安全多端自动覆盖」）。
//   6) **破坏性远端删除不自动应用**：远端提出的删除只登记为待确认项返回给界面
//      （架构 5.2「未批准不自动清除本地内容，保留待处理冲突」），合并结果里也不包含那些
//      被删除的实体——否则本机会用一次上传推翻远端的删除。
library;

import 'dart:convert';

import 'package:flux/core/core.dart';

/// 一次同步的结论类别。
enum SyncRunStatus {
  /// 发布成功并已在本机确认（或无事可做）。
  succeeded,

  /// 有同字段并发冲突：**尚未发布**，等待用户选版（T044 的冲突界面）。
  waitingConflictChoice,

  /// manifest 条件写冲突用尽 3 轮，或远端已发布而本机未确认：等待下一轮重试。
  waitingRetry,

  /// 服务器不支持条件写：只读拉取，**没有写入任何远端内容**。
  readonlyPull,

  /// 失败（网络/认证/解析/校验）。
  failed,
}

/// 一次同步的结果。
final class SyncRunResult {
  /// 构造结果。
  const SyncRunResult({
    required this.status,
    required this.attempts,
    required this.confirmedRevision,
    this.publishedVersion,
    this.merged,
    this.conflicts = const <SyncMergeConflict>[],
    this.pendingRemoteDeletions = const <SyncDeletion>[],
    this.preservedLocalFields = const <String>[],
    this.appliedCount = 0,
    this.recoveredWithoutUpload = false,
    this.pulledSnapshot,
    this.reason,
  });

  /// 结论。
  final SyncRunStatus status;

  /// 条件写实际尝试的轮数。
  final int attempts;

  /// 本轮固定的本地修订号上界（上传期间产生的新改动不在此范围内，因此不会被清除）。
  final int confirmedRevision;

  /// 发布成功的版本（快照哈希派生）。
  final String? publishedVersion;

  /// 合并后的快照（发布成功或等待选版时都有值）。
  final SyncSnapshot? merged;

  /// 同字段并发冲突（等待选版时非空）。
  final List<SyncMergeConflict> conflicts;

  /// 远端提出、本机未确认的破坏性删除（**尚未应用**）。
  final List<SyncDeletion> pendingRemoteDeletions;

  /// 因上传期间又有本地改动而被保留的字段（`kind/key/field` 三段列表）。
  final List<String> preservedLocalFields;

  /// 写回本机的字段数。
  final int appliedCount;

  /// 本轮是否只做了「补确认」而没有重复上传（崩溃恢复的幂等路径）。
  final bool recoveredWithoutUpload;

  /// 只读拉取时读到的远端快照（供显式导入预览）。
  final SyncSnapshot? pulledSnapshot;

  /// 失败原因的结构性标识（不含地址与凭据）。
  final String? reason;

  /// 是否成功。
  bool get isSuccess => status == SyncRunStatus.succeeded;

  /// 是否有待用户处理的事情（选版 / 破坏性删除确认）。
  bool get needsUserAction =>
      status == SyncRunStatus.waitingConflictChoice ||
      pendingRemoteDeletions.isNotEmpty;
}

/// 同步引擎。
final class SyncEngine {
  /// 构造引擎。
  const SyncEngine({
    required this.state,
    required this.content,
    required this.transport,
    required this.remoteRoot,
    required this.deviceName,
    required this.clock,
  });

  /// 协议状态（基线/待同步变更/墓碑；T041）。
  final SyncStore state;

  /// 本机内容快照的读写（T043）。
  final SyncLocalStore content;

  /// 传输端口（T043 端口 + T042 客户端实现）。
  final SyncTransport transport;

  /// 远端目录 URL（SET-070 的 `flux-v1`）。
  final Uri remoteRoot;

  /// 本机设备名（SET-070；写进 manifest 仅作展示）。
  final String deviceName;

  /// 时钟（只在「记录成功时刻」与诊断里用；**不参与合并判定**）。
  final Clock clock;

  /// manifest 的 URL。
  Uri get manifestUrl => _child(remoteRoot, syncManifestFileName);

  /// 某个快照文件名的 URL。
  Uri snapshotUrl(String name) => _child(remoteRoot, name);

  /// 只读远端当前快照（**不发任何写请求**）。
  ///
  /// 首次合并预览（T044）要用它：预览必须能做到「只看不动」——把「读远端」做成引擎上的
  /// 一个独立动作，预览路径就不可能顺手写点什么；而它复用 [ _readRemote ] 的全部读取规则
  /// （manifest 读不懂则明确失败、快照解析失败则失败），不会出现第二套读取语义。
  Future<Result<SyncSnapshot?>> readRemoteSnapshotOnly() async {
    final Result<RemoteState> remote = await _readRemote();
    if (remote.isErr) {
      return Err<SyncSnapshot?>(remote.errorOrNull!);
    }
    return Ok<SyncSnapshot?>(remote.unwrap().snapshot);
  }

  /// 执行一次同步。
  ///
  /// [capability] 来自 T042 的能力探测结论：不是 `conditionalWrite` 时本方法只读远端
  /// 快照，绝不写（降级路径）。
  /// [conflictPolicy] 与 [choices] 决定同字段并发冲突如何落地；[choices] 非空表示用户
  /// 已经选版（T044 的冲突界面回填）。
  Future<SyncRunResult> run({
    required WebDavWriteCapability capability,
    SyncConflictPolicy conflictPolicy = SyncConflictPolicy.manual,
    Map<String, SyncConflictChoice> choices =
        const <String, SyncConflictChoice>{},
  }) async {
    final Result<SyncBaseline> baselineRead = await state.readBaseline();
    if (baselineRead.isErr) {
      return _failed(baselineRead.errorOrNull!.kind, confirmedRevision: 0);
    }
    final SyncBaseline baseline = baselineRead.unwrap();

    // **本轮固定的修订号上界**：上传期间产生的新改动会拿到更大的修订号，因此不在
    // 确认范围内（架构 5.2「提交结果仅确认已包含的修订」）。
    final int confirmedRevision = baseline.localRevision;

    final Result<SyncSnapshot> localRead = await content.readLocalSnapshot();
    if (localRead.isErr) {
      return _failed(
        localRead.errorOrNull!.kind,
        confirmedRevision: confirmedRevision,
      );
    }
    final SyncSnapshot local = localRead.unwrap();

    final Result<RemoteState> remoteRead = await _readRemote();
    if (remoteRead.isErr) {
      return _failed(
        remoteRead.errorOrNull!.kind,
        confirmedRevision: confirmedRevision,
      );
    }
    RemoteState remote = remoteRead.unwrap();

    // 降级：只读拉取，一个字节都不写（能力未探测同样 fail-closed）。
    if (capability != WebDavWriteCapability.conditionalWrite) {
      return SyncRunResult(
        status: SyncRunStatus.readonlyPull,
        attempts: 0,
        confirmedRevision: confirmedRevision,
        pulledSnapshot: remote.snapshot,
        pendingRemoteDeletions: _pendingDeletionsFrom(remote, local),
        reason: 'conditionalWriteUnsupported',
      );
    }

    // **崩溃恢复的幂等入口**：远端当前版本的内容哈希与本机当前内容一致时，说明
    // 「远端发布成功但本机未确认」这件事已经发生过。此时只补一次本机确认，不重复上传。
    if (_alreadyPublished(baseline: baseline, remote: remote, local: local)) {
      final Result<SyncApplyOutcome> applied = await content
          .applyMergedSnapshot(
            merged: _withoutRemotelyDeleted(local, remote),
            confirmedRevision: confirmedRevision,
            baseVersion: remote.manifest!.version,
            syncedAt: clock.now().toUtc(),
          );
      if (applied.isErr) {
        return _failed(
          applied.errorOrNull!.kind,
          confirmedRevision: confirmedRevision,
        );
      }
      return SyncRunResult(
        status: SyncRunStatus.succeeded,
        attempts: 0,
        confirmedRevision: confirmedRevision,
        publishedVersion: remote.manifest!.version,
        merged: local,
        appliedCount: applied.unwrap().appliedCount,
        preservedLocalFields: applied.unwrap().preservedLocalFields,
        recoveredWithoutUpload: true,
        pendingRemoteDeletions: _pendingDeletionsFrom(remote, local),
        reason: 'alreadyPublished',
      );
    }

    SyncSnapshot base = SyncSnapshot.empty;
    final String? baseVersion = baseline.baseVersion;
    if (baseVersion != null) {
      final Result<SyncSnapshot?> baseRead = await _readSnapshotForVersion(
        baseVersion,
      );
      if (baseRead.isErr) {
        return _failed(
          baseRead.errorOrNull!.kind,
          confirmedRevision: confirmedRevision,
        );
      }
      // 找不到本机记录的基线快照（被清理）时退到远端 manifest 的父版本链，
      // 仍然找不到才按空基线合并——**绝不**假装有共同基线。
      base = baseRead.unwrap() ?? remote.baseSnapshot ?? SyncSnapshot.empty;
    } else if (remote.baseSnapshot != null) {
      base = remote.baseSnapshot!;
    }

    SyncMergeResult merge = threeWayMerge(
      base: base,
      local: local,
      remote: remote.snapshot ?? SyncSnapshot.empty,
      policy: conflictPolicy,
      choices: choices,
    );

    // manual 策略下**先不发布**：把冲突列出来等用户选版，本机内容、远端与本机基线都不动，
    // 因此用户的选择不会与一次已经发生的上传错位（架构 5.2「用户选择后形成新版本」）。
    if (merge.hasConflicts &&
        conflictPolicy == SyncConflictPolicy.manual &&
        choices.isEmpty) {
      return SyncRunResult(
        status: SyncRunStatus.waitingConflictChoice,
        attempts: 0,
        confirmedRevision: confirmedRevision,
        merged: merge.merged,
        conflicts: merge.conflicts,
        pendingRemoteDeletions: merge.pendingRemoteDeletions,
        reason: 'sameFieldConcurrentChange',
      );
    }

    SyncSnapshot toPublish = applyConflictPolicy(
      result: merge,
      policy: conflictPolicy,
    );
    int attempts = 0;

    for (attempts = 1; attempts <= manifestConflictRetryLimit; attempts++) {
      final List<int> bytes = utf8Encode(toPublish.encode());
      final String hash = snapshotContentHash(bytes);
      final SyncManifest next = SyncManifest.forSnapshot(
        snapshotHash: hash,
        deviceName: deviceName,
        revision: confirmedRevision,
        publishedAt: clock.now().toUtc(),
        parentVersion: remote.manifest?.version,
      );

      final Result<SyncTransportResponse> uploaded = await transport.write(
        snapshotUrl(next.snapshotName),
        bytes: bytes,
      );
      if (uploaded.isErr) {
        return _failed(
          uploaded.errorOrNull!.kind,
          confirmedRevision: confirmedRevision,
        );
      }
      final SyncTransportResponse uploadResponse = uploaded.unwrap();
      if (!uploadResponse.isOk &&
          uploadResponse.status != SyncTransportStatus.writeRejected) {
        // 非成功状态：明确失败（不把「没写成功」当成发布完成）。
        return _failed(
          uploadResponse.reason ?? uploadResponse.status.name,
          confirmedRevision: confirmedRevision,
        );
      }

      // 读回校验哈希：唯一能证明「远端真的存在这份内容」的手段。
      final Result<SyncTransportResponse> verified = await transport.read(
        snapshotUrl(next.snapshotName),
      );
      if (verified.isErr || !verified.unwrap().isOk) {
        return _failed(
          'snapshotReadBackFailed',
          confirmedRevision: confirmedRevision,
        );
      }
      final List<int>? readBack = verified.unwrap().bytes;
      if (readBack == null || snapshotContentHash(readBack) != hash) {
        return _failed(
          'snapshotHashMismatch',
          confirmedRevision: confirmedRevision,
        );
      }

      final Result<SyncTransportResponse> manifestWrite = await transport.write(
        manifestUrl,
        bytes: utf8Encode(next.encode()),
        // 首次发布用 If-Match: *（远端还没有当前版本）；之后用读到的 ETag。
        ifMatch: remote.manifestEtag ?? '*',
      );
      if (manifestWrite.isErr) {
        return _failed(
          manifestWrite.errorOrNull!.kind,
          confirmedRevision: confirmedRevision,
        );
      }
      final SyncTransportResponse manifestResponse = manifestWrite.unwrap();

      if (manifestResponse.status == SyncTransportStatus.conflict) {
        // 412：别的设备在我们上传期间发布了新版本。**重读 → 重合并 → 重试**，
        // 既不「先删后写」绕过条件写（那正是架构禁止的覆盖），也不把上一轮的内容硬塞进去。
        final Result<RemoteState> reread = await _readRemote();
        if (reread.isErr) {
          return _failed(
            reread.errorOrNull!.kind,
            confirmedRevision: confirmedRevision,
          );
        }
        remote = reread.unwrap();
        final SyncSnapshot remoteNow = remote.snapshot ?? SyncSnapshot.empty;
        if (!toPublish.sameContentAs(remoteNow)) {
          merge = threeWayMerge(
            base: base,
            local: local,
            remote: remoteNow,
            policy: conflictPolicy,
            choices: choices,
          );
          if (merge.hasConflicts && choices.isEmpty) {
            return SyncRunResult(
              status: SyncRunStatus.waitingConflictChoice,
              attempts: attempts,
              confirmedRevision: confirmedRevision,
              merged: merge.merged,
              conflicts: merge.conflicts,
              pendingRemoteDeletions: merge.pendingRemoteDeletions,
              reason: 'conflictAfterRetry',
            );
          }
          toPublish = applyConflictPolicy(
            result: merge,
            policy: conflictPolicy,
          );
        }
        continue;
      }

      if (!manifestResponse.isOk) {
        // 快照已在远端、manifest 未更新：**孤儿快照**（不是当前版本，无害）。
        // 本机不做确认，因此下一轮会重新走一遍，而远端当前版本仍是旧的那一版。
        return SyncRunResult(
          status: SyncRunStatus.waitingRetry,
          attempts: attempts,
          confirmedRevision: confirmedRevision,
          merged: toPublish,
          conflicts: merge.conflicts,
          pendingRemoteDeletions: merge.pendingRemoteDeletions,
          reason: 'orphanSnapshot',
        );
      }

      // 读回校验 manifest：只有「哈希一致 + 版本指向这次快照」才允许本机确认。
      final Result<RemoteState> confirmRead = await _readRemote();
      if (confirmRead.isErr) {
        return _failed(
          confirmRead.errorOrNull!.kind,
          confirmedRevision: confirmedRevision,
        );
      }
      final SyncManifest? confirmedManifest = confirmRead.unwrap().manifest;
      if (!canConfirmPublish(
        localHash: hash,
        readBackHash: hash,
        readBackManifest: confirmedManifest,
      )) {
        return SyncRunResult(
          status: SyncRunStatus.waitingRetry,
          attempts: attempts,
          confirmedRevision: confirmedRevision,
          merged: toPublish,
          conflicts: merge.conflicts,
          pendingRemoteDeletions: merge.pendingRemoteDeletions,
          reason: 'manifestVerifyFailed',
        );
      }

      // **本地事务确认**：写回内容 + 确认 ≤ confirmedRevision 的待同步变更。
      // 上传期间产生的新改动（修订号更大）不在范围内，因此仍留在待同步表里。
      final Result<SyncApplyOutcome> applied = await content
          .applyMergedSnapshot(
            merged: toPublish,
            confirmedRevision: confirmedRevision,
            baseVersion: confirmedManifest!.version,
            syncedAt: clock.now().toUtc(),
          );
      if (applied.isErr) {
        // 远端已发布、本机未确认：这正是「重启后按版本幂等补确认」要处理的状态，
        // 因此不改远端、也不谎称成功。
        return SyncRunResult(
          status: SyncRunStatus.waitingRetry,
          attempts: attempts,
          confirmedRevision: confirmedRevision,
          merged: toPublish,
          publishedVersion: confirmedManifest.version,
          conflicts: merge.conflicts,
          pendingRemoteDeletions: merge.pendingRemoteDeletions,
          reason: applied.errorOrNull!.kind,
        );
      }

      final SyncApplyOutcome outcome = applied.unwrap();
      return SyncRunResult(
        status: SyncRunStatus.succeeded,
        attempts: attempts,
        confirmedRevision: confirmedRevision,
        publishedVersion: confirmedManifest.version,
        merged: toPublish,
        conflicts: merge.conflicts,
        pendingRemoteDeletions: merge.pendingRemoteDeletions,
        appliedCount: outcome.appliedCount,
        preservedLocalFields: outcome.preservedLocalFields,
      );
    }

    // 3 轮用尽：远端与本机基线都不变，等下一轮。
    return SyncRunResult(
      status: SyncRunStatus.waitingRetry,
      attempts: manifestConflictRetryLimit,
      confirmedRevision: confirmedRevision,
      merged: toPublish,
      conflicts: merge.conflicts,
      pendingRemoteDeletions: merge.pendingRemoteDeletions,
      reason: 'manifestConflict',
    );
  }

  /// 读远端 manifest、它指向的快照，以及 manifest 父版本对应的快照（共同基线候选）。
  Future<Result<RemoteState>> _readRemote() async {
    final Result<SyncTransportResponse> manifestRead = await transport.read(
      manifestUrl,
    );
    if (manifestRead.isErr) {
      return Err<RemoteState>(manifestRead.errorOrNull!);
    }
    final SyncTransportResponse manifestResponse = manifestRead.unwrap();
    if (manifestResponse.status == SyncTransportStatus.notFound) {
      // 远端还没有当前版本：首次发布的正常状态（不是失败）。
      return const Ok<RemoteState>(
        RemoteState(manifest: null, manifestEtag: null, snapshot: null),
      );
    }
    if (!manifestResponse.isOk) {
      return Err<RemoteState>(
        NetworkError(
          uri: '',
          reason: manifestResponse.reason ?? manifestResponse.status.name,
          isRetryable: true,
        ),
      );
    }
    final List<int>? manifestBytes = manifestResponse.bytes;
    if (manifestBytes == null) {
      return Err<RemoteState>(
        StorageError(operation: 'sync.readManifest', detail: '响应体为空'),
      );
    }
    final SyncManifest? manifest = SyncManifest.decode(
      utf8Decode(manifestBytes),
    );
    if (manifest == null) {
      // 远端有一份读不懂的 manifest（更新版本写的、或损坏）：**明确失败**而不是
      // 当成「没有当前版本」——后者会让本机覆盖掉一份看不懂的版本。
      return Err<RemoteState>(
        ValidationError(field: 'syncManifest', reason: '远端 manifest 无法解析'),
      );
    }
    final Result<SyncSnapshot?> snapshotRead = await _readSnapshot(
      manifest.snapshotName,
    );
    if (snapshotRead.isErr) {
      return Err<RemoteState>(snapshotRead.errorOrNull!);
    }
    SyncSnapshot? baseSnapshot;
    final String? parentVersion = manifest.parentVersion;
    if (parentVersion != null) {
      final Result<SyncSnapshot?> baseRead = await _readSnapshotForVersion(
        parentVersion,
      );
      baseSnapshot = baseRead.valueOrNull;
    }
    return Ok<RemoteState>(
      RemoteState(
        manifest: manifest,
        manifestEtag: manifestResponse.etag,
        snapshot: snapshotRead.unwrap(),
        baseSnapshot: baseSnapshot,
      ),
    );
  }

  Future<Result<SyncSnapshot?>> _readSnapshot(String name) async {
    final Result<SyncTransportResponse> read = await transport.read(
      snapshotUrl(name),
    );
    if (read.isErr) {
      return Err<SyncSnapshot?>(read.errorOrNull!);
    }
    final SyncTransportResponse response = read.unwrap();
    if (response.status == SyncTransportStatus.notFound) {
      // manifest 指向一份不存在的快照（孤儿指针）：返回 null 而不是失败。上游会按
      // 「远端这一版没有内容」处理，而条件写仍会因父版本不符而失败，因此不会覆盖。
      return const Ok<SyncSnapshot?>(null);
    }
    if (!response.isOk) {
      return Err<SyncSnapshot?>(
        NetworkError(uri: '', reason: response.reason ?? response.status.name),
      );
    }
    final List<int>? bytes = response.bytes;
    if (bytes == null) {
      return const Ok<SyncSnapshot?>(null);
    }
    final SyncSnapshot? decoded = SyncSnapshot.decode(utf8Decode(bytes));
    if (decoded == null) {
      return Err<SyncSnapshot?>(
        ValidationError(field: 'syncSnapshot', reason: '远端快照无法解析'),
      );
    }
    return Ok<SyncSnapshot?>(decoded);
  }

  /// 按版本号找快照文件（内容寻址，因此版本 → 文件名是一次前缀匹配）。
  Future<Result<SyncSnapshot?>> _readSnapshotForVersion(String version) async {
    final Result<SyncTransportResponse> listing = await transport.listDirectory(
      remoteRoot,
    );
    if (listing.isErr) {
      return Err<SyncSnapshot?>(listing.errorOrNull!);
    }
    final SyncTransportResponse listed = listing.unwrap();
    if (!listed.isOk) {
      return const Ok<SyncSnapshot?>(null);
    }
    final String? name = snapshotNameForVersion(
      version: version,
      availableNames: listed.snapshotNames,
    );
    if (name == null) {
      return const Ok<SyncSnapshot?>(null);
    }
    return _readSnapshot(name);
  }

  /// 幂等判据：远端当前版本的内容哈希 == 本机当前内容。
  ///
  /// 为什么用**内容哈希**而不是「修订号或时间戳看起来一样」：版本号由内容哈希派生
  /// （T042），因此「哈希相等」严格等价于「远端那一版就是本机现在这一份内容」，
  /// 而修订号在另一台设备上是另一个序列、时间戳则完全不可比（架构 5.2 禁止比墙钟）。
  bool _alreadyPublished({
    required SyncBaseline baseline,
    required RemoteState remote,
    required SyncSnapshot local,
  }) {
    final SyncManifest? manifest = remote.manifest;
    if (manifest == null) {
      return false;
    }
    if (baseline.baseVersion != null &&
        baseline.baseVersion != manifest.version) {
      // 远端比本机记录的基线更新：不是「本机上次发布的那一版」，走正常合并。
      return false;
    }
    final String localHash = snapshotContentHash(utf8Encode(local.encode()));
    return localHash == manifest.snapshotHash;
  }

  SyncRunResult _failed(String reason, {required int confirmedRevision}) =>
      SyncRunResult(
        status: SyncRunStatus.failed,
        attempts: 0,
        confirmedRevision: confirmedRevision,
        reason: reason,
      );

  /// 只读拉取时，把远端墓碑里本机**确实有**的那些列成「待确认的破坏性删除」。
  List<SyncDeletion> _pendingDeletionsFrom(
    RemoteState remote,
    SyncSnapshot local,
  ) {
    final SyncSnapshot? snapshot = remote.snapshot;
    if (snapshot == null) {
      return const <SyncDeletion>[];
    }
    return snapshot.allDeletions
        .where(
          (SyncDeletion deletion) =>
              !local.hasDeletion(deletion.kind, deletion.key) &&
              local.hasEntity(deletion.kind, deletion.key),
        )
        .toList(growable: false);
  }

  /// 把远端墓碑对应的实体从本机快照里剔除（幂等确认路径上使用）。
  SyncSnapshot _withoutRemotelyDeleted(SyncSnapshot local, RemoteState remote) {
    final SyncSnapshot? snapshot = remote.snapshot;
    if (snapshot == null || snapshot.deletions.isEmpty) {
      return local;
    }
    final Map<String, Map<String, SyncEntity>> kept =
        <String, Map<String, SyncEntity>>{};
    for (final SyncEntity entity in local.allEntities) {
      if (snapshot.hasDeletion(entity.kind, entity.key)) {
        continue;
      }
      (kept[entity.kind] ??= <String, SyncEntity>{})[entity.key] = entity;
    }
    return SyncSnapshot(entities: kept, deletions: local.deletions);
  }
}

/// 远端的一版状态。
final class RemoteState {
  /// 构造状态。
  const RemoteState({
    required this.manifest,
    required this.manifestEtag,
    required this.snapshot,
    this.baseSnapshot,
  });

  /// 远端当前 manifest；远端还没有当前版本时为 null。
  final SyncManifest? manifest;

  /// manifest 的 ETag（条件写的前提条件）。
  final String? manifestEtag;

  /// manifest 指向的快照内容；读不到时为 null。
  final SyncSnapshot? snapshot;

  /// manifest 父版本对应的快照（能找到时；用于重试与首次合并）。
  final SyncSnapshot? baseSnapshot;
}

/// UTF-8 编码（快照字节的唯一来源，因此哈希与内容一一对应）。
List<int> utf8Encode(String text) => utf8.encode(text);

/// UTF-8 解码（对畸形字节宽容：快照非法由 JSON 解析层拒绝，不在这里崩）。
String utf8Decode(List<int> bytes) => utf8.decode(bytes, allowMalformed: true);

/// 在目录 URL 后拼接一个子路径（保留原路径的分段与编码）。
Uri _child(Uri base, String name) =>
    base.replace(pathSegments: <String>[...base.pathSegments, name]);
