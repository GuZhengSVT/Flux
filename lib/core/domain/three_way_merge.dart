// 三方合并（T043；架构 5.2「下载共同基线→三方比较→在本机暂存合并结果」、
// 「不同字段独立变更可合并；同字段并发（特别是 read/later/unread 与取消收藏）显示冲突，
// 保留本机有效值和两个候选，用户选择后形成新版本。不得用三态逻辑 OR 或仅比较设备墙钟」）。
//
// 这个文件是**纯函数**：三个快照进，一个合并结果出。没有 I/O、没有时钟、没有数据库。
//
// 为什么必须如此（而不写成「合并时顺手查一下本机库」）：
//   * 合并决定了「哪一份内容被写进远端」，因此它是**数据破坏面**最大的规则；
//   * 而它最容易出的错，恰好是那些在真实双设备场景下才偶发的：三态被 OR、收藏被 OR、
//     用两台设备的墙钟判断谁更新。这些都只有把规则抽成纯函数才能逐条钉住；
//   * 「不比较墙钟」在这里是**结构性**的：本文件的签名里没有任何时间参数，
//     也没有任何 `DateTime` 读取路径，因此「按时间戳挑一方」无法被后来者顺手加进来
//     而不改动签名（签名一改，评审与用例就会看见）。
//
// 合并规则（逐条对应架构原话）：
//
//   1) **双方同值 → 保留**（这也覆盖「谁都没改」：结果是基线值）。
//   2) **仅一方变更 → 取该方**。判据是 `该方 == 基线`，而不是「谁的时间戳更新」。
//   3) **同字段并发变更 → 冲突**。不自动挑一方、不做 OR/并集合并——
//      `read` 与 `later` 的 OR 是不存在的状态，而收藏的 OR 会把「我取消了收藏」
//      变成「远端又帮我加回来」。冲突项连**两个候选值**一起返回，界面据此让用户选版。
//   4) **不同字段独立合并**（同一实体里，名称冲突不影响分组字段的结果）。
//   5) **订阅/分组列表按 key 取并集**：新增项按 syncId 合并，不按本机自增 id。
//   6) **删除走墓碑，且删除优先于远端复活**：本地有墓碑时，远端快照里那条实体一律丢弃。
//   7) **远端删除只登记、不自动应用**（架构 5.2「未批准不自动清除本地内容」）：
//      它以 [SyncMergeResult.pendingRemoteDeletions] 的形式返回，供界面预览确认。
library;

import 'sync_snapshot.dart';

/// 「该字段在这份快照里没有出现」的哨兵值。
///
/// 为什么需要一个独立哨兵而不是用 `null`：`null` 已经是一个合法的字段值
/// （例如「远端没有发布该 prompt 的备注」），把「缺失」与「值为 null」压成同一个之后，
/// 合并会把「对端根本没报告这个字段」判成「对端把它改成了 null」并产生假冲突。
const Object syncFieldAbsent = _SyncFieldAbsent();

final class _SyncFieldAbsent {
  const _SyncFieldAbsent();

  @override
  String toString() => '<absent>';
}

/// 冲突的解决方向。
enum SyncConflictChoice {
  /// 采用本机值。
  local,

  /// 采用远端值。
  remote,
}

/// 冲突处理策略（SET-075 的 conflictPolicy：manual / preferLocal / preferRemote）。
///
/// [manual] 是注册表里的默认值，含义是「**先保留本机值**并把它列出来让用户选」：
/// 这两件事不矛盾——用户还没选的时候，本机必须有一个可用值（否则一次冲突会让本机
/// 连状态都读不到），而两个候选都留着，选完形成的才是新版本。
enum SyncConflictPolicy {
  /// 保留本机值并把冲突列出来等用户选择（默认）。
  manual,

  /// 一律采用本机值（用户显式选择「以这台设备为准」）。
  preferLocal,

  /// 一律采用远端值。
  preferRemote;

  /// 该策略下未指定方向时采用的默认方向。
  SyncConflictChoice get defaultChoice => switch (this) {
    SyncConflictPolicy.preferRemote => SyncConflictChoice.remote,
    SyncConflictPolicy.manual ||
    SyncConflictPolicy.preferLocal => SyncConflictChoice.local,
  };
}

/// 一处同字段并发冲突。
final class SyncMergeConflict {
  /// 构造冲突。
  const SyncMergeConflict({
    required this.kind,
    required this.key,
    required this.field,
    required this.baseValue,
    required this.localValue,
    required this.remoteValue,
  });

  /// 实体类别。
  final String kind;

  /// 实体键。
  final String key;

  /// 冲突字段名。
  final String field;

  /// 共同基线里的值（缺失时为 [syncFieldAbsent]）。
  final Object? baseValue;

  /// 本机的值（缺失时为 [syncFieldAbsent]）。
  final Object? localValue;

  /// 远端的值（缺失时为 [syncFieldAbsent]）。
  final Object? remoteValue;

  /// 冲突定位键（kind + key + field）。
  String get mapKey => '$kind\u0000$key\u0000$field';

  /// 基线里根本没有这个实体（首次同步且两边各自改过同一篇文章）。
  ///
  /// 单列出来是因为界面的说明不同：这一类冲突的用户提示是「这两台设备各自改过同一篇，
  /// 请选一个」（没有共同基线可比），而不是「同一项在两边被改成了不同值」。
  bool get withoutCommonBaseline => baseValue == syncFieldAbsent;

  @override
  String toString() =>
      'SyncMergeConflict($kind/$key.$field: base=$baseValue local=$localValue '
      'remote=$remoteValue)';
}

/// 一次三方合并的结果。
final class SyncMergeResult {
  /// 构造结果。
  const SyncMergeResult({
    required this.merged,
    required this.conflicts,
    required this.pendingRemoteDeletions,
    required this.appliedDeletions,
  });

  /// 合并后的快照（可直接上传）。
  ///
  /// 注意它**已经**按 [SyncConflictPolicy.manual] 的默认方向填好了未决冲突
  /// （保留本机值）；见 [forPublish] 与冲突策略的说明。
  final SyncSnapshot merged;

  /// 同字段并发冲突列表（含两个候选值，供界面选版）。
  final List<SyncMergeConflict> conflicts;

  /// 远端提出、但本机**尚未确认**的破坏性删除（架构 5.2「未批准不自动清除本地内容」）。
  ///
  /// 本机没有对应墓碑的远端删除会出现在这里，本任务**不**把它们应用到本机数据：
  /// 应用是 T045 的跨设备删除集成范围，而「未确认不清数据」这条规则在这里表现为
  /// 「合并结果里只登记，不落地」。
  final List<SyncDeletion> pendingRemoteDeletions;

  /// 本次合并中，因墓碑而**丢弃了远端实体**的键（删除优先于远端复活）。
  ///
  /// 单独返回是为了让诊断与用例能看见「这次真的挡住了复活」，而不是只能从
  /// 「结果里没有那条」间接推断。
  final List<SyncDeletion> appliedDeletions;

  /// 是否有需要用户处理的冲突。
  bool get hasConflicts => conflicts.isNotEmpty;

  /// 是否有待确认的远端破坏性删除。
  bool get hasPendingRemoteDeletions => pendingRemoteDeletions.isNotEmpty;
}

/// 三方合并（架构 5.2 的字段级规则）。
///
/// [base] 是**共同基线**（上一次成功同步发布的快照）；[local] 与 [remote] 是双方当前内容。
/// 首次同步时 [base] 传 [SyncSnapshot.empty]——注意这不是「没有基线所以随便挑一方」，
/// 而是「同一个键两边都有值时，两边**都相对基线变了**」，因此那是一条冲突，
/// 由界面让用户选版（T044 的首次合并预览）。
SyncMergeResult threeWayMerge({
  required SyncSnapshot base,
  required SyncSnapshot local,
  required SyncSnapshot remote,
  SyncConflictPolicy policy = SyncConflictPolicy.manual,
  Map<String, SyncConflictChoice> choices =
      const <String, SyncConflictChoice>{},
}) {
  final List<SyncMergeConflict> conflicts = <SyncMergeConflict>[];
  final List<SyncEntity> mergedEntities = <SyncEntity>[];

  // 键的并集：**不**按本机自增 id（架构 5.2），类别与键都参与排序以保证输出稳定。
  for (final String kind in _unionKinds(base, local, remote)) {
    for (final String key in _unionKeys(kind, base, local, remote)) {
      final SyncEntity? baseEntity = base.entity(kind, key);
      final SyncEntity? localEntity = local.entity(kind, key);
      final SyncEntity? remoteEntity = remote.entity(kind, key);
      if (localEntity == null && remoteEntity == null) {
        continue;
      }

      // 墓碑优先：本机删掉了就不接受远端复活（架构 5.2）。
      if (local.hasDeletion(kind, key)) {
        continue;
      }
      // 远端删掉了：登记待确认，并且**不**把这条实体写进合并结果——
      // 否则本机会把自己这边的内容发布成「远端已删的内容」，等于用一次上传推翻远端的删除。
      if (remote.hasDeletion(kind, key)) {
        continue;
      }

      if (localEntity == null || remoteEntity == null) {
        // 只有一方有这条实体：那不是「同字段并发」，直接取有值的一方。
        mergedEntities.add(localEntity ?? remoteEntity!);
        continue;
      }

      final Map<String, Object?> mergedFields = <String, Object?>{};
      for (final String field in _unionFields(
        baseEntity,
        localEntity,
        remoteEntity,
      )) {
        final Object? baseValue = _fieldOf(baseEntity, field);
        final Object? localRaw = _fieldOf(localEntity, field);
        final Object? remoteRaw = _fieldOf(remoteEntity, field);
        // 「这一方没有报告该字段」按「与基线相同」处理：缺失是**没有信息**，不是
        // 「把它改成了空」。否则远端只报了名字、没报排列权重时，本机的权重会因为
        // 「远端把它改成了缺失」而被清掉——这正是「缺失 ≠ 删除」那条规矩的落点。
        // 注意：**显式的 null** 不走这条替换，它是一次真实变更（有用例钉住）。
        final Object? localValue = localRaw == syncFieldAbsent
            ? baseValue
            : localRaw;
        final Object? remoteValue = remoteRaw == syncFieldAbsent
            ? baseValue
            : remoteRaw;

        // 1) 双方同值（含「谁都没改」）→ 保留。
        if (sameSyncValue(localValue, remoteValue)) {
          if (localValue != syncFieldAbsent) {
            mergedFields[field] = localValue;
          }
          continue;
        }
        // 2) 仅一方变更 → 取该方。「变更」的判据是与基线比较，**不是**时间戳。
        if (sameSyncValue(localValue, baseValue)) {
          if (remoteValue != syncFieldAbsent) {
            mergedFields[field] = remoteValue;
          }
          continue;
        }
        if (sameSyncValue(remoteValue, baseValue)) {
          if (localValue != syncFieldAbsent) {
            mergedFields[field] = localValue;
          }
          continue;
        }

        // 3) 同字段并发变更 → 冲突。两个候选都记下来，不 OR、不自动取胜方。
        final SyncMergeConflict conflict = SyncMergeConflict(
          kind: kind,
          key: key,
          field: field,
          baseValue: baseValue,
          localValue: localValue,
          remoteValue: remoteValue,
        );
        conflicts.add(conflict);
        final SyncConflictChoice? chosen = choices[conflict.mapKey];
        final Object? effective = switch (chosen ?? policy.defaultChoice) {
          SyncConflictChoice.local => localValue,
          SyncConflictChoice.remote => remoteValue,
        };
        if (effective != syncFieldAbsent) {
          mergedFields[field] = effective;
        }
      }
      mergedEntities.add(
        SyncEntity(kind: kind, key: key, fields: mergedFields),
      );
    }
  }

  // 删除事实取并集：墓碑是长期事实（架构 5.2「首发不自动清除」），因此合并结果里
  // 必须带着**双方已知的全部墓碑**，否则本机一次发布就会让对端看不见删除，
  // 那条订阅会在对端复活。
  //
  // 同一键两边都有墓碑时**本机的那一份胜出**（`local` 最后展开）：删除的「保留收藏」
  // 选择是本机用户做过的决定，用远端的那一份覆盖它会让本机下次展示的删除结果与用户
  // 当时的选择不符（而墓碑的存储语义也是「同键只保留第一条，重复删除不刷新」）。
  final Map<String, SyncDeletion> mergedDeletions = <String, SyncDeletion>{
    ...base.deletions,
    ...remote.deletions,
    ...local.deletions,
  };

  // 远端提出而本机没有墓碑的删除：登记待确认（架构 5.2「未批准不自动清除本地内容」）。
  final List<SyncDeletion> pending = remote.allDeletions
      .where(
        (SyncDeletion deletion) =>
            !local.hasDeletion(deletion.kind, deletion.key) &&
            deletion.mapKey.isNotEmpty,
      )
      .toList(growable: false);

  // 因墓碑而被丢弃的远端实体（「删除优先于远端复活」的可断言证据）。
  final List<SyncDeletion> applied = <SyncDeletion>[];
  for (final SyncDeletion deletion in local.allDeletions) {
    if (remote.hasEntity(deletion.kind, deletion.key)) {
      applied.add(deletion);
    }
  }

  return SyncMergeResult(
    merged: SyncSnapshot(
      entities: _groupByKind(mergedEntities),
      deletions: mergedDeletions,
    ),
    conflicts: List<SyncMergeConflict>.unmodifiable(conflicts),
    pendingRemoteDeletions: List<SyncDeletion>.unmodifiable(pending),
    appliedDeletions: List<SyncDeletion>.unmodifiable(applied),
  );
}

/// 用给定的冲突选择**重新**构造可发布快照。
///
/// 用户选完版之后形成的才是「新版本」（架构 5.2）。这里不重新做一遍合并，
/// 而是把同一组输入与新的选择交给 [threeWayMerge]：重新合并一次是廉价的纯函数调用，
/// 而「复用上次的中间结果」会让「用户选择」与「合并输入」之间出现窗口——
/// 用户思考期间本机又改了同一字段时，复用的中间结果会把那次改动丢掉。
SyncMergeResult mergeWithChoices({
  required SyncSnapshot base,
  required SyncSnapshot local,
  required SyncSnapshot remote,
  required Map<String, SyncConflictChoice> choices,
  SyncConflictPolicy policy = SyncConflictPolicy.manual,
}) => threeWayMerge(
  base: base,
  local: local,
  remote: remote,
  policy: policy,
  choices: choices,
);

/// 按策略解析为可发布快照（policy 决定未指定方向的冲突采用哪一方）。
SyncSnapshot applyConflictPolicy({
  required SyncMergeResult result,
  required SyncConflictPolicy policy,
}) {
  if (!result.hasConflicts || policy == SyncConflictPolicy.manual) {
    // manual 的默认方向已经在上面的合并里生效（保留本机值），因此这里不需要重算。
    return result.merged;
  }
  final SyncConflictChoice choice = policy.defaultChoice;
  final Map<String, Map<String, SyncEntity>> entities =
      <String, Map<String, SyncEntity>>{};
  for (final SyncEntity entity in result.merged.allEntities) {
    entities[entity.kind] ??= <String, SyncEntity>{};
    entities[entity.kind]![entity.key] = entity;
  }
  for (final SyncMergeConflict conflict in result.conflicts) {
    final SyncEntity? entity = entities[conflict.kind]?[conflict.key];
    if (entity == null) {
      continue;
    }
    final Object? value = switch (choice) {
      SyncConflictChoice.local => conflict.localValue,
      SyncConflictChoice.remote => conflict.remoteValue,
    };
    final Map<String, Object?> fields = Map<String, Object?>.of(entity.fields);
    if (value == syncFieldAbsent) {
      fields.remove(conflict.field);
    } else {
      fields[conflict.field] = value;
    }
    entities[conflict.kind]![conflict.key] = entity.withFields(fields);
  }
  return SyncSnapshot(entities: entities, deletions: result.merged.deletions);
}

// ---------------------------------------------------------------------------
// 内部：键的并集与字段访问
// ---------------------------------------------------------------------------

List<String> _unionKinds(
  SyncSnapshot base,
  SyncSnapshot local,
  SyncSnapshot remote,
) {
  final Set<String> kinds = <String>{
    ...base.entities.keys,
    ...local.entities.keys,
    ...remote.entities.keys,
  };
  final List<String> sorted = kinds.toList(growable: false)..sort();
  return sorted;
}

List<String> _unionKeys(
  String kind,
  SyncSnapshot base,
  SyncSnapshot local,
  SyncSnapshot remote,
) {
  final Set<String> keys = <String>{
    ...?base.entities[kind]?.keys,
    ...?local.entities[kind]?.keys,
    ...?remote.entities[kind]?.keys,
  };
  final List<String> sorted = keys.toList(growable: false)..sort();
  return sorted;
}

List<String> _unionFields(
  SyncEntity? base,
  SyncEntity local,
  SyncEntity remote,
) {
  final Set<String> fields = <String>{
    ...?base?.fields.keys,
    ...local.fields.keys,
    ...remote.fields.keys,
  };
  final List<String> sorted = fields.toList(growable: false)..sort();
  return sorted;
}

Object? _fieldOf(SyncEntity? entity, String field) {
  if (entity == null || !entity.hasField(field)) {
    return syncFieldAbsent;
  }
  return entity.fields[field];
}

Map<String, Map<String, SyncEntity>> _groupByKind(List<SyncEntity> entities) {
  final Map<String, Map<String, SyncEntity>> byKind =
      <String, Map<String, SyncEntity>>{};
  for (final SyncEntity entity in entities) {
    (byKind[entity.kind] ??= <String, SyncEntity>{})[entity.key] = entity;
  }
  return byKind;
}
