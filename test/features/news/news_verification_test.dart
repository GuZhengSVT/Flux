// T038：独立来源核验、转载聚类、引用校验与版本保存（架构 4.4、手册 6.3「两份转载不当
// 独立证据」「无搜索配置等待」）。
//
// 断言的重点是**判定的方向性**：
//   - 支持需要真的重叠（不是「搜到了就算支持」）；
//   - 冲突是保守的（无法确定绝不标冲突）；
//   - 转载不产生第二条独立来源；
//   - 核验失败不丢初稿。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/application/ai_task_budget.dart';
import 'package:flux/features/ai/application/ai_task_runner.dart';
import 'package:flux/features/ai/application/search_manager.dart';
import 'package:flux/features/ai/application/tool_executor.dart';
import 'package:flux/features/ai/domain/ai_model.dart';
import 'package:flux/features/ai/domain/ai_protocol.dart';
import 'package:flux/features/ai/domain/search_protocol.dart';
import 'package:flux/features/ai/domain/search_provider.dart';
import 'package:flux/features/ai/domain/search_result.dart';
import 'package:flux/features/ai/domain/search_service.dart';
import 'package:flux/features/ai/domain/tool_call.dart';
import 'package:flux/features/news/application/news_run_service.dart';
import 'package:flux/features/news/application/news_source_config.dart';
import 'package:flux/features/news/application/news_verification_service.dart';
import 'package:flux/infrastructure/local/diagnostics.dart';
import 'package:flux/infrastructure/local/feed_store_adapter.dart'
    show DiagnosticLogSink;

import '../ai/ai_runner_support.dart';
import '../ai/tool_support.dart';
import 'news_run_test.dart'
    show FakeCandidateStore, MemoryNewsRunStore, shanghai;

/// 返回固定结果的检索替身（与 tool_support 的 RecordingSearchFactory 不同：
/// 核验要按**查询**给不同结果，否则「支持/矛盾」两类判定无法区分）。
final class FakeSearchFactory implements SearchProviderFactory {
  final List<String> queries = <String>[];

  /// 查询 → 结果列表（未配置的查询返回空结果）。
  Map<String, List<SearchResult>> resultsByQuery =
      <String, List<SearchResult>>{};

  AppError? failWith;

  @override
  Result<SearchProvider> create({
    required SearchProtocol protocol,
    required String baseUrl,
    required String apiKey,
    Duration timeout = const Duration(seconds: 20),
    int maxResults = 10,
    bool allowPrivateEndpoint = false,
  }) => Ok<SearchProvider>(_FakeProvider(this, protocol));
}

final class _FakeProvider implements SearchProvider {
  _FakeProvider(this._factory, this._protocol);

  final FakeSearchFactory _factory;
  final SearchProtocol _protocol;

  @override
  String get providerId => _protocol.id;

  @override
  Future<Result<SearchResponse>> search(SearchRequest query) async {
    _factory.queries.add(query.text);
    final AppError? failure = _factory.failWith;
    if (failure != null) {
      return Err<SearchResponse>(failure);
    }
    final List<SearchResult> results =
        _factory.resultsByQuery[query.text] ?? const <SearchResult>[];
    return Ok<SearchResponse>(
      SearchResponse(
        provider: _protocol.id,
        query: query.text,
        results: results,
      ),
    );
  }
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
  late FakeSearchFactory searchFactory;
  late FakePageFetcher pageFetcher;
  late FakeImageInspector imageInspector;

  setUp(() async {
    clock = FakeClock(start: DateTime.utc(2026, 9, 22, 13));
    diagnostics = DiagnosticLog(level: DiagnosticLevel.info);
    candidateStore = FakeCandidateStore();
    runStore = MemoryNewsRunStore();
    serviceStore = FakeSearchServiceStore();
    credentials = FakeSearchCredentials();
    searchFactory = FakeSearchFactory();
    pageFetcher = FakePageFetcher();
    imageInspector = FakeImageInspector();
    await serviceStore.insert(
      const SearchService(
        label: 'main',
        protocol: SearchProtocol.tavily,
        baseUrl: 'https://api.example.com',
      ),
    );
    await credentials.write('main', 'k');
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

  NewsVerificationService service({int toolLimit = 30}) =>
      NewsVerificationService(
        buildTools: () => buildTools(toolLimit: toolLimit),
        diagnostics: DiagnosticLogSink(diagnostics),
      );

  NewsDraftItem item({
    int index = 1,
    String text = '央行今日宣布降息二十五个基点。',
    List<String> sourceIds = const <String>['rss.1'],
  }) => NewsDraftItem(
    index: index,
    text: text,
    sourceIds: sourceIds,
    status: NewsItemStatus.kept,
  );

  NewsMaterial material({
    String sourceId = 'rss.1',
    String title = '央行宣布降息',
    String url = 'https://a.example.com/news/1',
    String excerpt = '央行今日宣布降息二十五个基点，市场反应平稳。',
    DateTime? publishedAt,
    DateTime? accessedAt,
    CitationAccessMethod accessMethod = CitationAccessMethod.rss,
    int? articleId,
  }) => NewsMaterial(
    sourceId: sourceId,
    accessMethod: accessMethod,
    title: title,
    url: url,
    excerpt: excerpt,
    materialHash: 'hash-$sourceId',
    publishedAt: publishedAt,
    accessedAt: accessedAt,
    articleId: articleId,
  );

  SearchResult hit({
    required String title,
    required String snippet,
    required String url,
    int rank = 0,
  }) => SearchResult(
    sourceId: searchResultSourceId(
      provider: SearchProtocol.tavily.id,
      rank: rank,
    ),
    title: title,
    url: url,
    snippet: snippet,
    provider: SearchProtocol.tavily.id,
    accessCategory: SearchAccessCategory.news,
  );

  group('关键词提取与相似度（启发式，随标签记录）', () {
    test('中文按字符二元组切，英文按词切并丢停用词', () {
      final List<String> keywords = extractClaimKeywords('央行 the rate cut 降息');
      expect(keywords, contains('央行'));
      expect(keywords, contains('降息'));
      expect(keywords, contains('rate'));
      expect(keywords, isNot(contains('the')));
    });

    test('重叠度以条目关键词数为分母', () {
      final NewsClaim claim = NewsClaim.of('央行 降息');
      expect(
        claimOverlap(claimKeywords: claim.keywords, candidateText: '央行'),
        greaterThan(0),
      );
      expect(
        claimOverlap(claimKeywords: claim.keywords, candidateText: '完全无关的内容'),
        0,
      );
    });

    test('无关键词时重叠度为 0（不因除以零而抛错）', () {
      expect(
        claimOverlap(claimKeywords: const <String>[], candidateText: 'x'),
        0,
      );
    });

    test('标题相似度：同一稿件加前后缀仍接近 1，不同稿件明显更低', () {
      expect(
        titleSimilarity('央行今日宣布降息', '独家：央行今日宣布降息（组图）'),
        greaterThan(kNewsSyndicationTitleThreshold),
      );
      expect(
        titleSimilarity('央行今日宣布降息', '台风将于明日登陆东南沿海'),
        lessThan(kNewsSyndicationTitleThreshold),
      );
    });
  });

  group('独立来源判定', () {
    test('第二条来源重叠度达标 → 支持（不产生标签）', () {
      final NewsItemVerification result = verifyNewsItem(
        item: item(),
        candidates: <NewsEvidenceCandidate>[
          const NewsEvidenceCandidate(
            title: '央行宣布降息二十五个基点',
            text: '央行今日宣布降息二十五个基点，为年内第二次。',
            url: 'https://other.example.com/a',
          ),
        ],
      );
      expect(result.outcome, VerificationOutcome.supported);
      expect(result.labels, isEmpty);
      expect(result.hasIndependentCorroboration, isTrue);
      expect(result.independentSourceCount, 2);
    });

    test('只有检索结果与条目无关 → 材料不足', () {
      final NewsItemVerification result = verifyNewsItem(
        item: item(),
        candidates: <NewsEvidenceCandidate>[
          const NewsEvidenceCandidate(
            title: '台风将于明日登陆东南沿海',
            text: '气象台发布台风预警。',
            url: 'https://other.example.com/b',
          ),
        ],
      );
      expect(result.outcome, VerificationOutcome.insufficientMaterial);
      expect(result.labels, <NewsEvidenceLabel>[
        NewsEvidenceLabel.insufficientMaterial,
      ]);
    });

    test('没有任何候选 → 材料不足（区别于「未联网核验」）', () {
      final NewsItemVerification result = verifyNewsItem(
        item: item(),
        candidates: const <NewsEvidenceCandidate>[],
      );
      expect(result.outcome, VerificationOutcome.insufficientMaterial);
      expect(result.independentSourceCount, 1, reason: '仍有条目自己那一条来源');
    });

    test('没有配置搜索服务 → 未联网核验（不发任何查询）', () {
      final NewsItemVerification result = verifyNewsItem(
        item: item(),
        candidates: const <NewsEvidenceCandidate>[],
        searchConfigured: false,
      );
      expect(result.outcome, VerificationOutcome.notVerifiedOnline);
      expect(result.labels, <NewsEvidenceLabel>[
        NewsEvidenceLabel.notVerifiedOnline,
      ]);
    });
  });

  group('冲突：保守标记（无法确定绝不标冲突）', () {
    test('第二条来源明确否认同一事实 → 来源冲突', () {
      final NewsItemVerification result = verifyNewsItem(
        item: item(),
        candidates: <NewsEvidenceCandidate>[
          const NewsEvidenceCandidate(
            title: '央行否认降息传闻',
            text: '央行今日表示，关于降息的报道不属实。',
            url: 'https://other.example.com/c',
          ),
        ],
      );
      expect(result.outcome, VerificationOutcome.conflict);
      expect(result.labels, <NewsEvidenceLabel>[
        NewsEvidenceLabel.sourceConflict,
      ]);
    });

    test('否定词与陈述关键词无关时不判冲突（同段里的无关否定）', () {
      final NewsItemVerification result = verifyNewsItem(
        item: item(),
        candidates: <NewsEvidenceCandidate>[
          const NewsEvidenceCandidate(
            title: '央行今日宣布降息二十五个基点',
            text: '另据报道，某地一处工地事故的谣言已被否认。央行降息二十五个基点。',
            url: 'https://other.example.com/d',
          ),
        ],
      );
      expect(
        result.outcome,
        VerificationOutcome.supported,
        reason: '不相关的否定不得把一条支持性来源判成矛盾',
      );
    });

    test('「否认传闻并确认 X」这类确认性报道不被误判为冲突', () {
      // 这是真实的新闻写法：先否认传闻，再给出确认的事实。判据要求否定词附近出现**陈述的**
      // 关键词，而这里关键词紧跟的是确认语句。
      final NewsItemVerification result = verifyNewsItem(
        item: item(text: '某公司将裁员的传闻不属实，公司今日确认将扩招。'),
        candidates: <NewsEvidenceCandidate>[
          const NewsEvidenceCandidate(
            title: '公司确认扩招',
            text: '某公司今日确认将扩招，此前关于裁员的传闻不属实。',
            url: 'https://other.example.com/e',
          ),
        ],
      );
      expect(
        result.outcome,
        isNot(VerificationOutcome.conflict),
        reason: '保守方向：拿不准就不标冲突',
      );
    });
  });

  group('转载聚类（架构 4.4「转载同一稿件不能算两个证据」）', () {
    test('同稿多 URL（跟踪参数不同）聚成一簇', () {
      final List<NewsSourceCluster> clusters = clusterSyndicatedSources(
        <NewsEvidenceCandidate>[
          const NewsEvidenceCandidate(
            title: '央行宣布降息',
            text: '',
            url: 'https://a.example.com/news/1?utm_source=x',
          ),
          const NewsEvidenceCandidate(
            title: '央行宣布降息',
            text: '',
            url: 'https://a.example.com/news/1',
          ),
        ],
      );
      expect(clusters, hasLength(1));
      expect(clusters.single.members, hasLength(2));
    });

    test('不同站的同一稿件（标题高度相似）聚成一簇', () {
      final List<NewsSourceCluster> clusters = clusterSyndicatedSources(
        <NewsEvidenceCandidate>[
          const NewsEvidenceCandidate(
            title: '央行今日宣布降息二十五个基点',
            text: '',
            url: 'https://a.example.com/news/1',
          ),
          const NewsEvidenceCandidate(
            title: '央行今日宣布降息二十五个基点（转载）',
            text: '',
            url: 'https://b.example.com/x',
          ),
        ],
      );
      expect(clusters, hasLength(1));
    });

    test('同一事件的两家不同报道**不**合并（不同事实应算两条来源）', () {
      final List<NewsSourceCluster> clusters = clusterSyndicatedSources(
        <NewsEvidenceCandidate>[
          const NewsEvidenceCandidate(
            title: '央行宣布降息二十五个基点',
            text: '',
            url: 'https://a.example.com/news/1',
          ),
          const NewsEvidenceCandidate(
            title: '经济学家对本次降息的分歧解读',
            text: '',
            url: 'https://b.example.com/x',
          ),
        ],
      );
      expect(clusters, hasLength(2));
    });

    test('同域不同稿件不合并（不按域名聚类）', () {
      final List<NewsSourceCluster> clusters = clusterSyndicatedSources(
        <NewsEvidenceCandidate>[
          const NewsEvidenceCandidate(
            title: '央行宣布降息',
            text: '',
            url: 'https://a.example.com/news/1',
          ),
          const NewsEvidenceCandidate(
            title: '台风即将登陆',
            text: '',
            url: 'https://a.example.com/news/2',
          ),
        ],
      );
      expect(clusters, hasLength(2));
    });
  });

  group('引用字段完整性（架构 4.4）', () {
    test('完整引用带 URL / 时间 / 最小摘录与获取方式', () {
      final NewsVerifiedCitation citation = buildVerifiedCitation(
        material(
          publishedAt: DateTime.utc(2026, 9, 22, 2),
          accessMethod: CitationAccessMethod.fetch,
          articleId: 7,
        ),
      );
      expect(citation.complete, isTrue);
      expect(citation.accessMethod, CitationAccessMethod.fetch);
      expect(citation.url, isNotEmpty);
      expect(citation.excerpt, isNotEmpty);
      expect(citation.publishedAt, DateTime.utc(2026, 9, 22, 2));
      expect(citation.materialHash, 'hash-rss.1');
      expect(citation.articleId, 7);
    });

    test('只有访问时刻也算有时间（RSS 常没有发布时间）', () {
      final NewsVerifiedCitation citation = buildVerifiedCitation(
        material(accessedAt: DateTime.utc(2026, 9, 22, 13)),
      );
      expect(citation.complete, isTrue);
    });

    test('缺地址/时间/摘录的引用被标出缺哪几项', () {
      expect(
        citationIssueOf(material(url: '  ', accessedAt: DateTime.utc(2026)))!
            .missingFields,
        <String>['url'],
      );
      expect(citationIssueOf(material(excerpt: ''))!.missingFields, <String>[
        'time',
        'excerpt',
      ]);
      expect(citationIssueOf(material(accessedAt: DateTime.utc(2026))), isNull);
    });

    test('摘录长度受上限约束（最小摘录，不为引用长期保留整篇）', () {
      final NewsVerifiedCitation citation = buildVerifiedCitation(
        material(excerpt: '字' * 1000, accessedAt: DateTime.utc(2026)),
        excerptLimit: 50,
      );
      expect(citation.excerpt.length, 50);
    });

    test('resolveNewsCitations：未知引用被列出而不是静默丢弃', () {
      final NewsCitationResolution resolution = resolveNewsCitations(
        items: <NewsDraftItem>[
          item(sourceIds: <String>['rss.1', 'rss.404']),
        ],
        materials: <NewsMaterial>[material()],
      );
      expect(
        resolution.citations.map((NewsVerifiedCitation c) => c.sourceId),
        <String>['rss.1'],
      );
      expect(resolution.unknown, <String>['rss.404']);
      expect(resolution.hasUnknown, isTrue);
    });

    test('同一材料被多条条目引用时只出现一次', () {
      final NewsCitationResolution resolution = resolveNewsCitations(
        items: <NewsDraftItem>[item(index: 1), item(index: 2)],
        materials: <NewsMaterial>[material(accessedAt: DateTime.utc(2026))],
      );
      expect(resolution.citations, hasLength(1));
    });
  });

  group('核验编排：查询派生、禁词与预算', () {
    test('每条条目发一个派生查询，并把结论写回条目', () async {
      final NewsVerificationOutcome outcome = await service().verify(
        items: <NewsDraftItem>[item()],
        materials: <NewsMaterial>[material()],
        blockedQueryTerms: const <String>[],
        searchConfigured: true,
      );
      expect(searchFactory.queries, hasLength(1));
      expect(outcome.verifiedItemCount, 1);
      expect(outcome.method.usedSearch, isTrue);
      expect(outcome.method.searchProvider, SearchProtocol.tavily.id);
      expect(outcome.items.single.verificationNote, isNotNull);
    });

    test('检索结果与条目无关 → 标「材料不足」，条目照常保留', () async {
      searchFactory.resultsByQuery = <String, List<SearchResult>>{};
      final String query = NewsClaim.of('央行今日宣布降息二十五个基点。').query;
      searchFactory.resultsByQuery[query] = <SearchResult>[
        hit(
          title: '台风将于明日登陆',
          snippet: '气象台发布预警。',
          url: 'https://other.example.com/t',
        ),
      ];
      final NewsVerificationOutcome outcome = await service().verify(
        items: <NewsDraftItem>[item()],
        materials: <NewsMaterial>[material()],
        blockedQueryTerms: const <String>[],
        searchConfigured: true,
      );
      expect(outcome.items.single.labels, <NewsEvidenceLabel>[
        NewsEvidenceLabel.insufficientMaterial,
      ]);
      expect(outcome.items.single.kept, isTrue, reason: '核验结论不改变条目是否保留');
      expect(outcome.insufficientItemCount, 1);
    });

    test('支持性来源 → 不产生标签，且独立来源数增加', () async {
      final String query = NewsClaim.of('央行今日宣布降息二十五个基点。').query;
      searchFactory.resultsByQuery[query] = <SearchResult>[
        hit(
          title: '央行宣布降息二十五个基点',
          snippet: '央行今日宣布降息二十五个基点，为年内第二次。',
          url: 'https://other.example.com/a',
        ),
      ];
      final NewsVerificationOutcome outcome = await service().verify(
        items: <NewsDraftItem>[item()],
        materials: <NewsMaterial>[material()],
        blockedQueryTerms: const <String>[],
        searchConfigured: true,
      );
      expect(outcome.items.single.labels, isEmpty);
      expect(outcome.items.single.independentSourceCount, 2);
    });

    test('搜索结果就是条目自己引用的同一篇稿件 → 不算第二条独立来源', () async {
      final String query = NewsClaim.of('央行今日宣布降息二十五个基点。').query;
      // 同 URL（带跟踪参数）：这是转载/同页，绝不能算成第二份证据。
      searchFactory.resultsByQuery[query] = <SearchResult>[
        hit(
          title: '央行宣布降息',
          snippet: '央行今日宣布降息二十五个基点。',
          url: 'https://a.example.com/news/1?utm_source=share',
        ),
      ];
      final NewsVerificationOutcome outcome = await service().verify(
        items: <NewsDraftItem>[item()],
        materials: <NewsMaterial>[material()],
        blockedQueryTerms: const <String>[],
        searchConfigured: true,
      );
      expect(
        outcome.items.single.labels,
        contains(NewsEvidenceLabel.insufficientMaterial),
        reason: '同一稿件的另一条 URL 不是独立来源',
      );
    });

    test('派生查询命中禁词时不发查询，并标「材料不足」', () async {
      final NewsVerificationOutcome outcome = await service().verify(
        items: <NewsDraftItem>[item(text: '股市今日大幅波动，多家公司股价下挫。')],
        materials: <NewsMaterial>[material()],
        blockedQueryTerms: const <String>['股市'],
        searchConfigured: true,
      );
      expect(searchFactory.queries, isEmpty);
      expect(outcome.method.queriesIssued, 0);
      expect(outcome.items.single.labels, <NewsEvidenceLabel>[
        NewsEvidenceLabel.insufficientMaterial,
      ]);
    });

    test('没有配置搜索服务时一个查询都不发，全部标「未联网核验」', () async {
      final NewsVerificationOutcome outcome = await service().verify(
        items: <NewsDraftItem>[item(), item(index: 2)],
        materials: <NewsMaterial>[material()],
        blockedQueryTerms: const <String>[],
        searchConfigured: false,
      );
      expect(searchFactory.queries, isEmpty);
      expect(outcome.method.usedSearch, isFalse);
      expect(
        outcome.items.every(
          (NewsDraftItem i) =>
              i.labels.contains(NewsEvidenceLabel.notVerifiedOnline),
        ),
        isTrue,
      );
    });

    test('检索失败时如实标「材料不足」并记录失败，条目不被丢弃', () async {
      searchFactory.failWith = NetworkError(
        uri: 'https://api.example.com',
        reason: '连接失败',
      );
      final NewsVerificationOutcome outcome = await service().verify(
        items: <NewsDraftItem>[item()],
        materials: <NewsMaterial>[material()],
        blockedQueryTerms: const <String>[],
        searchConfigured: true,
      );
      expect(outcome.failed, isTrue);
      expect(outcome.error, isA<NetworkError>());
      expect(outcome.items.single.kept, isTrue);
      expect(outcome.insufficientItemCount, 1);
    });

    test('核验条数受预算限制（超出的条目保持未核验）', () async {
      final NewsVerificationService limited = NewsVerificationService(
        buildTools: buildTools,
        diagnostics: DiagnosticLogSink(diagnostics),
        budget: const NewsVerificationBudget(
          maxItemsVerified: 1,
          maxQueries: 1,
        ),
      );
      final NewsVerificationOutcome outcome = await limited.verify(
        items: <NewsDraftItem>[item(index: 1), item(index: 2)],
        materials: <NewsMaterial>[material()],
        blockedQueryTerms: const <String>[],
        searchConfigured: true,
      );
      expect(searchFactory.queries, hasLength(1));
      expect(outcome.verifiedItemCount, 1);
      expect(outcome.items, hasLength(2));
      expect(outcome.items.last.labels, isEmpty, reason: '未核验的条目不补标签（不假装核验过）');
    });

    test('诊断不记录条目正文与查询词（架构第 8 节）', () async {
      final String query = NewsClaim.of('机密陈述：某公司要被收购。').query;
      searchFactory.resultsByQuery[query] = <SearchResult>[
        hit(
          title: '机密的搜索结果标题',
          snippet: '机密片段内容',
          url: 'https://secret.example.com/x',
        ),
      ];
      await service().verify(
        items: <NewsDraftItem>[item(text: '机密陈述：某公司要被收购。')],
        materials: <NewsMaterial>[material()],
        blockedQueryTerms: const <String>[],
        searchConfigured: true,
      );
      final String log = diagnostics.entries.map((e) => e.message).join('\n');
      expect(log, isNot(contains('机密陈述')));
      expect(log, isNot(contains('机密的搜索结果标题')));
      expect(log, isNot(contains('secret.example.com')));
    });
  });

  group('端到端：核验后追加版本，失败保留上一版', () {
    NewsRunService buildRunService({
      required ScriptedAiFactory factory,
      ToolExecutor Function()? tools,
    }) => NewsRunService(
      candidates: candidateStore,
      runs: runStore,
      buildTools: tools ?? buildTools,
      runner: AiTaskRunner(
        credentials: const AlwaysCredentialStore(),
        factory: factory,
        diagnostics: DiagnosticLogSink(diagnostics),
        budget: const AiTaskBudget(),
        clock: clock,
        delayScheduler: AdvancingDelayScheduler(clock),
      ),
      loadModels: () async => const Ok<List<AiModel>>(<AiModel>[model]),
      searchAvailability: _AlwaysConfigured(),
      diagnostics: DiagnosticLogSink(diagnostics),
      clock: clock,
      zone: shanghai,
    );

    test('核验与初稿各留一个版本，最终版本带证据标签与方法记录', () async {
      candidateStore.rows = <NewsCandidateArticle>[
        NewsCandidateArticle(
          articleId: 1,
          feedId: 1,
          feedName: '源 A',
          title: '央行宣布降息',
          summary: '央行今日宣布降息二十五个基点。',
          fetchedAt: DateTime.utc(2026, 9, 22, 3),
          sourceUrl: 'https://a.example.com/news/1',
          publishedAt: DateTime.utc(2026, 9, 22, 2),
        ),
      ];
      final String query = NewsClaim.of('央行今日宣布降息二十五个基点。').query;
      searchFactory.resultsByQuery[query] = <SearchResult>[
        hit(
          title: '央行宣布降息二十五个基点',
          snippet: '央行今日宣布降息二十五个基点，为年内第二次。',
          url: 'https://other.example.com/a',
        ),
      ];
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'deepseek': <AiAttemptScript>[
            const ScriptSuccess(deltas: <String>['央行今日宣布降息二十五个基点。[rss.1]']),
          ],
        },
        scriptClock: clock,
      );
      final NewsRunOutcome outcome = await buildRunService(factory: factory)
          .run(
            NewsRunInput(
              taskId: 'news-1',
              config: NewsConfigState.initial(),
              globalEnabled: true,
            ),
          );
      expect(outcome.ok, isTrue);
      expect(outcome.record!.version, 2, reason: '初稿 v1、核验后 v2');
      expect(outcome.record!.isCurrent, isTrue);
      expect(outcome.record!.verificationMethod, contains('search=yes'));
      expect(outcome.record!.items.single.labels, isEmpty);
      expect(outcome.record!.items.single.independentSourceCount, 2);

      final List<NewsRunRecord> versions = (await runStore.loadVersions(
        localDate: '2026-09-22',
        timeZone: 'Asia/Shanghai',
      )).valueOrNull!;
      expect(versions, hasLength(2));
      expect(versions.first.items.single.labels, isEmpty);
      expect(
        versions.last.items.single.labels,
        isEmpty,
        reason: '初稿版本不带标签（那一次没核验）',
      );
      expect(versions.where((NewsRunRecord r) => r.isCurrent), hasLength(1));
    });

    test('核验失败时初稿版本仍是当前版本（保留上一次成功总结）', () async {
      candidateStore.rows = <NewsCandidateArticle>[
        NewsCandidateArticle(
          articleId: 1,
          feedId: 1,
          feedName: '源 A',
          title: '某事件',
          summary: '某事件发生。',
          fetchedAt: DateTime.utc(2026, 9, 22, 3),
          sourceUrl: 'https://a.example.com/news/1',
          publishedAt: DateTime.utc(2026, 9, 22, 2),
        ),
      ];
      // 核验的检索全部失败：核验阶段无法给出结论。
      final FakeSearchFactory failing = FakeSearchFactory()
        ..failWith = NetworkError(
          uri: 'https://api.example.com',
          reason: '连接失败',
        );
      ToolExecutor tools() => ToolExecutor(
        budget: ToolCallBudget(limit: 30),
        config: const ToolExecutorConfig(),
        searchManager: SearchManager(
          store: serviceStore,
          credentials: credentials,
          diagnostics: DiagnosticLogSink(diagnostics),
          factory: failing,
        ),
        pageFetcher: pageFetcher,
        imageInspector: imageInspector,
        diagnostics: DiagnosticLogSink(diagnostics),
      );
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'deepseek': <AiAttemptScript>[
            const ScriptSuccess(deltas: <String>['某事件发生。[rss.1]']),
          ],
        },
        scriptClock: clock,
      );
      final NewsRunOutcome outcome =
          await buildRunService(factory: factory, tools: tools).run(
            NewsRunInput(
              taskId: 'news-1',
              config: NewsConfigState.initial(),
              globalEnabled: true,
            ),
          );
      expect(outcome.status, TaskStatus.partial, reason: '核验失败 → 部分结果');
      expect(outcome.record!.items.single.labels, <NewsEvidenceLabel>[
        NewsEvidenceLabel.insufficientMaterial,
      ]);
      final NewsRunRecord current = (await runStore.loadCurrent(
        localDate: '2026-09-22',
        timeZone: 'Asia/Shanghai',
      )).valueOrNull!;
      expect(current.isCurrent, isTrue);
      expect(current.items.single.kept, isTrue, reason: '核验失败不得丢掉条目');
    });

    test('出现来源冲突时状态为 partial（不声称完整成功）', () async {
      candidateStore.rows = <NewsCandidateArticle>[
        NewsCandidateArticle(
          articleId: 1,
          feedId: 1,
          feedName: '源 A',
          title: '央行宣布降息',
          summary: '央行今日宣布降息二十五个基点。',
          fetchedAt: DateTime.utc(2026, 9, 22, 3),
          sourceUrl: 'https://a.example.com/news/1',
          publishedAt: DateTime.utc(2026, 9, 22, 2),
        ),
      ];
      final String query = NewsClaim.of('央行今日宣布降息二十五个基点。').query;
      searchFactory.resultsByQuery[query] = <SearchResult>[
        hit(
          title: '央行否认降息传闻',
          snippet: '央行表示关于降息二十五个基点的报道不属实。',
          url: 'https://other.example.com/c',
        ),
      ];
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'deepseek': <AiAttemptScript>[
            const ScriptSuccess(deltas: <String>['央行今日宣布降息二十五个基点。[rss.1]']),
          ],
        },
        scriptClock: clock,
      );
      final NewsRunOutcome outcome = await buildRunService(factory: factory)
          .run(
            NewsRunInput(
              taskId: 'news-1',
              config: NewsConfigState.initial(),
              globalEnabled: true,
            ),
          );
      expect(outcome.status, TaskStatus.partial);
      expect(outcome.record!.items.single.labels, <NewsEvidenceLabel>[
        NewsEvidenceLabel.sourceConflict,
      ]);
    });
  });
}

/// 检索可用性替身（始终「有配置」）。
final class _AlwaysConfigured implements NewsSearchAvailability {
  @override
  Future<Result<bool>> hasEnabledService() async => const Ok<bool>(true);
}
