// 组合根（T011，架构第 2.2 节「组合入口负责注入具体实现」）。
//
// 本文件是**唯一**知道「哪个接口用哪个基础设施实现」的地方之一（另一处是
// lib/app/app_bootstrap.dart 的启动流程）。它完成 T010 遗留的第 3 条：
// 把数据库、设置仓储、凭据存储与诊断日志接到应用启动流程上。
//
// 为什么 Provider 定义在 app 层而不是 infrastructure：
//   - Riverpod 的 Provider 是**装配**概念，不是实现的一部分。放进 infrastructure
//     会让 infra 依赖状态容器，也会让「哪个实现被选中」散落到多个文件；
//   - 各 Provider 的默认实现故意抛错，这样漏接线会在启动时立刻失败，而不是退化
//     成某个静默的空实现，把「已持久化/已可用」演得像真的一样。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
// Override 类型在 riverpod 3 的 misc 入口（flutter_riverpod.dart 不再导出它）。
import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:flux/core/core.dart';
import 'package:flux/features/articles/application/article_ports.dart';
import 'package:flux/features/ai/application/ai_ports.dart';
import 'package:flux/features/ai/application/model_manager.dart';
import 'package:flux/features/ai/application/model_manager_controller.dart';
import 'package:flux/features/ai/domain/ai_model_store.dart';
import 'package:flux/features/ai/domain/ai_task_store.dart';
import 'package:flux/features/ai/domain/ai_provider.dart';
import 'package:flux/features/ai/domain/search_provider.dart';
import 'package:flux/features/ai/domain/search_service_store.dart';
import 'package:flux/features/ai/application/tool_ports.dart';
import 'package:flux/features/ai/application/vision_ports.dart';
import 'package:flux/features/articles/application/article_platform_ports.dart';
import 'package:flux/features/articles/application/article_extraction_ports.dart';
import 'package:flux/features/articles/application/article_image_ports.dart';
import 'package:flux/features/articles/application/fetch_original_article.dart';
import 'package:flux/features/feeds/application/file_access.dart';
import 'package:flux/features/feeds/application/feed_ports.dart';
import 'package:flux/features/feeds/application/refresh_providers.dart';
import 'package:flux/features/onboarding/application/onboarding_state.dart';
import 'package:flux/features/settings/application/settings_controller.dart';
import 'package:flux/features/settings/application/settings_store.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/article_catalog_store.dart';
import 'package:flux/infrastructure/local/article_search_store.dart';
import 'package:flux/infrastructure/local/article_image_loader.dart';
import 'package:flux/infrastructure/local/image_cache_service.dart';
import 'package:flux/infrastructure/local/degraded_article_catalog_store.dart';
import 'package:flux/infrastructure/local/degraded_article_extraction_store.dart';
import 'package:flux/infrastructure/local/degraded_reading_stats_store.dart';
import 'package:flux/infrastructure/local/diagnostics.dart';
import 'package:flux/infrastructure/local/device_state_repository.dart';
import 'package:flux/infrastructure/local/daily_summary_counter_store.dart';
import 'package:flux/features/articles/application/article_ai_providers.dart';
import 'package:flux/infrastructure/local/feed_catalog_store.dart';
import 'package:flux/infrastructure/local/feed_store_adapter.dart';
import 'package:flux/infrastructure/local/group_collapse_repository.dart';
import 'package:flux/infrastructure/local/ai_model_store.dart';
import 'package:flux/infrastructure/local/degraded_ai_model_store.dart';
import 'package:flux/infrastructure/local/ai_task_store.dart';
import 'package:flux/infrastructure/local/degraded_ai_task_store.dart';
import 'package:flux/infrastructure/local/search_service_store.dart';
import 'package:flux/infrastructure/local/degraded_search_service_store.dart';
import 'package:flux/infrastructure/local/article_extraction_store.dart';
import 'package:flux/infrastructure/local/reading_stats_store.dart';
import 'package:flux/infrastructure/network/feed_fetcher.dart';
import 'package:flux/infrastructure/network/static_page_fetcher_adapter.dart';
import 'package:flux/infrastructure/network/ai_provider_factory.dart';
import 'package:flux/infrastructure/network/search_provider_factory.dart';
import 'package:flux/infrastructure/network/tool_port_adapters.dart';
import 'package:flux/infrastructure/network/vision_adapters.dart';
import 'package:flux/infrastructure/network/media_fetcher.dart';
import 'package:flux/infrastructure/platform/network_conditions.dart';
import 'package:flux/infrastructure/platform/credential_store.dart';
import 'package:flux/infrastructure/platform/ai_credential_adapter.dart';
import 'package:flux/infrastructure/platform/external_link_opener.dart';
import 'package:flux/infrastructure/platform/file_selector_access.dart';
import 'package:flux/infrastructure/platform/image_save_service.dart';
import 'package:flux/infrastructure/platform/system_share_service.dart';
import 'package:flux/infrastructure/platform/device_local_zone.dart';
import 'package:flux/features/statistics/application/reading_stats_ports.dart';

import 'app_bootstrap.dart';

/// 打开（或已确认无法打开）的本地数据库句柄。
///
/// 故意没有默认实现：「数据库还没准备好就有人读它」是必须尽早暴露的装配错误。
/// 数据库不可用是**可诊断的正常状态**，由 [appBootstrapStatusProvider] 表达，
/// 而不是靠这里返回 null 让每个调用点各写一套空值处理。
final Provider<AppDatabase> databaseProvider = Provider<AppDatabase>(
  (Ref ref) =>
      throw StateError('databaseProvider 未被组合根覆盖：见 lib/app/app_bootstrap.dart'),
);

/// 凭据存储（T010 交付的能力）。
final Provider<CredentialStore> credentialStoreProvider =
    Provider<CredentialStore>(
      (Ref ref) => throw StateError(
        'credentialStoreProvider 未被组合根覆盖：见 lib/app/app_bootstrap.dart',
      ),
    );

/// 诊断日志（T010 交付的能力）。
final Provider<DiagnosticLog> diagnosticLogProvider = Provider<DiagnosticLog>(
  (Ref ref) => throw StateError(
    'diagnosticLogProvider 未被组合根覆盖：见 lib/app/app_bootstrap.dart',
  ),
);

/// 启动状态：数据库是否可用，以及失败类别。
final class AppBootstrapStatus {
  /// 构造启动状态。
  const AppBootstrapStatus({required this.degraded, this.failureKind});

  /// 数据库不可用（本次运行不持久化任何改动）。
  final bool degraded;

  /// 失败类别（例如 storage），不含路径与用户内容。
  final String? failureKind;
}

/// 启动状态 Provider（由组合根注入）。
final Provider<AppBootstrapStatus> appBootstrapStatusProvider =
    Provider<AppBootstrapStatus>(
      (Ref ref) => throw StateError(
        'appBootstrapStatusProvider 未被组合根覆盖：见 lib/app/app_bootstrap.dart',
      ),
    );

/// 把一次启动装配结果翻译成 ProviderScope 的 overrides。
///
/// 这是唯一的装配点：main.dart 调用它，测试也用同一函数（换成内存数据库或替身），
/// 因此测试走的就是生产注入路径，不会出现「测试里能过、真实启动漏接线」。
/// [feedFetcher] 只给测试注入替身用：生产不传，默认就是真实的 HTTP 抓取器。
/// [networkConditions] 同理：测试用它构造「当前是计费网络 / 无网络」的世界。
///
/// 为什么参数化而不是让测试自己 override：Riverpod 不允许在同一容器里覆盖同一个
/// Provider 两次，因此「测试再覆盖一次」会在运行时断言失败；而把抓取端口从这里
/// 放出去，测试覆盖的是**接线本身**（拿到的就是生产装配路径上的那一个位置）。
List<Override> bootstrapOverrides(
  AppBootstrapResult result, {
  FeedFetcher? feedFetcher,
  NetworkConditionPort? networkConditions,
  ExternalLinkOpener? externalLinkOpener,
  ImageSaveService? imageSaveService,
  SystemShareService? systemShareService,
  ArticleImageLoader? articleImageLoader,
  // T023：统计的三个端口也参数化，理由与上面几个**完全一致**——Riverpod 不允许在同一个
  // 容器里覆盖同一个 Provider 两次，因此测试必须通过这里（生产装配路径上的那一个位置）
  // 换掉时区/时钟/统计存储，而不是在 ProviderScope 里再覆盖一遍（那会直接断言失败）。
  SessionLocalZone? sessionZone,
  Clock? statsClock,
  ReadingStatsStore? readingStatsStore,
  // T024：静态网页抓取端口也参数化（理由同上：Riverpod 禁止重复覆盖）。
  StaticPageFetcherPort? staticPageFetcher,
  // T025：AI 模型存储端口同样参数化（同一理由）。默认值按数据库是否可用选择
  // （见下方 catalogDatabase 分支）；参数化让测试能构造「列表读取失败」这类无法用
  // 内存库直接制造的世界。
  AiModelStore? aiModelStore,
  // T025：适配器工厂。生产在 T026 接上真实适配器；为空时「测试连接」会明确报
  // 「适配器尚未实现」，而不是静默什么都不做。
  AiProviderFactory? aiProviderFactory,
  // T030：任务与缓存的存储端口也参数化（理由同 aiModelStore：Riverpod 禁止重复覆盖，
  // 测试要能构造「任务读取失败」「缓存写入失败」这类无法用内存库直接制造的世界）。
  AiTaskStore? aiTaskStore,
  AiResultCache? aiResultCache,
  // T031：搜索服务的存储与适配器工厂同样参数化（理由同 aiModelStore）。
  SearchServiceStore? searchServiceStore,
  SearchProviderFactory? searchProviderFactory,
}) {
  return <Override>[
    appBootstrapStatusProvider.overrideWithValue(
      AppBootstrapStatus(
        degraded: result.isDegraded,
        failureKind: result.databaseFailure?.kind,
      ),
    ),
    // features 层不得 import lib/app，因此「降级启动」以 features 自己的 Provider
    // 暴露给它（见 degradedStartupProvider 的说明）。这里把两者对齐。
    degradedStartupProvider.overrideWithValue(result.isDegraded),
    settingsStoreProvider.overrideWithValue(result.settingsStore),
    onboardingStoreProvider.overrideWithValue(result.onboardingStore),
    credentialStoreProvider.overrideWithValue(result.credentialStore),
    diagnosticLogProvider.overrideWithValue(result.diagnosticLog),
    // 诊断端口是**派生**端口：它没有第二条实现（诊断永远走 DiagnosticLog，
    // 脱敏由日志层负责），因此在这里一次性接好，不需要调用方各自组装适配器。
    diagnosticSinkProvider.overrideWithValue(
      DiagnosticLogSink(result.diagnosticLog),
    ),
    // ---- T025：AI 模型与凭据 ------------------------------------------------
    // 凭据端口读的是**同一个** result.credentialStore：组合根已经决定好「这次运行
    // 用 Keychain 还是会话内存」，AI 配置不该有第二条判断路径——否则两处可能得出
    // 不同结论（一处以为会持久化，另一处知道不会）。
    aiCredentialStoreProvider.overrideWithValue(
      AiCredentialStoreAdapter(result.credentialStore),
    ),
    aiDiagnosticSinkProvider.overrideWithValue(
      DiagnosticLogSink(result.diagnosticLog),
    ),
    // 设置读取端口复用同一个 settingsStore：引用检查（SET-034/035）读到的值必须与
    // 设置页写到的是同一份，否则删除确认框会基于另一份配置说「没有被引用」。
    aiSettingsReaderProvider.overrideWithValue(
      SettingsStoreReader(result.settingsStore),
    ),
    // T026：生产默认使用真实的 OpenAI 双协议适配器工厂；测试可注入替身
    // （参数化而不是在 ProviderScope 里再覆盖一次，理由同上面几个端口）。
    aiProviderFactoryProvider.overrideWithValue(
      aiProviderFactory ?? const OpenAiProviderFactory(),
    ),
    // ---- T031：搜索服务 ------------------------------------------------------
    // 凭据端口读的是**同一个** result.credentialStore，但类别前缀不同
    // （search-service）：SET-039 要求搜索凭据与 AI 凭据分开管理，而分开的落点就是
    // Keychain 的类别。共用两份判断路径会让「搜索 Key 被当 API Key 发出去」成为可能。
    searchCredentialStoreProvider.overrideWithValue(
      SearchCredentialStoreAdapter(result.credentialStore),
    ),
    searchProviderFactoryProvider.overrideWithValue(
      searchProviderFactory ?? const HttpSearchProviderFactory(),
    ),
    if (result.database case final AppDatabase database)
      databaseProvider.overrideWithValue(database),
    // ---- T014：订阅管理相关的端口 -------------------------------------------
    // 抓取端口与数据库无关（它只需要 HTTP），因此两种启动状态下都给真实实现：
    // 降级模式下「预览」仍然可用，只有「确认入库」会因存储失败而明确报错，
    // 这比让整个页面不可用更符合实际（用户至少能看到地址是否可解析）。
    feedFetcherProvider.overrideWithValue(feedFetcher ?? HttpFeedFetcher()),
    // ---- T015：OPML 导入/导出的文件读写端口 --------------------------------
    // 与数据库无关（它只需要系统文件面板），因此两种启动状态下都给真实实现：
    // 降级模式下仍可导出当前（可能为空的）清单、仍可读文件做预览，只有入库会
    // 因存储失败而明确报错。
    fileAccessProvider.overrideWithValue(const FileSelectorAccess()),
    // ---- T020：正文的平台动作（外开 / 图片保存 / 系统分享 / 去设置） --------------
    // 四个端口都与数据库无关，因此两种启动状态下都给真实实现：降级模式只是不持久化
    // 数据，打开浏览器、保存一张图、弹出分享面板都不需要数据库。
    externalLinkOpenerProvider.overrideWithValue(
      externalLinkOpener ?? const UrlLauncherLinkOpener(),
    ),
    // 保存图片同样走受控管线：它必须在管线建好之后才能构造（见下方 articleImageLoader
    // 的说明），因此这里用一个「读同一容器里的加载器」的装配，而不是就地 new 一个。
    imageSaveServiceProvider.overrideWith(
      (Ref ref) =>
          imageSaveService ??
          HttpImageSaveService(
            imageLoader: ref.watch(articleImageLoaderProvider),
          ),
    ),
    // macOS 原生 NSSharingServicePicker 通道；通道不存在时 isAvailable() 返回 false，
    // 上层回退复制（架构 4.2），因此这里不需要按平台分支。
    systemShareServiceProvider.overrideWithValue(
      systemShareService ?? const NativeSystemShareService(),
    ),
    // ---- T016：网络状况探测（计费/离线） -----------------------------------
    // 与数据库无关（它只需要本机网络接口信息），因此两种启动状态下都给真实实现。
    // 桌面实现的边界写在 infrastructure/platform/network_conditions.dart：
    // macOS 没有公开的计费网络 API，因此 isMetered 始终为 false（如实记为未实现，
    // 不用 true 假装遵守 SET-013）。
    networkConditionsProvider.overrideWithValue(
      networkConditions ?? const DesktopNetworkConditions(),
    ),
    // ---- T021：远程图片缓存管线 --------------------------------------------
    // 图片加载器（守卫 + MIME/体积/魔数校验 + 磁盘 LRU 缓存）。两种启动状态下都给
    // 真实实现：数据目录不可用时 cache 传 null（本次运行不落盘），而不是把图片功能
    // 整个关掉——「降级」的语义是不持久化，不是功能不可用。
    //
    // SET-080 的上限在这里读取（异步），因此缓存目录对象先建好、上限由读取结果在
    // 首次使用时应用；读取失败退回注册表默认值 512 MiB。
    articleImageLoaderProvider.overrideWith(
      (Ref ref) =>
          articleImageLoader ??
          CachedArticleImageLoader(
            fetcher: HttpMediaFetcher(),
            cache: result.mediaCacheDirectory == null
                ? null
                : ImageCacheService(root: result.mediaCacheDirectory!),
            policy: SettingsMediaDownloadPolicy(
              settings: result.settingsStore,
              networkConditions:
                  networkConditions ?? const DesktopNetworkConditions(),
            ),
          ),
    ),
    // ---- T023：阅读统计 ------------------------------------------------------
    // 会话时区在**启动时**取一次快照：会话归属依据是「会话发生时的时区」，而不是
    // 查询时的时区（架构 5.3）。取一次快照也避免同一次会话的不同片段因为中途重读
    // 系统时区而落到不同日期上。
    //
    // 时钟给真实系统时钟：统计的时间必须来自墙钟（假时钟只用于测试）。
    sessionZoneProvider.overrideWithValue(
      sessionZone ?? DeviceLocalZone.current(),
    ),
    statsClockProvider.overrideWithValue(statsClock ?? const SystemClock()),
    if (result.database case final AppDatabase catalogDatabase) ...<Override>[
      feedCatalogProvider.overrideWithValue(
        DriftFeedCatalogStore(catalogDatabase),
      ),
      feedArticleStoreProvider.overrideWithValue(
        DriftFeedArticleStore(catalogDatabase),
      ),
      // T017：文章阅读端口（列表 + 状态写入）。
      articleCatalogProvider.overrideWithValue(
        DriftArticleCatalogStore(catalogDatabase),
      ),
      // T022：全文检索端口（同一份数据上的 fts5 索引）。
      articleSearchProvider.overrideWithValue(
        DriftArticleSearchStore(catalogDatabase),
      ),
      groupCollapseStoreProvider.overrideWithValue(
        GroupCollapseRepository(catalogDatabase),
      ),
      // T023：阅读统计读写。
      readingStatsProvider.overrideWithValue(
        readingStatsStore ?? DriftReadingStatsStore(catalogDatabase),
      ),
      // T025：AI 模型记录。与其它数据表同一个库，因此「数据库不可用」时下面的
      // 降级分支会给出明确的只读/写入失败语义。
      aiModelStoreProvider.overrideWithValue(
        aiModelStore ?? DriftAiModelStore(catalogDatabase),
      ),
      // T030：AI 任务的持久记录与结果缓存。与模型记录同一个库，因此「数据库不可用」
      // 时下面的降级分支会给出明确的只读/写入失败语义。
      aiTaskStoreProvider.overrideWithValue(
        aiTaskStore ?? DriftAiTaskStore(catalogDatabase),
      ),
      aiResultCacheProvider.overrideWithValue(
        aiResultCache ?? DriftAiResultCache(catalogDatabase),
      ),
      // T031：搜索服务记录。与其它数据表同一个库，因此「数据库不可用」时下面的
      // 降级分支会给出明确的只读/写入失败语义。
      searchServiceStoreProvider.overrideWithValue(
        searchServiceStore ?? DriftSearchServiceStore(catalogDatabase),
      ),
      // T024：提取正文读写。
      articleExtractionProvider.overrideWithValue(
        DriftArticleExtractionStore(catalogDatabase),
      ),
    ] else ...<Override>[
      feedCatalogProvider.overrideWithValue(const DegradedFeedCatalogStore()),
      feedArticleStoreProvider.overrideWithValue(
        const DegradedFeedArticleStore(),
      ),
      // 降级模式下文章列表退到内存空实现：读返回空集合、写返回类型化失败。
      // 不返回假的成功，理由与另外两个端口一致（见 feed_store_adapter 的说明）。
      articleCatalogProvider.overrideWithValue(
        const DegradedArticleCatalogStore(),
      ),
      // 降级模式下检索退到明确失败：没有库就没有索引，假装「没搜到」会把
      // 「数据库不可用」演成「库里没有这篇文章」。
      articleSearchProvider.overrideWithValue(
        const DegradedArticleSearchStore(),
      ),
      // 折叠状态在降级模式下退到会话内存：记不住不算错误（见端口说明）。
      groupCollapseStoreProvider.overrideWithValue(
        InMemoryGroupCollapseStore(),
      ),
      // 降级模式下统计读返回空、写与清空明确失败（见该实现的说明）。
      readingStatsProvider.overrideWithValue(
        readingStatsStore ?? const DegradedReadingStatsStore(),
      ),
      articleExtractionProvider.overrideWithValue(
        const DegradedArticleExtractionStore(),
      ),
      // T025：数据库不可用时模型列表读作空（这是**真实**答案：本次运行确实没有
      // 任何可用模型），写入明确失败（不假装保存成功）。
      aiModelStoreProvider.overrideWithValue(
        aiModelStore ?? const DegradedAiModelStore(),
      ),
      // T030：降级模式下任务列表读作空（本次运行确实没有可读记录），写入明确失败；
      // 缓存永不命中（这是真实答案，功能照常发起真实请求）。
      aiTaskStoreProvider.overrideWithValue(
        aiTaskStore ?? const DegradedAiTaskStore(),
      ),
      aiResultCacheProvider.overrideWithValue(
        aiResultCache ?? const DegradedAiResultCache(),
      ),
      // T031：数据库不可用时搜索服务列表读作空（这是**真实**答案：本次运行确实
      // 没有可用服务），写入明确失败（不假装保存成功）。
      searchServiceStoreProvider.overrideWithValue(
        searchServiceStore ?? const DegradedSearchServiceStore(),
      ),
    ],
    // ---- T024：静态网页抓取 --------------------------------------------------
    // 与数据库无关（只需要 HTTP），因此两种启动状态下都给真实实现：降级模式只是不
    // 持久化，抓一页网页不需要数据库。
    staticPageFetcherProvider.overrideWithValue(
      staticPageFetcher ?? HttpStaticPageFetcherAdapter(),
    ),
    // ---- T032：受控工具的两个执行端口 ----------------------------------------
    // 两者都与数据库无关，因此两种启动状态下都给真实实现。
    //
    // 网页抓取**复用 T024 的抓取端口**（上面刚装配好的那一个）：它已经带完整安全链
    // （地址守卫 + DNS 解析后复检 + 逐跳重定向校验 + 体积/解压上限）。另起一条
    // 「只给工具用」的下载路径会让两条路径的判据各自漂移。
    controlledPageFetcherProvider.overrideWith(
      (Ref ref) => ControlledPageFetcherAdapter(
        fetcher: ref.watch(staticPageFetcherProvider),
      ),
    ),
    // 图片查看**复用 T021 的受控加载器**（阅读器图片走同一条路，含 MIME/体积/魔数
    // 校验与缓存），因此这里也读同一个 Provider，而不是另建一条下载路径。
    toolImageInspectorProvider.overrideWith(
      (Ref ref) =>
          ToolImageInspectorAdapter(ref.watch(articleImageLoaderProvider)),
    ),
    // 单材料预算（SET-061）由设置读取；接线到这里之后执行器就能拿到用户配置的值。
    toolBudgetSettingsProvider.overrideWithValue(
      SettingsStoreToolBudgetReader(result.settingsStore),
    ),
    // ---- T033：视觉链路 ------------------------------------------------------
    //
    // 图片加载**复用 T021 的受控加载器**（地址守卫 + MIME/魔数/体积校验 + 磁盘缓存），
    // 并在超出 SET-065 单图上限时降采样：另起一条「只给视觉用」的下载路径会让两条路径的
    // 判据各自漂移，而漂移的后果是「阅读时挡住了一张图、发给模型时没挡住」。
    visionImageLoaderProvider.overrideWith(
      (Ref ref) => CachedVisionImageLoader(
        loader: ref.watch(articleImageLoaderProvider),
      ),
    ),
    // SET-034 / SET-065 的只读读取。
    visionSettingsReaderProvider.overrideWithValue(
      SettingsStoreVisionSettings(result.settingsStore),
    ),
    // 发送告知的确认记录：属于本机运行授权状态，不用 SET 编号（架构第 8 节）。
    // 数据库不可用时给 null（读取按「未确认」处理，因此**不会**发出图片）——这是 fail-closed
    // 的方向：功能暂时用不了，而不是未经授权发送一次。
    visionConsentStoreProvider.overrideWithValue(
      result.database == null
          ? null
          : DeviceStateVisionConsent(DeviceStateRepository(result.database!)),
    ),
    // 工具执行器的视觉分析端口（T033）：把视觉链路接到 inspectImage 上。
    toolVisionAnalyzerProvider.overrideWith(
      (Ref ref) => VisualRouterToolAnalyzer(ref.watch(visualRouterProvider)),
    ),
    // ---- T034：选词解释 / 单文摘要 / 自动摘要 ----------------------------------
    //
    // 日期时区与会话时区用**同一份快照**：两处各读一次设备时区会让「会话归属」与
    // 「当天额度」在跨午夜的那一秒落在不同的日期上，而用户会看到「昨天的额度今天又
    // 用了一遍」这种无法解释的计数。
    summaryZoneProvider.overrideWithValue(
      sessionZone ?? DeviceLocalZone.current(),
    ),
    // SET-061 的单材料预算：与 aiTaskBudgetProvider 同一口径，先用注册表默认值（8000），
    // 由 T041 的同步投影统一接上「读用户值」。这里不引入第二套设置读取路径。
    // 当天自动摘要计数：用 settings 窄表的 device. 命名空间（本机运行计数，不参与同步）。
    // 数据库不可用时给 null（读取抛错 → 批处理会**不发请求**），这是 fail-closed 的方向：
    // 功能暂时用不了，而不是绕过当天的费用上限。
    dailySummaryCounterProvider.overrideWithValue(
      // 数据库不可用时用「读失败、写失败」的降级实现，而不是让 Provider 抛错：批处理会因
      // 读不到额度而**不发请求**（fail-closed），而抛错会让一次刷新带上一条无关的崩溃。
      result.database == null
          ? const DegradedDailySummaryCounter()
          : SettingsDailySummaryCounter(result.database!),
    ),
  ];
}

/// 把设置端口接成工具预算读取端口（SET-061）。
///
/// 与 SettingsStoreReader 同一做法：只转发「按编号读」，不给写入口——给工具层写设置的
/// 能力会让「一次工具执行顺手改了用户配置」成为可能，而设置页不会因此刷新。
final class SettingsStoreToolBudgetReader implements ToolBudgetSettings {
  /// 绑定一个设置端口。
  const SettingsStoreToolBudgetReader(this._store);

  final SettingsStore _store;

  @override
  Future<Object?> readSingleMaterialBudget() async {
    final Result<Object?> read = await _store.readSetting(SettingId.set061);
    return read.isOk ? read.valueOrNull : null;
  }
}

/// 把 T011 的 [SettingsStore] 适配成 T025 的只读设置端口。
///
/// 只转发「按编号读」：模型管理只需要 SET-034/035 两个值做引用检查，不需要写入口——
/// 给它写能力会让「模型管理顺手改了设置」成为可能，而设置页的状态并不会因此刷新，
/// 出现两处状态源。
final class SettingsStoreReader implements SettingsReader {
  /// 绑定一个设置端口。
  const SettingsStoreReader(this._store);

  final SettingsStore _store;

  @override
  Future<Result<Object?>> readSetting(SettingId id) => _store.readSetting(id);
}
