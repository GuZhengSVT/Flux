// 降级启动时同步内容端口的替身（T044）。
//
// 数据库不可用时（降级启动）同步**不能**假装可用：读快照返回类型化失败、写回明确失败，
// 因此「打开同步设置页」不会显示一个看起来能用的界面，而「立即同步」会得到一条明确的
// 「存储不可用」而不是一个空成功。
//
// 与 T041 的 DegradedFeedCatalogStore 同一口径：读返回**真实答案**（这次运行确实没有内容
// 可读），写返回失败（不假装保存成功）。
library;

import 'package:flux/core/core.dart';

/// 降级实现的同步内容端口。
final class DegradedSyncLocalStore implements SyncLocalStore {
  /// 构造降级实现。
  const DegradedSyncLocalStore();

  @override
  Future<Result<SyncSnapshot>> readLocalSnapshot() async => Err<SyncSnapshot>(
    StorageError(operation: 'sync.readLocalSnapshot', detail: '数据库不可用（降级启动）'),
  );

  @override
  Future<Result<SyncApplyOutcome>> applyMergedSnapshot({
    required SyncSnapshot merged,
    required int confirmedRevision,
    required String baseVersion,
    required DateTime syncedAt,
  }) async => Err<SyncApplyOutcome>(
    StorageError(operation: 'sync.applyMergedSnapshot', detail: '数据库不可用（降级启动）'),
  );
}
