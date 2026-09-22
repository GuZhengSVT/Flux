// T039：今日页端到端（日期切换查询、版本列表/删除、六阶段推进、逐站进度、取消落 cancelled）。
//
// 用真实控制器 + 内存端口 + 假时钟，因此断言的是「界面拿到的状态」而不是「调用了哪个方法」。
// 模型与抓取全部为脚本化替身，**不发任何真实请求**。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/application/ai_task_budget.dart';
import 'package:flux/features/ai/application/ai_task_providers.dart';
import 'package:flux/features/ai/application/ai_task_runner.dart';
import 'package:flux/features/ai/application/model_manager.dart'
    show SettingsReader;
import 'package:flux/features/ai/application/search_manager.dart';
import 'package:flux/features/ai/application/tool_executor.dart';
import 'package:flux/features/ai/domain/ai_model.dart';
import 'package:flux/features/ai/domain/ai_protocol.dart';
import 'package:flux/features/ai/domain/tool_call.dart';
import 'package:flux/features/articles/application/article_ai_providers.dart'
    show summaryZoneProvider;
import 'package:flux/features/articles/application/article_ports.dart'
    show articleCatalogProvider;
import 'package:flux/features/ai/application/tool_ports.dart'
    show ControlledPageFetcher, FetchedPage;
import 'package:flux/features/news/application/news_run_providers.dart';
import 'package:flux/features/news/application/news_run_service.dart';
import 'package:flux/features/news/application/news_source_providers.dart';
import 'package:flux/features/news/application/news_today_controller.dart';
import 'package:flux/features/settings/application/settings_controller.dart'
    show settingsStoreProvider;
import 'package:flux/features/settings/application/settings_store.dart';
import 'package:flux/infrastructure/local/diagnostics.dart';
import 'package:flux/infrastructure/local/feed_store_adapter.dart'
    show DiagnosticLogSink;

import '../ai/ai_runner_support.dart';
import '../ai/tool_support.dart';
import 'news_run_test.dart'
    show FakeCandidateStore, FakeSearchAvailability, MemoryNewsRunStore;

/// 上海时区（固定 +8）。
const SessionLocalZone shanghai = FixedOffsetZone(
  Duration(hours: 8),
  ianaName: 'Asia/Shanghai',
);

/// 只读设置端口替身（费用确认要读 SET-060 的上限）。
final class _FakeSettingsReader implements SettingsReader {
  @override
  Future<Result<Object?>> readSetting(SettingId id) async =>
      Ok<Object?>(SettingRegistry.findById(id)?.defaultValue);
}

/// 必访站抓取全部成功的替身。
final class _CountingFetcher implements ControlledPageFetcher {
  _CountingFetcher({this.failing = const <String>{}});

  /// 这些地址按失败返回（逐站失败可见的验证）。
  final Set<String> failing;
  int calls = 0;

  @override
  Future<Result<FetchedPage>> fetch(Uri uri) async {
    calls++;
    if (failing.contains(uri.toString())) {
      return Err<FetchedPage>(
        NetworkError(uri: uri.toString(), reason: 'stub-failure'),
      );
    }
    return Ok<FetchedPage>(
      FetchedPage(
        finalUri: uri.toString(),
        title: uri.host,
        text: '页面正文',
        imageUrls: const <String>[],
        outcome: 'ok',
      ),
    );
  }
}

/// 引用正文探测用的文章端口替身：只回答「这篇文章存在吗、正文在不在」。
final class _BodyProbeCatalog implements ArticleCatalogStore {
  /// 文章 id → 正文（null 表示正文已被清理）。
  final Map<int, String?> bodies = <int, String?>{};

  /// 文章 id → 正文完整性。
  final Map<int, BodyCompleteness> completeness = <int, BodyCompleteness>{};

  @override
  Future<Result<ArticleListEntry?>> findArticle(int articleId) async {
    final String? body = bodies[articleId];
    if (body == null && !bodies.containsKey(articleId)) {
      return const Ok<ArticleListEntry?>(null);
    }
    return Ok<ArticleListEntry?>(
      ArticleListEntry(
        id: articleId,
        feedId: 1,
        feedName: '测试源',
        title: '本机文章',
        readingState: ReadingState.unread,
        favorite: false,
        publishedAt: DateTime.utc(2026, 9, 22, 12),
        fetchedAt: DateTime.utc(2026, 9, 22, 12),
        bodyCompleteness:
            completeness[articleId] ?? BodyCompleteness.sourceBody,
      ),
    );
  }

  @override
  Future<Result<String?>> readArticleBody(int articleId) async =>
      Ok<String?>(bodies[articleId]);

  // 其余方法在本用例里不涉及；抛错以免被误当成「返回空」而静默通过。
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} 未在替身里实现');
}

/// 设置端口替身：读回注册表默认值（本用例只关心上限与语言默认值）。
final class _FakeSettingsStore implements SettingsStore {
  @override
  Future<Result<Object?>> readSetting(SettingId id) async =>
      Ok<Object?>(SettingRegistry.findById(id)?.defaultValue);

  @override
  Future<Result<Object?>> writeSetting(SettingId id, Object? value) async =>
      Ok<Object?>(value);

  @override
  Future<Result<Map<String, Object?>>> readEffectiveSettings() async =>
      const Ok<Map<String, Object?>>(<String, Object?>{});
}

/// 站点配置存储替身（只提供必访站，其余类别为空）。
final class _FakeSourceConfigStore implements NewsSourceConfigStore {
  _FakeSourceConfigStore(this.sites);

  final List<NewsRequiredSite> sites;

  @override
  Future<Result<List<NewsRequiredSite>>> loadRequiredSites() async =>
      Ok<List<NewsRequiredSite>>(sites);

  @override
  Future<Result<void>> replaceRequiredSites(
    List<NewsRequiredSite> value,
  ) async => okUnit();

  @override
  Future<Result<List<String>>> loadList(String kind) async =>
      const Ok<List<String>>(<String>[]);

  @override
  Future<Result<void>> replaceList(String kind, List<String> values) async =>
      okUnit();

  @override
  Future<Result<List<NewsPromptVersion>>> loadPromptVersions(
    String language,
  ) async => const Ok<List<NewsPromptVersion>>(<NewsPromptVersion>[]);

  @override
  Future<Result<NewsPromptVersion>> savePromptVersion(
    NewsPromptVersion version,
  ) async => Ok<NewsPromptVersion>(version);

  @override
  Future<Result<void>> deletePromptVersion({
    required String language,
    required int version,
  }) async => okUnit();
}

void main() {
  late FakeClock clock;
  late MemoryNewsRunStore runStore;
  late FakeCandidateStore candidateStore;
  late FakeSearchAvailability availability;

  setUp(() {
    clock = FakeClock(start: DateTime.utc(2026, 9, 22, 13));
    runStore = MemoryNewsRunStore();
    candidateStore = FakeCandidateStore();
    availability = FakeSearchAvailability(available: false);
  });

  /// 造一个容器，可注入必访站与模型剧本。
  ProviderContainer container({
    List<NewsRequiredSite> sites = const <NewsRequiredSite>[],
    List<AiAttemptScript>? scripts,
    _CountingFetcher? fetcher,
  }) {
    final DiagnosticLog diagnostics = DiagnosticLog(
      level: DiagnosticLevel.error,
    );
    final _CountingFetcher pageFetcher = fetcher ?? _CountingFetcher();
    final ScriptedAiFactory factory = ScriptedAiFactory(
      <String, List<AiAttemptScript>>{
        'deepseek':
            scripts ??
            <AiAttemptScript>[
              const ScriptSuccess(deltas: <String>['[rss.1] 某地发生某事。']),
            ],
      },
      scriptClock: clock,
    );
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        aiTaskClockProvider.overrideWithValue(clock),
        settingsStoreProvider.overrideWithValue(_FakeSettingsStore()),
        summaryZoneProvider.overrideWithValue(shanghai),
        newsRunStoreProvider.overrideWithValue(runStore),
        newsCandidateStoreProvider.overrideWithValue(candidateStore),
        newsSearchAvailabilityProvider.overrideWithValue(availability),
        newsSourceConfigProvider.overrideWithValue(
          _FakeSourceConfigStore(sites),
        ),
        newsSettingsReaderProvider.overrideWithValue(_FakeSettingsReader()),
        articleCatalogProvider.overrideWithValue(_BodyProbeCatalog()),
        newsRunServiceBuilderProvider.overrideWith(
          (Ref ref) =>
              ({
                required SessionLocalZone zone,
                void Function(NewsRunStage stage)? onStage,
                void Function(NewsSiteFetchResult result)? onSiteResult,
              }) async => NewsRunService(
                candidates: candidateStore,
                runs: runStore,
                buildTools: () => ToolExecutor(
                  budget: ToolCallBudget(limit: 30),
                  config: const ToolExecutorConfig(),
                  searchManager: SearchManager(
                    store: FakeSearchServiceStore(),
                    credentials: FakeSearchCredentials(),
                    diagnostics: DiagnosticLogSink(diagnostics),
                    factory: RecordingSearchFactory(),
                  ),
                  pageFetcher: pageFetcher,
                  imageInspector: FakeImageInspector(),
                  diagnostics: DiagnosticLogSink(diagnostics),
                ),
                runner: AiTaskRunner(
                  credentials: const AlwaysCredentialStore(),
                  factory: factory,
                  diagnostics: DiagnosticLogSink(diagnostics),
                  budget: const AiTaskBudget(),
                  clock: clock,
                  delayScheduler: AdvancingDelayScheduler(clock),
                ),
                loadModels: () async => const Ok<List<AiModel>>(<AiModel>[
                  AiModel(
                    alias: 'deepseek',
                    protocol: AiProtocol.openAiChatCompletions,
                    baseUrl: 'https://api.example.com',
                    modelId: 'deepseek-chat',
                  ),
                ]),
                searchAvailability: availability,
                diagnostics: DiagnosticLogSink(diagnostics),
                clock: clock,
                zone: zone,
                onStage: onStage,
                onSiteResult: onSiteResult,
                verifyCitations: false,
              ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('日期切换', () {
    test('按 (日期, 时区) 查询；「今天」不随翻页移动', () async {
      final ProviderContainer c = container();
      final NewsTodayController controller = c.read(
        newsTodayControllerProvider.notifier,
      );
      final NewsTodayState initial = await c.read(
        newsTodayControllerProvider.future,
      );
      expect(initial.localDate, '2026-09-22');
      expect(initial.today, '2026-09-22');
      expect(initial.recentDates.length, 7);

      await controller.selectDate('2026-09-01');
      final NewsTodayState shifted = c.read(newsTodayControllerProvider).value!;
      expect(shifted.localDate, '2026-09-01');
      expect(shifted.today, '2026-09-22', reason: '翻页不改变「今天」');
      expect(shifted.isToday, isFalse);
      expect(shifted.current, isNull);
    });

    test('历史日期按当时的时区查得旧记录（不因现在时区而查不到）', () async {
      // 一条在 UTC+8 生成、归属 2026-09-01 的记录。
      await runStore.append(
        NewsRunRecord(
          localDate: '2026-09-01',
          timeZone: 'Asia/Shanghai',
          version: 1,
          status: TaskStatus.succeeded,
          snapshot: _snapshot(localDate: '2026-09-01'),
          siteResults: const <NewsSiteFetchResult>[],
          materials: const <NewsMaterial>[],
          items: const <NewsDraftItem>[
            NewsDraftItem(
              index: 1,
              text: '九月初的旧条目。',
              sourceIds: <String>[],
              status: NewsItemStatus.kept,
            ),
          ],
          createdAt: DateTime.utc(2026, 9, 1, 13),
          isCurrent: true,
        ),
      );
      final ProviderContainer c = container();
      await c.read(newsTodayControllerProvider.future);
      await c
          .read(newsTodayControllerProvider.notifier)
          .selectDate('2026-09-01');
      final NewsTodayState state = c.read(newsTodayControllerProvider).value!;
      expect(state.current!.version, 1);
      expect(state.current!.timeZone, 'Asia/Shanghai');
      expect(state.activeTimeZone, 'Asia/Shanghai');
    });
  });

  group('版本管理', () {
    test('版本列表含初稿与核验后；删除非当前版本成功', () async {
      await runStore.append(_draft(version: 1, current: false));
      await runStore.append(_draft(version: 2, current: true));
      final ProviderContainer c = container();
      await c.read(newsTodayControllerProvider.future);
      NewsTodayState state = c.read(newsTodayControllerProvider).value!;
      expect(state.versions.length, 2);
      expect(state.hasMultipleVersions, isTrue);

      final Result<void> deleted = await c
          .read(newsTodayControllerProvider.notifier)
          .deleteVersion(1);
      expect(deleted.isOk, isTrue);
      state = c.read(newsTodayControllerProvider).value!;
      expect(state.versions.length, 1);
      expect(state.versions.single.version, 2);
    });

    test('删除当前版本被拒，库内不变', () async {
      await runStore.append(_draft(version: 1, current: true));
      final ProviderContainer c = container();
      await c.read(newsTodayControllerProvider.future);
      final Result<void> deleted = await c
          .read(newsTodayControllerProvider.notifier)
          .deleteVersion(1);
      expect(deleted.isErr, isTrue);
      expect(deleted.errorOrNull!.kind, 'validation');
      final NewsTodayState state = c.read(newsTodayControllerProvider).value!;
      expect(state.versions.length, 1);
      expect(state.current, isNotNull);
    });

    test('切换版本后当前版本随之改变', () async {
      await runStore.append(_draft(version: 1, current: false));
      await runStore.append(_draft(version: 2, current: true));
      final ProviderContainer c = container();
      await c.read(newsTodayControllerProvider.future);
      await c.read(newsTodayControllerProvider.notifier).selectVersion(1);
      final NewsTodayState state = c.read(newsTodayControllerProvider).value!;
      expect(state.current!.version, 1);
      expect(state.versions.where((NewsRunRecord r) => r.isCurrent).length, 1);
    });
  });

  group('生成进度（假任务）', () {
    test('六阶段按顺序推进，且必访站逐站结果实时到达', () async {
      candidateStore.rows = <NewsCandidateArticle>[_candidate()];
      final List<NewsRunStage> seen = <NewsRunStage>[];
      final List<String> liveSites = <String>[];
      final ProviderContainer c = container(
        sites: const <NewsRequiredSite>[
          NewsRequiredSite(name: '甲站', url: 'https://a.example.com'),
          NewsRequiredSite(name: '乙站', url: 'https://b.example.com'),
        ],
        fetcher: _CountingFetcher(failing: <String>{'https://b.example.com'}),
      );
      final NewsTodayController controller = c.read(
        newsTodayControllerProvider.notifier,
      );
      await c.read(newsTodayControllerProvider.future);
      // 订阅阶段的写入（顺序即实际执行顺序）。
      c.listen(newsTodayControllerProvider, (
        AsyncValue<NewsTodayState>? _,
        AsyncValue<NewsTodayState> next,
      ) {
        final NewsRunStage? stage = next.value?.stage;
        if (stage != null && (seen.isEmpty || seen.last != stage)) {
          seen.add(stage);
        }
        for (final NewsSiteFetchResult site
            in next.value?.sites ?? const <NewsSiteFetchResult>[]) {
          final String key = '${site.name}:${site.status.name}';
          if (!liveSites.contains(key)) {
            liveSites.add(key);
          }
        }
      });
      final NewsRunOutcome? outcome = await controller.generate();
      expect(outcome, isNotNull);
      expect(outcome!.ok, isTrue, reason: '必访站部分失败仍是 partial（有产出）');
      expect(seen, <NewsRunStage>[
        NewsRunStage.snapshot,
        NewsRunStage.requiredSites,
        NewsRunStage.search,
        NewsRunStage.generate,
        NewsRunStage.save,
      ], reason: '核验关闭时没有 verify 阶段');
      // 逐站：一成功一失败，都进了版本的 siteResults（界面据此显示）。
      final NewsRunRecord record = c
          .read(newsTodayControllerProvider)
          .value!
          .current!;
      expect(record.siteResults.length, 2);
      expect(record.siteResults[0].status, NewsSiteStatus.ok);
      expect(record.siteResults[1].status, NewsSiteStatus.failed);
      expect(record.status, TaskStatus.partial);
      // 逐站结果在**运行中**就到达界面（不只是落库后可读）。
      expect(liveSites, contains('甲站:ok'));
      expect(liveSites, contains('乙站:failed'));
    });

    test('取消落 cancelled，且保留已完成阶段信息', () async {
      candidateStore.rows = <NewsCandidateArticle>[_candidate()];
      // 必访站抓取时取消：任务在 requiredSites 之后就不再继续。
      final ProviderContainer c = container(
        sites: const <NewsRequiredSite>[
          NewsRequiredSite(name: '甲站', url: 'https://a.example.com'),
        ],
      );
      final NewsTodayController controller = c.read(
        newsTodayControllerProvider.notifier,
      );
      await c.read(newsTodayControllerProvider.future);
      // 阶段推进到 generate 前发出取消（用监听器在 snapshot 之后取消）。
      c.listen(newsTodayControllerProvider, (
        AsyncValue<NewsTodayState>? _,
        AsyncValue<NewsTodayState> next,
      ) {
        if (next.value?.stage == NewsRunStage.requiredSites) {
          controller.cancel();
        }
      });
      final NewsRunOutcome? outcome = await controller.generate();
      expect(outcome, isNotNull);
      expect(outcome!.status, TaskStatus.cancelled);
      expect(outcome.stage, isNotNull, reason: '保留中止时所在阶段');
      final NewsTodayState state = c.read(newsTodayControllerProvider).value!;
      expect(state.generating, isFalse);
      expect(state.cancelling, isFalse);
      expect(state.latest!.status, TaskStatus.cancelled);
    });

    test('取消后 cancelling 为真（按钮进入「正在取消」而不是立刻可再点）', () async {
      candidateStore.rows = <NewsCandidateArticle>[_candidate()];
      final ProviderContainer c = container();
      final NewsTodayController controller = c.read(
        newsTodayControllerProvider.notifier,
      );
      await c.read(newsTodayControllerProvider.future);
      final Future<NewsRunOutcome?> running = controller.generate();
      controller.cancel();
      expect(c.read(newsTodayControllerProvider).value!.cancelling, isTrue);
      final NewsRunOutcome? outcome = await running;
      expect(outcome!.status, TaskStatus.cancelled);
      expect(c.read(newsTodayControllerProvider).value!.cancelling, isFalse);
    });
  });

  group('状态矩阵（架构第 7 节的每页状态）', () {
    test('无输入：不生成任何内容，落 failed 且 latest 可读', () async {
      // 无文章、无关键词、无必访站。
      final ProviderContainer c = container();
      final NewsTodayController controller = c.read(
        newsTodayControllerProvider.notifier,
      );
      await c.read(newsTodayControllerProvider.future);
      final NewsRunOutcome? outcome = await controller.generate();
      expect(outcome!.status, TaskStatus.failed);
      expect(outcome.shortfall, isNotNull);
      final NewsTodayState state = c.read(newsTodayControllerProvider).value!;
      expect(state.current, isNull, reason: '失败不产生可用版本');
      expect(state.latest!.errorKind, 'validation');
      expect(state.latest!.stage, NewsRunStage.save);
    });

    test('取消未发起请求时不新增成功版本（失败记录不覆盖已有成功版本）', () async {
      await runStore.append(_draft(version: 1, current: true));
      final ProviderContainer c = container();
      final NewsTodayController controller = c.read(
        newsTodayControllerProvider.notifier,
      );
      await c.read(newsTodayControllerProvider.future);
      final Future<NewsRunOutcome?> running = controller.generate();
      controller.cancel();
      await running;
      final NewsTodayState state = c.read(newsTodayControllerProvider).value!;
      expect(state.current!.version, 1, reason: '上一版成功总结仍在');
      expect(state.versions.length, 2, reason: '取消也留一条记录（如实说明试过）');
      expect(state.latest!.status, TaskStatus.cancelled);
    });
  });
}

NewsRunRecord _draft({required int version, required bool current}) =>
    NewsRunRecord(
      localDate: '2026-09-22',
      timeZone: 'Asia/Shanghai',
      version: version,
      status: TaskStatus.succeeded,
      snapshot: _snapshot(),
      siteResults: const <NewsSiteFetchResult>[],
      materials: const <NewsMaterial>[],
      items: <NewsDraftItem>[
        NewsDraftItem(
          index: 1,
          text: '条目 $version。',
          sourceIds: const <String>[],
          status: NewsItemStatus.kept,
        ),
      ],
      createdAt: DateTime.utc(2026, 9, 22, 13, version),
      isCurrent: current,
      providerAlias: 'deepseek',
      modelId: 'deepseek-chat',
    );

NewsCandidateArticle _candidate() => NewsCandidateArticle(
  articleId: 1,
  feedId: 1,
  feedName: '测试源',
  title: '今天的某件事发生了',
  summary: '摘要正文。',
  fetchedAt: DateTime.utc(2026, 9, 22, 12),
  publishedAt: DateTime.utc(2026, 9, 22, 12),
  sourceUrl: 'https://example.com/1',
);

NewsInputSnapshot _snapshot({String localDate = '2026-09-22'}) =>
    NewsInputSnapshot(
      localDate: localDate,
      deviceTimeZone: 'Asia/Shanghai',
      utcOffsetMinutes: 480,
      dayStartUtc: DateTime.utc(2026, 9, 21, 16),
      dayEndUtc: DateTime.utc(2026, 9, 22, 16),
      frozenAtUtc: DateTime.utc(2026, 9, 22, 13),
      candidates: const <NewsMaterial>[],
      requiredSites: const <NewsRequiredSite>[],
      keywords: const <String>[],
      blockedQueryTerms: const <String>[],
      excludedTopics: const <String>[],
      promptVersionRef: 'zh-Hans#builtin',
      promptText: '任务段',
      maxArticles: 50,
      maxSites: 10,
      maxQueries: 10,
      singleMaterialBudget: 8000,
      globalEnabled: true,
    );
