// 本机删除事实的记录（T045；架构 5.2「删除使用墓碑，首发不自动清除」与「删除操作元数据」）。
//
// 为什么需要一个**共用**的记录器：删除本机数据的地方有两处——用户在订阅管理页删（T018 的
// deleteFeed / deleteGroupWithFeeds）与用户确认应用远端提出的删除（T045）。两处都必须留下
// 同样形状的墓碑，否则「已删除条目不复活」只对其中一条路径成立，而症状是「我在 A 设备删的源
// 在 B 设备确认之后又被刷回来了」，并且没有任何报错。
//
// 三条实现纪律：
//
//   1) **调用方必须已在事务内**。墓碑、待同步标记与修订号推进必须与业务删除同生共死：
//      删掉了订阅却没留下墓碑，等于把一次删除变成一次「源还在、本机不知道」，而它会在
//      下一次刷新时把整条订阅连文章一起拉回来。
//   2) **修订号由本机分配**。墓碑带的 revision 取「当前本地修订 +1」并把 sync_state 推进到
//      该值，因此「哪些改动还没上传」在本机有一致的口径；让调用方传一个数字会让「谁才是当前
//      修订」有两个来源。
//   3) **重复删除幂等且不刷新时间**。insertOrIgnore 保留第一条墓碑：重复删除不应让
//      「什么时候删的」漂移（与 T041 的 recordTombstone 同一口径）。
library;

import 'package:drift/drift.dart';

import 'package:flux/core/core.dart';

import 'database.dart';
import 'tables/sync_tables.dart';

/// 记录一次本机删除事实：墓碑 + 待同步标记 + 修订号推进。
///
/// 返回本次分配的修订号（供诊断与用例断言）。**必须在事务内调用**，且调用方已经完成
/// 业务数据（订阅/分组/文章）的删除——本函数只负责「让这次删除成为一件跨设备可见的事实」。
///
/// [displayName] 会存进墓碑与删除事件（让别的设备能说明「删的是哪一个」），因此它必须是
/// 展示名而不是任何形式的正文或地址参数（架构第 8 节：墓碑不是第二条泄露路径）。
Future<int> recordLocalDeletionFact(
  AppDatabase db, {
  required String entityKind,
  required String entityKey,
  required String displayName,
  required DateTime deletedAt,
}) async {
  final int revision = await _bumpRevision(db);
  // 同一实体只保留第一条墓碑：重复删除幂等，且不刷新删除时间。
  //
  // 「保留收藏」这份**操作元数据**不在这里：它住在 T018 的 deletion_events
  // （那本来就是「用户做过一次删除」的业务记录），快照读墓碑时按同一 syncId 关联它。
  // 复制一份进墓碑表会让两处对「当时选了什么」各有说法，而它们迟早会不一致。
  await db
      .into(db.syncTombstones)
      .insert(
        SyncTombstonesCompanion.insert(
          entityKind: entityKind,
          entityKey: entityKey,
          deletedAt: deletedAt,
          revision: revision,
          displayName: Value<String?>(displayName),
        ),
        mode: InsertMode.insertOrIgnore,
      );
  // 待同步标记：让「本机还有没上传的改动」这件事在设置页与同步流程里可见。
  // 字段名用空串表示「整行」（与 T041 的约定一致：空串是普通值，因此唯一索引真正生效）。
  await db
      .into(db.syncPendingChanges)
      .insert(
        SyncPendingChangesCompanion.insert(
          entityKind: entityKind,
          entityKey: entityKey,
          fieldName: const Value<String>(''),
          revision: revision,
          changedAt: deletedAt,
        ),
        // 同一实体整行只有一条待同步记录：新删除覆盖旧记录的修订号。
        onConflict: DoUpdate<$SyncPendingChangesTable, SyncPendingChange>(
          (SyncPendingChanges old) => SyncPendingChangesCompanion(
            revision: Value<int>(revision),
            changedAt: Value<DateTime>(deletedAt),
          ),
          target: <Column<Object>>[
            db.syncPendingChanges.entityKind,
            db.syncPendingChanges.entityKey,
            db.syncPendingChanges.fieldName,
          ],
        ),
      );
  return revision;
}

/// 忘记某个实体的墓碑（用户在**本机显式重新添加**同一源时调用）。
///
/// 为什么必须能忘记：订阅的 syncId 是「规范化地址的摘要」（T014），因此重新添加同一个源
/// 必然得到**同一个 syncId**。若不忘记旧墓碑，那个源会被墓碑判定为「已删除」而永远跳过
/// 刷新——用户会看到一个加不进来内容的订阅，且没有任何线索指向那次删除。
///
/// 这**不**违反「已删除条目不复活」：那一条约束的是「别的设备的旧快照不得把本机删掉的源
/// 带回来」，而这里是用户在**本机**主动重新添加，是一次新的决定，不是复活。
Future<void> forgetLocalDeletionTombstone(
  AppDatabase db, {
  required String entityKind,
  required String entityKey,
}) async {
  await (db.delete(db.syncTombstones)..where(
        (SyncTombstones t) =>
            t.entityKind.equals(entityKind) & t.entityKey.equals(entityKey),
      ))
      .go();
  await (db.delete(db.syncPendingChanges)..where(
        (SyncPendingChanges t) =>
            t.entityKind.equals(entityKind) & t.entityKey.equals(entityKey),
      ))
      .go();
}

/// 推进本地修订号并返回新值（与 DriftSyncStore.bumpRevision 同一口径）。
Future<int> _bumpRevision(AppDatabase db) async {
  final SyncStateRecord? row =
      await (db.select(db.syncStateRecords)..where(
            (SyncStateRecords t) => t.id.equals(SyncStateRecords.singletonId),
          ))
          .getSingleOrNull();
  if (row == null) {
    // 缺单行同步状态：迁移与新库都会写入它，缺它说明库已经不一致。抛错由事务回滚，
    // 而不是编一个修订号——编出来的号会让「已确认到哪」与实际内容对不上。
    throw StorageError(
      operation: 'recordLocalDeletionFact',
      detail: '缺少单行同步状态（建库与迁移都会写入它）',
      isMissing: true,
    );
  }
  final int next = row.localRevision + 1;
  await (db.update(db.syncStateRecords)..where(
        (SyncStateRecords t) => t.id.equals(SyncStateRecords.singletonId),
      ))
      .write(SyncStateRecordsCompanion(localRevision: Value<int>(next)));
  return next;
}
