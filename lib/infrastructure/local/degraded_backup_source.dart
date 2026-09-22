// 降级启动时备份端口的替身（T046）。
//
// 没有数据库就没有可备份的内容，也没有可写的数据目录。这里**明确失败**而不是返回空快照：
// 一个空快照会让「导出」看起来成功了，而包里只有一份空库——用户会以为自己的数据备份好了，
// 直到需要恢复时才发现里面什么都没有（与 T044 的 DegradedSyncLocalStore 同一口径）。
library;

import 'dart:typed_data';

import 'package:flux/core/core.dart';

import 'package:flux/features/sync/application/backup_ports.dart';

/// 降级实现的备份内容来源。
final class DegradedBackupContentSource implements BackupContentSource {
  /// 构造降级实现。
  const DegradedBackupContentSource();

  /// 统一失败（所有读取动作都返回同一条明确的「本次运行没有数据库」）。
  static Err<T> _degraded<T>(String operation) =>
      Err<T>(StorageError(operation: operation, detail: '数据库不可用（降级启动）'));

  @override
  Future<Result<Uint8List>> snapshotDatabase() async =>
      _degraded<Uint8List>('backup.snapshot');

  @override
  Future<Result<int>> schemaVersion() async =>
      _degraded<int>('backup.schemaVersion');

  @override
  Future<Result<({int articles, int feeds})>> contentCounts() async =>
      _degraded<({int articles, int feeds})>('backup.contentCounts');

  @override
  Future<Result<List<MediaCacheEntry>>> readMediaCache() async =>
      _degraded<List<MediaCacheEntry>>('backup.readMediaCache');
}
