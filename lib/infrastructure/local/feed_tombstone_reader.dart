// 订阅墓碑的只读读取（T045；端口在 core/domain/remote_deletion.dart）。
//
// 为什么单独一个文件而不是塞进 DriftSyncStore：这个端口被**刷新调度**使用，而同步存储
// 端口还带着基线、待同步变更与占位行写入（刷新一概不需要，也不该拿得到）。分开之后，
// 「刷新能不能写同步状态」在类型上就是否定的。
//
// 只读、只返回一个 syncId 集合：调度在一次刷新开始时问一次「哪些订阅被删过」，然后把
// 候选源过滤掉。逐源查询会把 N 次数据库往返叠在派发之前，而它本来只是一次全表扫描。
library;

import 'package:flux/core/core.dart';

import 'database.dart';
import 'tables/sync_tables.dart';

/// drift 实现。
final class DriftFeedTombstoneReader implements FeedTombstoneReader {
  /// 绑定一个已打开的数据库。
  const DriftFeedTombstoneReader(this._db);

  final AppDatabase _db;

  @override
  Future<Result<Set<String>>> readFeedTombstoneSyncIds() async {
    try {
      final List<SyncTombstoneRecord> rows =
          await (_db.select(_db.syncTombstones)..where(
                (SyncTombstones t) => t.entityKind.equals(SyncEntityKind.feed),
              ))
              .get();
      return Ok<Set<String>>(<String>{
        for (final SyncTombstoneRecord row in rows) row.entityKey,
      });
    } on Exception catch (error, stackTrace) {
      return Err<Set<String>>(
        StorageError(
          operation: 'sync.readFeedTombstones',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}
