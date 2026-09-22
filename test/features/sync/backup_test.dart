// T046：明文备份导出与安全恢复（架构 5.3 的备份/恢复段、SET-076、手册 6.3「恢复」节）。
//
// 六组用例，逐条对应 T046 的验收点：
//   1) **导出内容正确**：清单里每个文件的 SHA-256 与内容一致、包内**没有**任何凭据形态、
//      含/不含媒体两种开关都覆盖；
//   2) **WAL 一致性**：写入进行中（有未落盘改动）时导出的快照可以恢复且数据完整；
//   3) **路径穿越被拒**：绝对路径、上跳路径、反斜杠、盘符都拒绝，且**不动原库**；
//   4) **各失败分支都不动原库**：损坏 ZIP、错包结构版本、schema 更新、大小不符、哈希不符、
//      白名单外条目、目标目录非空；
//   5) **恢复后数据完整**：恢复出的库能打开、订阅/文章/阅读状态/收藏/正文都在，媒体按开关落地；
//   6) **清单编解码**：确定性编码、结构问题一律返回 null、条目白名单。
//
// 用**真实文件系统**（临时目录）与真实数据库，不用替身：恢复这条路径的全部价值就在于
// 「文件真的写对了吗」，用替身断言「调用了写入方法」等于什么都没验。
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:flux/core/core.dart';
import 'package:flux/features/feeds/application/file_access.dart';
import 'package:flux/features/sync/application/backup_ports.dart';
import 'package:flux/features/sync/application/backup_use_case.dart';
import 'package:flux/infrastructure/local/backup_content_source.dart';
import 'package:flux/infrastructure/local/database.dart';

/// 文件端口替身：从内存里给出一个包、保存到内存（恢复路径不经过系统面板）。
final class _FakeFiles implements FileAccessPort {
  _FakeFiles({this.archive, this.savePath});

  /// 「用户选中的」包字节；null 表示取消。
  Uint8List? archive;

  /// 保存路径；null 表示取消。
  String? savePath;

  /// 最近一次保存写下的字节（导出内容断言用）。
  Uint8List? savedBytes;

  @override
  Future<Result<PickedFile?>> pickArchiveToRead() async {
    final Uint8List? bytes = archive;
    if (bytes == null) {
      return const Ok<PickedFile?>(null);
    }
    return Ok<PickedFile?>(
      PickedFile(path: '/fake/backup.zip', content: '', bytes: bytes),
    );
  }

  @override
  Future<Result<String?>> saveBytes(
    String suggestedName,
    List<int> bytes, {
    required String mimeType,
    required List<String> extensions,
  }) async {
    savedBytes = Uint8List.fromList(bytes);
    return Ok<String?>(savePath);
  }

  @override
  Future<Result<PickedFile?>> pickOpmlToRead() async =>
      const Ok<PickedFile?>(null);

  @override
  Future<Result<String?>> saveOpml(
    String suggestedName,
    String content,
  ) async => const Ok<String?>(null);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory tempDir;
  late AppDatabase db;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('flux-backup-test');
    db = AppDatabase.openFile(File(p.join(tempDir.path, fluxDatabaseFileName)));
    await db.customSelect('SELECT 1').get();
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  /// 建立一份有内容的库：1 个源 + 2 篇文章（含状态与收藏与正文）。
  Future<int> seedContent() async {
    final int feedId = await db
        .into(db.feeds)
        .insert(
          FeedsCompanion.insert(
            syncId: 'feed.backup',
            normalizedUrl: 'https://backup.example.com/feed.xml',
            name: '备份示例源',
          ),
        );
    await db
        .into(db.articles)
        .insert(
          ArticlesCompanion.insert(
            feedId: Value<int?>(feedId),
            title: '收藏的文章',
            identityBasis: IdentityBasis.guid,
            guid: const Value<String?>('g-1'),
            guidPresent: const Value<bool>(true),
            favorite: const Value<bool>(true),
            body: const Value<String?>('正文内容'),
            bodyHash: const Value<String?>('hash-1'),
          ),
        );
    await db
        .into(db.articles)
        .insert(
          ArticlesCompanion.insert(
            feedId: Value<int?>(feedId),
            title: '稍后再读',
            identityBasis: IdentityBasis.guid,
            guid: const Value<String?>('g-2'),
            guidPresent: const Value<bool>(true),
            readingState: const Value<ReadingState>(ReadingState.later),
          ),
        );
    return feedId;
  }

  BackupUseCase useCase({FileAccessPort? files}) => BackupUseCase(
    content: DriftBackupContentSource(db, dataDirectoryPath: tempDir.path),
    restoreTarget: FileBackupRestoreTarget(dataDirectoryPath: tempDir.path),
    files: files ?? _FakeFiles(),
    currentSchemaVersion: db.schemaVersion,
  );

  group('导出：内容、清单哈希与秘密排除', () {
    test('包内只有快照/清单/媒体，清单哈希与内容一致，且没有任何凭据形态', () async {
      await seedContent();
      final _FakeFiles files = _FakeFiles(savePath: '/tmp/out.zip');
      final BackupExportResult result = (await useCase(
        files: files,
      ).export(includeMedia: false, suggestedName: 'flux.zip')).unwrap()!;

      expect(result.path, '/tmp/out.zip');
      expect(result.includeMedia, isFalse);
      expect(result.mediaEntryCount, 0);

      final List<ZipDecodedEntry> entries = zipDecode(files.savedBytes!)!;
      final Set<String> names = entries
          .map((ZipDecodedEntry e) => e.name)
          .toSet();
      expect(names, <String>{backupManifestFileName, backupDatabaseEntryName});

      // 清单里的每个条目：大小与 SHA-256 必须与实际内容一致。
      final BackupManifest manifest = BackupManifest.decode(
        utf8.decode(
          entries
              .firstWhere(
                (ZipDecodedEntry e) => e.name == backupManifestFileName,
              )
              .bytes,
        ),
      )!;
      expect(manifest.schemaVersion, db.schemaVersion);
      expect(manifest.includeMedia, isFalse);
      expect(manifest.feedCount, 1);
      expect(manifest.articleCount, 2);
      for (final BackupEntryRecord record in manifest.entries) {
        final ZipDecodedEntry actual = entries.firstWhere(
          (ZipDecodedEntry e) => e.name == record.name,
        );
        expect(actual.bytes.length, record.size, reason: record.name);
        expect(sha256Hex(actual.bytes), record.sha256, reason: record.name);
      }

      // **没有凭据形态**：快照里不含任何 Keychain 的引用值或秘密设置。
      final ZipDecodedEntry database = entries.firstWhere(
        (ZipDecodedEntry e) => e.name == backupDatabaseEntryName,
      );
      final String raw = latin1.decode(database.bytes, allowInvalid: true);
      for (final String forbidden in <String>[
        'webdav:',
        'ai-provider:',
        'search-provider:',
        'feed-auth:',
        'SET-071',
        'SET-027',
      ]) {
        expect(
          raw.contains(forbidden),
          isFalse,
          reason: '包内不得出现凭据形态：$forbidden',
        );
      }
    });

    test('含媒体开关打开时把缓存条目打进包（排除 .part 半成品）', () async {
      await seedContent();
      final Directory media = Directory(p.join(tempDir.path, 'media'));
      media.createSync(recursive: true);
      File(p.join(media.path, 'abc.img')).writeAsBytesSync(<int>[1, 2, 3, 4]);
      File(p.join(media.path, 'abc.meta'))
          .writeAsStringSync('{"mime":"image/png"}');
      // 写入中的半成品：必须被排除（打进包会让恢复出的缓存里出现永远解不开的文件）。
      File(p.join(media.path, 'pending.part')).writeAsBytesSync(<int>[9, 9]);

      final _FakeFiles files = _FakeFiles(savePath: '/tmp/with-media.zip');
      final BackupExportResult result = (await useCase(
        files: files,
      ).export(includeMedia: true, suggestedName: 'flux.zip')).unwrap()!;

      expect(result.includeMedia, isTrue);
      expect(result.mediaEntryCount, 2);
      final List<ZipDecodedEntry> entries = zipDecode(files.savedBytes!)!;
      final Set<String> names = entries
          .map((ZipDecodedEntry e) => e.name)
          .toSet();
      expect(names, contains('${backupMediaEntryPrefix}abc.img'));
      expect(names, contains('${backupMediaEntryPrefix}abc.meta'));
      expect(names, isNot(contains('${backupMediaEntryPrefix}pending.part')));
    });

    test('用户取消保存：返回 Ok(null) 而不是错误', () async {
      await seedContent();
      final Result<BackupExportResult?> result = await useCase(
        files: _FakeFiles(),
      ).export(includeMedia: false, suggestedName: 'flux.zip');
      expect(result.isOk, isTrue);
      expect(result.unwrap(), isNull);
    });

    test('导出用的临时快照文件在导出后被清掉（不留明文副本）', () async {
      await seedContent();
      await useCase(files: _FakeFiles(savePath: '/tmp/x.zip'))
          .export(includeMedia: false, suggestedName: 'x.zip');
      final List<File> leftovers = tempDir
          .listSync()
          .whereType<File>()
          .where((File f) => f.path.contains('backup-snapshot-'))
          .toList(growable: false);
      expect(leftovers, isEmpty, reason: '临时快照是一份明文副本，必须清掉（用户以为只导到了选定位置）');
    });
  });

  group('WAL 一致性：写进行中导出的快照可恢复且数据完整', () {
    test('插入后立即导出：快照含全部已提交内容（复制活动文件会丢掉它们）', () async {
      final int feedId = await seedContent();
      // 再追加一批「刚写下」的行：如果实现是复制活动数据库文件，日志里已提交但
      // 未落盘的页就会缺失，而这批行正是判据。
      for (int i = 0; i < 50; i++) {
        await db
            .into(db.articles)
            .insert(
              ArticlesCompanion.insert(
                feedId: Value<int?>(feedId),
                title: '刚写入的 $i',
                identityBasis: IdentityBasis.guid,
                guid: Value<String?>('g-bulk-$i'),
                guidPresent: const Value<bool>(true),
              ),
            );
      }

      final _FakeFiles files = _FakeFiles(savePath: '/tmp/live.zip');
      await useCase(files: files)
          .export(includeMedia: false, suggestedName: 'live.zip');
      final BackupManifest manifest = BackupManifest.decode(
        utf8.decode(
          zipDecode(files.savedBytes!)!
              .firstWhere(
                (ZipDecodedEntry e) => e.name == backupManifestFileName,
              )
              .bytes,
        ),
      )!;
      expect(manifest.articleCount, 52, reason: '52 = 2 篇种子 + 50 篇刚写入');

      // 恢复到一个新目录并逐行核对：一致性不是「数对了」，而是「内容真的在」。
      final String restored = p.join(tempDir.path, 'restored');
      final Result<BackupRestoreResult> result = await _restoreInto(
        useCase: useCase(files: files),
        archive: files.savedBytes!,
        target: restored,
      );
      expect(result.isOk, isTrue, reason: result.errorOrNull?.message);
      final AppDatabase restoredDb = AppDatabase.openFile(
        File(p.join(restored, fluxDatabaseFileName)),
      );
      addTearDown(restoredDb.close);
      final List<Article> rows = await restoredDb
          .select(restoredDb.articles)
          .get();
      expect(rows.length, 52);
      expect(
        rows.where((Article a) => a.title == '刚写入的 49').length,
        1,
        reason: '最后写入的那一篇也在（WAL 里已提交的内容没有丢）',
      );
    });
  });

  group('路径穿越与白名单', () {
    test('不安全条目名都被拒（绝对路径 / 上跳 / 反斜杠 / 盘符 / 空段）', () {
      for (final String bad in <String>[
        '/etc/passwd',
        '../../etc/passwd',
        'media/../../escape.img',
        r'media\windows.img',
        'C:/windows/system32',
        'a//b',
        'media/',
        '.',
        '..',
        '',
      ]) {
        expect(isSafeBackupEntryName(bad), isFalse, reason: '不安全的名字必须被拒：$bad');
      }
      for (final String good in <String>[
        'flux.sqlite',
        'manifest.json',
        'media/abc.img',
        'media/中文-图.img',
      ]) {
        expect(isSafeBackupEntryName(good), isTrue, reason: good);
      }
    });

    test('带路径穿越的包被拒，且**原库一行不动**', () async {
      await seedContent();
      final Uint8List archive = zipEncode(<ZipEntry>[
        ZipEntry(
          name: 'manifest.json',
          bytes: Uint8List.fromList(utf8.encode('{}')),
        ),
        ZipEntry(
          name: '../../evil.sqlite',
          bytes: Uint8List.fromList(<int>[1, 2, 3]),
        ),
      ]);
      final Result<BackupInspection?> preview = await useCase(
        files: _FakeFiles(archive: archive),
      ).inspectBackup();
      expect(preview.isErr, isTrue);
      expect(preview.errorOrNull!.message.contains('unsafeEntryPath'), isTrue);

      // 原库与它的目录在拒绝之后完全一致。
      expect(
        File(p.join(tempDir.path, fluxDatabaseFileName)).existsSync(),
        isTrue,
      );
      expect((await db.select(db.articles).get()).length, 2);
      final List<String> dirEntries = tempDir
          .listSync()
          .map((FileSystemEntity e) => p.basename(e.path))
          .toList();
      expect(dirEntries.contains('evil.sqlite'), isFalse);
      expect(dirEntries.contains('restored'), isFalse);
    });

    test('白名单之外的条目被拒（清单里声明了它也一样）', () {
      final Uint8List archive = zipEncode(<ZipEntry>[
        ZipEntry(
          name: backupManifestFileName,
          bytes: _manifestBytes(
            entries: const <String>['flux.sqlite', 'settings.json'],
          ),
        ),
        ZipEntry(
          name: 'flux.sqlite',
          bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
        ),
        ZipEntry(
          name: 'settings.json',
          bytes: Uint8List.fromList(utf8.encode('{"secret":"x"}')),
        ),
      ]);
      final Result<BackupRestorePreview> inspected = useCase()
          .inspectArchiveBytes(archive);
      expect(inspected.isErr, isTrue);
      expect(
        inspected.errorOrNull!.message.contains('manifestUnreadable') ||
            inspected.errorOrNull!.message.contains('disallowedEntry'),
        isTrue,
        reason: inspected.errorOrNull!.message,
      );
    });
  });

  group('各失败分支都不动原库', () {
    test('损坏的 ZIP（截断）被拒', () async {
      await seedContent();
      final Uint8List archive = zipEncode(<ZipEntry>[
        ZipEntry(
          name: backupManifestFileName,
          bytes: _manifestBytes(entries: const <String>['flux.sqlite']),
        ),
        ZipEntry(
          name: 'flux.sqlite',
          bytes: Uint8List.fromList(
            List<int>.generate(500, (int i) => i % 251),
          ),
        ),
      ]);
      final Uint8List truncated = Uint8List.sublistView(
        archive,
        0,
        archive.length - 12,
      );
      final Result<BackupInspection?> preview = await useCase(
        files: _FakeFiles(archive: truncated),
      ).inspectBackup();
      expect(preview.isErr, isTrue);
      expect(preview.errorOrNull!.message.contains('corruptArchive'), isTrue);
      expect((await db.select(db.articles).get()).length, 2);
    });

    test('包结构版本更高时拒绝（读不懂的包不按旧形状尽力解读）', () {
      final Uint8List archive = zipEncode(<ZipEntry>[
        ZipEntry(
          name: backupManifestFileName,
          bytes: Uint8List.fromList(
            utf8.encode(
              jsonEncode(<String, Object?>{
                'formatVersion': backupFormatVersion + 1,
                'schemaVersion': 1,
                'appVersion': '9.9.9',
                'createdAt': DateTime.utc(2026).toIso8601String(),
                'includeMedia': false,
                'articleCount': 0,
                'feedCount': 0,
                'entries': <Object?>[],
              }),
            ),
          ),
        ),
        ZipEntry(
          name: 'flux.sqlite',
          bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
        ),
      ]);
      final Result<BackupRestorePreview> inspected = useCase()
          .inspectArchiveBytes(archive);
      expect(inspected.isErr, isTrue);
      expect(
        inspected.errorOrNull!.message.contains('manifestUnreadable'),
        isTrue,
      );
    });

    test('备份 schema 比当前应用新时拒绝（旧版本不能写较新 schema）', () {
      expect(
        backupSchemaIsRestorable(
          backupSchemaVersion: 17,
          currentSchemaVersion: 16,
        ),
        isFalse,
      );
      expect(
        backupSchemaIsRestorable(
          backupSchemaVersion: 16,
          currentSchemaVersion: 16,
        ),
        isTrue,
      );
      expect(
        backupSchemaIsRestorable(
          backupSchemaVersion: 5,
          currentSchemaVersion: 16,
        ),
        isTrue,
        reason: '旧备份由 SQLite 打开时按真实迁移策略升级',
      );
    });

    test('哈希与清单不符时拒绝，且原库不动', () async {
      await seedContent();
      final Uint8List database = Uint8List.fromList(<int>[7, 7, 7, 7]);
      final Uint8List archive = zipEncode(<ZipEntry>[
        ZipEntry(
          name: backupManifestFileName,
          // 清单声明的哈希与真实内容不符（模拟「导出后被人改过」）。
          bytes: _manifestBytes(
            entries: const <String>['flux.sqlite'],
            overrideHash: 'deadbeef',
            databaseSize: database.length,
          ),
        ),
        ZipEntry(name: 'flux.sqlite', bytes: database),
      ]);
      final Result<BackupInspection?> preview = await useCase(
        files: _FakeFiles(archive: archive),
      ).inspectBackup();
      expect(preview.isErr, isTrue);
      expect(preview.errorOrNull!.message.contains('hashMismatch'), isTrue);
      expect((await db.select(db.articles).get()).length, 2);
    });

    test('大小与清单不符时拒绝（sizeMismatch）', () {
      final Uint8List database = Uint8List.fromList(<int>[7, 7, 7, 7]);
      final Uint8List archive = zipEncode(<ZipEntry>[
        ZipEntry(
          name: backupManifestFileName,
          bytes: _manifestBytes(
            entries: const <String>['flux.sqlite'],
            databaseSize: database.length + 10,
          ),
        ),
        ZipEntry(name: 'flux.sqlite', bytes: database),
      ]);
      final Result<BackupRestorePreview> inspected = useCase()
          .inspectArchiveBytes(archive);
      expect(inspected.isErr, isTrue);
      expect(inspected.errorOrNull!.message.contains('sizeMismatch'), isTrue);
    });

    test('清单声明的条目在包里缺失：拒绝，不是「少一个也能恢复」', () {
      final Uint8List archive = zipEncode(<ZipEntry>[
        ZipEntry(
          name: backupManifestFileName,
          bytes: _manifestBytes(
            entries: const <String>['flux.sqlite', 'media/abc.img'],
          ),
        ),
        ZipEntry(
          name: 'flux.sqlite',
          bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
        ),
      ]);
      final Result<BackupRestorePreview> inspected = useCase()
          .inspectArchiveBytes(archive);
      expect(inspected.isErr, isTrue);
      expect(
        inspected.errorOrNull!.message.contains('databaseEntryMissing'),
        isTrue,
        reason: inspected.errorOrNull!.message,
      );
    });

    test('缺版本清单：拒绝（manifestMissing）', () {
      final Uint8List archive = zipEncode(<ZipEntry>[
        ZipEntry(
          name: 'flux.sqlite',
          bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
        ),
      ]);
      expect(
        useCase().inspectArchiveBytes(archive).errorOrNull!.message,
        contains('manifestMissing'),
      );
    });

    test('目标目录非空时拒绝写入（不覆盖已有数据目录）', () async {
      await seedContent();
      final Directory occupied = Directory(p.join(tempDir.path, 'occupied'));
      occupied.createSync(recursive: true);
      File(p.join(occupied.path, 'something.txt')).writeAsStringSync('x');

      final Result<void> written =
          await FileBackupRestoreTarget(dataDirectoryPath: tempDir.path)
              .writeRestoredData(
                directory: occupied.path,
                databaseBytes: Uint8List.fromList(<int>[1, 2, 3]),
                media: const <MediaCacheEntry>[],
              );
      expect(written.isErr, isTrue);
      expect(
        File(p.join(occupied.path, 'something.txt')).readAsStringSync(),
        'x',
        reason: '拒绝写入：目标目录里原有的东西一行不动',
      );
    });
  });

  group('恢复后数据完整', () {
    test('恢复到新目录：订阅/文章/状态/收藏/正文都在，且能真的打开', () async {
      await seedContent();
      final _FakeFiles files = _FakeFiles(savePath: '/tmp/full.zip');
      await useCase(files: files)
          .export(includeMedia: false, suggestedName: 'full.zip');
      final String restored = p.join(tempDir.path, 'restored-full');
      final Result<BackupRestoreResult> result = await _restoreInto(
        useCase: useCase(files: files),
        archive: files.savedBytes!,
        target: restored,
      );
      expect(result.isOk, isTrue, reason: result.errorOrNull?.message);
      expect(result.unwrap().directory, restored);
      // 预检信息可读（界面在切换前要把它给用户看）。
      expect(result.unwrap().preview.articleCount, 2);
      expect(result.unwrap().preview.schemaVersion, db.schemaVersion);

      final AppDatabase restoredDb = AppDatabase.openFile(
        File(p.join(restored, fluxDatabaseFileName)),
      );
      addTearDown(restoredDb.close);
      final List<Feed> feeds = await restoredDb.select(restoredDb.feeds).get();
      expect(feeds.length, 1);
      expect(feeds.single.name, '备份示例源');
      final List<Article> articles = await restoredDb
          .select(restoredDb.articles)
          .get();
      expect(articles.length, 2);
      final Article favorite = articles.firstWhere(
        (Article a) => a.title == '收藏的文章',
      );
      expect(favorite.favorite, isTrue);
      expect(favorite.body, '正文内容');
      expect(favorite.bodyHash, 'hash-1');
      final Article later = articles.firstWhere(
        (Article a) => a.title == '稍后再读',
      );
      expect(later.readingState, ReadingState.later);
      // 原库仍在原位、内容不变（恢复从来不动它）。
      expect((await db.select(db.articles).get()).length, 2);
    });

    test('恢复时不含媒体：媒体条目被丢掉，数据库照常恢复', () async {
      await seedContent();
      final Directory media = Directory(p.join(tempDir.path, 'media'));
      media.createSync(recursive: true);
      File(p.join(media.path, 'a.img')).writeAsBytesSync(<int>[1, 2, 3]);

      final _FakeFiles files = _FakeFiles(savePath: '/tmp/m.zip');
      await useCase(files: files)
          .export(includeMedia: true, suggestedName: 'm.zip');
      // 恢复时「用户选中刚才导出的那个文件」：替身据此提供预检与恢复用的字节。
      files.archive = files.savedBytes;
      final String restored = p.join(tempDir.path, 'restored-nomedia');
      final BackupInspection preview = (await useCase(
        files: files,
      ).inspectBackup()).unwrap()!;
      final Result<BackupRestoreResult> result = await useCase(files: files)
          .restore(
            preview: preview.preview,
            archiveBytes: preview.archiveBytes,
            targetDirectory: restored,
            includeMedia: false,
          );
      expect(result.isOk, isTrue, reason: result.errorOrNull?.message);
      expect(
        Directory(p.join(restored, 'media')).existsSync(),
        isFalse,
        reason: '不含媒体时连目录都不建',
      );
      expect(File(p.join(restored, fluxDatabaseFileName)).existsSync(), isTrue);
    });

    test('恢复时含媒体：媒体文件按原名落到新目录的 media/ 下', () async {
      await seedContent();
      final Directory media = Directory(p.join(tempDir.path, 'media'));
      media.createSync(recursive: true);
      File(p.join(media.path, 'pic.img')).writeAsBytesSync(<int>[5, 6, 7, 8]);
      File(p.join(media.path, 'pic.meta')).writeAsStringSync('meta');

      final _FakeFiles files = _FakeFiles(savePath: '/tmp/m2.zip');
      await useCase(files: files)
          .export(includeMedia: true, suggestedName: 'm2.zip');
      files.archive = files.savedBytes;
      final String restored = p.join(tempDir.path, 'restored-media');
      final BackupInspection preview = (await useCase(
        files: files,
      ).inspectBackup()).unwrap()!;
      final Result<BackupRestoreResult> result = await useCase(files: files)
          .restore(
            preview: preview.preview,
            archiveBytes: preview.archiveBytes,
            targetDirectory: restored,
          );
      expect(result.isOk, isTrue, reason: result.errorOrNull?.message);
      final File restoredImage = File(p.join(restored, 'media', 'pic.img'));
      expect(restoredImage.existsSync(), isTrue);
      expect(restoredImage.readAsBytesSync(), <int>[5, 6, 7, 8]);
      expect(
        File(p.join(restored, 'media', 'pic.meta')).readAsStringSync(),
        'meta',
      );
    });

    test('恢复出来的文件不是有效数据库时校验失败（写入完成 != 恢复成功）', () async {
      final String bogus = p.join(tempDir.path, 'bogus');
      final Result<void> written =
          await FileBackupRestoreTarget(dataDirectoryPath: tempDir.path)
              .writeRestoredData(
                directory: bogus,
                databaseBytes: Uint8List.fromList(
                  utf8.encode('this is not a sqlite file'),
                ),
                media: const <MediaCacheEntry>[],
              );
      expect(written.isOk, isTrue, reason: '写入本身会成功（字节确实写下去了）');
      final Result<void> check = await FileBackupRestoreTarget(
        dataDirectoryPath: tempDir.path,
      ).verifyRestoredData(directory: bogus, expectedSchemaVersion: 16);
      expect(check.isErr, isTrue, reason: '校验必须发现「这个文件根本打不开」，否则用户重启后才知道');
    });

    test('schema 与清单不一致时校验失败', () async {
      await seedContent();
      final String restored = p.join(tempDir.path, 'restored-schema');
      await FileBackupRestoreTarget(dataDirectoryPath: tempDir.path)
          .writeRestoredData(
            directory: restored,
            databaseBytes: (await DriftBackupContentSource(
              db,
              dataDirectoryPath: tempDir.path,
            ).snapshotDatabase()).unwrap(),
            media: const <MediaCacheEntry>[],
          );
      final Result<void> check = await FileBackupRestoreTarget(
        dataDirectoryPath: tempDir.path,
      ).verifyRestoredData(directory: restored, expectedSchemaVersion: 999);
      expect(check.isErr, isTrue);
      expect(check.errorOrNull!.message.contains('schemaMismatch'), isTrue);
    });
  });

  group('清单编解码与白名单', () {
    test('清单编码确定性：同内容同字节（条目顺序无关）', () {
      final BackupManifest a = BackupManifest(
        formatVersion: backupFormatVersion,
        schemaVersion: 16,
        appVersion: '0.2.0+1',
        createdAt: DateTime.utc(2026, 9, 22, 12),
        includeMedia: false,
        entries: const <BackupEntryRecord>[
          BackupEntryRecord(name: 'flux.sqlite', size: 3, sha256: 'aa'),
          BackupEntryRecord(name: 'manifest.json', size: 1, sha256: 'bb'),
        ],
        articleCount: 2,
        feedCount: 1,
      );
      expect(a.encode(), a.encode());
      final BackupManifest reversed = BackupManifest(
        formatVersion: backupFormatVersion,
        schemaVersion: 16,
        appVersion: '0.2.0+1',
        createdAt: DateTime.utc(2026, 9, 22, 12),
        includeMedia: false,
        entries: a.entries.reversed.toList(growable: false),
        articleCount: 2,
        feedCount: 1,
      );
      expect(reversed.encode(), a.encode());
    });

    test('清单解码：缺字段、类型错、白名单外条目、未知包版本一律返回 null', () {
      expect(BackupManifest.decode('not json'), isNull);
      expect(BackupManifest.decode('{}'), isNull);
      expect(
        BackupManifest.decode(
          jsonEncode(<String, Object?>{
            'formatVersion': backupFormatVersion,
            'schemaVersion': 16,
            'appVersion': '1',
            'createdAt': '2026-09-22T12:00:00.000Z',
            'includeMedia': false,
            'articleCount': 0,
            'feedCount': 0,
            'entries': <Object?>[
              <String, Object?>{
                'name': 'flux.sqlite',
                'size': 1,
                'sha256': 'a',
              },
              <String, Object?>{'name': 'evil.bin', 'size': 1, 'sha256': 'a'},
            ],
          }),
        ),
        isNull,
        reason: '清单里出现白名单之外的条目 = 这个包不属于本应用',
      );
      expect(
        BackupManifest.decode(
          jsonEncode(<String, Object?>{
            'formatVersion': backupFormatVersion + 1,
            'schemaVersion': 16,
            'appVersion': '1',
            'createdAt': '2026-09-22T12:00:00.000Z',
            'includeMedia': false,
            'articleCount': 0,
            'feedCount': 0,
            'entries': <Object?>[],
          }),
        ),
        isNull,
      );
    });

    test('备份条目白名单：只允许快照/清单/媒体', () {
      expect(backupEntryAllowed(backupManifestFileName), isTrue);
      expect(backupEntryAllowed(backupDatabaseEntryName), isTrue);
      expect(backupEntryAllowed('media/x.img'), isTrue);
      expect(backupEntryAllowed('settings.json'), isFalse);
      expect(backupEntryAllowed('keychain.json'), isFalse);
      expect(backupEntryAllowed('diagnostics.log'), isFalse);
      expect(
        backupEntryAllowed('media/../../escape.img'),
        isFalse,
        reason: '前缀正确但目标在包外：仍要过路径检查',
      );
      expect(backupEntryAllowed('media'), isFalse);
      // 安全类失败可被单独识别（界面据此给出不同的说明与处置）。
      expect(
        isBackupSecurityFailure(BackupFailureKind.unsafeEntryPath),
        isTrue,
      );
      expect(isBackupSecurityFailure(BackupFailureKind.hashMismatch), isFalse);
    });
  });
}

/// 走一次「预检 → 恢复」并把结果返回（恢复路径必须经预检，不能直接给字节）。
Future<Result<BackupRestoreResult>> _restoreInto({
  required BackupUseCase useCase,
  required Uint8List archive,
  required String target,
}) async {
  final Result<BackupRestorePreview> preview = useCase.inspectArchiveBytes(
    archive,
  );
  if (preview.isErr) {
    return Err<BackupRestoreResult>(preview.errorOrNull!);
  }
  return useCase.restore(
    preview: preview.unwrap(),
    archiveBytes: archive,
    targetDirectory: target,
  );
}

/// 造一份最小可用的清单字节（[entries] 是清单声明的条目名）。
Uint8List _manifestBytes({
  required List<String> entries,
  String? overrideHash,
  int? databaseSize,
}) {
  final List<BackupEntryRecord> records = <BackupEntryRecord>[
    for (final String name in entries)
      BackupEntryRecord(
        name: name,
        size: databaseSize ?? 4,
        sha256:
            overrideHash ?? sha256Hex(Uint8List.fromList(<int>[1, 2, 3, 4])),
      ),
  ];
  return Uint8List.fromList(
    utf8.encode(
      BackupManifest(
        formatVersion: backupFormatVersion,
        schemaVersion: 16,
        appVersion: '0.2.0+1',
        createdAt: DateTime.utc(2026, 9, 22),
        includeMedia: false,
        entries: records,
        articleCount: 0,
        feedCount: 0,
      ).encode(),
    ),
  );
}
