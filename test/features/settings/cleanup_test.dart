// T047：存储清理的用例层验收（架构 5.3 的清理段、SET-077/078/079/080）。
//
// 用例按验收点分组：
//   1) 分类统计准确性（媒体/正文/总结/其他缓存/数据库各自字节与条目数）；
//   2) 一键清缓存**不动**状态/订阅/秘密/付费结果（逐项断言）；
//   3) 自动清理的天数边界与保护规则（收藏/later 默认保护，开关可解禁）；
//   4) 正文释放**保身份**（刷新不复活未读）；
//   5) 缓存 LRU 淘汰（真实 SQLite 上的端到端）；
//   6) 彻底删除联动（关联范围与清理，不留隐藏副本）。
//
// 用**真实内存数据库**与**真实临时目录**，不用替身：这条路径的全部价值在于「数据真的被删对
// 了吗」，而用替身断言「调用了删除方法」等于什么都没验。
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/domain/ai_task_record.dart';
import 'package:flux/features/settings/application/cleanup_ports.dart';
import 'package:flux/features/settings/application/cleanup_service.dart';
import 'package:flux/infrastructure/local/ai_task_store.dart';
import 'package:flux/infrastructure/local/article_store.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/image_cache_service.dart';
import 'package:flux/infrastructure/local/media_cache_port_adapter.dart';
import 'package:flux/infrastructure/local/storage_cleanup_store.dart';
import 'package:flux/infrastructure/local/tables/article_tables.dart';

/// 固定时钟（让「天数边界」可确定地断言）。
///
/// 与 core 的 [FakeClock] 分开：这里需要**直接设定**当前时刻（多个用例从同一个 `now` 出发
/// 分别跳到不同时刻），而 FakeClock 只提供「向前推进」，从同一个起点跳到不同终点要靠一串
/// 差值计算，写起来更容易出错。
final class _FixedClock implements Clock {
  _FixedClock(this._now);

  DateTime _now;

  /// 把「现在」推到某一时刻。
  void set(DateTime value) => _now = value;

  @override
  DateTime now() => _now;

  /// 单调时间在本次用例里不使用（清理判定只看墙钟）。
  @override
  Duration monotonic() => Duration.zero;
}

/// 快照 GC 替身（记录删除调用，便于断言「预览不删」）。
final class _FakeSnapshotGc implements SnapshotGcPort {
  _FakeSnapshotGc(this.facts);

  final List<RemoteSnapshotFact> facts;
  final List<String> deleted = <String>[];

  @override
  Future<Result<List<RemoteSnapshotFact>>> listSnapshots() async =>
      Ok<List<RemoteSnapshotFact>>(facts);

  @override
  Future<Result<bool>> deleteSnapshot(String name) async {
    deleted.add(name);
    return const Ok<bool>(true);
  }
}

/// 永远失败的媒体端口（用于验证「一类失败不影响整页」）。
final class _FailingMediaPort implements MediaCachePort {
  @override
  Future<Result<({int entries, int bytes})>> stats() async =>
      Err<({int entries, int bytes})>(
        StorageError(operation: 'mediaCache.stats', detail: '模拟失败'),
      );

  @override
  Future<
    Result<({int entryCount, int imageBytes, int metaBytes, int tempBytes})>
  >
  diskUsage() async =>
      Err<({int entryCount, int imageBytes, int metaBytes, int tempBytes})>(
        StorageError(operation: 'mediaCache.diskUsage', detail: '模拟失败'),
      );

  @override
  Future<Result<({int entries, int bytes})>> expiredUsage({
    required DateTime cutoffUtc,
  }) async => Err<({int entries, int bytes})>(
    StorageError(operation: 'mediaCache.expiredUsage', detail: '模拟失败'),
  );

  @override
  Future<Result<({int entries, int bytes})>> deleteExpired({
    required DateTime cutoffUtc,
  }) async => Err<({int entries, int bytes})>(
    StorageError(operation: 'mediaCache.deleteExpired', detail: '模拟失败'),
  );

  @override
  Future<Result<int>> clearAll() async =>
      Err<int>(StorageError(operation: 'mediaCache.clear', detail: '模拟失败'));

  @override
  Future<Result<int>> enforceLimit() async => Err<int>(
    StorageError(operation: 'mediaCache.enforceLimit', detail: '模拟失败'),
  );

  @override
  Future<Result<void>> applyLimitMiB(int limitMiB) async => Err<void>(
    StorageError(operation: 'mediaCache.applyLimit', detail: '模拟失败'),
  );
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late Directory mediaDir;
  late _FixedClock clock;
  late CleanupService service;

  /// 固定「现在」。
  final DateTime now = DateTime.utc(2026, 9, 22, 12);

  setUp(() async {
    db = AppDatabase.memory();
    await db.customSelect('SELECT 1').get();
    mediaDir = Directory.systemTemp.createTempSync('flux_t047_');
    clock = _FixedClock(now);
    service = CleanupService(
      store: DriftStorageCleanupStore(
        db,
        mediaDirectoryPath: mediaDir.path,
        clock: clock,
      ),
      mediaCache: ImageCacheMediaPort(
        ImageCacheService(root: mediaDir, clock: clock),
      ),
      clock: clock,
    );
  });

  tearDown(() async {
    await db.close();
    if (mediaDir.existsSync()) {
      mediaDir.deleteSync(recursive: true);
    }
  });

  /// 建一个订阅并返回 id。
  Future<int> addFeed({
    String name = '源',
    String url = 'https://a.example/feed',
  }) => db
      .into(db.feeds)
      .insert(
        FeedsCompanion.insert(
          syncId: 'feed-$name',
          normalizedUrl: url,
          name: name,
        ),
      );

  /// 建一篇文章并返回 id。
  Future<int> addArticle({
    required int feedId,
    required String title,
    required DateTime publishedAt,
    String? body,
    String readingState = 'read',
    bool favorite = false,
    String? guid,
    String? imageUrl,
    String? aiSummary,
  }) => db
      .into(db.articles)
      .insert(
        ArticlesCompanion.insert(
          feedId: Value<int?>(feedId),
          title: title,
          identityBasis: guid == null
              ? IdentityBasis.normalizedLink
              : IdentityBasis.guid,
          guid: Value<String?>(guid),
          guidPresent: Value<bool>(guid != null),
          normalizedLink: Value<String?>('https://a.example/$title'),
          publishedAt: Value<DateTime?>(publishedAt),
          body: Value<String?>(body),
          bodyHash: Value<String?>(body == null ? null : 'h-$title'),
          readingState: Value<ReadingState>(
            ReadingState.values.firstWhere(
              (ReadingState state) => state.name == readingState,
            ),
          ),
          favorite: Value<bool>(favorite),
          imageUrl: Value<String?>(imageUrl),
          aiSummary: Value<String?>(aiSummary),
        ),
      );

  /// 造一条 AI 结果缓存。
  Future<void> addCache({
    required String key,
    required String text,
    DateTime? createdAt,
    DateTime? lastUsedAt,
  }) => db
      .into(db.aiResultCacheRecords)
      .insert(
        AiResultCacheRecordsCompanion.insert(
          cacheKey: key,
          text_: text,
          providerAlias: 'main',
          modelId: 'm1',
          createdAt: createdAt ?? now,
          byteLength: Value<int>(utf8ByteLength(text)),
          lastUsedAt: Value<DateTime?>(lastUsedAt),
        ),
      );

  /// 造一个 AI 任务行（失败/成功的草稿）。
  Future<void> addTask({
    required String taskId,
    required String status,
    String resultText = '',
  }) => db
      .into(db.aiTasks)
      .insert(
        AiTasksCompanion.insert(
          taskId: taskId,
          kind: 'summary',
          inputSnapshot: jsonEncode(<String, Object?>{'messages': <Object>[]}),
          promptHash: 'h-$taskId',
          modelAliases: '[]',
          routeModelIds: '[]',
          status: status,
          resultText: Value<String?>(resultText),
          createdAt: now,
          updatedAt: now,
        ),
      );

  /// 造一条新闻版本。
  Future<int> addSummaryRun({
    required String localDate,
    required DateTime createdAt,
    String materials = '[]',
  }) => db
      .into(db.newsRuns)
      .insert(
        NewsRunsCompanion.insert(
          localDate: localDate,
          timeZone: 'Asia/Shanghai',
          version: 1,
          taskStatus: TaskStatus.succeeded,
          inputSnapshot: '{}',
          snapshotHash: 'h-$localDate',
          siteResults: '[]',
          materials: materials,
          items: '[]',
          createdAt: createdAt,
        ),
      );

  /// 造一条 T009 的**总结版本**（citations 的外键指向它，而不是 news_runs）。
  Future<int> addSummaryVersion({required String localDate, String? content}) =>
      db
          .into(db.summaryVersions)
          .insert(
            SummaryVersionsCompanion.insert(
              localDate: localDate,
              timeZone: 'Asia/Shanghai',
              taskStatus: TaskStatus.succeeded,
              content: Value<String?>(content),
            ),
          );

  group('分类占用统计的准确性', () {
    test('五类各自独立：正文/总结/其他缓存/数据库都有数，媒体由文件系统提供', () async {
      final int feedId = await addFeed();
      await addArticle(
        feedId: feedId,
        title: 'a',
        publishedAt: now,
        body: '正文正文',
      );
      await addArticle(
        feedId: feedId,
        title: 'b',
        publishedAt: now,
        body: null, // 没有正文：不该被计入「文章正文」这一类
      );
      await addSummaryRun(localDate: '2026-09-22', createdAt: now);
      await addCache(key: 'k1', text: '你好');
      await addTask(taskId: 't-failed', status: 'failed');

      // 媒体缓存里放一张真图。
      final ImageCacheService cache = ImageCacheService(
        root: mediaDir,
        clock: clock,
      );
      await cache.write(
        url: 'https://a.example/1.jpg',
        bytes: Uint8List.fromList(List<int>.filled(100, 7)),
        mimeType: 'image/jpeg',
        width: 10,
        height: 10,
      );

      final Result<StorageUsageReport> measured = await service.measure(
        mediaLimitMiB: 512,
      );
      final StorageUsageReport report = measured.unwrap();
      expect(report.measuredAt, now);
      expect(report.mediaLimitBytes, 512 * 1024 * 1024);
      // 媒体：图片字节 + 元数据字节都算进去（元数据也占磁盘）。
      final StorageCategoryUsage media = report.usageOf(
        StorageCategory.mediaCache,
      );
      expect(media.itemCount, 1);
      expect(media.byteCount, greaterThanOrEqualTo(100));
      // 正文：只有 a 有正文（b 的 body 是 null）。
      final StorageCategoryUsage bodies = report.usageOf(
        StorageCategory.articleBody,
      );
      expect(bodies.itemCount, 1, reason: '没有正文的行不计入正文占用');
      expect(bodies.byteCount, utf8ByteLength('正文正文'));
      // 总结：一条版本。
      expect(report.usageOf(StorageCategory.newsSummary).itemCount, 1);
      // 其他缓存：AI 结果 1 条 + 失败草稿 1 条。
      final StorageCategoryUsage other = report.usageOf(
        StorageCategory.otherCache,
      );
      expect(other.itemCount, 2);
      expect(other.byteCount, greaterThan(0));
      // 数据库类：内存库不在磁盘上 → 0 字节，但表数应大于 0。
      expect(
        report.usageOf(StorageCategory.database).itemCount,
        greaterThan(0),
        reason: '表数是这一类「是什么」的说明',
      );
    });

    test('媒体端口失败不导致整页失败：其余四类仍然读得到', () async {
      final CleanupService failing = CleanupService(
        store: DriftStorageCleanupStore(db, clock: clock),
        mediaCache: _FailingMediaPort(),
        clock: clock,
      );
      final Result<StorageUsageReport> measured = await failing.measure(
        mediaLimitMiB: 512,
      );
      expect(measured.isOk, isTrue, reason: '一类读不到不该让统计整体失败');
      expect(
        measured.unwrap().usageOf(StorageCategory.mediaCache).byteCount,
        0,
      );
      expect(measured.unwrap().categories.length, 5);
    });
  });

  group('一键清缓存：只删可再生内容', () {
    test('清掉媒体/AI 结果/失败草稿，**不动**状态、收藏、订阅、付费结果与成功任务', () async {
      final int feedId = await addFeed();
      final int readId = await addArticle(
        feedId: feedId,
        title: 'a',
        publishedAt: now,
        body: '正文',
        readingState: 'read',
        favorite: true,
      );
      await addArticle(
        feedId: feedId,
        title: 'b',
        publishedAt: now,
        body: '正文2',
        readingState: 'later',
      );
      await addSummaryRun(localDate: '2026-09-22', createdAt: now);
      await addCache(key: 'k1', text: '缓存结果');
      await addTask(taskId: 't-failed', status: 'failed');
      await addTask(taskId: 't-cancelled', status: 'cancelled');
      await addTask(taskId: 't-interrupted', status: 'interrupted');
      await addTask(
        taskId: 't-succeeded',
        status: 'succeeded',
        resultText: '付费产出',
      );
      await addTask(taskId: 't-running', status: 'running');

      final ImageCacheService cache = ImageCacheService(
        root: mediaDir,
        clock: clock,
      );
      await cache.write(
        url: 'https://a.example/1.jpg',
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
        mimeType: 'image/jpeg',
        width: 1,
        height: 1,
      );

      final Result<CleanupImpact> preview = await service
          .previewClearRegenerable();
      expect(preview.unwrap().mediaEntries, 1);
      expect(preview.unwrap().aiCacheEntries, 1);
      expect(preview.unwrap().failedTaskDrafts, 3);

      final Result<CleanupImpact> done = await service.clearRegenerable();
      expect(done.isOk, isTrue);
      expect(done.unwrap().mediaEntries, 1);
      expect(done.unwrap().aiCacheEntries, 1);
      expect(done.unwrap().failedTaskDrafts, 3);
      expect(done.unwrap().totalBytes, greaterThan(0));

      // 真实删除效果。
      expect(await db.select(db.aiResultCacheRecords).get(), isEmpty);
      expect(
        (await db.select(db.aiTasks).get()).map((AiTask t) => t.taskId).toSet(),
        <String>{'t-succeeded', 't-running'},
        reason: '只删失败/取消/中断的草稿；成功（付费）与进行中的一行都不动',
      );
      final List<File> mediaFiles = mediaDir
          .listSync()
          .whereType<File>()
          .toList(growable: false);
      expect(mediaFiles, isEmpty, reason: '媒体缓存全清（含元数据）');

      // **不变量**：状态、收藏、订阅、付费结果全部原样。
      final Article read = (await db.select(db.articles).get()).firstWhere(
        (Article a) => a.id == readId,
      );
      expect(read.readingState.name, 'read');
      expect(read.favorite, isTrue);
      expect(read.body, '正文');
      final List<Article> all = await db.select(db.articles).get();
      expect(all.length, 2, reason: '文章一行都不该被清缓存删掉');
      expect(all.any((Article a) => a.readingState.name == 'later'), isTrue);
      expect((await db.select(db.feeds).get()).length, 1);
      expect(
        (await db.select(db.newsRuns).get()).length,
        1,
        reason: '付费总结不在清缓存范围',
      );
      final AiTask succeeded = (await db.select(db.aiTasks).get()).firstWhere(
        (AiTask t) => t.taskId == 't-succeeded',
      );
      expect(succeeded.resultText, '付费产出');
    });

    test('缓存与任务表里没有秘密列（清缓存不准顺手加一个「清理 Key」）', () async {
      // 「秘密不在库里」是架构 5.1/第 8 节的约束，而清缓存是最可能顺手加一个「清理凭据」
      // 动作的地方。这里逐列断言两张表都没有凭据列。
      for (final String table in <String>[
        'ai_result_cache_records',
        'ai_tasks',
      ]) {
        final List<QueryRow> columns = await db
            .customSelect('PRAGMA table_info($table)')
            .get();
        for (final QueryRow row in columns) {
          final String name = row.read<String>('name').toLowerCase();
          expect(
            name,
            isNot(
              anyOf(
                contains('secret'),
                contains('password'),
                contains('api_key'),
              ),
            ),
            reason: '$table.$name 不该存在；凭据只住 Keychain',
          );
        }
      }
    });

    test('空缓存时清缓存不报错，影响为空', () async {
      final Result<CleanupImpact> preview = await service
          .previewClearRegenerable();
      expect(preview.unwrap().isEmpty, isTrue);
      final Result<CleanupImpact> done = await service.clearRegenerable();
      expect(done.isOk, isTrue);
      expect(done.unwrap().isEmpty, isTrue);
    });
  });

  group('自动清理：天数边界与保护规则', () {
    test('三个开关全关时预览与执行都不动任何东西', () async {
      final int feedId = await addFeed();
      await addArticle(
        feedId: feedId,
        title: 'old',
        publishedAt: now.subtract(const Duration(days: 500)),
        body: '很老的正文',
      );
      final Result<CleanupImpact> preview = await service.previewAutoCleanup(
        AutoCleanupPolicy.defaults,
      );
      expect(preview.unwrap().isEmpty, isTrue);
      final Result<CleanupImpact> done = await service.runAutoCleanup(
        AutoCleanupPolicy.defaults,
      );
      expect(done.unwrap().isEmpty, isTrue);
      final Article article = (await db.select(db.articles).get()).single;
      expect(article.body, '很老的正文', reason: '默认全关时一行都不该被清理');
    });

    test('正文按发布/抓取时间：到期释放、未到期不动（天数边界）', () async {
      final int feedId = await addFeed();
      final int oldId = await addArticle(
        feedId: feedId,
        title: 'old',
        publishedAt: now.subtract(const Duration(days: 91)),
        body: '很老的正文',
      );
      final int freshId = await addArticle(
        feedId: feedId,
        title: 'fresh',
        publishedAt: now.subtract(const Duration(days: 89)),
        body: '较新的正文',
      );
      final AutoCleanupPolicy policy = AutoCleanupPolicy.defaults.copyWith(
        articleEnabled: true,
        articleDays: 90,
      );

      final Result<CleanupImpact> preview = await service.previewAutoCleanup(
        policy,
      );
      expect(preview.unwrap().articleBodies, 1);

      final Result<CleanupImpact> done = await service.runAutoCleanup(policy);
      expect(done.unwrap().articleBodies, 1);

      final List<Article> articles = await db.select(db.articles).get();
      expect(
        articles.firstWhere((Article a) => a.id == oldId).body,
        isNull,
        reason: '91 天前的正文到期释放',
      );
      expect(
        articles.firstWhere((Article a) => a.id == freshId).body,
        '较新的正文',
        reason: '89 天前未到期，一行不动',
      );
    });

    test('保护规则：收藏与 later 默认不动；打开开关后同一批被释放', () async {
      final int feedId = await addFeed();
      final int favoriteId = await addArticle(
        feedId: feedId,
        title: 'fav',
        publishedAt: now.subtract(const Duration(days: 200)),
        body: '收藏的正文',
        favorite: true,
      );
      final int laterId = await addArticle(
        feedId: feedId,
        title: 'later',
        publishedAt: now.subtract(const Duration(days: 200)),
        body: '稍后再读的正文',
        readingState: 'later',
      );
      final int plainId = await addArticle(
        feedId: feedId,
        title: 'plain',
        publishedAt: now.subtract(const Duration(days: 200)),
        body: '普通正文',
      );

      final AutoCleanupPolicy guarded = AutoCleanupPolicy.defaults.copyWith(
        articleEnabled: true,
        articleDays: 90,
      );
      final Result<CleanupImpact> preview = await service.previewAutoCleanup(
        guarded,
      );
      expect(preview.unwrap().articleBodies, 1, reason: '只有普通文章到期');
      expect(
        preview.unwrap().protectedArticles,
        2,
        reason: '收藏与 later 各一篇被保护，数字必须出现在预览里（用户能看到开关的效果）',
      );
      await service.runAutoCleanup(guarded);
      List<Article> articles = await db.select(db.articles).get();
      expect(
        articles.firstWhere((Article a) => a.id == favoriteId).body,
        '收藏的正文',
      );
      expect(
        articles.firstWhere((Article a) => a.id == laterId).body,
        '稍后再读的正文',
      );
      expect(articles.firstWhere((Article a) => a.id == plainId).body, isNull);

      // 打开两个保护开关（SET-078）后，同一批也会被释放。
      final AutoCleanupPolicy unguarded = guarded.copyWith(
        includeFavorite: true,
        includeLater: true,
      );
      final Result<CleanupImpact> second = await service.runAutoCleanup(
        unguarded,
      );
      expect(second.unwrap().articleBodies, 2);
      expect(second.unwrap().protectedArticles, 0);
      articles = await db.select(db.articles).get();
      expect(articles.every((Article a) => a.body == null), isTrue);
    });

    test('正文释放**保身份与状态**：行、GUID、同步键、收藏、later 都在原处', () async {
      final int feedId = await addFeed();
      final int articleId = await addArticle(
        feedId: feedId,
        title: 'keep-identity',
        publishedAt: now.subtract(const Duration(days: 200)),
        body: '待释放的正文',
        guid: 'guid-1',
        readingState: 'later',
        favorite: true,
      );
      await (db.update(
        db.articles,
      )..where((Articles a) => a.id.equals(articleId))).write(
        const ArticlesCompanion(syncKey: Value<String?>('sync-key-1')),
      );

      await service.runAutoCleanup(
        AutoCleanupPolicy.defaults.copyWith(
          articleEnabled: true,
          articleDays: 90,
          // 这一条验的是「释放正文后身份与状态原样」，因此必须让保护规则放行收藏与 later；
          // 保护规则本身的行为由前一条用例单独覆盖。
          includeFavorite: true,
          includeLater: true,
        ),
      );

      final List<Article> rows = await db.select(db.articles).get();
      expect(rows.length, 1, reason: '只释放正文，行必须留着');
      final Article row = rows.single;
      expect(row.id, articleId);
      expect(row.body, isNull, reason: '正文被释放');
      expect(row.bodyHash, isNull);
      expect(row.guid, 'guid-1', reason: '身份证据必须保留');
      expect(row.syncKey, 'sync-key-1', reason: '同步键必须保留（否则跨设备身份漂移）');
      expect(row.readingState.name, 'later', reason: '阅读状态必须保留');
      expect(row.favorite, isTrue, reason: '收藏必须保留');
      expect(row.feedId, feedId);
      expect(
        row.bodyCompleteness.name,
        'summaryOnly',
        reason: '库里现在只有标题与摘要，这是与当前数据一致的取值（也能被如实说明为「原文已清理」）',
      );
    });

    test('释放正文后刷新同一篇文章**不复活成未读**（身份规则仍命中同一行）', () async {
      final int feedId = await addFeed();
      final int articleId = await addArticle(
        feedId: feedId,
        title: 'refreshed',
        publishedAt: now.subtract(const Duration(days: 200)),
        body: '旧正文',
        guid: 'guid-refresh',
        readingState: 'read',
      );
      await service.runAutoCleanup(
        AutoCleanupPolicy.defaults.copyWith(
          articleEnabled: true,
          articleDays: 90,
        ),
      );

      // 用同一份来源数据再「抓」一次（GUID 相同 = 同一篇）。
      final Result<ArticleImportOutcome> imported = await db.upsertArticles(
        <ArticleImport>[
          ArticleImport(
            feedId: feedId,
            title: 'refreshed',
            identityBasis: IdentityBasis.guid,
            guid: 'guid-refresh',
            guidPresent: true,
            body: '新抓到的正文',
            bodyHash: 'new-hash',
            publishedAt: now.subtract(const Duration(days: 200)),
            fetchedAt: now,
          ),
        ],
      );
      expect(imported.isOk, isTrue, reason: '${imported.errorOrNull}');
      expect(imported.unwrap().inserted, 0, reason: '不得为同一篇文章插一行新的');

      final List<Article> rows = await db.select(db.articles).get();
      expect(rows.length, 1, reason: '刷新不复活（身份规则仍命中被释放的那一行）');
      expect(rows.single.id, articleId);
      expect(
        rows.single.readingState.name,
        'read',
        reason: '用户已读状态不被刷新改回 unread —— 这正是「保留身份防复活」的目的',
      );
      expect(rows.single.body, '新抓到的正文', reason: '重新抓回的正文照常写入');
    });

    test('媒体按最后访问时间清理；刚访问过的不动（LRU 语义）', () async {
      final ImageCacheService cache = ImageCacheService(
        root: mediaDir,
        clock: clock,
      );
      await cache.write(
        url: 'https://a.example/old.jpg',
        bytes: Uint8List.fromList(List<int>.filled(10, 1)),
        mimeType: 'image/jpeg',
        width: 1,
        height: 1,
      );
      await cache.write(
        url: 'https://a.example/used.jpg',
        bytes: Uint8List.fromList(List<int>.filled(10, 2)),
        mimeType: 'image/jpeg',
        width: 1,
        height: 1,
      );
      // 把两个文件的时间都推到很早，然后把「used」的时间刷成现在（模拟它刚被访问过）。
      final DateTime early = now.subtract(const Duration(days: 200));
      for (final File file in mediaDir.listSync().whereType<File>()) {
        file.setLastModifiedSync(early);
      }
      cache.dataFileFor('https://a.example/used.jpg').setLastModifiedSync(now);
      cache.metaFileFor('https://a.example/used.jpg').setLastModifiedSync(now);

      final AutoCleanupPolicy policy = AutoCleanupPolicy.defaults.copyWith(
        mediaEnabled: true,
        mediaDays: 30,
      );
      final Result<CleanupImpact> preview = await service.previewAutoCleanup(
        policy,
      );
      expect(preview.unwrap().mediaEntries, 1, reason: '只有 200 天前访问的那张到期');

      final Result<CleanupImpact> done = await service.runAutoCleanup(policy);
      expect(done.unwrap().mediaEntries, 1);
      expect(
        cache.dataFileFor('https://a.example/old.jpg').existsSync(),
        isFalse,
      );
      expect(
        cache.dataFileFor('https://a.example/used.jpg').existsSync(),
        isTrue,
        reason: '刚访问过的不该被清（LRU 的语义）',
      );
    });

    test('总结按创建时间清理：到期的删、未到期的不动，且不为引用留下隐藏副本', () async {
      // 一条到期的版本，它的**引用最小摘录**就在同一行（material 列为引用的载体）。
      // 总结这一类的引用与材料是同一次事实的组成部分，因此删版本时它们一起消失——
      // 只删版本而把摘录留在别处就是架构 5.3 说的「隐藏副本」。
      await addSummaryRun(
        localDate: '2025-01-01',
        createdAt: now.subtract(const Duration(days: 500)),
        materials: jsonEncode(<Map<String, Object?>>[
          <String, Object?>{'sourceId': 'rss.1', 'excerpt': '最小摘录'},
        ]),
      );
      await addSummaryRun(
        localDate: '2026-09-21',
        createdAt: now.subtract(const Duration(days: 1)),
        materials: jsonEncode(<Map<String, Object?>>[
          <String, Object?>{'sourceId': 'rss.2', 'excerpt': '仍在的摘录'},
        ]),
      );

      final AutoCleanupPolicy policy = AutoCleanupPolicy.defaults.copyWith(
        summaryEnabled: true,
        summaryDays: 365,
      );
      final Result<CleanupImpact> preview = await service.previewAutoCleanup(
        policy,
      );
      expect(preview.unwrap().summaryRuns, 1);

      final Result<CleanupImpact> done = await service.runAutoCleanup(policy);
      expect(done.unwrap().summaryRuns, 1);
      final List<NewsRun> runs = await db.select(db.newsRuns).get();
      expect(runs.length, 1);
      expect(runs.single.localDate, '2026-09-21', reason: '未到期的版本仍在');
      expect(
        runs.single.materials.contains('仍在的摘录'),
        isTrue,
        reason: '未到期版本的材料与被引用摘录原样保留',
      );
      expect(
        runs.any((NewsRun r) => r.materials.contains('最小摘录')),
        isFalse,
        reason: '到期版本的摘录随那一行一起消失，不留隐藏副本',
      );
    });
  });

  group('AI 结果缓存的上限与淘汰（真实 SQLite）', () {
    test('写入超限后按最近使用淘汰，且本次写入的条目保留', () async {
      final DriftAiResultCache bounded = DriftAiResultCache(
        db,
        limits: const AiCacheLimits(maxEntries: 3, maxBytes: 100000),
        clock: clock,
      );
      await bounded.save(
        AiResultCacheEntry(
          key: 'k1',
          text: '一',
          providerAlias: 'main',
          modelId: 'm1',
          createdAt: now,
        ),
      );
      await bounded.save(
        AiResultCacheEntry(
          key: 'k2',
          text: '二',
          providerAlias: 'main',
          modelId: 'm1',
          createdAt: now.add(const Duration(minutes: 1)),
        ),
      );
      await bounded.save(
        AiResultCacheEntry(
          key: 'k3',
          text: '三',
          providerAlias: 'main',
          modelId: 'm1',
          createdAt: now.add(const Duration(minutes: 2)),
        ),
      );
      // 读一次 k2 → 它是最近使用的。
      clock.set(now.add(const Duration(minutes: 3)));
      expect((await bounded.find('k2')).unwrap(), isNotNull);
      // 写入第 4 条：超条数上限，应淘汰最久没用的 k1。
      await bounded.save(
        AiResultCacheEntry(
          key: 'k4',
          text: '四',
          providerAlias: 'main',
          modelId: 'm1',
          createdAt: now.add(const Duration(minutes: 4)),
        ),
      );
      final List<String> keys = (await db.select(db.aiResultCacheRecords).get())
          .map((AiResultCacheRecord r) => r.cacheKey)
          .toList();
      expect(keys.contains('k1'), isFalse, reason: 'k1 从写入后从未被读过 → 最久没用');
      expect(keys, containsAll(<String>['k2', 'k3', 'k4']));
      expect(keys.length, 3);
      final Result<({int entries, int bytes})> usage = await bounded.usage();
      expect(usage.unwrap().entries, 3);
      expect(usage.unwrap().bytes, greaterThan(0));
    });

    test('命中会把条目刷成最近使用（LRU，不是 FIFO）', () async {
      final DriftAiResultCache bounded = DriftAiResultCache(
        db,
        limits: const AiCacheLimits(maxEntries: 2, maxBytes: 100000),
        clock: clock,
      );
      await bounded.save(
        AiResultCacheEntry(
          key: 'first',
          text: 'a',
          providerAlias: 'main',
          modelId: 'm1',
          createdAt: now,
        ),
      );
      await bounded.save(
        AiResultCacheEntry(
          key: 'second',
          text: 'b',
          providerAlias: 'main',
          modelId: 'm1',
          createdAt: now,
        ),
      );
      // 在写入第三条之前先读一次 first：它变成最近使用。
      clock.set(now.add(const Duration(hours: 1)));
      expect((await bounded.find('first')).unwrap(), isNotNull);
      clock.set(now.add(const Duration(hours: 2)));
      await bounded.save(
        AiResultCacheEntry(
          key: 'third',
          text: 'c',
          providerAlias: 'main',
          modelId: 'm1',
          createdAt: now.add(const Duration(hours: 2)),
        ),
      );
      final List<String> keys = (await db.select(db.aiResultCacheRecords).get())
          .map((AiResultCacheRecord r) => r.cacheKey)
          .toList();
      expect(
        keys.contains('second'),
        isFalse,
        reason: 'second 是唯一从未被读过的 → 被淘汰；first 因命中而留下',
      );
      expect(keys, containsAll(<String>['first', 'third']));
    });

    test('字节上限独立生效（条数远未超限时也淘汰）', () async {
      final DriftAiResultCache bounded = DriftAiResultCache(
        db,
        limits: const AiCacheLimits(maxEntries: 100, maxBytes: 40),
        clock: clock,
      );
      // 每条 12 字节（4 个汉字）。
      for (int i = 0; i < 4; i++) {
        clock.set(now.add(Duration(minutes: i)));
        await bounded.save(
          AiResultCacheEntry(
            key: 'k$i',
            text: '你好世界',
            providerAlias: 'main',
            modelId: 'm1',
            createdAt: now.add(Duration(minutes: i)),
          ),
        );
      }
      final Result<({int entries, int bytes})> usage = await bounded.usage();
      expect(usage.unwrap().entries, 3, reason: '40 字节 / 12 字节 = 3.33 → 留 3 条');
      expect(usage.unwrap().bytes, 36);
    });
  });

  group('彻底删除：列出关联并清理', () {
    test('关联范围包含译文/会话/引用/图片缓存，执行后全部清理且引用被断链', () async {
      final int feedId = await addFeed();
      final int articleId = await addArticle(
        feedId: feedId,
        title: 'to-purge',
        publishedAt: now,
        body: '将被彻底删除的正文',
        imageUrl: 'https://a.example/cover.jpg',
        aiSummary: 'AI 生成的摘要',
      );
      // 译文（含一段）。
      final int translationId = await db
          .into(db.articleTranslationRecords)
          .insert(
            ArticleTranslationRecordsCompanion.insert(
              articleId: articleId,
              targetLanguage: 'en',
              sourceDigest: 'd',
            ),
          );
      await db
          .into(db.translationSegmentRecords)
          .insert(
            TranslationSegmentRecordsCompanion.insert(
              translationId: translationId,
              segmentIndex: 0,
              blockKind: 'paragraph',
              sourceDigest: 'd',
              sourceText: '原文',
              status: 'translated',
            ),
          );
      // 阅读会话。
      await db
          .into(db.readingSessions)
          .insert(
            ReadingSessionsCompanion.insert(
              articleId: articleId,
              startedAt: now,
              timeZone: 'Asia/Shanghai',
              localDate: '2026-09-22',
            ),
          );
      // 引用（指向本机文章）。
      await addSummaryRun(
        localDate: '2026-09-22',
        createdAt: now,
        materials: jsonEncode(<Map<String, Object?>>[
          <String, Object?>{'articleId': articleId, 'title': 'to-purge'},
        ]),
      );
      // citations 的外键指向 T009 的 summary_versions（每日总结版本行），与 news_runs 是两件事。
      final int versionId = await addSummaryVersion(localDate: '2026-09-22');
      await db
          .into(db.citations)
          .insert(
            CitationsCompanion.insert(
              summaryVersionId: versionId,
              sourceId: 'rss.$articleId',
              excerpt: '摘录',
              accessMethod: CitationAccessMethod.rss,
              articleId: Value<int?>(articleId),
            ),
          );
      // 图片缓存（文件名由地址哈希决定）。
      final ImageCacheService cache = ImageCacheService(
        root: mediaDir,
        clock: clock,
      );
      await cache.write(
        url: 'https://a.example/cover.jpg',
        bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
        mimeType: 'image/jpeg',
        width: 1,
        height: 1,
      );

      final Result<ArticlePurgeImpact> impact = await service
          .previewArticlePurge(articleId);
      expect(impact.unwrap().title, 'to-purge');
      expect(impact.unwrap().translations, 1);
      expect(impact.unwrap().readingSessions, 1);
      expect(impact.unwrap().citations, 1);
      expect(impact.unwrap().aiSummaries, 1);
      expect(impact.unwrap().cachedMedia, 2, reason: '图片数据 + 元数据两个文件');
      expect(impact.unwrap().newsReferences, 1, reason: '被 1 条新闻引用');
      expect(impact.unwrap().hasRelated, isTrue);

      // 预览**只读**：数据一行未动。
      expect((await db.select(db.articles).get()).length, 1);
      expect(
        cache.dataFileFor('https://a.example/cover.jpg').existsSync(),
        isTrue,
      );

      final Result<ArticlePurgeImpact> purged = await service.purgeArticle(
        articleId,
      );
      expect(purged.isOk, isTrue);

      // 文章本体与关联全部消失。
      expect(await db.select(db.articles).get(), isEmpty);
      expect(await db.select(db.articleTranslationRecords).get(), isEmpty);
      expect(await db.select(db.translationSegmentRecords).get(), isEmpty);
      expect(await db.select(db.readingSessions).get(), isEmpty);
      // 引用**保留**但断链（架构 4.4：引用保留最小快照作为历史总结的出处）。
      final List<Citation> citations = await db.select(db.citations).get();
      expect(citations.length, 1, reason: '引用本身必须保留（最小快照）');
      expect(citations.single.articleId, isNull, reason: '指向本机文章的指针被断掉');
      expect(citations.single.excerpt, '摘录', reason: '最小摘录仍在');
      // 图片缓存被回收（不留隐藏副本）。
      expect(
        cache.dataFileFor('https://a.example/cover.jpg').existsSync(),
        isFalse,
      );
      expect(
        cache.metaFileFor('https://a.example/cover.jpg').existsSync(),
        isFalse,
      );
      // 订阅与新闻版本不受影响（删文章不等于删源或删历史总结）。
      expect((await db.select(db.feeds).get()).length, 1);
      expect((await db.select(db.newsRuns).get()).length, 1);
    });

    test('不存在的文章返回类型化失败（不是假成功）', () async {
      final Result<ArticlePurgeImpact> impact = await service
          .previewArticlePurge(999);
      expect(impact.isErr, isTrue);
      expect(impact.errorOrNull!.kind, 'storage');
      final Result<ArticlePurgeImpact> purged = await service.purgeArticle(999);
      expect(purged.isErr, isTrue, reason: '删一个不存在的目标必须失败，否则界面会显示假回执');
    });
  });

  group('孤儿快照 GC（T042 遗留）', () {
    test('未配置同步时返回 null（不是错误）', () async {
      final Result<SnapshotGcResult?> result = await service
          .collectOrphanSnapshots(referencedNames: const <String>{});
      expect(result.isOk, isTrue);
      expect(result.valueOrNull, isNull);
    });

    test('dryRun 只报告不删除；执行时删除到期且未被引用的', () async {
      final _FakeSnapshotGc gc = _FakeSnapshotGc(<RemoteSnapshotFact>[
        RemoteSnapshotFact(
          name: 'snapshot-current.json',
          lastModified: now.subtract(const Duration(days: 400)),
        ),
        RemoteSnapshotFact(
          name: 'snapshot-old-orphan.json',
          lastModified: now.subtract(const Duration(days: 200)),
        ),
        const RemoteSnapshotFact(name: 'snapshot-no-time.json'),
      ]);
      final CleanupService withGc = CleanupService(
        store: DriftStorageCleanupStore(db, clock: clock),
        mediaCache: ImageCacheMediaPort(
          ImageCacheService(root: mediaDir, clock: clock),
        ),
        snapshotGc: gc,
        clock: clock,
      );

      final Result<SnapshotGcResult?> dry = await withGc.collectOrphanSnapshots(
        referencedNames: const <String>{'snapshot-current.json'},
        dryRun: true,
      );
      expect(dry.unwrap()!.collected, <String>['snapshot-old-orphan.json']);
      expect(dry.unwrap()!.considered, 3);
      expect(
        dry.unwrap()!.skippedForMissingTime,
        1,
        reason: '缺服务器时间的快照必须出现在报告里，否则「列得出但删不掉」完全不可见',
      );
      expect(gc.deleted, isEmpty, reason: '预览不得删除任何东西');

      final Result<SnapshotGcResult?> real = await withGc
          .collectOrphanSnapshots(
            referencedNames: const <String>{'snapshot-current.json'},
          );
      expect(real.unwrap()!.collected, <String>['snapshot-old-orphan.json']);
      expect(gc.deleted, <String>['snapshot-old-orphan.json']);
    });
  });
}
