// 同步初始状态与待同步计数的读取（T044；设置页与冲突页的数据来源）。
//
// 「读初始状态」必须**不发任何网络请求**：设置页一打开就要显示「上次同步 / 待同步数 /
// 冲突数 / 能力」，如果这些数字要靠连一次远端才能得到，那么「打开设置」就会变成一次
// 同步（用户只是看一眼状态，却触发了上传）。因此这里全部读本机状态：
//   * 共同基线版本与上次成功时刻、能力三态 → `sync_state`（T041）；
//   * 待同步变更数 → `sync_pending_changes` 的行数；
//   * 冲突数 → 本机**没有**一份持久化的冲突表（冲突是「这一次合并的结论」），因此它只能
//     由管理器在内存里维护，这里如实返回 0，而不是编一个数。
library;

import 'package:flux/core/core.dart';

import 'database.dart';
import 'tables/sync_tables.dart';

/// drift 实现：读同步初始状态。
final class DriftSyncStatusReader {
  /// 绑定一个已打开的数据库。
  const DriftSyncStatusReader(this._db);

  final AppDatabase _db;

  /// 读初始状态（不发网络请求）。
  Future<Result<SyncStatusBaseline>> read() async {
    try {
      final SyncStateRecord? state =
          await (_db.select(_db.syncStateRecords)..where(
                (SyncStateRecords t) =>
                    t.id.equals(SyncStateRecords.singletonId),
              ))
              .getSingleOrNull();
      final int pending = await _pendingCount();
      return Ok<SyncStatusBaseline>(
        SyncStatusBaseline(
          capability: _capabilityOf(state?.supportsConditionalWrite),
          lastSyncedAt: state?.lastSyncedAt,
          baseVersion: state?.baseVersion,
          pendingChangeCount: pending,
        ),
      );
    } on Exception catch (error, stackTrace) {
      return Err<SyncStatusBaseline>(
        StorageError(
          operation: 'sync.readStatusBaseline',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  Future<int> _pendingCount() async {
    final List<SyncPendingChange> rows = await _db
        .select(_db.syncPendingChanges)
        .get();
    return rows.length;
  }

  static WebDavWriteCapability _capabilityOf(bool? supportsConditionalWrite) {
    if (supportsConditionalWrite == null) {
      return WebDavWriteCapability.unknown;
    }
    return supportsConditionalWrite
        ? WebDavWriteCapability.conditionalWrite
        : WebDavWriteCapability.readOnlyPull;
  }
}
