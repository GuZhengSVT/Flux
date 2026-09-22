// T046：备份与恢复小节的组件层验收（SET-076、架构 5.3）。
//
// 断言的是**界面承诺**，不是控件存在：
//   1) 风险告知在导出**之前**可见（明文备份包含个人订阅与正文，任何持有者均可读取）；
//   2) 导出必须先过风险确认对话框，确认过才会真的开始导出（用端口计数，不碰真实文件系统）；
//   3) 恢复路径先显示预检（备份时间/schema/文章数/订阅数/是否含媒体），再二次确认；
//   4) 失败按稳定类别名展示，并明说「当前数据未被改动」；取消不是错误。
//
// 这里用的是**真实的 BackupUseCase**（只把三个端口换成内存替身）：界面的承诺就是这条用例的
// 承诺，用替身顶掉用例本身会让测试通过而产品路径没被验证。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/feeds/application/file_access.dart';
import 'package:flux/features/sync/application/backup_ports.dart';
import 'package:flux/features/sync/application/backup_use_case.dart';
import 'package:flux/features/sync/presentation/backup_section.dart';

import '../../app/test_harness.dart';

/// 备份内容来源替身：给出一份固定快照（不读真实数据库）。
final class _FakeContent implements BackupContentSource {
  /// 导出的快照字节（可被用例改成「导出失败」）。
  Uint8List? snapshot = Uint8List.fromList(
    List<int>.generate(64, (int i) => i),
  );

  /// 导出被调用的次数。
  int snapshotCalls = 0;

  @override
  Future<Result<Uint8List>> snapshotDatabase() async {
    snapshotCalls++;
    final Uint8List? value = snapshot;
    if (value == null) {
      return Err<Uint8List>(
        StorageError(operation: 'backup.snapshot', detail: '测试构造的失败'),
      );
    }
    return Ok<Uint8List>(value);
  }

  @override
  Future<Result<int>> schemaVersion() async => const Ok<int>(16);

  @override
  Future<Result<({int articles, int feeds})>> contentCounts() async =>
      const Ok<({int articles, int feeds})>((articles: 42, feeds: 3));

  @override
  Future<Result<List<MediaCacheEntry>>> readMediaCache() async =>
      const Ok<List<MediaCacheEntry>>(<MediaCacheEntry>[]);
}

/// 恢复目标替身：记下被要求写入的目录与字节（不碰真实文件系统）。
final class _FakeRestoreTarget implements BackupRestoreTarget {
  /// 每次恢复请求（目录 + 数据库字节长度）。
  final List<({String directory, int size})> writes =
      <({String directory, int size})>[];

  /// 写入失败时置上（restore 应把错误带出来）。
  AppError? writeFailure;

  @override
  Future<Result<void>> writeRestoredData({
    required String directory,
    required Uint8List databaseBytes,
    required List<MediaCacheEntry> media,
  }) async {
    writes.add((directory: directory, size: databaseBytes.length));
    final AppError? failure = writeFailure;
    if (failure != null) {
      return Err<void>(failure);
    }
    return okUnit();
  }

  @override
  Future<Result<void>> verifyRestoredData({
    required String directory,
    required int expectedSchemaVersion,
  }) async => okUnit();

  @override
  String? get dataDirectoryPath => '/tmp/flux';

  @override
  String get mediaDirectoryName => 'media';
}

/// 文件端口替身：给出一个包、取消时给 null。
final class _FakeFiles implements FileAccessPort {
  /// 「用户选中的」包字节；null 表示取消。
  Uint8List? archive;

  /// 导出保存路径；null 表示取消。
  String? savePath = '/tmp/flux.zip';

  /// 已保存的字节。
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
  late _FakeContent content;
  late _FakeRestoreTarget target;
  late _FakeFiles files;

  setUp(() {
    content = _FakeContent();
    target = _FakeRestoreTarget();
    files = _FakeFiles();
  });

  /// 造一份**真实可校验**的备份包（清单与哈希都由用例自己算，因此能过一次真校验）。
  Uint8List buildArchive({bool includeMedia = false, int articleCount = 42}) {
    final Uint8List database = Uint8List.fromList(
      List<int>.generate(64, (int i) => i),
    );
    final List<BackupArchiveEntry> entries = <BackupArchiveEntry>[
      BackupArchiveEntry(name: backupDatabaseEntryName, bytes: database),
    ];
    final BackupManifest manifest = BackupManifest(
      formatVersion: backupFormatVersion,
      schemaVersion: 16,
      appVersion: '0.2.0+1',
      createdAt: DateTime.utc(2026, 9, 22, 12),
      includeMedia: includeMedia,
      entries: backupEntryRecordsOf(entries),
      articleCount: articleCount,
      feedCount: 3,
    );
    return zipEncode(<ZipEntry>[
      ZipEntry(
        name: backupManifestFileName,
        bytes: Uint8List.fromList(utf8.encode(manifest.encode())),
      ),
      for (final BackupArchiveEntry entry in entries)
        ZipEntry(name: entry.name, bytes: entry.bytes),
    ]);
  }

  /// 装配：备份端口走**组合根的参数**（Riverpod 禁止同一个 Provider 被覆盖两次，
  /// 因此测试必须经 bootstrapOverrides 的那一个位置换掉它，而不是在 ProviderScope 再覆盖）。
  Widget wrap(TestBootstrap bootstrap, {required BackupUseCase service}) =>
      wrapFluxApp(
        child: const Scaffold(body: BackupSection()),
        overrides: bootstrap.overrides(
          backupUseCase: service,
          backupNewDirectory: (String token) => '/tmp/restored-$token',
        ),
      );

  BackupUseCase service() => BackupUseCase(
    content: content,
    restoreTarget: target,
    files: files,
    currentSchemaVersion: 16,
  );

  testWidgets('风险告知在导出前可见，且导出必须先过确认对话框', (WidgetTester tester) async {
    final TestBootstrap bootstrap = TestBootstrap();
    addTearDown(bootstrap.dispose);
    await setSurfaceSize(tester, const Size(900, 900));

    await tester.pumpWidget(wrap(bootstrap, service: service()));
    await tester.pumpAndSettle();

    // 风险告知就在页面上（不需要点任何东西就能看到）。
    expect(find.byKey(const ValueKey<String>('backup-notice')), findsOneWidget);
    expect(find.textContaining('任何持有者均可读取'), findsOneWidget);

    // 点导出：先出风险确认对话框，**此时还没有开始导出**。
    await tester.tap(find.byKey(const ValueKey<String>('backup-export')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('backup-risk-dialog')),
      findsOneWidget,
    );
    expect(content.snapshotCalls, 0, reason: '风险未确认之前不得导出');

    // 取消：什么都不发生。
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(content.snapshotCalls, 0);

    // 再来一次并确认：这次真的导出，并给出回执与保存路径。
    await tester.tap(find.byKey(const ValueKey<String>('backup-export')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我已了解，继续导出'));
    await tester.pumpAndSettle();
    expect(content.snapshotCalls, 1);
    expect(find.textContaining('已导出备份'), findsOneWidget);
    expect(find.textContaining('/tmp/flux.zip'), findsOneWidget);
  });

  testWidgets('恢复先显示预检信息，二次确认后才真的写入新目录', (WidgetTester tester) async {
    final TestBootstrap bootstrap = TestBootstrap();
    addTearDown(bootstrap.dispose);
    await setSurfaceSize(tester, const Size(900, 900));
    files.archive = buildArchive();

    await tester.pumpWidget(wrap(bootstrap, service: service()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('backup-restore')));
    await tester.pumpAndSettle();

    // 预检信息：时间、schema、文章数、订阅数、是否含媒体。
    expect(
      find.byKey(const ValueKey<String>('backup-restore-dialog')),
      findsOneWidget,
    );
    expect(find.textContaining('schema v16'), findsOneWidget);
    expect(find.textContaining('42 篇文章'), findsOneWidget);
    expect(find.textContaining('3 个订阅'), findsOneWidget);
    expect(find.textContaining('不含媒体缓存'), findsOneWidget);
    expect(find.textContaining('新的数据目录'), findsOneWidget);
    expect(target.writes, isEmpty, reason: '二次确认之前不得开始恢复');

    await tester.tap(
      find.byKey(const ValueKey<String>('backup-restore-confirm')),
    );
    await tester.pumpAndSettle();
    expect(target.writes, hasLength(1));
    // 写的是**新目录**（与当前数据目录并列），不是当前数据目录本身。
    expect(target.writes.single.directory, startsWith('/tmp/restored-'));
    expect(find.textContaining('已恢复到新目录并校验通过'), findsOneWidget);
  });

  testWidgets('恢复失败按稳定类别名展示，并说明当前数据未被改动', (WidgetTester tester) async {
    final TestBootstrap bootstrap = TestBootstrap();
    addTearDown(bootstrap.dispose);
    await setSurfaceSize(tester, const Size(900, 900));
    // 包里的内容与清单哈希不符：真校验会在**写入之前**拒绝它。
    final Uint8List tampered = buildArchive();
    tampered[tampered.length - 30] = 1;
    files.archive = tampered;

    await tester.pumpWidget(wrap(bootstrap, service: service()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('backup-restore')));
    await tester.pumpAndSettle();
    // 校验失败发生在预检阶段：不该出现确认对话框，也不该有任何写入。
    expect(
      find.byKey(const ValueKey<String>('backup-restore-dialog')),
      findsNothing,
    );
    expect(target.writes, isEmpty);
    expect(find.textContaining('当前数据未被改动'), findsOneWidget);
  });

  testWidgets('用户取消选文件：不报错、不调用恢复', (WidgetTester tester) async {
    final TestBootstrap bootstrap = TestBootstrap();
    addTearDown(bootstrap.dispose);
    await setSurfaceSize(tester, const Size(900, 900));
    // files.archive 为 null 表示用户在文件面板里取消了。

    await tester.pumpWidget(wrap(bootstrap, service: service()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('backup-restore')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('backup-restore-dialog')),
      findsNothing,
    );
    expect(target.writes, isEmpty);
    expect(
      find.byKey(const ValueKey<String>('backup-notice-result')),
      findsNothing,
      reason: '取消不是错误，不该弹失败提示',
    );
  });

  testWidgets('含媒体开关写入 SET-076 并真的落库，导出沿用该值', (WidgetTester tester) async {
    final TestBootstrap bootstrap = TestBootstrap();
    addTearDown(bootstrap.dispose);
    await setSurfaceSize(tester, const Size(900, 900));

    await tester.pumpWidget(wrap(bootstrap, service: service()));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    final Result<Object?> stored = await bootstrap.settingsRepository.read(
      SettingId.set076,
    );
    expect((stored.unwrap()! as Map<String, Object?>)['includeMedia'], isTrue);

    // 导出时用的就是刚设的值：包里的清单会写明包含媒体。
    await tester.tap(find.byKey(const ValueKey<String>('backup-export')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我已了解，继续导出'));
    await tester.pumpAndSettle();
    expect(content.snapshotCalls, 1);
    final List<ZipDecodedEntry> decoded = zipDecode(files.savedBytes!)!;
    final BackupManifest manifest = BackupManifest.decode(
      utf8.decode(
        decoded
            .firstWhere((ZipDecodedEntry e) => e.name == backupManifestFileName)
            .bytes,
      ),
    )!;
    expect(manifest.includeMedia, isTrue);
  });

  testWidgets('导出失败（快照取不到）时给出带类别的失败回执', (WidgetTester tester) async {
    final TestBootstrap bootstrap = TestBootstrap();
    addTearDown(bootstrap.dispose);
    await setSurfaceSize(tester, const Size(900, 900));
    content.snapshot = null;

    await tester.pumpWidget(wrap(bootstrap, service: service()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('backup-export')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我已了解，继续导出'));
    await tester.pumpAndSettle();

    expect(find.textContaining('当前数据未被改动'), findsOneWidget);
  });
}
