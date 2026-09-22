// T037：新闻任务版本表的读写（架构 4.4「成功版本不被草稿覆盖」「历史结果保存日期+时区」）。
//
// 断言四件事：
//   1) **追加而不覆盖**：版本号只增，历史行都在；
//   2) **失败/取消的追加不动 is_current**：用户仍然看到上一次成功总结；
//   3) 快照/逐站状态/材料/条目四组 JSON 往返无损（含截断标记与证据标签）；
//   4) 选材查询只取「参与新闻的源」与当日区间的文章。
library;

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/news_run_store.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late DriftNewsRunStore store;

  setUp(() async {
    db = AppDatabase.memory();
    await db.customSelect('SELECT 1').get();
    store = DriftNewsRunStore(db);
  });

  tearDown(() async {
    await db.close();
  });

  NewsInputSnapshot snapshot({
    String localDate = '2026-09-22',
    String timeZone = 'Asia/Shanghai',
    List<NewsMaterial> candidates = const <NewsMaterial>[],
  }) => NewsInputSnapshot(
    localDate: localDate,
    deviceTimeZone: timeZone,
    utcOffsetMinutes: 480,
    dayStartUtc: DateTime.utc(2026, 9, 21, 16),
    dayEndUtc: DateTime.utc(2026, 9, 22, 16),
    frozenAtUtc: DateTime.utc(2026, 9, 22, 13),
    candidates: candidates,
    requiredSites: const <NewsRequiredSite>[
      NewsRequiredSite(name: '甲站', url: 'https://a.example.com'),
    ],
    keywords: const <String>['关键词'],
    blockedQueryTerms: const <String>['禁词'],
    excludedTopics: const <String>['主题'],
    promptVersionRef: 'zh-Hans#1',
    promptText: '任务段\n\n来源段\n\n引用协议',
    maxArticles: 50,
    maxSites: 10,
    maxQueries: 10,
    singleMaterialBudget: 8000,
    globalEnabled: true,
  );

  NewsRunRecord record({
    required int version,
    TaskStatus status = TaskStatus.succeeded,
    bool isCurrent = true,
    List<NewsDraftItem> items = const <NewsDraftItem>[],
  }) {
    final NewsMaterial material = NewsMaterial(
      sourceId: 'rss.7',
      accessMethod: CitationAccessMethod.rss,
      title: '文章七',
      url: 'https://example.com/7',
      publishedAt: DateTime.utc(2026, 9, 22, 2),
      accessedAt: DateTime.utc(2026, 9, 22, 13),
      excerpt: '正文前段',
      materialHash: 'hash-7',
      truncated: true,
      contentLength: 20000,
      articleId: 7,
      feedName: '源 A',
    );
    return NewsRunRecord(
      localDate: '2026-09-22',
      timeZone: 'Asia/Shanghai',
      version: version,
      status: status,
      snapshot: snapshot(candidates: <NewsMaterial>[material]),
      siteResults: const <NewsSiteFetchResult>[
        NewsSiteFetchResult(
          name: '甲站',
          url: 'https://a.example.com',
          status: NewsSiteStatus.timeout,
        ),
        NewsSiteFetchResult(
          name: '乙站',
          url: 'https://b.example.com',
          status: NewsSiteStatus.ok,
          sourceId: 'fetch.abc',
          charCount: 900,
        ),
      ],
      materials: <NewsMaterial>[material],
      items: items.isEmpty
          ? <NewsDraftItem>[
              const NewsDraftItem(
                index: 1,
                text: '某事发生。',
                sourceIds: <String>['rss.7'],
                status: NewsItemStatus.kept,
              ),
              const NewsDraftItem(
                index: 2,
                text: '假事。',
                sourceIds: <String>[],
                status: NewsItemStatus.rejectedUnknownCitation,
                unknownSourceIds: <String>['rss.999'],
              ),
            ]
          : items,
      createdAt: DateTime.utc(2026, 9, 22, 13, 5),
      isCurrent: isCurrent,
      draftText: '某事发生。[rss.7]',
      providerAlias: 'deepseek',
      modelId: 'deepseek-chat',
      consumedTokens: 1234,
      attemptCount: 1,
    );
  }

  group('版本追加与保留', () {
    test('成功版本可以被标为当前版本，四组 JSON 往返无损', () async {
      final Result<NewsRunRecord> saved = await store.append(
        record(version: 1),
      );
      expect(saved.isErr, isFalse);

      final Result<NewsRunRecord?> loaded = await store.loadCurrent(
        localDate: '2026-09-22',
        timeZone: 'Asia/Shanghai',
      );
      final NewsRunRecord current = loaded.valueOrNull!;
      expect(current.version, 1);
      expect(current.isCurrent, isTrue);
      expect(current.status, TaskStatus.succeeded);
      expect(current.snapshot.promptVersionRef, 'zh-Hans#1');
      expect(current.snapshot.dayStartUtc, DateTime.utc(2026, 9, 21, 16));
      expect(current.snapshot.keywords, <String>['关键词']);
      expect(current.snapshot.blockedQueryTerms, <String>['禁词']);
      expect(
        current.snapshot.requiredSites.single.url,
        'https://a.example.com',
      );

      expect(current.siteResults, hasLength(2));
      expect(current.siteResults.first.status, NewsSiteStatus.timeout);
      expect(current.siteResults.last.sourceId, 'fetch.abc');

      expect(current.materials.single.sourceId, 'rss.7');
      expect(current.materials.single.truncated, isTrue);
      expect(current.materials.single.contentLength, 20000);
      expect(current.materials.single.articleId, 7);
      expect(current.materials.single.accessMethod, CitationAccessMethod.rss);

      expect(current.items, hasLength(2));
      expect(current.items.first.kept, isTrue);
      expect(current.items.last.unknownSourceIds, <String>['rss.999']);
      expect(current.items.last.status, NewsItemStatus.rejectedUnknownCitation);
      expect(current.consumedTokens, 1234);
    });

    test('追加失败版本时**不动** is_current：上一次成功版本仍是当前版本', () async {
      await store.append(record(version: 1));
      final Result<NewsRunRecord> failed = await store.append(
        record(
          version: 2,
          status: TaskStatus.failed,
          isCurrent: false,
          items: const <NewsDraftItem>[],
        ),
      );
      expect(failed.isErr, isFalse);

      final NewsRunRecord current = (await store.loadCurrent(
        localDate: '2026-09-22',
        timeZone: 'Asia/Shanghai',
      )).valueOrNull!;
      expect(current.version, 1, reason: '失败草稿不得覆盖上一次成功总结');

      final List<NewsRunRecord> versions = (await store.loadVersions(
        localDate: '2026-09-22',
        timeZone: 'Asia/Shanghai',
      )).valueOrNull!;
      expect(versions, hasLength(2));
      expect(versions.first.version, 2, reason: '版本列表按版本号倒序');
    });

    test('新成功版本接管 is_current，旧版本保留为历史', () async {
      await store.append(record(version: 1));
      await store.append(record(version: 2));
      final List<NewsRunRecord> versions = (await store.loadVersions(
        localDate: '2026-09-22',
        timeZone: 'Asia/Shanghai',
      )).valueOrNull!;
      expect(versions.where((NewsRunRecord r) => r.isCurrent), hasLength(1));
      expect(versions.firstWhere((NewsRunRecord r) => r.isCurrent).version, 2);
    });

    test('历史结果按「日期 + 时区」分开保存：换时区不会串到同一天的另一组', () async {
      await store.append(record(version: 1));
      final Result<NewsRunRecord> other = await store.append(
        NewsRunRecord(
          localDate: '2026-09-22',
          timeZone: 'America/New_York',
          version: 1,
          status: TaskStatus.succeeded,
          snapshot: snapshot(timeZone: 'America/New_York'),
          siteResults: const <NewsSiteFetchResult>[],
          materials: const <NewsMaterial>[],
          items: const <NewsDraftItem>[],
          createdAt: DateTime.utc(2026, 9, 22, 13),
          isCurrent: true,
        ),
      );
      expect(other.isErr, isFalse);
      expect(
        (await store.loadVersions(
          localDate: '2026-09-22',
          timeZone: 'Asia/Shanghai',
        )).valueOrNull,
        hasLength(1),
      );
    });

    test('setCurrentVersion 拒绝把失败版本设为当前版本，且信息可读', () async {
      await store.append(
        record(version: 1, status: TaskStatus.failed, isCurrent: false),
      );
      final Result<void> result = await store.setCurrentVersion(
        localDate: '2026-09-22',
        timeZone: 'Asia/Shanghai',
        version: 1,
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<ValidationError>());
    });

    test('setCurrentVersion 可以把历史成功版本切回当前（用户手动回退）', () async {
      await store.append(record(version: 1));
      await store.append(record(version: 2));
      final Result<void> result = await store.setCurrentVersion(
        localDate: '2026-09-22',
        timeZone: 'Asia/Shanghai',
        version: 1,
      );
      expect(result.isErr, isFalse);
      expect(
        (await store.loadCurrent(
          localDate: '2026-09-22',
          timeZone: 'Asia/Shanghai',
        )).valueOrNull!.version,
        1,
      );
    });

    test('listDates 按日期倒序返回有记录的日期', () async {
      await store.append(record(version: 1));
      await store.append(
        NewsRunRecord(
          localDate: '2026-09-23',
          timeZone: 'Asia/Shanghai',
          version: 1,
          status: TaskStatus.succeeded,
          snapshot: snapshot(localDate: '2026-09-23'),
          siteResults: const <NewsSiteFetchResult>[],
          materials: const <NewsMaterial>[],
          items: const <NewsDraftItem>[],
          createdAt: DateTime.utc(2026, 9, 23, 13),
          isCurrent: true,
        ),
      );
      expect((await store.listDates()).valueOrNull, <String>[
        '2026-09-23',
        '2026-09-22',
      ]);
    });
  });

  group('选材查询（SET-050 逐源开关、架构 4.1）', () {
    late DriftNewsCandidateStore candidates;

    setUp(() async {
      candidates = DriftNewsCandidateStore(db);
    });

    Future<int> insertFeed({
      required String syncId,
      required bool enabled,
      bool? newsEnabled,
    }) => db
        .into(db.feeds)
        .insert(
          FeedsCompanion.insert(
            syncId: syncId,
            normalizedUrl: 'https://$syncId.example.com/feed.xml',
            name: syncId,
            enabled: Value<bool>(enabled),
            newsEnabled: Value<bool?>(newsEnabled),
          ),
        );

    Future<int> insertArticle({
      required int? feedId,
      required String title,
      DateTime? publishedAt,
      DateTime? fetchedAt,
      String? guid,
    }) => db
        .into(db.articles)
        .insert(
          ArticlesCompanion.insert(
            feedId: Value<int?>(feedId),
            title: title,
            identityBasis: IdentityBasis.guid,
            guid: Value<String?>(guid),
            publishedAt: Value<DateTime?>(publishedAt),
            fetchedAt: fetchedAt == null
                ? const Value<DateTime>.absent()
                : Value<DateTime>(fetchedAt),
            sourceUrl: Value<String?>('https://example.com/$title'),
            normalizedLink: Value<String?>('https://example.com/$title'),
          ),
        );

    test('未做过新闻选择的源跟随 enabled（SET-050「已启用订阅默认开」）', () async {
      final int on = await insertFeed(syncId: 'on', enabled: true);
      final int off = await insertFeed(syncId: 'off', enabled: false);
      final DateTime inWindow = DateTime.utc(2026, 9, 22, 5);
      await insertArticle(
        feedId: on,
        title: '参与',
        publishedAt: inWindow,
        guid: 'g1',
      );
      await insertArticle(
        feedId: off,
        title: '不参与',
        publishedAt: inWindow,
        guid: 'g2',
      );

      final List<NewsCandidateArticle> rows = (await candidates.loadCandidates(
        startUtc: DateTime.utc(2026, 9, 21, 16),
        endUtc: DateTime.utc(2026, 9, 22, 16),
        limit: 50,
      )).valueOrNull!;
      expect(rows, hasLength(1));
      expect(rows.single.title, '参与');
    });

    test('显式关掉新闻的源不参与，显式打开的源即使订阅禁用也参与', () async {
      final int excluded = await insertFeed(
        syncId: 'excluded',
        enabled: true,
        newsEnabled: false,
      );
      final int included = await insertFeed(
        syncId: 'included',
        enabled: false,
        newsEnabled: true,
      );
      final DateTime inWindow = DateTime.utc(2026, 9, 22, 5);
      await insertArticle(
        feedId: excluded,
        title: '被排除',
        publishedAt: inWindow,
        guid: 'g1',
      );
      await insertArticle(
        feedId: included,
        title: '被纳入',
        publishedAt: inWindow,
        guid: 'g2',
      );

      final List<NewsCandidateArticle> rows = (await candidates.loadCandidates(
        startUtc: DateTime.utc(2026, 9, 21, 16),
        endUtc: DateTime.utc(2026, 9, 22, 16),
        limit: 50,
      )).valueOrNull!;
      expect(rows.map((NewsCandidateArticle a) => a.title), <String>['被纳入']);
    });

    test('窗口外的文章不参与（发布时间优先，缺失时按抓取时间）', () async {
      final int feed = await insertFeed(syncId: 'feed', enabled: true);
      await insertArticle(
        feedId: feed,
        title: '昨天',
        publishedAt: DateTime.utc(2026, 9, 21, 1),
        guid: 'g1',
      );
      await insertArticle(
        feedId: feed,
        title: '无日期但今天抓到',
        fetchedAt: DateTime.utc(2026, 9, 22, 6),
        guid: 'g2',
      );
      await insertArticle(
        feedId: feed,
        title: '无日期且昨天抓到',
        fetchedAt: DateTime.utc(2026, 9, 21, 6),
        guid: 'g3',
      );

      final List<NewsCandidateArticle> rows = (await candidates.loadCandidates(
        startUtc: DateTime.utc(2026, 9, 21, 16),
        endUtc: DateTime.utc(2026, 9, 22, 16),
        limit: 50,
      )).valueOrNull!;
      expect(rows.map((NewsCandidateArticle a) => a.title), <String>[
        '无日期但今天抓到',
      ]);
      expect(rows.single.publishedAtMissing, isTrue);
      expect(rows.single.guid, 'g2');
    });

    test('已脱离源的文章（feed_id 为空）不参与选材', () async {
      await insertArticle(
        feedId: null,
        title: '孤儿',
        publishedAt: DateTime.utc(2026, 9, 22, 5),
        guid: 'g1',
      );
      final List<NewsCandidateArticle> rows = (await candidates.loadCandidates(
        startUtc: DateTime.utc(2026, 9, 21, 16),
        endUtc: DateTime.utc(2026, 9, 22, 16),
        limit: 50,
      )).valueOrNull!;
      expect(rows, isEmpty);
    });
  });
}
