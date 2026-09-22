// WebDAV 能力探测、不可变快照与共享 manifest 的**纯规则**（T042；架构 5.2）。
//
// 架构原话（逐条对应下面的实现）：
//   * 「多写入服务须验证强 ETag/If-Match 等条件发布能力」；
//   * 「协议使用不可变快照 + 共享 manifest：下载共同基线→三方比较→在本机暂存合并结果→
//     上传唯一快照并读回校验→以条件写更新 manifest→本地事务确认成功」；
//   * 「manifest 冲突重新读取/合并，最多 3 轮，之后等待重试」；
//   * 「上传中断的孤儿快照不是当前版本」；
//   * 「不具备可靠条件发布的服务器降级为只读拉取或显式快照导入/导出，不开启不安全多端
//     自动覆盖」。
//
// 为什么这些规则必须住在 core 且是纯函数：能力探测的判定（「这个服务器到底支不支持
// 条件写」）与「这次上传算不算成功」直接决定**要不要在另一台设备上覆盖数据**。把它们
// 藏进 HTTP 调用里，就只能靠一台真实 WebDAV 服务器才能验证；而本任务没有凭据，
// 真实服务器调用按手册 7.3 记 NOT_RUN。纯函数让协议规则本身可被逐条钉住。
library;

import 'dart:convert';

import '../digest/sha256.dart';

/// WebDAV 上路径的默认远端目录（SET-070：远端独立目录 flux-v1）。
const String defaultWebDavRemoteRoot = 'flux-v1';

/// manifest 文件名（与快照同目录，文件名固定因此可被条件写）。
const String syncManifestFileName = 'manifest.json';

/// 快照文件名前缀（内容哈希命名，因此同一个哈希永远指向同一个快照）。
const String syncSnapshotPrefix = 'snapshot-';

/// 能力探测结果（SET-070/072 与架构 5.2 的「降级只读拉取」开关）。
enum WebDavWriteCapability {
  /// 未探测（首次配置前的诚实状态）。
  unknown,

  /// 支持强 ETag 与 If-Match：允许多端条件写。
  conditionalWrite,

  /// 不支持可靠条件发布：**降级为只读拉取**，禁止多端自动覆盖。
  readOnlyPull,
}

/// 一次能力探测的输入事实（全部来自真实 HTTP 往返，由客户端收集）。
final class WebDavProbeFacts {
  /// 构造事实。
  const WebDavProbeFacts({
    required this.probePutOk,
    required this.firstEtag,
    required this.conditionalPutOk,
    required this.secondEtag,
    required this.staleIfMatchRejected,
  });

  /// 不带 If-Match 的首次 PUT 是否成功（服务器允许写）。
  final bool probePutOk;

  /// 首次 PUT 之后读回的 ETag；null 表示服务器不提供。
  final String? firstEtag;

  /// 带 If-Match（旧 ETag）的 PUT 是否成功。
  final bool conditionalPutOk;

  /// 条件写之后读回的 ETag（应当与 [firstEtag] 不同）。
  final String? secondEtag;

  /// 再用**已过期**的 ETag 写一次，服务器是否拒绝（412）。
  final bool staleIfMatchRejected;
}

/// 探测的判定结果。
final class WebDavProbeResult {
  /// 构造结果。
  const WebDavProbeResult({required this.capability, required this.reason});

  /// 能力结论。
  final WebDavWriteCapability capability;

  /// 结论的结构性原因标识（不含地址与凭据）。
  final String reason;

  /// 是否允许多端条件写。
  bool get allowsConditionalWrite =>
      capability == WebDavWriteCapability.conditionalWrite;
}

/// 由探测事实判定能力（架构 5.2「须验证强 ETag/If-Match」）。
///
/// 判定顺序与判据：
///   1) 连写都不成功 → 无所谓能力，直接降级（并要求先修配置）；
///   2) **服务器必须给出 ETag**：没有 ETag 就没有可用的前提条件，条件写在协议上无从
///      表达（不是「大致能用」）；
///   3) 带 If-Match 的写入必须成功，且写入后 ETag **必须变化**：不变说明服务器要么没
///      真的写、要么 ETag 不是内容摘要（弱 ETag/固定值），两种情况都会让「条件写」变成
///      「无条件覆盖」；
///   4) **必须拒绝过期 ETag**：这是唯一能证明服务器真的执行了条件判定的实验。少了这一步，
///      一台忽略 If-Match 的服务器会通过前三点检测，然后在多端并发时静默互相覆盖。
WebDavProbeResult evaluateConditionalWriteProbe(WebDavProbeFacts facts) {
  if (!facts.probePutOk) {
    return const WebDavProbeResult(
      capability: WebDavWriteCapability.readOnlyPull,
      reason: 'probePutFailed',
    );
  }
  final String? first = _nonEmpty(facts.firstEtag);
  if (first == null) {
    return const WebDavProbeResult(
      capability: WebDavWriteCapability.readOnlyPull,
      reason: 'noEtag',
    );
  }
  if (!facts.conditionalPutOk) {
    return const WebDavProbeResult(
      capability: WebDavWriteCapability.readOnlyPull,
      reason: 'ifMatchRejected',
    );
  }
  final String? second = _nonEmpty(facts.secondEtag);
  if (second == null || second == first) {
    return const WebDavProbeResult(
      capability: WebDavWriteCapability.readOnlyPull,
      reason: 'etagNotContentBased',
    );
  }
  if (!facts.staleIfMatchRejected) {
    return const WebDavProbeResult(
      capability: WebDavWriteCapability.readOnlyPull,
      reason: 'ifMatchNotEnforced',
    );
  }
  return const WebDavProbeResult(
    capability: WebDavWriteCapability.conditionalWrite,
    reason: 'verified',
  );
}

/// 由内容哈希生成快照文件名（**不可变**：同一内容永远得到同一个名字）。
///
/// 内容寻址而不是「时间戳命名」的原因：架构 5.2 要求快照不可变，而时间戳命名的文件
/// 内容可能变（重传同名文件会覆盖），于是「下载的基线」与「manifest 指向的版本」会
/// 在某个中间态上对不上。内容哈希命名让「名字就代表内容」这个等式成立。
String snapshotFileName(String contentHash) =>
    '$syncSnapshotPrefix${contentHash.toLowerCase()}.json';

/// 计算快照内容哈希（SHA-256 十六进制）。
String snapshotContentHash(List<int> bytes) => sha256Hex(bytes);

/// 共享 manifest：当前版本指针（架构 5.2）。
///
/// 字段刻意分成两类：
///   * **指针**（[snapshotName]/[snapshotHash]/[parentVersion]）：三方合并（T043）靠它们
///     找到共同基线与本次发布的内容；
///   * **元数据**（[revision]/[deviceName]/[publishedAt]）：只用于展示与诊断。
///     **不参与「谁更新」的判定**——架构 5.2 明确「不得……仅比较设备墙钟」，先后由
///     [parentVersion] 链与条件写冲突共同决定。
final class SyncManifest {
  /// 构造 manifest。
  const SyncManifest({
    required this.version,
    required this.snapshotName,
    required this.snapshotHash,
    required this.parentVersion,
    required this.revision,
    required this.deviceName,
    required this.publishedAt,
  });

  /// 本次发布的版本标识（等于 [snapshotHash] 的前 32 位，见 [versionForSnapshot]）。
  final String version;

  /// 快照文件名。
  final String snapshotName;

  /// 快照内容哈希（读回校验的依据）。
  final String snapshotHash;

  /// 父版本（上一版 manifest 的 [version]）；首次发布为 null。
  final String? parentVersion;

  /// 发布者当时的本地修订号（**只作诊断**，不用于判定先后）。
  final int revision;

  /// 发布者设备名（本机项，仅展示）。
  final String deviceName;

  /// 发布时刻（UTC；只作展示与诊断）。
  final DateTime publishedAt;

  /// 序列化为规范 JSON 文本（字段顺序固定，便于逐字比对与 diff）。
  String encode() =>
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'version': version,
        'snapshotName': snapshotName,
        'snapshotHash': snapshotHash,
        'parentVersion': parentVersion,
        'revision': revision,
        'deviceName': deviceName,
        'publishedAt': publishedAt.toUtc().toIso8601String(),
        'protocol': syncProtocolVersion,
      });

  /// 解析 manifest JSON。
  ///
  /// 任何字段缺失/类型不对都返回 null（调用方按「远端 manifest 不可用」处理），而不是
  /// 用默认值凑一个出来：一个凑出来的 manifest 会带着**不存在的父版本**，让三方合并把
  /// 两份无关的快照当成有共同基线（架构 5.2 明令禁止静默误合并）。
  static SyncManifest? decode(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    final Object? version = decoded['version'];
    final Object? snapshotName = decoded['snapshotName'];
    final Object? snapshotHash = decoded['snapshotHash'];
    final Object? revision = decoded['revision'];
    final Object? deviceName = decoded['deviceName'];
    final Object? publishedAt = decoded['publishedAt'];
    if (version is! String ||
        snapshotName is! String ||
        snapshotHash is! String ||
        revision is! int ||
        deviceName is! String ||
        publishedAt is! String) {
      return null;
    }
    final DateTime? parsedAt = DateTime.tryParse(publishedAt);
    if (parsedAt == null) {
      return null;
    }
    final Object? protocol = decoded['protocol'];
    if (protocol != null && protocol != syncProtocolVersion) {
      // 新协议写过的远端：旧客户端**不得**按自己的形状解读。返回 null 让上层提示
      // 「远端由更新版本写入」（架构 5.2「新 schema 阻写」，T043 细化）。
      return null;
    }
    final Object? parent = decoded['parentVersion'];
    if (parent != null && parent is! String) {
      return null;
    }
    return SyncManifest(
      version: version,
      snapshotName: snapshotName,
      snapshotHash: snapshotHash,
      parentVersion: parent as String?,
      revision: revision,
      deviceName: deviceName,
      publishedAt: parsedAt,
    );
  }

  /// 由父版本派生本次发布（快照哈希决定版本号）。
  static SyncManifest forSnapshot({
    required String snapshotHash,
    required String deviceName,
    required int revision,
    required DateTime publishedAt,
    String? parentVersion,
  }) => SyncManifest(
    version: versionForSnapshot(snapshotHash),
    snapshotName: snapshotFileName(snapshotHash),
    snapshotHash: snapshotHash,
    parentVersion: parentVersion,
    revision: revision,
    deviceName: deviceName,
    publishedAt: publishedAt,
  );
}

/// 同步协议的版本标识（写进 manifest，用于「新 schema 阻写」）。
const String syncProtocolVersion = 'flux-sync-1';

/// 由快照哈希派生版本标识（确定性：同一内容得到同一个版本号）。
///
/// 取哈希前 32 个字符（与文章同步键同样的截断长度）；哈希短于 32 字符时原样使用，
/// 而不是按固定位置截断——真实哈希总是 64 字符，但让函数对短输入也成立可以避免
/// 「只有真实调用才不崩」这种构造出来的脆弱点。
String versionForSnapshot(String snapshotHash) {
  final String hash = snapshotHash.toLowerCase();
  return 'v-${hash.length <= 32 ? hash : hash.substring(0, 32)}';
}

/// 条件写冲突的重试上限（架构 5.2「最多 3 轮，之后等待重试」）。
const int manifestConflictRetryLimit = 3;

/// 一次发布尝试的结论。
enum SnapshotPublishStatus {
  /// 发布成功（快照已读回校验、manifest 已条件写更新、本地可确认）。
  published,

  /// 冲突重试次数用尽：留待下一轮（不改远端，不覆盖）。
  conflictExhausted,

  /// 服务器不支持条件写：降级为只读拉取，**没有写入任何远端内容**。
  degradedReadOnly,

  /// 快照已上传但 manifest 更新失败：留下**孤儿快照**（无害，T047 清理）。
  orphanSnapshot,

  /// 失败（网络/认证/校验）。
  failed,
}

/// 一次发布尝试的结果。
final class SnapshotPublishOutcome {
  /// 构造结果。
  const SnapshotPublishOutcome({
    required this.status,
    required this.attempts,
    this.manifest,
    this.reason,
  });

  /// 结论。
  final SnapshotPublishStatus status;

  /// 实际尝试的条件写轮数。
  final int attempts;

  /// 成功发布时的 manifest。
  final SyncManifest? manifest;

  /// 失败原因的结构性标识（不含地址与凭据）。
  final String? reason;

  /// 远端当前版本是否发生了改变（只有 published 才为 true）。
  bool get advancedRemoteVersion => status == SnapshotPublishStatus.published;

  /// 是否留下了孤儿快照（无害；不是当前版本）。
  bool get leftOrphanSnapshot => status == SnapshotPublishStatus.orphanSnapshot;
}

/// 上传中断/半途失败之后，远端当前的**有效版本**仍然是 manifest 指向的那一版。
///
/// 这条纯函数的用途是让「孤儿快照无害」成为可断言的规则，而不是一句口头保证：
/// 快照列表里多出一个文件时，当前版本由 manifest 决定，任何名字不在 manifest 里的快照
/// 都不是当前版本（架构 5.2「上传中断的孤儿快照不是当前版本」）。
bool isCurrentSnapshot({
  required String snapshotName,
  required SyncManifest? currentManifest,
}) => currentManifest != null && currentManifest.snapshotName == snapshotName;

/// 从远端快照列表中挑出孤儿（不是当前版本、且父版本链上也不在）。
///
/// 判定需要的不只是当前 manifest：上一版仍可能被别的设备当作合并基线使用，因此**只把
/// 既不是当前版本、也没有被任何 manifest 引用的文件算作孤儿**这一点由调用方传入的
/// 已知引用集合表达（T047 的 GC 会传入更完整的引用集合；本任务只提供这条判据）。
List<String> orphanSnapshots({
  required List<String> remoteSnapshotNames,
  required SyncManifest? currentManifest,
  Set<String> referencedNames = const <String>{},
}) {
  final Set<String> referenced = <String>{
    ...referencedNames,
    if (currentManifest != null) currentManifest.snapshotName,
  };
  return remoteSnapshotNames
      .where((String name) => !referenced.contains(name))
      .toList(growable: false);
}

/// 本地能否确认这次发布（架构 5.2「本地事务确认成功」）。
///
/// 三个条件缺一不可，且**都必须是读回的事实**：
///   1) 远端读回的快照哈希与本地一致；
///   2) manifest 里的哈希与本地一致；
///   3) manifest 的版本指向这次快照。
bool canConfirmPublish({
  required String localHash,
  required String? readBackHash,
  required SyncManifest? readBackManifest,
}) =>
    readBackHash != null &&
    readBackHash == localHash &&
    readBackManifest != null &&
    readBackManifest.snapshotHash == localHash &&
    readBackManifest.snapshotName == snapshotFileName(localHash);

String? _nonEmpty(String? value) {
  if (value == null) {
    return null;
  }
  final String trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
