// 快照发布编排（T042；架构 5.2 的条件发布协议）。
//
// 流程（架构原话的顺序，逐步对应）：
//   1) 读远端 manifest 与它的 ETag（共同基线的入口）；
//   2) 上传**不可变快照**（内容哈希命名，已存在则跳过）；
//   3) **读回校验哈希**；
//   4) **条件写** manifest（If-Match 用步骤 1 的 ETag）；
//   5) 412 → 重读 manifest 重试（≤ 3 轮）；
//   6) 成功 → 返回结论让上层在**本地事务**里确认。
//
// 三条边界：
//   * **不发网络请求进数据库事务**（架构 5.2）——本文件完全不碰数据库；
//   * **上传中断留孤儿快照**：快照已 PUT 但 manifest 未更新时返回 orphanSnapshot，
//     远端当前版本仍是 manifest 指向的那一版（[isCurrentSnapshot] 的判据）；
//   * **服务器不支持条件写就不写**：降级只读拉取，不开启不安全多端覆盖。
library;

import 'dart:convert';

import 'package:flux/core/core.dart';

import 'webdav_client.dart';

/// 快照发布的依赖（便于用内存服务器替换）。
final class SnapshotPublisher {
  /// 构造发布器。
  const SnapshotPublisher({
    required this.client,
    required this.username,
    required this.password,
  });

  /// WebDAV 客户端。
  final WebDavClient client;

  /// 用户名（SET-070；非秘密，可落库）。
  final String username;

  /// 密码（SET-071；调用方在**本次调用期间**从 Keychain 取出，本类不持有、不缓存、
  /// 不落库）。
  final String password;

  /// 读远端 manifest 及其 ETag；远端还没有 manifest 时返回 (null, null)。
  Future<Result<({SyncManifest? manifest, String? etag})>> readManifest(
    Uri manifestUrl,
  ) async {
    final WebDavResponse response = await client.get(
      manifestUrl,
      username: username,
      password: password,
    );
    if (response.status == WebDavStatus.notFound) {
      // 远端还没有当前版本：这是首次发布的正常状态，**不是失败**。
      return const Ok<({SyncManifest? manifest, String? etag})>((
        manifest: null,
        etag: null,
      ));
    }
    if (!response.isOk) {
      return Err<({SyncManifest? manifest, String? etag})>(
        _statusError(response, 'sync.readManifest'),
      );
    }
    final String? text = response.bodyText;
    final SyncManifest? manifest = text == null
        ? null
        : SyncManifest.decode(text);
    if (manifest == null) {
      // 远端有一个 manifest 但读不懂（被别的版本写过、或损坏）：明确失败而不是
      // 当作「没有当前版本」——后者会让本机**覆盖**掉一份看不懂的当前版本。
      return Err<({SyncManifest? manifest, String? etag})>(
        StorageError(
          operation: 'sync.readManifest',
          detail: '远端 manifest 无法解析（可能是更新版本写入的协议）',
        ),
      );
    }
    return Ok<({SyncManifest? manifest, String? etag})>((
      manifest: manifest,
      etag: response.etag,
    ));
  }

  /// 上传不可变快照（已存在则跳过，幂等）。
  ///
  /// 先 PROPFIND 判断同名快照是否已在：快照是内容寻址的，**同一个名字必然同一个内容**，
  /// 因此重传没有任何意义（只是白传一次可能很大的正文）。
  Future<Result<WebDavStatus>> putSnapshot(
    Uri snapshotUrl, {
    required String contentHash,
    required List<int> bytes,
  }) async {
    final WebDavResponse probe = await client.propfind(
      snapshotUrl,
      username: username,
      password: password,
      depth: 0,
    );
    if (probe.isOk) {
      return const Ok<WebDavStatus>(WebDavStatus.ok);
    }
    if (probe.status != WebDavStatus.notFound &&
        probe.status != WebDavStatus.failed) {
      return Err<WebDavStatus>(_statusError(probe, 'sync.probeSnapshot'));
    }
    final WebDavResponse put = await client.put(
      snapshotUrl,
      username: username,
      password: password,
      bytes: bytes,
      // 快照**不加** If-Match：它是内容寻址的不可变对象，并发写同一个名字必然写同样的
      // 字节。要求前提条件反而会让两台设备同时上传同一快照时其中一台莫名失败。
    );
    if (!put.isOk) {
      return Err<WebDavStatus>(_statusError(put, 'sync.putSnapshot'));
    }
    // 读回校验：**唯一**能证明「远端真的存在这份内容」的手段（PUT 返回 2xx 只说明它
    // 接受了请求）。哈希不一致时明确失败，绝不继续去写 manifest 指向一份错内容。
    final WebDavResponse readBack = await client.get(
      snapshotUrl,
      username: username,
      password: password,
    );
    if (!readBack.isOk) {
      return Err<WebDavStatus>(_statusError(readBack, 'sync.readBackSnapshot'));
    }
    final List<int>? remote = readBack.bodyBytes;
    if (remote == null) {
      return Err<WebDavStatus>(
        StorageError(operation: 'sync.readBackSnapshot', detail: '读回的快照为空'),
      );
    }
    final String remoteHash = snapshotContentHash(remote);
    if (remoteHash != contentHash.toLowerCase()) {
      return Err<WebDavStatus>(
        ValidationError(field: 'snapshotHash', reason: '读回校验失败：远端哈希与本地不一致'),
      );
    }
    return const Ok<WebDavStatus>(WebDavStatus.ok);
  }

  /// 条件写 manifest（[ifMatch] 为 null 时用 If-Match: * 表达「必须不存在」）。
  Future<WebDavResponse> putManifest(
    Uri manifestUrl, {
    required SyncManifest manifest,
    String? ifMatch,
  }) => client.put(
    manifestUrl,
    username: username,
    password: password,
    bytes: utf8.encode(manifest.encode()),
    ifMatch: ifMatch ?? '*',
  );

  /// 走完整条发布流程（含 412 重试）。
  ///
  /// [buildSnapshot] 在每一轮重试时被重新调用：冲突重试意味着要基于**新读到的**父版本
  /// 重新构造内容（T043 的合并会在这里接上）。本任务只做单机语义，因此默认实现直接返回
  /// 同一份字节，但接口形状已经允许「重试时内容不同」。
  Future<Result<SnapshotPublishOutcome>> publish({
    required Uri manifestUrl,
    required Uri Function(String snapshotName) snapshotUrlFor,
    required List<int> Function(SyncManifest? parent) buildSnapshot,
    required String deviceName,
    required int revision,
    required DateTime publishedAt,
    required WebDavWriteCapability capability,
  }) async {
    // 服务器不支持条件写：**一个字节都不写**。这是架构 5.2 的降级口径（只读拉取或
    // 显式导入导出），在这里表现为「根本没进入写入路径」。
    if (capability != WebDavWriteCapability.conditionalWrite) {
      return const Ok<SnapshotPublishOutcome>(
        SnapshotPublishOutcome(
          status: SnapshotPublishStatus.degradedReadOnly,
          attempts: 0,
          reason: 'conditionalWriteUnsupported',
        ),
      );
    }

    for (int attempt = 1; attempt <= manifestConflictRetryLimit; attempt++) {
      final Result<({SyncManifest? manifest, String? etag})> current =
          await readManifest(manifestUrl);
      if (current.isErr) {
        return Ok<SnapshotPublishOutcome>(
          SnapshotPublishOutcome(
            status: SnapshotPublishStatus.failed,
            attempts: attempt,
            reason: current.errorOrNull!.kind,
          ),
        );
      }
      final SyncManifest? parent = current.unwrap().manifest;
      final String? parentEtag = current.unwrap().etag;

      final List<int> bytes = buildSnapshot(parent);
      final String hash = snapshotContentHash(bytes);
      final SyncManifest next = SyncManifest.forSnapshot(
        snapshotHash: hash,
        deviceName: deviceName,
        revision: revision,
        publishedAt: publishedAt,
        parentVersion: parent?.version,
      );

      final Result<WebDavStatus> uploaded = await putSnapshot(
        snapshotUrlFor(next.snapshotName),
        contentHash: hash,
        bytes: bytes,
      );
      if (uploaded.isErr) {
        return Ok<SnapshotPublishOutcome>(
          SnapshotPublishOutcome(
            status: SnapshotPublishStatus.failed,
            attempts: attempt,
            reason: uploaded.errorOrNull!.kind,
          ),
        );
      }

      final WebDavResponse written = await putManifest(
        manifestUrl,
        manifest: next,
        ifMatch: parentEtag,
      );
      if (written.status == WebDavStatus.conflict) {
        // 412：别的设备在我们上传期间发布了新版本。重读 manifest 再来一轮
        // （**不**做「先删后写」那种绕过条件写的动作：那正好是架构禁止的覆盖）。
        if (attempt == manifestConflictRetryLimit) {
          return Ok<SnapshotPublishOutcome>(
            SnapshotPublishOutcome(
              status: SnapshotPublishStatus.conflictExhausted,
              attempts: attempt,
              reason: 'manifestConflict',
            ),
          );
        }
        continue;
      }
      if (!written.isOk) {
        // 快照在远端、manifest 没更新：这是**孤儿快照**（无害，不是当前版本）。
        // 本机状态不变，下次同步会重新走一遍；T047 负责清理孤儿。
        return Ok<SnapshotPublishOutcome>(
          SnapshotPublishOutcome(
            status: SnapshotPublishStatus.orphanSnapshot,
            attempts: attempt,
            reason: written.reason,
          ),
        );
      }

      // 读回校验 manifest：只有在「读回的哈希与本地一致、且版本指向这次快照」时才
      // 允许上层做本地确认（架构 5.2「上传唯一快照并读回校验→以条件写更新 manifest
      // →本地事务确认成功」）。
      final Result<({SyncManifest? manifest, String? etag})> verified =
          await readManifest(manifestUrl);
      if (verified.isErr) {
        return Ok<SnapshotPublishOutcome>(
          SnapshotPublishOutcome(
            status: SnapshotPublishStatus.orphanSnapshot,
            attempts: attempt,
            reason: verified.errorOrNull!.kind,
          ),
        );
      }
      final SyncManifest? confirmed = verified.unwrap().manifest;
      if (!canConfirmPublish(
        localHash: hash,
        readBackHash: hash,
        readBackManifest: confirmed,
      )) {
        return Ok<SnapshotPublishOutcome>(
          SnapshotPublishOutcome(
            status: SnapshotPublishStatus.orphanSnapshot,
            attempts: attempt,
            reason: 'manifestVerifyFailed',
          ),
        );
      }
      return Ok<SnapshotPublishOutcome>(
        SnapshotPublishOutcome(
          status: SnapshotPublishStatus.published,
          attempts: attempt,
          manifest: confirmed,
        ),
      );
    }

    // 循环必然在上面 return（attempt == limit 时返回 conflictExhausted），
    // 这一行是给编译器的兜底。
    return const Ok<SnapshotPublishOutcome>(
      SnapshotPublishOutcome(
        status: SnapshotPublishStatus.conflictExhausted,
        attempts: manifestConflictRetryLimit,
        reason: 'manifestConflict',
      ),
    );
  }

  static AppError _statusError(WebDavResponse response, String operation) {
    if (response.status == WebDavStatus.unauthorized) {
      return AuthError(
        provider: 'webdav',
        statusCode: response.httpStatus,
        detail: '认证失败：请检查用户名与密码（SET-070/071）',
      );
    }
    if (response.httpStatus == null) {
      return NetworkError(uri: '', reason: response.reason ?? 'WebDAV 请求失败');
    }
    // 错误消息里**不含 URL 与凭据**：reason 是结构性标识，httpStatus 是数字。
    return NetworkError(
      uri: '',
      statusCode: response.httpStatus,
      reason: response.reason ?? operation,
    );
  }
}
