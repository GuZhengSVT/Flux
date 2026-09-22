// 首次合并预览（T043 规则 + T044 界面；SET-075 的 firstSyncPreview、架构 5.2）。
//
// 架构原话：「必须为首次同步/冲突处理提供稳定的备份/回滚策略；不得静默覆盖」（SET-075）。
// 因此「本机第一次连上某个远端」这件事**不能**直接跑一次合并然后上传：那时没有共同基线，
// 任何相同键上的不同值都是一条无法自动判定的分歧，而默认「以远端为准」会把本机已有的
// 订阅与阅读状态一次性改掉——用户从界面上看不出发生了什么。
//
// 这个文件负责把「接下来会发生什么」变成用户能读懂的**数字与差异**，并且给出默认策略：
// **不覆盖本地**（[SyncFirstMergePreview.recommendedPolicy]）。
//
// 为什么默认不是「以远端为准」：远端可能是另一台设备的一次实验性改动，而本机是用户此刻
// 正在用的那一份。默认覆盖本地会让「连上同步」这个动作变成一次数据回退。
library;

import 'sync_snapshot.dart';
import 'three_way_merge.dart';

/// 一行「同一项在两边不一样」的预览条目。
final class SyncPreviewDifference {
  /// 构造条目。
  const SyncPreviewDifference({
    required this.kind,
    required this.key,
    required this.field,
    required this.localValue,
    required this.remoteValue,
  });

  /// 实体类别。
  final String kind;

  /// 实体键。
  final String key;

  /// 字段名。
  final String field;

  /// 本机值（缺失时为 [syncFieldAbsent]）。
  final Object? localValue;

  /// 远端值（缺失时为 [syncFieldAbsent]）。
  final Object? remoteValue;

  @override
  String toString() =>
      'SyncPreviewDifference($kind/$key.$field: local=$localValue remote=$remoteValue)';
}

/// 首次合并预览。
final class SyncFirstMergePreview {
  /// 构造预览。
  const SyncFirstMergePreview({
    required this.localEntityCount,
    required this.remoteEntityCount,
    required this.sharedKeys,
    required this.localOnlyKeys,
    required this.remoteOnlyKeys,
    required this.fieldDifferences,
    required this.remoteDeletionCount,
    required this.recommendedPolicy,
  });

  /// 本机快照里的实体数。
  final int localEntityCount;

  /// 远端快照里的实体数。
  final int remoteEntityCount;

  /// 两边都有的键数。
  final int sharedKeys;

  /// 只有本机有的键数（远端没有报告它们——**不是**远端删除了它们）。
  final int localOnlyKeys;

  /// 只有远端有的键数（首次合并会把它们并进来）。
  final int remoteOnlyKeys;

  /// 同键字段差异（预览只展示前若干条，界面据此说明「有多少项不同」）。
  final List<SyncPreviewDifference> fieldDifferences;

  /// 远端提出的破坏性删除数量（本机没有对应墓碑的那些）。
  final int remoteDeletionCount;

  /// 推荐的合并策略（固定为「以本机为准」，见 [SyncConflictPolicy.preferLocal]）。
  final SyncConflictPolicy recommendedPolicy;

  /// 是否两边都有内容（有内容分歧时才需要用户真正做选择）。
  bool get hasRemoteContent => remoteEntityCount > 0;

  /// 差异条目数（字段级）。
  int get differenceCount => fieldDifferences.length;

  /// 是否有需要用户注意的差异。
  bool get needsAttention =>
      fieldDifferences.isNotEmpty || remoteDeletionCount > 0;
}

/// 计算首次合并预览。
///
/// 首次同步时**没有共同基线**，因此「同键字段不同」一律按差异列出（而不是自动合并）：
/// 用 [threeWayMerge] 以空基线跑一遍能直接给出这套判定，且与正式合并走**同一条规则**——
/// 预览与真正执行之间不会出现两套判据。
SyncFirstMergePreview buildFirstMergePreview({
  required SyncSnapshot local,
  required SyncSnapshot remote,
  int maxDifferences = 50,
}) {
  final SyncMergeResult probe = threeWayMerge(
    base: SyncSnapshot.empty,
    local: local,
    remote: remote,
    policy: SyncConflictPolicy.preferLocal,
  );
  final List<SyncPreviewDifference> differences = probe.conflicts
      .take(maxDifferences)
      .map(
        (SyncMergeConflict conflict) => SyncPreviewDifference(
          kind: conflict.kind,
          key: conflict.key,
          field: conflict.field,
          localValue: conflict.localValue,
          remoteValue: conflict.remoteValue,
        ),
      )
      .toList(growable: false);

  int shared = 0;
  int localOnly = 0;
  int remoteOnly = 0;
  for (final SyncEntity entity in local.allEntities) {
    if (remote.hasEntity(entity.kind, entity.key)) {
      shared++;
    } else {
      localOnly++;
    }
  }
  for (final SyncEntity entity in remote.allEntities) {
    if (!local.hasEntity(entity.kind, entity.key)) {
      remoteOnly++;
    }
  }

  return SyncFirstMergePreview(
    localEntityCount: local.entityCount,
    remoteEntityCount: remote.entityCount,
    sharedKeys: shared,
    localOnlyKeys: localOnly,
    remoteOnlyKeys: remoteOnly,
    fieldDifferences: differences,
    remoteDeletionCount: probe.pendingRemoteDeletions.length,
    recommendedPolicy: SyncConflictPolicy.preferLocal,
  );
}
