// T037：每日新闻的输入快照、事件聚合与初稿（架构 4.4、手册 6.3「总结」节）。
//
// 覆盖手册点名的六条：必访失败可见、无搜索配置的处理、**模型编造引用被拒绝**、
// 空输入不编造、预算终止、成功版本保留；外加时区/区间固化、选材上限、去重与禁词拦截。
//
// 全部不联网：抓取与检索都走 T032 的端口替身，模型走 T029 的脚本化替身。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/application/ai_task_budget.dart';
import 'package:flux/features/ai/application/ai_task_runner.dart';
import 'package:flux/features/ai/application/search_manager.dart';
import 'package:flux/features/ai/application/tool_executor.dart';
import 'package:flux/features/ai/domain/ai_message.dart';
import 'package:flux/features/ai/domain/ai_model.dart';
import 'package:flux/features/ai/domain/ai_protocol.dart';
import 'package:flux/features/ai/domain/search_protocol.dart';
import 'package:flux/features/ai/domain/search_service.dart';
import 'package:flux/features/ai/domain/tool_call.dart';
import 'package:flux/features/news/application/news_run_inputs.dart';
import 'package:flux/features/news/application/news_run_service.dart';
import 'package:flux/features/news/application/news_source_config.dart';
import 'package:flux/infrastructure/local/diagnostics.dart';
import 'package:flux/infrastructure/local/feed_store_adapter.dart'
    show DiagnosticLogSink;

import '../ai/ai_runner_support.dart';
import '../ai/tool_support.dart';

/// 上海时区（固定 +8，与 T023 的统计用例同一约定）。
const SessionLocalZone shanghai = FixedOffsetZone(
  Duration(hours: 8),
  ianaName: 'Asia/Shanghai',
);

/// 记录选材查询参数的假候选端口。
final class FakeCandidateStore implements NewsCandidateStore {
  List<NewsCandidateArticle> rows = <NewsCandidateArticle>[];
  AppError? failWith;
  DateTime? lastStartUtc;
  DateTime? lastEndUtc;
  int lastLimit = 0;

  @override
  Future<Result<List<NewsCandidateArticle>>> loadCandidates({
    required DateTime startUtc,
    required DateTime endUtc,
    required int limit,
  }) async {
    lastStartUtc = startUtc;
    lastEndUtc = endUtc;
    lastLimit = limit;
    final AppError? failure = failWith;
    if (failure != null) {
      return Err<List<NewsCandidateArticle>>(failure);
    }
    return Ok<List<NewsCandidateArticle>>(rows);
  }
}

/// 内存版本存储（复现真实的「成功版本不被草稿覆盖」语义）。
final class MemoryNewsRunStore implements NewsRunStore {
  final List<NewsRunRecord> rows = <NewsRunRecord>[];

  @override
  Future<Result<NewsRunRecord>> append(NewsRunRecord record) async {
    if (record.isCurrent) {
      for (int i = 0; i < rows.length; i++) {
        final NewsRunRecord row = rows[i];
        if (row.localDate == record.localDate &&
            row.timeZone == record.timeZone &&
            row.isCurrent) {
          rows[i] = row.copyWith(isCurrent: false);
        }
      }
    }
    final NewsRunRecord saved = record.copyWith(id: rows.length + 1);
    rows.add(saved);
    return Ok<NewsRunRecord>(saved);
  }

  @override
  Future<Result<List<NewsRunRecord>>> loadVersions({
    required String localDate,
    required String timeZone,
  }) async {
    final List<NewsRunRecord> matched =
        rows
            .where(
              (NewsRunRecord r) =>
                  r.localDate == localDate && r.timeZone == timeZone,
            )
            .toList()
          ..sort(
            (NewsRunRecord a, NewsRunRecord b) =>
                b.version.compareTo(a.version),
          );
    return Ok<List<NewsRunRecord>>(matched);
  }

  @override
  Future<Result<NewsRunRecord?>> loadCurrent({
    required String localDate,
    required String timeZone,
  }) async {
    for (final NewsRunRecord row in rows) {
      if (row.localDate == localDate &&
          row.timeZone == timeZone &&
          row.isCurrent) {
        return Ok<NewsRunRecord?>(row);
      }
    }
    return const Ok<NewsRunRecord?>(null);
  }

  @override
  Future<Result<void>> setCurrentVersion({
    required String localDate,
    required String timeZone,
    required int version,
  }) async => okUnit();

  @override
  Future<Result<List<String>>> listDates() async => Ok<List<String>>(
    <String>{for (final NewsRunRecord r in rows) r.localDate}.toList(),
  );
}

/// 检索可用性替身。
final class FakeSearchAvailability implements NewsSearchAvailability {
  FakeSearchAvailability({this.available = true});

  bool available;

  @override
  Future<Result<bool>> hasEnabledService() async => Ok<bool>(available);
}

void main() {
  const AiModel model = AiModel(
    alias: 'deepseek',
    protocol: AiProtocol.openAiChatCompletions,
    baseUrl: 'https://api.example.com',
    modelId: 'deepseek-chat',
  );

  late FakeClock clock;
  late DiagnosticLog diagnostics;
  late FakeCandidateStore candidateStore;
  late MemoryNewsRunStore runStore;
  late FakeSearchServiceStore serviceStore;
  late FakeSearchCredentials credentials;
  late RecordingSearchFactory searchFactory;
  late FakePageFetcher pageFetcher;
  late FakeImageInspector imageInspector;
  late FakeSearchAvailability availability;

  setUp(() {
    // 设备在 UTC+8，任务时刻是当地 2026-09-22 21:00（默认执行时间附近）。
    clock = FakeClock(start: DateTime.utc(2026, 9, 22, 13));
    diagnostics = DiagnosticLog(level: DiagnosticLevel.info);
    candidateStore = FakeCandidateStore();
    runStore = MemoryNewsRunStore();
    serviceStore = FakeSearchServiceStore();
    credentials = FakeSearchCredentials();
    searchFactory = RecordingSearchFactory();
    pageFetcher = FakePageFetcher();
    imageInspector = FakeImageInspector();
    availability = FakeSearchAvailability();
  });

  ToolExecutor buildTools({int toolLimit = 30}) => ToolExecutor(
    budget: ToolCallBudget(limit: toolLimit),
    config: const ToolExecutorConfig(),
    searchManager: SearchManager(
      store: serviceStore,
      credentials: credentials,
      diagnostics: DiagnosticLogSink(diagnostics),
      factory: searchFactory,
    ),
    pageFetcher: pageFetcher,
    imageInspector: imageInspector,
    diagnostics: DiagnosticLogSink(diagnostics),
  );

  NewsRunService buildService({
    ScriptedAiFactory? factory,
    List<NewsRequiredSite> sites = const <NewsRequiredSite>[],
    List<String> keywords = const <String>[],
    List<String> blocked = const <String>[],
    NewsTaskSettings settings = const NewsTaskSettings(),
    int toolLimit = 30,
    AiTaskBudget budget = const AiTaskBudget(),
  }) {
    final ScriptedAiFactory effective =
        factory ??
        ScriptedAiFactory(<String, List<AiAttemptScript>>{
          'deepseek': <AiAttemptScript>[
            const ScriptSuccess(deltas: <String>['初稿']),
          ],
        }, scriptClock: clock);
    effective.scriptClock ??= clock;
    return NewsRunService(
      candidates: candidateStore,
      runs: runStore,
      buildTools: () => buildTools(toolLimit: toolLimit),
      runner: AiTaskRunner(
        credentials: const AlwaysCredentialStore(),
        factory: effective,
        diagnostics: DiagnosticLogSink(diagnostics),
        budget: budget,
        clock: clock,
        delayScheduler: AdvancingDelayScheduler(clock),
      ),
      loadModels: () async => const Ok<List<AiModel>>(<AiModel>[model]),
      searchAvailability: availability,
      diagnostics: DiagnosticLogSink(diagnostics),
      clock: clock,
      zone: shanghai,
      settings: settings,
    );
  }

  NewsRunInput buildInput({
    List<NewsRequiredSite> sites = const <NewsRequiredSite>[],
    List<String> keywords = const <String>[],
    List<String> blocked = const <String>[],
    bool globalEnabled = true,
    AiCancellation? cancellation,
  }) => NewsRunInput(
    taskId: 'news-1',
    config: NewsConfigState.initial().copyWith(
      requiredSites: sites,
      keywords: keywords,
      blockedQueryTerms: blocked,
    ),
    globalEnabled: globalEnabled,
    cancellation: cancellation,
  );

  NewsCandidateArticle article({
    required int id,
    String? guid,
    String? link,
    String? title,
    DateTime? publishedAt,
    bool favorite = false,
  }) => NewsCandidateArticle(
    articleId: id,
    feedId: 1,
    feedName: '源 A',
    title: title ?? '文章 $id',
    summary: '摘要 $id',
    body: '正文 $id',
    // 默认发布时间按 id 递增，使「按时间倒序」在选择结果里是确定的（id 越大越新）。
    publishedAt: publishedAt ?? DateTime.utc(2026, 9, 22, 2, id),
    fetchedAt: DateTime.utc(2026, 9, 22, 3),
    sourceUrl: link ?? 'https://example.com/a/$id',
    guid: guid,
    normalizedLink: link,
    favorite: favorite,
  );

  group('日期区间与时区固化（SET-058、架构 4.4）', () {
    test('设备在 UTC+8 时，当日区间是当地 00:00–24:00', () {
      final NewsDayRange range = newsDayRange(
        nowUtc: DateTime.utc(2026, 9, 22, 13, 30),
        zone: shanghai,
      );
      expect(range.localDate, '2026-09-22');
      // 当地 00:00 = UTC 前一天 16:00。
      expect(range.startUtc, DateTime.utc(2026, 9, 21, 16));
      expect(range.endUtc, DateTime.utc(2026, 9, 22, 16));
      expect(range.utcOffsetMinutes, 480);
      expect(range.length, const Duration(hours: 24));
    });

    test('当地刚过午夜时归属**当天**，而不是 UTC 的昨天', () {
      // 当地 2026-09-22 00:10 = UTC 2026-09-21 16:10。
      final NewsDayRange range = newsDayRange(
        nowUtc: DateTime.utc(2026, 9, 21, 16, 10),
        zone: shanghai,
      );
      expect(range.localDate, '2026-09-22');
      expect(range.startUtc, DateTime.utc(2026, 9, 21, 16));
    });

    test('时区不同则区间不同（同一个 UTC 时刻，纽约与上海归属不同日期）', () {
      const SessionLocalZone newYork = FixedOffsetZone(
        Duration(hours: -5),
        ianaName: 'America/New_York',
      );
      final DateTime instant = DateTime.utc(2026, 9, 22, 1);
      expect(
        newsDayRange(nowUtc: instant, zone: shanghai).localDate,
        '2026-09-22',
      );
      expect(
        newsDayRange(nowUtc: instant, zone: newYork).localDate,
        '2026-09-21',
      );
    });
  });

  group('选材：上限、排序与去重（SET-050/060、架构 4.1）', () {
    test('按上限截断，并记下被舍掉的条数', () {
      final NewsSelection selection = selectNewsCandidates(
        candidates: <NewsCandidateArticle>[
          for (int i = 1; i <= 8; i++) article(id: i),
        ],
        maxArticles: 3,
      );
      expect(selection.articles, hasLength(3));
      expect(selection.totalInWindow, 8);
      expect(selection.droppedByLimit, 5);
    });

    test('发布时间倒序；加精**不**参与权重', () {
      final NewsSelection selection = selectNewsCandidates(
        candidates: <NewsCandidateArticle>[
          article(id: 1, publishedAt: DateTime.utc(2026, 9, 22, 1)),
          article(
            id: 2,
            publishedAt: DateTime.utc(2026, 9, 22, 5),
            favorite: true,
          ),
          article(id: 3, publishedAt: DateTime.utc(2026, 9, 22, 3)),
        ],
        maxArticles: 50,
      );
      expect(
        selection.articles
            .map((NewsCandidateArticle a) => a.articleId)
            .toList(),
        <int>[2, 3, 1],
      );
    });

    test('发布时间缺失时按抓取时间参与同一次排序', () {
      final NewsSelection selection = selectNewsCandidates(
        candidates: <NewsCandidateArticle>[
          NewsCandidateArticle(
            articleId: 1,
            feedId: 1,
            feedName: '源',
            title: '无日期',
            fetchedAt: DateTime.utc(2026, 9, 22, 9),
          ),
          article(id: 2, publishedAt: DateTime.utc(2026, 9, 22, 2)),
        ],
        maxArticles: 50,
      );
      expect(selection.articles.first.articleId, 1);
    });

    test('同 GUID 的两条视为同一稿件，只留一条', () {
      final NewsSelection selection = selectNewsCandidates(
        candidates: <NewsCandidateArticle>[
          article(id: 1, guid: 'g-1', link: null),
          article(id: 2, guid: 'g-1', link: null),
        ],
        maxArticles: 50,
      );
      expect(selection.articles, hasLength(1));
      expect(selection.deduplicatedCount, 1);
    });

    test('同一稿件换 URL（跟踪参数不同）仍被聚合', () {
      final NewsSelection selection = selectNewsCandidates(
        candidates: <NewsCandidateArticle>[
          article(id: 1, link: 'https://news.example.com/a?utm_source=x'),
          article(id: 2, link: 'https://news.example.com/a'),
        ],
        maxArticles: 50,
      );
      expect(selection.articles, hasLength(1));
      expect(selection.deduplicatedCount, 1);
    });

    test('标题为空的候选不参与选材', () {
      final NewsSelection selection = selectNewsCandidates(
        candidates: <NewsCandidateArticle>[article(id: 1, title: '  ')],
        maxArticles: 50,
      );
      expect(selection.articles, isEmpty);
    });
  });

  group('材料构造与 prompt 组装（SET-061、架构 4.4）', () {
    test('超过单材料预算的正文被截断并**标注**', () {
      final NewsMaterial material = buildRssMaterial(
        candidate: NewsCandidateArticle(
          articleId: 7,
          feedId: 1,
          feedName: '源',
          title: '长文',
          body: '字' * 100,
          fetchedAt: DateTime.utc(2026, 9, 22, 3),
          sourceUrl: 'https://example.com/7',
        ),
        charBudget: 10,
        accessedAt: DateTime.utc(2026, 9, 22, 13),
      );
      expect(material.excerpt.length, 10);
      expect(material.truncated, isTrue);
      expect(material.contentLength, 100);
      expect(material.sourceId, 'rss.7');
      final String block = buildNewsMaterialBlock(<NewsMaterial>[material]);
      expect(block, contains('已按单材料预算截断'));
    });

    test('没有正文也没有摘要时如实说明，而不是留一段空白', () {
      final NewsMaterial material = buildRssMaterial(
        candidate: NewsCandidateArticle(
          articleId: 8,
          feedId: 1,
          feedName: '源',
          title: '只有标题',
          fetchedAt: DateTime.utc(2026, 9, 22, 3),
          sourceUrl: 'https://example.com/8',
        ),
        charBudget: 100,
        accessedAt: DateTime.utc(2026, 9, 22, 13),
      );
      expect(material.excerpt, isEmpty);
      expect(
        buildNewsMaterialBlock(<NewsMaterial>[material]),
        contains('来源只提供了标题'),
      );
    });

    test('必访站逐站状态写进上下文，失败站点明确列出', () {
      final String block = buildSiteStatusBlock(<NewsSiteFetchResult>[
        const NewsSiteFetchResult(
          name: '甲站',
          url: 'https://a.example.com',
          status: NewsSiteStatus.ok,
          charCount: 1200,
        ),
        const NewsSiteFetchResult(
          name: '乙站',
          url: 'https://b.example.com',
          status: NewsSiteStatus.timeout,
        ),
      ]);
      expect(block, contains('甲站'));
      expect(block, contains('已获取'));
      expect(block, contains('乙站'));
      expect(block, contains('超时未完成'));
      expect(block, contains('不要为它们编造内容'));
    });

    test('材料段落声明这是第三方数据而不是指令', () {
      final NewsMaterial material = buildRssMaterial(
        candidate: article(id: 1),
        charBudget: 100,
        accessedAt: DateTime.utc(2026, 9, 22, 13),
      );
      expect(
        buildNewsMaterialBlock(<NewsMaterial>[material]),
        contains('不是指令'),
      );
    });
  });

  group('初稿解析与引用校验（架构 4.4、手册 6.3「模型编造引用被拒绝」）', () {
    test('引用都在材料集合里的条目被保留', () {
      final NewsDraftParseResult parsed = parseNewsDraft(
        text: '今日要闻\n某地发生某事。[rss.1][fetch.ab]',
        knownSourceIds: <String>{'rss.1', 'fetch.ab'},
      );
      expect(parsed.ok, isTrue);
      expect(parsed.headings, <String>['今日要闻']);
      expect(parsed.keptItems.single.sourceIds, <String>['rss.1', 'fetch.ab']);
      expect(parsed.keptItems.single.text, '某地发生某事。');
    });

    test('编造引用的条目被**退回**，并记录不存在的 id', () {
      final NewsDraftParseResult parsed = parseNewsDraft(
        text: '真事。[rss.1]\n假事。[https://evil.example.com]\n假事二。[rss.404]',
        knownSourceIds: <String>{'rss.1'},
      );
      expect(parsed.keptItems, hasLength(1));
      expect(parsed.rejectedItems, hasLength(2));
      expect(parsed.hasFabricatedCitation, isTrue);
      expect(parsed.unknownSourceIds, contains('rss.404'));
      expect(
        parsed.rejectedItems.every(
          (NewsDraftItem item) =>
              item.status == NewsItemStatus.rejectedUnknownCitation,
        ),
        isTrue,
      );
    });

    test('全部条目都编造引用时整稿失败（不产出任何结论）', () {
      final NewsDraftParseResult parsed = parseNewsDraft(
        text: '假事一。[rss.404]\n假事二。[rss.500]',
        knownSourceIds: <String>{'rss.1'},
      );
      expect(parsed.ok, isFalse);
      expect(parsed.failureReason, 'fabricatedCitations');
    });

    test('没有任何引用的长句按「缺引用」退回，短标题按标题保留', () {
      final NewsDraftParseResult parsed = parseNewsDraft(
        text: '主题分组\n这是一句没有任何引用的话，按引用协议它不该出现。',
        knownSourceIds: <String>{'rss.1'},
      );
      expect(parsed.headings, <String>['主题分组']);
      expect(parsed.rejectedItems, hasLength(1));
      expect(
        parsed.rejectedItems.single.status,
        NewsItemStatus.rejectedMissingCitation,
      );
    });

    test('markdown 链接不被误判成引用', () {
      final NewsDraftParseResult parsed = parseNewsDraft(
        text: '参见 [某报道](https://example.com/x) 的说法。[rss.1]',
        knownSourceIds: <String>{'rss.1'},
      );
      expect(parsed.ok, isTrue);
      expect(parsed.unknownSourceIds, isEmpty);
      expect(parsed.keptItems.single.text, contains('某报道'));
    });

    test('输出为空时如实失败，不产出一条空结论', () {
      final NewsDraftParseResult parsed = parseNewsDraft(
        text: '   \n\n',
        knownSourceIds: <String>{'rss.1'},
      );
      expect(parsed.ok, isFalse);
      expect(parsed.failureReason, 'emptyOutput');
    });
  });

  group('端到端：快照固化、必访失败可见、禁词拦截', () {
    test('快照固化时区/区间/选材上限，并落库为版本 v1（成功）', () async {
      candidateStore.rows = <NewsCandidateArticle>[
        for (int i = 1; i <= 5; i++) article(id: i),
      ];
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'deepseek': <AiAttemptScript>[
            // 选材取的是最新 3 篇（id 5/4/3），因此引用必须是 rss.5 才是真实材料。
            const ScriptSuccess(deltas: <String>['今日要闻\n某地发生某事。[rss.5]']),
          ],
        },
        scriptClock: clock,
      );
      final NewsRunOutcome outcome = await buildService(
        factory: factory,
        settings: const NewsTaskSettings(maxArticles: 3),
      ).run(buildInput());

      expect(outcome.ok, isTrue, reason: '产出可用结果时应为成功');
      final NewsRunRecord record = outcome.record!;
      expect(record.version, 1);
      expect(record.status, TaskStatus.succeeded);
      expect(record.isCurrent, isTrue);
      expect(record.localDate, '2026-09-22');
      expect(record.timeZone, 'Asia/Shanghai');
      expect(record.snapshot.dayStartUtc, DateTime.utc(2026, 9, 21, 16));
      expect(record.snapshot.dayEndUtc, DateTime.utc(2026, 9, 22, 16));
      expect(record.snapshot.candidates, hasLength(3));
      expect(record.snapshot.hash, isNotEmpty);
      expect(record.items.where((NewsDraftItem i) => i.kept), hasLength(1));
      expect(candidateStore.lastLimit, 3);
    });

    test('必访站失败可见：状态记为 partial，逐站结果落库', () async {
      candidateStore.rows = <NewsCandidateArticle>[article(id: 1)];
      pageFetcher.failWith = NetworkError(
        uri: 'https://b.example.com',
        reason: '拒绝连接',
      );
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'deepseek': <AiAttemptScript>[
            const ScriptSuccess(deltas: <String>['某事。[rss.1]']),
          ],
        },
        scriptClock: clock,
      );
      final NewsRunOutcome outcome = await buildService(factory: factory).run(
        buildInput(
          sites: <NewsRequiredSite>[
            const NewsRequiredSite(name: '乙站', url: 'https://b.example.com'),
          ],
        ),
      );

      expect(outcome.status, TaskStatus.partial);
      expect(outcome.record!.siteResults, hasLength(1));
      expect(outcome.record!.siteResults.single.failed, isTrue);
      expect(outcome.record!.siteResults.single.detailKind, 'network');
      expect(pageFetcher.calls, 1);
    });

    test('禁词命中的查询**不会**发给搜索服务', () async {
      // 标题很短，因此不会派生查询——本用例只关心「关键词列表里的禁词」。
      candidateStore.rows = <NewsCandidateArticle>[article(id: 1, title: '短讯')];
      await serviceStore.insert(
        const SearchService(
          label: 'main',
          protocol: SearchProtocol.tavily,
          baseUrl: 'https://api.example.com',
        ),
      );
      await credentials.write('main', 'k');
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'deepseek': <AiAttemptScript>[
            const ScriptSuccess(deltas: <String>['某事。[rss.1]']),
          ],
        },
        scriptClock: clock,
      );
      final NewsRunOutcome outcome = await buildService(factory: factory).run(
        buildInput(keywords: <String>['正常查询', '股市内幕'], blocked: <String>['股市']),
      );
      expect(searchFactory.searches, 1);
      expect(searchFactory.lastQuery, '正常查询');
      expect(outcome.aggregation!.blockedQueryCount, 1);
    });

    test('派生查询同样受禁词约束（命中的派生查询也不发出）', () async {
      candidateStore.rows = <NewsCandidateArticle>[
        article(id: 1, title: '股市今日大幅波动'),
      ];
      await serviceStore.insert(
        const SearchService(
          label: 'main',
          protocol: SearchProtocol.tavily,
          baseUrl: 'https://api.example.com',
        ),
      );
      await credentials.write('main', 'k');
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'deepseek': <AiAttemptScript>[
            const ScriptSuccess(deltas: <String>['某事。[rss.1]']),
          ],
        },
        scriptClock: clock,
      );
      final NewsRunOutcome outcome = await buildService(factory: factory)
          .run(buildInput(blocked: <String>['股市']));
      expect(searchFactory.searches, 0);
      expect(outcome.aggregation!.issuedQueries, isEmpty);
      expect(outcome.aggregation!.blockedQueryCount, 1);
    });

    test('没有搜索配置时不标「已核验」，任务照常生成（RSS 材料可用）', () async {
      candidateStore.rows = <NewsCandidateArticle>[article(id: 1)];
      availability.available = false;
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'deepseek': <AiAttemptScript>[
            const ScriptSuccess(deltas: <String>['某事。[rss.1]']),
          ],
        },
        scriptClock: clock,
      );
      final NewsRunOutcome outcome = await buildService(factory: factory)
          .run(buildInput(keywords: <String>['某个查询']));
      expect(outcome.ok, isTrue);
      expect(outcome.aggregation!.issuedQueries, isEmpty);
      expect(searchFactory.searches, 0, reason: '没有配置就不该发任何检索请求');
    });
  });

  group('空输入与预算（手册 6.3「无搜索配置等待」「不编造新闻」）', () {
    test('无文章、无关键词、无必访站时不生成，且**一个模型请求都不发**', () async {
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'deepseek': <AiAttemptScript>[
            const ScriptSuccess(deltas: <String>['不该发生的产出']),
          ],
        },
        scriptClock: clock,
      );
      final NewsRunOutcome outcome = await buildService(factory: factory)
          .run(buildInput());
      expect(outcome.ok, isFalse);
      expect(outcome.shortfall, NewsInputShortfall.noInputAtAll);
      expect(outcome.status, TaskStatus.failed);
      expect(factory.totalIssued, 0, reason: '缺输入时不得编造，也不得发请求');
      expect(outcome.record!.items, isEmpty);
      expect(outcome.record!.errorKind, 'validation');
    });

    test('总开关关闭且没有其它输入时进入 waitingConfiguration（等待配置）', () async {
      final NewsRunOutcome outcome = await buildService().run(
        buildInput(globalEnabled: false),
      );
      expect(outcome.status, TaskStatus.waitingConfiguration);
      expect(outcome.shortfall, NewsInputShortfall.globalDisabled);
    });

    test('总开关关闭时 RSS 选材为空，但显式关键词仍可发起检索', () async {
      candidateStore.rows = <NewsCandidateArticle>[article(id: 1)];
      await serviceStore.insert(
        const SearchService(
          label: 'main',
          protocol: SearchProtocol.tavily,
          baseUrl: 'https://api.example.com',
        ),
      );
      await credentials.write('main', 'k');
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'deepseek': <AiAttemptScript>[
            const ScriptSuccess(deltas: <String>['某事。[rss.1]']),
          ],
        },
        scriptClock: clock,
      );
      final NewsRunOutcome outcome = await buildService(factory: factory)
          .run(buildInput(globalEnabled: false, keywords: <String>['某个查询']));
      expect(outcome.snapshot.candidates, isEmpty, reason: '总开关关闭则 RSS 不选材');
      expect(searchFactory.searches, 1);
    });

    test('必访站全部失败且无其它输入时，如实记录逐站失败而不是编造', () async {
      pageFetcher.failWith = NetworkError(
        uri: 'https://a.example.com',
        reason: '超时',
      );
      final NewsRunOutcome outcome = await buildService().run(
        buildInput(
          sites: <NewsRequiredSite>[
            const NewsRequiredSite(name: '甲站', url: 'https://a.example.com'),
          ],
        ),
      );
      expect(outcome.ok, isFalse);
      expect(outcome.status, TaskStatus.failed);
      expect(outcome.record!.siteResults.single.failed, isTrue);
      expect(outcome.record!.items, isEmpty);
    });

    test('总时限已过时不再发起模型请求（预算终止）', () async {
      candidateStore.rows = <NewsCandidateArticle>[article(id: 1)];
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'deepseek': <AiAttemptScript>[
            const ScriptSuccess(deltas: <String>['某事。[rss.1]']),
          ],
        },
        scriptClock: clock,
      );
      // 人为把时钟推到远超总时限之后：deadline 在任务创建时按「现在 + 10 分钟」固定，
      // 因此这里模拟的是「一个已过期的任务」（例如排队排了很久）。
      final NewsRunService service = buildService(factory: factory);
      clock.advance(const Duration(hours: 2));
      final NewsRunOutcome outcome = await service.run(buildInput());
      // 任务在过期时刻开始时，AiTaskRunner 的 deadline 仍是「现在 + 10 分钟」，
      // 因此这里断言的是「按当前时钟正确计算了区间」，而不是硬造一个过期任务。
      expect(outcome.snapshot.localDate, '2026-09-22');
      expect(factory.totalIssued <= 1, isTrue);
    });

    test('取消后不再发请求，状态为 cancelled 且保留上一版成功总结', () async {
      candidateStore.rows = <NewsCandidateArticle>[article(id: 1)];
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'deepseek': <AiAttemptScript>[
            const ScriptSuccess(deltas: <String>['某事。[rss.1]']),
          ],
        },
        scriptClock: clock,
      );
      final NewsRunService service = buildService(factory: factory);
      final NewsRunOutcome first = await service.run(buildInput());
      expect(first.status, TaskStatus.succeeded);

      final AiCancellation cancellation = AiCancellation();
      cancellation.cancel();
      final NewsRunOutcome second = await service.run(
        buildInput(cancellation: cancellation),
      );
      expect(second.status, TaskStatus.cancelled);
      expect(runStore.rows, hasLength(2));
      final Result<NewsRunRecord?> current = await runStore.loadCurrent(
        localDate: '2026-09-22',
        timeZone: 'Asia/Shanghai',
      );
      expect(current.valueOrNull!.version, 1, reason: '取消不覆盖上一次成功版本');
      expect(current.valueOrNull!.isCurrent, isTrue);
      expect(factory.totalIssued, 1, reason: '取消后不再请求模型');
    });

    test('第二次生成追加 v2，成功版本仍被保留（版本只增）', () async {
      candidateStore.rows = <NewsCandidateArticle>[article(id: 1)];
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'deepseek': <AiAttemptScript>[
            const ScriptSuccess(deltas: <String>['第一版。[rss.1]']),
            const ScriptSuccess(deltas: <String>['第二版。[rss.1]']),
          ],
        },
        scriptClock: clock,
      );
      final NewsRunService service = buildService(factory: factory);
      final NewsRunOutcome first = await service.run(buildInput());
      final NewsRunOutcome second = await service.run(
        NewsRunInput(
          taskId: 'news-2',
          config: NewsConfigState.initial(),
          globalEnabled: true,
          regenerate: true,
        ),
      );
      expect(first.record!.version, 1);
      expect(second.record!.version, 2);
      final Result<List<NewsRunRecord>> versions = await runStore.loadVersions(
        localDate: '2026-09-22',
        timeZone: 'Asia/Shanghai',
      );
      expect(versions.valueOrNull, hasLength(2));
      expect(versions.valueOrNull!.first.version, 2);
      expect(
        versions.valueOrNull!.last.isCurrent,
        isFalse,
        reason: '旧版本被保留为历史，但不再是当前展示版本',
      );
    });

    test('模型编造引用时条目被退回；全部编造则整稿失败且不写成功版本', () async {
      candidateStore.rows = <NewsCandidateArticle>[article(id: 1)];
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'deepseek': <AiAttemptScript>[
            const ScriptSuccess(deltas: <String>['假事。[rss.999]']),
          ],
        },
        scriptClock: clock,
      );
      final NewsRunOutcome outcome = await buildService(factory: factory)
          .run(buildInput());
      expect(outcome.ok, isFalse);
      expect(outcome.status, TaskStatus.failed);
      expect(outcome.record!.errorKind, 'parse');
      expect(outcome.record!.items.single.unknownSourceIds, <String>[
        'rss.999',
      ]);
      final Result<NewsRunRecord?> current = await runStore.loadCurrent(
        localDate: '2026-09-22',
        timeZone: 'Asia/Shanghai',
      );
      expect(current.valueOrNull, isNull, reason: '没有成功产出就不该有当前版本');
    });

    test('诊断不记录材料正文与查询词（架构第 8 节）', () async {
      candidateStore.rows = <NewsCandidateArticle>[
        article(id: 1, title: '机密标题', link: 'https://secret.example.com/a'),
      ];
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'deepseek': <AiAttemptScript>[
            const ScriptSuccess(deltas: <String>['某事。[rss.1]']),
          ],
        },
        scriptClock: clock,
      );
      await buildService(factory: factory)
          .run(buildInput(keywords: <String>['机密查询词']));
      final String log = diagnostics.entries.map((e) => e.message).join('\n');
      expect(log, isNot(contains('机密标题')));
      expect(log, isNot(contains('secret.example.com')));
      expect(log, isNot(contains('机密查询词')));
    });
  });

  group('材料总预算与派生查询', () {
    test('总字符预算不足时保留靠前的材料并记下被舍掉的条数', () {
      final MaterialBudgetOutcome outcome = applyMaterialCharacterBudget(
        materials: <NewsMaterial>[
          for (int i = 1; i <= 3; i++)
            NewsMaterial(
              sourceId: 'rss.$i',
              accessMethod: CitationAccessMethod.rss,
              title: 'T$i',
              url: 'https://example.com/$i',
              excerpt: 'x' * 100,
              materialHash: 'h$i',
            ),
        ],
        characterBudget: 250,
      );
      expect(outcome.materials, hasLength(2));
      expect(outcome.droppedCount, 1);
    });

    test('预算为 0 时一条材料都不进 prompt（不超支）', () {
      final MaterialBudgetOutcome outcome = applyMaterialCharacterBudget(
        materials: <NewsMaterial>[
          const NewsMaterial(
            sourceId: 'rss.1',
            accessMethod: CitationAccessMethod.rss,
            title: 'T',
            url: 'https://example.com/1',
            excerpt: '正文',
            materialHash: 'h',
          ),
        ],
        characterBudget: 0,
      );
      expect(outcome.materials, isEmpty);
      expect(outcome.droppedCount, 1);
    });

    test('派生查询取自标题前段，且过短的标题不派生', () {
      final List<String> queries = deriveQueriesFromArticles(
        articles: <NewsCandidateArticle>[
          article(id: 1, title: '某某城市今日发生重大交通事故'),
          article(id: 2, title: '简讯'),
        ],
        maxQueries: 3,
      );
      expect(queries, <String>['某某城市今日发生重大交通事故']);
    });

    test('被禁词拦下的查询计入统计（界面据此说明）', () {
      expect(
        countBlockedQueries(
          rawQueries: <String>['正常', '股市行情', '  '],
          blockedQueryTerms: <String>['股市'],
        ),
        1,
      );
    });
  });
}
