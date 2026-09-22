// T048：诊断导出**用例层**验收（SET-082、架构第 8 节）。
//
// 与 test/core/diagnostics_export_test.dart 的分工：那一条验「白名单与脱敏的规则」，这一条验
// 「**真实四节内容**装进包之后仍然没有秘密/原文/prompt」。这是最要紧的一条——规则正确但某节
// 实现顺手把正文塞进一个白名单字段（例如把整段正文放进 logText），规则层是看不出来的。
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/feeds/application/file_access.dart';
import 'package:flux/features/settings/application/diagnostics_export_service.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/diagnostics.dart';
import 'package:flux/infrastructure/local/diagnostics_export_source.dart';
import 'package:flux/infrastructure/local/image_cache_service.dart';
import 'package:flux/infrastructure/local/media_cache_port_adapter.dart';
import 'package:flux/infrastructure/local/storage_cleanup_store.dart';

/// 文件端口替身：保存到内存（不弹系统面板）。
final class _FakeFiles implements FileAccessPort {
  /// 最近一次保存的字节。
  List<int>? savedBytes;

  /// 保存路径；null 表示用户取消。
  String? savePath = '/tmp/flux-diagnostics.txt';

  @override
  Future<Result<String?>> saveBytes(
    String suggestedName,
    List<int> bytes, {
    required String mimeType,
    required List<String> extensions,
  }) async {
    savedBytes = bytes;
    return Ok<String?>(savePath);
  }

  @override
  Future<Result<String?>> saveOpml(
    String suggestedName,
    String content,
  ) async => const Ok<String?>(null);

  @override
  Future<Result<PickedFile?>> pickOpmlToRead() async =>
      const Ok<PickedFile?>(null);

  @override
  Future<Result<PickedFile?>> pickArchiveToRead() async =>
      const Ok<PickedFile?>(null);
}

/// 固定时钟。
final class _FixedClock implements Clock {
  _FixedClock(this._now);

  final DateTime _now;

  @override
  DateTime now() => _now;

  @override
  Duration monotonic() => Duration.zero;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late Directory mediaDir;
  late DiagnosticLog log;
  late _FakeFiles files;
  late DiagnosticsExportService service;
  final DateTime now = DateTime.utc(2026, 9, 22, 12);

  /// 库里写入的敏感样本（断言它们**不**出现在包里）。
  const String secretBody = '这是文章的正文原文，含个人订阅内容';
  const String secretPrompt = '你是一个新闻编辑，请把下面的材料写成摘要';
  const String apiKey = 'sk-abcdefghijklmnop1234567890';
  const String webdavPassword = 'correcthorsebatterystaple';

  setUp(() async {
    db = AppDatabase.memory();
    await db.customSelect('SELECT 1').get();
    mediaDir = Directory.systemTemp.createTempSync('flux_t048_diag_');
    log = DiagnosticLog();
    files = _FakeFiles();

    // 库里放一份「有内容」的数据：正文、AI 结果、任务输入快照（prompt）。
    final int feedId = await db
        .into(db.feeds)
        .insert(
          FeedsCompanion.insert(
            syncId: 'feed-1',
            normalizedUrl: 'https://dav.example/feed.xml',
            name: '含秘密参数的源',
          ),
        );
    await db
        .into(db.articles)
        .insert(
          ArticlesCompanion.insert(
            feedId: Value<int?>(feedId),
            title: '标题里也可能有原文',
            identityBasis: IdentityBasis.guid,
            body: const Value<String?>(secretBody),
          ),
        );
    // AI 任务：输入快照里带 prompt，结果里带产出。
    await db.customStatement(
      'INSERT INTO ai_tasks (task_id, kind, input_snapshot, prompt_hash, '
      'model_aliases, route_model_ids, status, consumed_tokens, attempt_count, '
      'result_text, from_cache, created_at, updated_at) VALUES '
      "('t1', 'summary', ?, 'h', '[]', '[]', 'succeeded', 0, 1, "
      "'AI 产出的摘要', 0, ?, ?)",
      <Object?>[
        jsonEncode(<String, Object?>{'prompt': secretPrompt}),
        now.toIso8601String(),
        now.toIso8601String(),
      ],
    );
    // 日志里写入**凭据形态**的内容（这才是日志层承诺要挡住的东西）。
    //
    // 用 error 级别：SET-082 的默认级别就是 error，而 `DiagnosticLog` 会**按级别过滤**
    // （info 在默认配置下被丢弃并计入 suppressedByLevel）。用 info 写会让它根本不进日志，
    // 于是「密钥被抹掉」这条断言会变成「日志里本来就没有它」——通过了，但什么都没验。
    //
    // 刻意**不**把文章正文写进日志：日志是**调用方给的文本流**，它的契约是「凭据被脱敏」
    // （T010），而不是「认得出任意一段散文是不是服务器正文」。见本文件与 R048 的说明。
    log.error('请求失败：$apiKey', tag: 'ai.http');
    log.error('WebDAV 认证失败：Authorization: Bearer $webdavPassword', tag: 'sync');
    expect(log.entries.length, 2, reason: '两条都真的进了日志（否则下面的断言是空转）');
    expect(log.suppressedByLevel, 0);

    service = DiagnosticsExportService(
      source: LocalDiagnosticsExportSource(
        log: log,
        appVersion: '0.2.0+1',
        cleanupStore: DriftStorageCleanupStore(
          db,
          mediaDirectoryPath: mediaDir.path,
        ),
        mediaCache: ImageCacheMediaPort(ImageCacheService(root: mediaDir)),
        syncSummary: () async => const Ok<SyncStatusBaseline>(
          SyncStatusBaseline(
            capability: WebDavWriteCapability.conditionalWrite,
            pendingChangeCount: 0,
          ),
        ),
        environment: DiagnosticsEnvironment.current(),
        settingsSummary: () async => (locale: 'zh-Hans', themeMode: 'system'),
        dataDirectoryPresent: true,
        counts: () async => (feeds: 1, articles: 1),
        clock: _FixedClock(now),
      ),
      files: files,
      clock: _FixedClock(now),
    );
  });

  tearDown(() async {
    await db.close();
    if (mediaDir.existsSync()) {
      mediaDir.deleteSync(recursive: true);
    }
  });

  group('包内容：有系统信息、没有原文/prompt/秘密', () {
    test('四节都在，且系统信息真实', () async {
      final String report = (await service.buildReport()).unwrap();
      expect(report, contains('[system]'));
      expect(report, contains('[storage]'));
      expect(report, contains('[sync]'));
      expect(report, contains('[log]'));
      expect(report, contains('appVersion=0.2.0+1'));
      expect(report, contains('osName='));
      expect(report, contains('dartVersion='));
      expect(report, contains('cpuArchitecture='));
      expect(report, contains('buildMode=debug'));
      expect(report, contains('locale=zh-Hans'));
      expect(report, contains('themeMode=system'));
      // 数据目录只报存在性，不报路径。
      expect(report, contains('dataDirectoryPresent=true'));
      expect(report, isNot(contains('dataDirectoryPath')));
      // 存储统计与计数。
      expect(report, contains('articleCount=1'));
      expect(report, contains('feedCount=1'));
      // 同步摘要的能力三态（不是地址）。
      expect(report, contains('capability=conditionalWrite'));
    });

    test('**没有**文章原文、AI 产出、prompt 与密钥', () async {
      final String report = (await service.buildReport()).unwrap();
      // 这几条是**结构性**的：存储统计只读计数与字节数、同步摘要只读协议状态、系统信息只读
      // 平台事实，没有任何一节读过 articles.body / ai_tasks.input_snapshot / news_runs.prompt。
      expect(report, isNot(contains(secretBody)), reason: '文章正文不得进包');
      expect(report, isNot(contains('标题里也可能有原文')));
      expect(report, isNot(contains('AI 产出的摘要')), reason: 'AI 产出是付费结果，不进诊断包');
      expect(report, isNot(contains(secretPrompt)), reason: 'prompt 不得进包');
      // 日志里的凭据被两层脱敏抹掉。
      expect(report, isNot(contains(apiKey)), reason: '密钥必须被脱敏抹掉');
      expect(report, isNot(contains('abcdefghijklmnop1234567890')));
      expect(report, isNot(contains(webdavPassword)));
      // 订阅地址（含路径）也不进包。
      expect(report, isNot(contains('dav.example')));
      expect(report, contains(SecretRedaction.masked), reason: '确实发生了一次脱敏');
    });

    test('日志里写的凭据形态被抹掉（日志层的承诺）', () async {
      final String report = (await service.buildReport()).unwrap();
      expect(report, contains('[log]'), reason: '日志小节确实在包里');
      expect(
        report,
        contains('logText='),
        reason: '日志文本确实进了包（否则上一条的「不含密钥」是空转）',
      );
      // 两条日志的原文都还在（说明它们没被整段丢弃），但凭据部分已被替换。
      expect(report, contains('请求失败'));
      expect(report, contains(SecretRedaction.masked));
      expect(report, isNot(contains('sk-abcdefghijklmnop1234567890')));
      expect(
        report,
        isNot(contains('Bearer correcthorsebatterystaple')),
        reason: 'Bearer 后面的 token 必须被抹掉（core 与日志兜底两层都覆盖它）',
      );
    });

    test('脱敏二次检查：导出文本再跑一遍脱敏得到同一结果（幂等）', () async {
      // 「导出时再跑一遍」的可测推论：对**已经脱敏**的文本再脱敏一次必须不变。若它还变，
      // 说明第一次留下了可以继续被识别的秘密碎片。
      final String report = (await service.buildReport()).unwrap();
      expect(SecretRedaction.redact(report), report);
      expect(DiagnosticRedaction.sanitize(report), report);
    });

    test('数据库不可用时仍能导出（其余三节可读，storage 如实报读不到）', () async {
      final DiagnosticsExportService degraded = DiagnosticsExportService(
        source: LocalDiagnosticsExportSource(
          log: log,
          appVersion: '0.2.0+1',
          cleanupStore: null,
          mediaCache: null,
          syncSummary: null,
          environment: DiagnosticsEnvironment.current(),
          settingsSummary: null,
          dataDirectoryPresent: false,
          clock: _FixedClock(now),
        ),
        files: files,
        clock: _FixedClock(now),
      );
      final String report = (await degraded.buildReport()).unwrap();
      expect(report, contains('[system]'));
      expect(report, contains('dataDirectoryPresent=false'));
      expect(
        report,
        contains('locale=unavailable'),
        reason: '读不到设置时如实报 unavailable，而不是填一个占位字符串',
      );
      expect(report, contains('measuredAt=unavailable:database'));
      expect(report, contains('configured=false'));
    });
  });

  group('导出落盘', () {
    test('导出写入 UTF-8 文本，回执含字段数与日志条数', () async {
      final Result<DiagnosticsExportResult?> result = await service.export();
      expect(result.isOk, isTrue);
      final DiagnosticsExportResult done = result.unwrap()!;
      expect(done.path, '/tmp/flux-diagnostics.txt');
      expect(done.byteCount, greaterThan(0));
      expect(done.fieldCount, greaterThan(8));
      expect(files.savedBytes, isNotNull);
      final String written = utf8.decode(files.savedBytes!);
      expect(written, contains('[system]'));
      expect(written, isNot(contains(apiKey)));
      expect(written, isNot(contains(secretPrompt)));
      expect(written, isNot(contains(secretBody)));
    });

    test('用户在保存面板取消：Ok(null)，不带任何回执', () async {
      files.savePath = null;
      final Result<DiagnosticsExportResult?> result = await service.export();
      expect(result.isOk, isTrue);
      expect(result.valueOrNull, isNull);
      expect(files.savedBytes, isNotNull, reason: '内容已经组装好，只是用户没有选位置');
    });

    test('文件名带日期、不带设备名或用户名', () async {
      final _RecordingFiles recorder = _RecordingFiles();
      final DiagnosticsExportService named = DiagnosticsExportService(
        source: LocalDiagnosticsExportSource(
          log: log,
          appVersion: '0.2.0+1',
          cleanupStore: null,
          mediaCache: null,
          syncSummary: null,
          environment: DiagnosticsEnvironment.current(),
          settingsSummary: null,
          clock: _FixedClock(now),
        ),
        files: recorder,
        clock: _FixedClock(now),
      );
      await named.export();
      expect(recorder.lastName, 'flux-diagnostics-2026-09-22.txt');
    });
  });
}

/// 记录建议文件名的文件端口替身。
final class _RecordingFiles implements FileAccessPort {
  /// 最近一次的 suggestedName。
  String? lastName;

  @override
  Future<Result<String?>> saveBytes(
    String suggestedName,
    List<int> bytes, {
    required String mimeType,
    required List<String> extensions,
  }) async {
    lastName = suggestedName;
    return const Ok<String?>('/tmp/out.txt');
  }

  @override
  Future<Result<String?>> saveOpml(
    String suggestedName,
    String content,
  ) async => const Ok<String?>(null);

  @override
  Future<Result<PickedFile?>> pickOpmlToRead() async =>
      const Ok<PickedFile?>(null);

  @override
  Future<Result<PickedFile?>> pickArchiveToRead() async =>
      const Ok<PickedFile?>(null);
}
