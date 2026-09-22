// 本机内容的快照读写端口（T043；架构 5.2 的「在本机暂存合并结果」「本地事务确认成功」）。
//
// 与 T041 的 [SyncStore] 分工不同，因此是两个端口：
//   * [SyncStore] 管**协议状态**（基线版本、待同步变更、墓碑、别名、占位行）；
//   * 本端口管**内容**：把本机当前的订阅/分组/设置/阅读状态读成一份规范化快照，
//     以及把合并结果写回本机。
//
// 为什么必须分开：合并的输入是三份**同形态的快照**（基线/本机/远端），而协议状态
// 不是内容的一部分——把两者塞进一个端口会让「读一份快照」变成一次跨越协议表与内容表的
// 大查询，且用例层再也无法用纯 fixture 提供「本机当前」这一侧。
//
// 三条纪律：
//   1) **写回必须尊重更新的本地改动**：上传期间用户又改了同一个字段时，那一列以本机为准
//      （[SyncApplyOutcome.preservedLocalFields]），因为「上传期间的新修改」比这次上传更新
//      （架构 5.2 明确要求提交只确认已包含的修订）；
//   2) **写回不做破坏性删除**：墓碑与远端删除都不在这里应用（跨设备删除应用属 T045），
//      本端口因此没有任何「删除订阅/清空文章」的语句；
//   3) **凭据不经过这里**：快照里没有秘密字段（T041 的投影已逐条排除），本端口也不接受
//      任何凭据参数。
library;

import '../result.dart';

import 'sync_snapshot.dart';

/// 一次写回的结果。
final class SyncApplyOutcome {
  /// 构造结果。
  const SyncApplyOutcome({
    required this.appliedCount,
    required this.preservedLocalFields,
    required this.confirmedPendingCount,
    required this.skippedRemoteOnlyCount,
  });

  /// 真正写入本机的字段数。
  final int appliedCount;

  /// 因本机在上传期间又有改动而被**保留**的字段（`kind/key/field` 三段的列表）。
  ///
  /// 这个计数必须能被观察到：它是「上传期间的新修改不丢失」这条验收的落点，
  /// 而不是一句口头保证。
  final List<String> preservedLocalFields;

  /// 被确认（从待同步表清除）的变更数。
  final int confirmedPendingCount;

  /// 因为本机没有对应对齐、因而**跳过**的远端实体数。
  ///
  /// 例如远端送来一条本机还没有的订阅：它的分组引用（groupSyncId）在本机可能指向一个
  /// 尚未建立的分组。跳过（而不是编一个分组）保证了本机的分组引用永远指向真实存在的行。
  final int skippedRemoteOnlyCount;
}

/// 本机内容的快照读写端口。
abstract interface class SyncLocalStore {
  /// 读本机当前内容的规范化快照。
  ///
  /// 快照里已经包含本机的墓碑（[SyncSnapshot.deletions]），因此合并时不需要第二个
  /// 「本机删过什么」的入参——两份删除数据源会让「哪一份才是真的」成为一个只有运行时
  /// 才能回答的问题。
  Future<Result<SyncSnapshot>> readLocalSnapshot();

  /// 把合并结果写回本机，并确认 ≤ [confirmedRevision] 的待同步变更。
  ///
  /// [baseVersion] 是本次发布后的版本（写进基线，供下一轮当共同基线使用）。
  /// 整个过程必须在一个事务里：写回一半会让「已确认的修订」与「实际写回的内容」不一致，
  /// 而重试路径会据此认为无事可做。
  Future<Result<SyncApplyOutcome>> applyMergedSnapshot({
    required SyncSnapshot merged,
    required int confirmedRevision,
    required String baseVersion,
    required DateTime syncedAt,
  });
}
