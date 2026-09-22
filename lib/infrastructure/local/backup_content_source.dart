// 备份内容来源与恢复目标的 drift/文件实现（T046；端口在 features/sync/application/backup_ports.dart）。
//
// **一致性快照**（架构 5.3 明确「使用 SQLite 备份机制而非复制活动数据库并遗漏 WAL」）：
//
//   本实现用 `VACUUM INTO '<临时文件>'`。为什么是它而不是 `sqlite3_backup` 的 Dart 绑定：
//     * sqlite3 3.x 的 Dart 包只在 sqlite3.dart 里暴露 open/execute/select 这类接口，
//       备份 API 需要拿到原生 `sqlite3_backup_*` 句柄，得走 FFI 自己声明——那是**更多**的
//       原生面与更多的崩溃点；
//     * `VACUUM INTO` 是 SQLite 3.27 起的**公开 SQL 语句**，语义是「把当前库的一份一致性
//       快照写进一个新文件」。它与备份 API 一样会读到 WAL 中已提交的内容（它走的是正常的
//       读事务），因此不会出现「复制文件丢 WAL」那个真实缺陷；
//     * 它顺带压实了空闲页，因此导出的快照通常比原库小——这一点是副产品，不是选它的理由。
//
//   临时文件写在**与数据库同一目录**（同卷，保证 rename 语义），完成后读成字节并删除。
//   不直接写到用户选的位置：`VACUUM INTO` 的目标文件由 SQLite 决定内容，而我们还要把它装进
//   ZIP，因此中间必然有一份临时副本。
//
// **恢复**：只写调用方给的**新目录**（不存在则创建，已存在且非空则拒绝），写完用
// `openAppDatabase` 真的打开一次做校验。本文件里**没有任何**写到「当前数据目录」的语句——
// 「失败不动原库」因此是结构性的。
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import 'package:flux/core/core.dart';
import 'package:flux/features/sync/application/backup_ports.dart';

import 'database.dart';

/// 媒体缓存里**算作条目**的文件扩展名（与 T021 的 ImageCacheService 同一口径）。
const List<String> backupMediaEntryExtensions = <String>['.img', '.meta'];

/// 媒体缓存里**明确排除**的文件扩展名（写入中的半成品）。
///
/// 把 `.part` 打进备份会让恢复出来的缓存里出现一批永远解不开的残缺文件——而它们会一直占着
/// 空间直到 LRU 淘汰，用户却没有任何办法分辨「这张图为什么打不开」。
const List<String> backupMediaExcludedExtensions = <String>['.part'];

/// 从打开的数据库读备份内容。
final class DriftBackupContentSource implements BackupContentSource {
  /// 绑定数据库与数据目录。
  const DriftBackupContentSource(this._db, {required this.dataDirectoryPath});

  final AppDatabase _db;

  /// 数据目录（临时快照与媒体目录都在它下面）。
  final String dataDirectoryPath;

  @override
  Future<Result<Uint8List>> snapshotDatabase() async {
    final String target = p.join(
      dataDirectoryPath,
      'backup-snapshot-${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    try {
      // VACUUM INTO 的目标**不能已存在**（SQLite 会直接报错），因此这里先确认它不存在。
      final File file = File(target);
      if (file.existsSync()) {
        await file.delete();
      }
      // 单引号在 SQL 里转义：路径可能含单引号（用户主目录名），不转义会让语句直接语法错误。
      final String escaped = target.replaceAll("'", "''");
      await _db.customStatement("VACUUM INTO '$escaped'");
      if (!file.existsSync()) {
        return Err<Uint8List>(
          StorageError(
            operation: 'backup.snapshot',
            detail: 'VACUUM INTO 未产出文件',
          ),
        );
      }
      final Uint8List bytes = await file.readAsBytes();
      return Ok<Uint8List>(bytes);
    } on Exception catch (error, stackTrace) {
      return Err<Uint8List>(
        StorageError(
          operation: 'backup.snapshot',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    } finally {
      // 临时文件必须清掉：它是一份**明文副本**，留在数据目录里等于备份的旁路（用户以为
      // 「只导出到选定的位置」，而磁盘上还躺着一份）。删除失败不报错（下一次导出会覆盖
      // 同名规则之外的旧文件，且它不含任何原库没有的东西）。
      try {
        final File file = File(target);
        if (file.existsSync()) {
          await file.delete();
        }
      } on Exception {
        // 见上。
      }
    }
  }

  @override
  Future<Result<int>> schemaVersion() async {
    try {
      final List<QueryRow> rows = await _db
          .customSelect('PRAGMA user_version')
          .get();
      final Object? value = rows.isEmpty ? null : rows.first.data.values.first;
      final int version = value is int ? value : _db.schemaVersion;
      return Ok<int>(version);
    } on Exception catch (error, stackTrace) {
      return Err<int>(
        StorageError(
          operation: 'backup.schemaVersion',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<({int articles, int feeds})>> contentCounts() async {
    try {
      final List<QueryRow> articles = await _db
          .customSelect('SELECT COUNT(*) AS n FROM articles')
          .get();
      final List<QueryRow> feeds = await _db
          .customSelect('SELECT COUNT(*) AS n FROM feeds')
          .get();
      return Ok<({int articles, int feeds})>((
        articles: _countOf(articles),
        feeds: _countOf(feeds),
      ));
    } on Exception catch (error, stackTrace) {
      return Err<({int articles, int feeds})>(
        StorageError(
          operation: 'backup.contentCounts',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<List<MediaCacheEntry>>> readMediaCache() async {
    try {
      final Directory root = Directory(p.join(dataDirectoryPath, 'media'));
      if (!root.existsSync()) {
        return const Ok<List<MediaCacheEntry>>(<MediaCacheEntry>[]);
      }
      final List<MediaCacheEntry> entries = <MediaCacheEntry>[];
      for (final FileSystemEntity entity in root.listSync()) {
        if (entity is! File) {
          continue;
        }
        final String name = p.basename(entity.path);
        if (backupMediaExcludedExtensions.any(name.endsWith)) {
          continue;
        }
        if (!backupMediaEntryExtensions.any(name.endsWith)) {
          continue;
        }
        entries.add(
          MediaCacheEntry(
            relativePath: name,
            bytes: await entity.readAsBytes(),
          ),
        );
      }
      // 排序让**同一份内容编出同一份包**（用例可以据此断言确定性）。
      entries.sort(
        (MediaCacheEntry a, MediaCacheEntry b) =>
            a.relativePath.compareTo(b.relativePath),
      );
      return Ok<List<MediaCacheEntry>>(entries);
    } on Exception catch (error, stackTrace) {
      return Err<List<MediaCacheEntry>>(
        StorageError(
          operation: 'backup.readMediaCache',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  static int _countOf(List<QueryRow> rows) {
    if (rows.isEmpty) {
      return 0;
    }
    final Object? value = rows.first.data.values.first;
    return value is int ? value : int.tryParse('$value') ?? 0;
  }
}

/// 把恢复结果写到新目录并校验。
final class FileBackupRestoreTarget implements BackupRestoreTarget {
  /// 构造目标。
  const FileBackupRestoreTarget({required this.dataDirectoryPath});

  @override
  final String? dataDirectoryPath;

  @override
  String get mediaDirectoryName => fluxMediaDirectoryName;

  @override
  Future<Result<void>> writeRestoredData({
    required String directory,
    required Uint8List databaseBytes,
    required List<MediaCacheEntry> media,
  }) async {
    try {
      final Directory target = Directory(directory);
      // 目标必须**不存在或为空**：写到一个已经有数据的目录上会让「失败不动原库」失效
      // （失败时原库已被部分覆盖）。这是本实现里唯一一条写前检查，因为它守的是最坏的情形。
      if (target.existsSync()) {
        final bool empty = target.listSync().isEmpty;
        if (!empty) {
          return Err<void>(
            StorageError(
              operation: 'backup.restore',
              detail: '目标目录非空（恢复必须写到干净目录）',
            ),
          );
        }
      } else {
        await target.create(recursive: true);
      }

      await File(p.join(directory, fluxDatabaseFileName))
          .writeAsBytes(databaseBytes, flush: true);
      if (media.isNotEmpty) {
        final Directory mediaRoot = Directory(
          p.join(directory, fluxMediaDirectoryName),
        );
        await mediaRoot.create(recursive: true);
        for (final MediaCacheEntry entry in media) {
          // 条目名由**校验过**的包内名字派生（相对路径已经过 isSafeBackupEntryName）：
          // 这里再拼一次 p.join 而不是直接用包内名字，保证最终路径一定在 mediaRoot 之下。
          final String name = p.basename(entry.relativePath);
          await File(p.join(mediaRoot.path, name))
              .writeAsBytes(entry.bytes, flush: true);
        }
      }
      return okUnit();
    } on Exception catch (error, stackTrace) {
      return Err<void>(
        StorageError(
          operation: 'backup.restore',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<void>> verifyRestoredData({
    required String directory,
    required int expectedSchemaVersion,
  }) async {
    final File file = File(p.join(directory, fluxDatabaseFileName));
    if (!file.existsSync()) {
      return Err<void>(
        StorageError(
          operation: 'backup.verify',
          detail: '恢复目录里没有数据库文件',
          isMissing: true,
        ),
      );
    }
    // 用**真实打开**做校验：文件存在、大小对、甚至 header 对，都不等于这个库能用
    // （页结构损坏、迁移中断都会在读第一张表时才暴露）。
    final Result<AppDatabase> opened = await openAppDatabase(file);
    if (opened.isErr) {
      return Err<void>(opened.errorOrNull!);
    }
    final AppDatabase db = opened.unwrap();
    try {
      await db.customSelect('SELECT 1').get();
      final List<QueryRow> rows = await db
          .customSelect('PRAGMA user_version')
          .get();
      final Object? value = rows.isEmpty ? null : rows.first.data.values.first;
      final int actual = value is int ? value : -1;
      if (actual != expectedSchemaVersion) {
        return Err<void>(
          ValidationError(
            field: 'backupRestore',
            reason: 'schemaMismatch',
            value: 'expected=$expectedSchemaVersion actual=$actual',
          ),
        );
      }
      return okUnit();
    } on Exception catch (error, stackTrace) {
      return Err<void>(
        StorageError(
          operation: 'backup.verify',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    } finally {
      await db.close();
    }
  }

  /// 恢复结果里媒体目录的名字（与运行时同名，恢复出来的目录才能直接被应用使用）。
  String get fluxMediaDirectoryName => 'media';
}
