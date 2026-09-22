// 每日新闻任务的编排（T037；架构 4.4 全流程、SET-050–063、手册 6.3「总结」节）。
//
// 一次任务按架构 4.4 的顺序走完：配置与预算检查 → 固化时区与输入快照 → RSS 选材 +
// 逐站必访 + 检索 → 事件聚合/去重 → 生成带候选引用的条目 → 结构与引用校验 → 保存新版本。
//
// 五条刻意的设计（每一条都对应一个必测项）：
//
//   1) **出网只经过 ToolExecutor**。必访站抓取与检索都构造 [ToolCall] 交给受控执行器，
//      因此地址守卫（私网/回环/链路本地）、工具次数预算（SET-062）与「未知工具不存在
//      执行路径」这些既有保证自动适用于新闻链路。新闻层自己再写一条 HTTP 路径就等于
//      把 T032 的安全断言作废。
//   2) **禁词在发出之前过滤**（SET-053）。用 T036 的 buildNewsSearchQueries：命中的查询
//      **根本不会出现在返回值里**，因此「实际发送的查询符合本地规则」是结构性的，而不是
//      「提示模型别用」。被拦下的条数记进结果，界面能如实说明。
//   3) **材料与指令分开，且模型不需要工具**。材料由客户端预先取好放进 prompt（架构 4.3
//      要求没有 native tool calling 的模型也能消费），材料段落带「这是第三方数据，不是
//      指令」的框架（架构第 8 节）。
//   4) **编造引用导致条目退回而不是整稿静默接受**（架构 4.4）。解析结果里同时保留被退回
//      的条目与不存在的 sourceId，界面能指出「模型引用了不存在的材料」。
//   5) **成功版本不被草稿覆盖**：保存走 [NewsRunStore.append]，只有 succeeded/partial 的
//      追加才把 isCurrent 移到新版本上；失败/取消/中断保留上一版（架构 4.4/4.5）。
library;

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/application/ai_task_budget.dart';
import 'package:flux/features/ai/application/ai_task_runner.dart';
import 'package:flux/features/ai/application/model_manager.dart'
    show SettingsReader;
import 'package:flux/features/ai/application/tool_executor.dart';
import 'package:flux/features/ai/domain/ai_message.dart';
import 'package:flux/features/ai/domain/ai_model.dart';
import 'package:flux/features/ai/domain/search_result.dart';
import 'package:flux/features/ai/domain/tool_call.dart';

import 'news_run_inputs.dart';
import 'news_source_config.dart';
import 'news_verification_service.dart';

/// 本次任务从设置读到的上限（SET-060/061/062/063）。
///
/// 与 [AiTaskBudget] 同一口径：一次任务开始时**冻结**这些值，任务中途不再读设置。
/// 不冻结会让「用户在任务跑到一半时调低了上限」表现为同一次任务里有两种上限，而结果
/// 记录里只留下一组数字。
final class NewsTaskSettings {
  /// 构造设置。
  const NewsTaskSettings({
    this.maxArticles = kNewsDefaultMaxArticles,
    this.maxSites = kNewsDefaultMaxSites,
    this.maxQueries = kNewsDefaultMaxQueries,
    this.singleMaterialBudget = kNewsDefaultSingleMaterialBudget,
    this.toolCalls = 30,
    this.totalMaterialCharacterBudget = kNewsDefaultTotalMaterialCharacters,
  });

  /// SET-060 的文章上限。
  final int maxArticles;

  /// SET-060 的必访站上限。
  final int maxSites;

  /// SET-060 的查询上限。
  final int maxQueries;

  /// SET-061 的单材料字符预算。
  final int singleMaterialBudget;

  /// SET-062 的工具调用总次数。
  final int toolCalls;

  /// 材料总字符预算（由 SET-063 的 Token 预算派生，防止一次把上下文塞到超预算）。
  final int totalMaterialCharacterBudget;

  /// 从设置读取；读取失败或结构不符的项回退注册表默认值（与 AiTaskBudget 同一口径：
  /// 预算是总资源边界，读不到就按保守默认值继续，比「因为一次设置读失败就什么都不做」
  /// 更符合用户预期）。
  static Future<NewsTaskSettings> fromSettingsReader(
    SettingsReader? reader,
  ) async {
    if (reader == null) {
      return const NewsTaskSettings();
    }
    final Object? set060 = await _read(reader, SettingId.set060);
    final Object? set061 = await _read(reader, SettingId.set061);
    final Object? set062 = await _read(reader, SettingId.set062);
    final Object? set063 = await _read(reader, SettingId.set063);
    final int articles = _int(set060, 'maxArticles', kNewsDefaultMaxArticles);
    final int sites = _int(set060, 'maxSites', kNewsDefaultMaxSites);
    final int queries = _int(set060, 'maxQueries', kNewsDefaultMaxQueries);
    final int budget = _int(set061, null, kNewsDefaultSingleMaterialBudget);
    final int tools = _int(set062, 'toolCalls', 30);
    final int tokens = _int(set063, null, 100000);
    return NewsTaskSettings(
      maxArticles: articles < 0 ? 0 : articles,
      maxSites: sites < 0 ? 0 : sites,
      maxQueries: queries < 0 ? 0 : queries,
      singleMaterialBudget: budget < 1 ? 1 : budget,
      toolCalls: tools < 1 ? 1 : tools,
      // 材料总预算按 Token 预算的一半计：还要给 prompt、逐站状态与输出留空间，
      // 而「把所有预算都给输入」正是架构 4.5 说的「仅靠时间不能控制费用」之外的
      // 另一种失控（一次任务把上下文塞满并全部计费）。
      totalMaterialCharacterBudget: tokens <= 0 ? 0 : tokens ~/ 2,
    );
  }

  static Future<Object?> _read(SettingsReader reader, SettingId id) async {
    final Result<Object?> read = await reader.readSetting(id);
    return read.isOk ? read.valueOrNull : null;
  }

  static int _int(Object? raw, String? field, int fallback) {
    final Object? value = field == null
        ? raw
        : (raw is Map<Object?, Object?> ? raw[field] : null);
    return value is int ? value : fallback;
  }
}

/// 材料总字符预算的默认值（SET-063 的 100000 Token 的一半）。
const int kNewsDefaultTotalMaterialCharacters = 50000;

/// 一次检索最多接纳多少条结果作为材料（服务商返回数由 SET-040 决定）。
const int kNewsMaxSearchMaterialsPerQuery = 10;

/// 检索可用性端口（「有没有启用的搜索服务」）。
///
/// 单独一个端口而不是从一次失败里推断：没有搜索配置是**配置状态**（界面要指向设置页，
/// 并把结果标为「未联网核验」），而不是一次失败。用「先试一次再猜」的写法会让用户每次
/// 生成都先发一个注定被拒的调用。
abstract interface class NewsSearchAvailability {
  /// 是否存在启用的搜索服务。
  Future<Result<bool>> hasEnabledService();
}

/// 一次新闻任务的输入（界面传入；全部为**纯数据**，便于测试）。
final class NewsRunInput {
  /// 构造输入。
  const NewsRunInput({
    required this.taskId,
    required this.config,
    required this.globalEnabled,
    this.cancellation,
    this.regenerate = false,
  });

  /// 任务标识。
  final String taskId;

  /// 新闻来源配置（T036 的 NewsConfigState：必访站、关键词、禁词、prompt 模式与版本）。
  final NewsConfigState config;

  /// SET-050 的总开关。
  final bool globalEnabled;

  /// 取消信号。
  final AiCancellation? cancellation;

  /// 是否为「用户再次生成」（当天已有成功版本时的二次收费，界面必须已经确认）。
  final bool regenerate;
}

/// 一次任务的产出（界面据此渲染与提示）。
final class NewsRunOutcome {
  /// 构造产出。
  const NewsRunOutcome({
    required this.status,
    required this.snapshot,
    this.record,
    this.aggregation,
    this.error,
    this.shortfall,
    this.stage,
  });

  /// 终态。
  final TaskStatus status;

  /// 输入快照（无论成败都有：它是「这次任务看的是什么」的事实）。
  final NewsInputSnapshot snapshot;

  /// 落库后的记录；保存失败时为 null。
  final NewsRunRecord? record;

  /// 聚合结果（材料与逐站状态）。
  final NewsAggregationResult? aggregation;

  /// 失败/取消原因。
  final AppError? error;

  /// 缺少输入的说明（有输入时为 null）。
  final NewsInputShortfall? shortfall;

  /// 中断/失败时所在的阶段。
  final NewsRunStage? stage;

  /// 是否产出了可用结果。
  bool get ok => status == TaskStatus.succeeded || status == TaskStatus.partial;
}

/// 新闻任务的编排服务。
final class NewsRunService {
  /// 构造服务。
  const NewsRunService({
    required this.candidates,
    required this.runs,
    required this.buildTools,
    required this.runner,
    required this.loadModels,
    required this.searchAvailability,
    required this.diagnostics,
    required this.clock,
    required this.zone,
    this.settings = const NewsTaskSettings(),
    this.onStage,
    this.verifyCitations = true,
    this.verificationBudget = const NewsVerificationBudget(),
  });

  /// 选材候选读取端口。
  final NewsCandidateStore candidates;

  /// 版本存储端口。
  final NewsRunStore runs;

  /// 受控工具执行器的**构造**（必访抓取与检索的唯一出口）。
  ///
  /// 做成构造而不是一个实例：工具次数预算（SET-062）是**每任务**的，复用同一个执行器
  /// 会让第二次生成继承第一次已用掉的次数（甚至直接以「次数用尽」拒绝所有调用），
  /// 而用户看到的是「同一天里第二次生成什么都没抓到」。每次 run 造一个新的执行器，
  /// 预算就从零开始。
  final ToolExecutor Function() buildTools;

  /// 有预算的模型队列（总时限/次数/Token/取消都在它里面）。
  final AiTaskRunner runner;

  /// 读启用模型（按故障转移顺序）。
  final Future<Result<List<AiModel>>> Function() loadModels;

  /// 检索可用性（决定是否标「未联网核验」）。
  final NewsSearchAvailability searchAvailability;

  /// 诊断记录。
  final DiagnosticSink diagnostics;

  /// 时钟（测试注入假时钟）。
  final Clock clock;

  /// 设备时区（任务开始时固化）。
  final SessionLocalZone zone;

  /// 本次任务的上限（冻结值）。
  final NewsTaskSettings settings;

  /// 阶段变更回调（界面进度显示）。
  final void Function(NewsRunStage stage)? onStage;

  /// 是否执行 T038 的独立来源核验。
  ///
  /// 默认开启（架构 4.4 的流程里核验是必经一步）。允许关闭只为两种真实场景：
  /// 用户明确只要初稿（不需要联网核验的二次检索），以及测试里把核验与生成分开验证。
  final bool verifyCitations;

  /// 核验的资源上限（T038）。
  final NewsVerificationBudget verificationBudget;

  /// 执行一次任务。
  Future<NewsRunOutcome> run(NewsRunInput input) async {
    final ToolExecutor tools = buildTools();
    final DateTime nowUtc = clock.now().toUtc();
    final NewsDayRange range = newsDayRange(nowUtc: nowUtc, zone: zone);
    final AiCancellation cancel = input.cancellation ?? AiCancellation();

    // ---- 阶段 1：固化输入快照（时区/区间/选材/prompt 版本） ------------------
    _stage(NewsRunStage.snapshot);
    final Result<List<NewsCandidateArticle>> loaded = await candidates
        .loadCandidates(
          startUtc: range.startUtc,
          endUtc: range.endUtc,
          limit: settings.maxArticles,
        );
    if (loaded.isErr) {
      return _persistFailure(
        input: input,
        range: range,
        nowUtc: nowUtc,
        error: loaded.errorOrNull!,
        status: TaskStatus.failed,
        stage: NewsRunStage.snapshot,
        siteResults: const <NewsSiteFetchResult>[],
        materials: const <NewsMaterial>[],
      );
    }
    final NewsSelection selection = selectNewsCandidates(
      candidates: input.globalEnabled
          ? loaded.valueOrNull!
          : const <NewsCandidateArticle>[],
      maxArticles: settings.maxArticles,
    );
    final List<NewsMaterial> rssMaterials = <NewsMaterial>[
      for (final NewsCandidateArticle article in selection.articles)
        buildRssMaterial(
          candidate: article,
          charBudget: settings.singleMaterialBudget,
          accessedAt: nowUtc,
        ),
    ];
    final List<NewsRequiredSite> sites = input.config.promptInput.enabledSites
        .take(settings.maxSites)
        .toList(growable: false);
    final String promptText = input.config.resolvedPrompt;
    final NewsInputSnapshot snapshot = NewsInputSnapshot(
      localDate: range.localDate,
      deviceTimeZone: zone.ianaName,
      utcOffsetMinutes: range.utcOffsetMinutes,
      dayStartUtc: range.startUtc,
      dayEndUtc: range.endUtc,
      frozenAtUtc: nowUtc,
      candidates: rssMaterials,
      requiredSites: sites,
      keywords: input.config.keywords,
      blockedQueryTerms: input.config.blockedQueryTerms,
      excludedTopics: input.config.excludedTopics,
      promptVersionRef: _promptVersionRef(input.config),
      promptText: promptText,
      maxArticles: settings.maxArticles,
      maxSites: settings.maxSites,
      maxQueries: settings.maxQueries,
      singleMaterialBudget: settings.singleMaterialBudget,
      globalEnabled: input.globalEnabled,
      language: input.config.language,
    );
    diagnostics.info(
      '新闻任务快照已固化 date=${snapshot.localDate} tz=${snapshot.deviceTimeZone} '
      'articles=${rssMaterials.length} sites=${sites.length} '
      'keywords=${snapshot.keywords.length} prompt=${snapshot.promptVersionRef}',
      tag: 'news.run',
    );

    if (cancel.isCancelled) {
      return _persistFailure(
        input: input,
        range: range,
        nowUtc: nowUtc,
        snapshot: snapshot,
        error: CancelledError(reason: '任务开始前已取消'),
        status: TaskStatus.cancelled,
        stage: NewsRunStage.snapshot,
        siteResults: const <NewsSiteFetchResult>[],
        materials: rssMaterials,
      );
    }

    // ---- 阶段 2：逐站必访（SET-051：逐站执行并记录结果） ----------------------
    _stage(NewsRunStage.requiredSites);
    final List<NewsSiteFetchResult> siteResults = <NewsSiteFetchResult>[];
    final List<NewsMaterial> fetchedMaterials = <NewsMaterial>[];
    for (final NewsRequiredSite site in sites) {
      if (cancel.isCancelled) {
        break;
      }
      final _SiteFetchOutcome outcome = await _fetchSite(
        site: site,
        cancel: cancel,
        nowUtc: nowUtc,
        tools: tools,
      );
      siteResults.add(outcome.result);
      if (outcome.material != null) {
        fetchedMaterials.add(outcome.material!);
      }
    }

    // ---- 阶段 3：联网检索（禁词在发出前过滤，SET-052/053） --------------------
    _stage(NewsRunStage.search);
    final List<String> requested = buildNewsSearchQueries(
      keywords: snapshot.keywords,
      derivedQueries: deriveQueriesFromArticles(
        articles: selection.articles,
        maxQueries: settings.maxQueries,
      ),
      blockedQueryTerms: snapshot.blockedQueryTerms,
      maxQueries: settings.maxQueries,
    );
    final int blockedQueries = countBlockedQueries(
      rawQueries: <String>[
        ...snapshot.keywords,
        ...deriveQueriesFromArticles(
          articles: selection.articles,
          maxQueries: settings.maxQueries,
        ),
      ],
      blockedQueryTerms: snapshot.blockedQueryTerms,
    );
    final Result<bool> searchReady = await searchAvailability
        .hasEnabledService();
    final bool searchConfigured = searchReady.isOk && searchReady.valueOrNull!;
    final List<NewsMaterial> searchMaterials = <NewsMaterial>[];
    final List<String> issued = <String>[];
    int searchResultCount = 0;
    if (searchConfigured && !cancel.isCancelled) {
      for (final String query in requested) {
        if (cancel.isCancelled) {
          break;
        }
        issued.add(query);
        final ToolResult result = await tools.execute(
          ToolCall(
            id: 'news-search-${issued.length}',
            rawName: ToolName.search.wireName,
            args: <String, Object?>{'query': query},
          ),
        );
        final ToolPayload? payload = result.payload;
        if (payload is! SearchToolPayload) {
          // 检索失败不终止任务：RSS 与必访站的材料仍然可用（架构 4.4 的「部分结果
          // 清楚标注」）。只记结构事实，不记查询词与响应体。
          diagnostics.warning(
            '新闻检索未返回可用结果 queryIndex=${issued.length} '
            'kind=${result.reason?.name ?? 'failed'}',
            tag: 'news.run',
          );
          continue;
        }
        searchResultCount += payload.results.length;
        for (final SearchResult hit in payload.results.take(
          kNewsMaxSearchMaterialsPerQuery,
        )) {
          final String excerpt = clampSearchText(
            hit.snippet,
            settings.singleMaterialBudget,
          );
          final String sourceId = hit.sourceId;
          if (findMaterial(searchMaterials, sourceId) != null) {
            continue;
          }
          searchMaterials.add(
            NewsMaterial(
              sourceId: sourceId,
              accessMethod: CitationAccessMethod.search,
              title: clampSearchText(hit.title, kSearchTitleMaxLength),
              url: hit.url,
              publishedAt: hit.publishedAt,
              accessedAt: nowUtc,
              excerpt: excerpt,
              materialHash: materialHashOf(
                sourceId: sourceId,
                url: hit.url,
                excerpt: excerpt,
              ),
              truncated: hit.snippet.length > excerpt.length,
              contentLength: hit.snippet.length,
            ),
          );
        }
      }
    }

    // ---- 事件聚合：材料合并 + 总字符预算 --------------------------------------
    final List<NewsMaterial> merged = <NewsMaterial>[];
    final Map<String, NewsMaterial> byId = <String, NewsMaterial>{};
    for (final NewsMaterial material in <NewsMaterial>[
      ...rssMaterials,
      ...fetchedMaterials,
      ...searchMaterials,
    ]) {
      if (byId.containsKey(material.sourceId)) {
        continue;
      }
      byId[material.sourceId] = material;
      merged.add(material);
    }
    final MaterialBudgetOutcome budgeted = applyMaterialCharacterBudget(
      materials: merged,
      characterBudget: settings.totalMaterialCharacterBudget,
    );
    final List<NewsMaterial> materials = budgeted.materials;
    final NewsAggregationResult aggregation = NewsAggregationResult(
      materials: materials,
      siteResults: siteResults,
      issuedQueries: issued,
      searchResultCount: searchResultCount,
      blockedQueryCount: blockedQueries,
    );
    final NewsInputShortfall? shortfall = detectInputShortfall(
      aggregation: aggregation,
      snapshot: snapshot,
    );
    if (shortfall != null || materials.isEmpty) {
      // 缺少输入：**不生成、不编造**（架构 4.4、手册 6.3「无搜索配置等待」）。
      _stage(NewsRunStage.save);
      final AppError error = ValidationError(
        field: 'news.input',
        reason: shortfall == NewsInputShortfall.globalDisabled
            ? 'newsGlobalDisabled'
            : 'newsMissingInput',
      );
      return _persistFailure(
        input: input,
        range: range,
        nowUtc: nowUtc,
        snapshot: snapshot,
        error: error,
        status: shortfall == NewsInputShortfall.globalDisabled
            ? TaskStatus.waitingConfiguration
            : TaskStatus.failed,
        stage: NewsRunStage.save,
        siteResults: siteResults,
        materials: materials,
        aggregation: aggregation,
        shortfall: shortfall ?? NewsInputShortfall.noInputAtAll,
      );
    }

    if (cancel.isCancelled) {
      return _persistFailure(
        input: input,
        range: range,
        nowUtc: nowUtc,
        snapshot: snapshot,
        error: CancelledError(reason: '任务在生成前被取消'),
        status: TaskStatus.cancelled,
        stage: NewsRunStage.search,
        siteResults: siteResults,
        materials: materials,
        aggregation: aggregation,
      );
    }

    // ---- 阶段 4：生成初稿（预算全接在 AiTaskRunner 上） -----------------------
    _stage(NewsRunStage.generate);
    final Result<List<AiModel>> models = await loadModels();
    if (models.isErr) {
      return _persistFailure(
        input: input,
        range: range,
        nowUtc: nowUtc,
        snapshot: snapshot,
        error: models.errorOrNull!,
        status: TaskStatus.failed,
        stage: NewsRunStage.generate,
        siteResults: siteResults,
        materials: materials,
        aggregation: aggregation,
      );
    }
    if (models.valueOrNull!.isEmpty) {
      return _persistFailure(
        input: input,
        range: range,
        nowUtc: nowUtc,
        snapshot: snapshot,
        error: ProviderError(
          provider: '-',
          kind: 'noEnabledModel',
          detail: '没有启用的模型',
        ),
        status: TaskStatus.waitingConfiguration,
        stage: NewsRunStage.generate,
        siteResults: siteResults,
        materials: materials,
        aggregation: aggregation,
      );
    }
    final AiTaskOutcome outcome = await runner.run(
      taskId: input.taskId,
      request: AiRequest(
        modelId: models.valueOrNull!.first.modelId,
        messages: <AiMessage>[
          AiMessage.user(
            buildNewsUserMessage(
              promptText: promptText,
              materialBlock: buildNewsMaterialBlock(materials),
              siteStatusBlock: buildSiteStatusBlock(siteResults),
            ),
          ),
        ],
        cancellation: cancel,
      ),
      models: models.valueOrNull!,
    );
    final String? text = outcome.text;
    if (!outcome.hasResult || text == null) {
      return _persistFailure(
        input: input,
        range: range,
        nowUtc: nowUtc,
        snapshot: snapshot,
        error:
            outcome.error ??
            ProviderError(provider: '-', kind: 'noOutput', detail: '模型没有产出'),
        status: outcome.status == TaskStatus.cancelled
            ? TaskStatus.cancelled
            : TaskStatus.failed,
        stage: NewsRunStage.generate,
        siteResults: siteResults,
        materials: materials,
        aggregation: aggregation,
        providerAlias: outcome.alias,
        modelId: outcome.modelId,
        consumedTokens: outcome.consumedTokens,
        attemptCount: outcome.attemptCount,
        draftText: text,
      );
    }

    // ---- 阶段 5：结构与引用校验（编造引用 → 条目退回） ------------------------
    final NewsDraftParseResult parsed = parseNewsDraft(
      text: text,
      knownSourceIds: byId.keys.toSet(),
    );
    if (parsed.hasFabricatedCitation) {
      diagnostics.warning(
        '新闻初稿引用了不存在的材料 count=${parsed.unknownSourceIds.length} '
        'rejected=${parsed.rejectedItems.length}',
        tag: 'news.run',
      );
    }
    if (!parsed.ok) {
      return _persistFailure(
        input: input,
        range: range,
        nowUtc: nowUtc,
        snapshot: snapshot,
        error: ParseError(
          source: 'news.draft',
          detail: parsed.failureReason ?? 'noUsableItem',
        ),
        status: outcome.status == TaskStatus.cancelled
            ? TaskStatus.cancelled
            : TaskStatus.failed,
        stage: NewsRunStage.generate,
        siteResults: siteResults,
        materials: materials,
        aggregation: aggregation,
        providerAlias: outcome.alias,
        modelId: outcome.modelId,
        consumedTokens: outcome.consumedTokens,
        attemptCount: outcome.attemptCount,
        draftText: text,
        items: parsed.items,
      );
    }

    // ---- 阶段 6：保存新版本 ---------------------------------------------------
    //
    // 分两步保存（T038）：**先存初稿版本**，再做独立来源核验，核验后追加一个带证据标签的
    // 新版本。这样用户能在版本列表里对照「初稿」与「核验后」两份内容，而不是只看到一份
    // 被就地改写的文本（架构 4.4「保存新版本 / 保留上个成功版本」）。
    final bool anySiteFailed = siteResults.any(
      (NewsSiteFetchResult r) => r.failed,
    );
    List<NewsDraftItem> finalItems = parsed.items;
    NewsVerificationMethod? verificationMethod;
    bool verificationFailed = false;
    AppError? verificationError;
    int verifiedCount = 0;

    if (verifyCitations) {
      _stage(NewsRunStage.save);
      final NewsRunRecord draftRecord = NewsRunRecord(
        localDate: snapshot.localDate,
        timeZone: snapshot.deviceTimeZone,
        version: await _nextVersion(snapshot),
        status: anySiteFailed ? TaskStatus.partial : TaskStatus.succeeded,
        snapshot: snapshot,
        siteResults: siteResults,
        materials: materials,
        items: parsed.items,
        createdAt: nowUtc,
        isCurrent: true,
        draftText: text,
        providerAlias: outcome.alias,
        modelId: outcome.modelId,
        consumedTokens: outcome.consumedTokens,
        attemptCount: outcome.attemptCount,
      );
      final Result<NewsRunRecord> draftSaved = await runs.append(draftRecord);
      if (draftSaved.isErr) {
        diagnostics.warning(
          '新闻初稿保存失败 kind=${draftSaved.errorOrNull!.kind}',
          tag: 'news.run',
        );
        return NewsRunOutcome(
          status: TaskStatus.failed,
          snapshot: snapshot,
          aggregation: aggregation,
          error: draftSaved.errorOrNull,
          stage: NewsRunStage.save,
        );
      }

      _stage(NewsRunStage.verify);
      final NewsVerificationOutcome verification =
          await NewsVerificationService(
            buildTools: buildTools,
            diagnostics: diagnostics,
            budget: verificationBudget,
          ).verify(
            items: parsed.items,
            materials: materials,
            blockedQueryTerms: snapshot.blockedQueryTerms,
            searchConfigured: searchConfigured,
            cancellation: cancel,
          );
      finalItems = verification.items;
      verificationMethod = verification.method;
      verificationFailed = verification.failed;
      verificationError = verification.error;
      verifiedCount = verification.verifiedItemCount;
      if (verificationFailed) {
        // 核验失败**不丢初稿**（见 NewsVerificationService 的文件头说明）：初稿版本已经
        // 落库且仍是当前版本，因此用户手上的东西一件都没少。
        diagnostics.warning(
          '核验未完成（保留初稿版本）kind=${verificationError?.kind ?? 'unknown'}',
          tag: 'news.run',
        );
      }
    }

    _stage(NewsRunStage.save);
    final bool hasConflict = finalItems.any(
      (NewsDraftItem item) =>
          item.labels.contains(NewsEvidenceLabel.sourceConflict),
    );
    // 有站点失败、核验失败或出现来源冲突 → partial（部分结果，清楚标注）；
    // 其余为完整成功。
    final bool degraded = anySiteFailed || verificationFailed || hasConflict;
    final NewsRunRecord record = NewsRunRecord(
      localDate: snapshot.localDate,
      timeZone: snapshot.deviceTimeZone,
      version: await _nextVersion(snapshot),
      status: degraded ? TaskStatus.partial : TaskStatus.succeeded,
      snapshot: snapshot,
      siteResults: siteResults,
      materials: materials,
      items: finalItems,
      createdAt: nowUtc,
      isCurrent: true,
      draftText: text,
      providerAlias: outcome.alias,
      modelId: outcome.modelId,
      consumedTokens: outcome.consumedTokens,
      attemptCount: outcome.attemptCount,
      verificationMethod: verificationMethod?.describe(),
    );
    final Result<NewsRunRecord> saved = await runs.append(record);
    if (saved.isErr) {
      diagnostics.warning(
        '新闻结果保存失败 kind=${saved.errorOrNull!.kind}',
        tag: 'news.run',
      );
      return NewsRunOutcome(
        status: TaskStatus.failed,
        snapshot: snapshot,
        aggregation: aggregation,
        error: saved.errorOrNull,
        stage: NewsRunStage.save,
      );
    }
    diagnostics.info(
      '新闻任务完成 date=${snapshot.localDate} status=${record.status.name} '
      'items=${parsed.keptItems.length} rejected=${parsed.rejectedItems.length} '
      'materials=${materials.length} tokens=${outcome.consumedTokens} '
      'verified=$verifiedCount',
      tag: 'news.run',
    );
    return NewsRunOutcome(
      status: record.status,
      snapshot: snapshot,
      record: saved.valueOrNull!,
      aggregation: aggregation,
      stage: NewsRunStage.save,
    );
  }

  /// 取下一个版本号（同一日期 + 时区下最大值 + 1）。
  Future<int> _nextVersion(NewsInputSnapshot snapshot) async {
    final Result<List<NewsRunRecord>> existing = await runs.loadVersions(
      localDate: snapshot.localDate,
      timeZone: snapshot.deviceTimeZone,
    );
    if (existing.isErr) {
      // 读不到历史时按 1 记：写库时唯一约束会拒绝重复，而不是静默覆盖一条既有版本。
      return 1;
    }
    int max = 0;
    for (final NewsRunRecord record in existing.valueOrNull!) {
      if (record.version > max) {
        max = record.version;
      }
    }
    return max + 1;
  }

  /// 抓取一个必访站；失败与超时都变成**可见的逐站状态**（SET-051）。
  Future<_SiteFetchOutcome> _fetchSite({
    required NewsRequiredSite site,
    required AiCancellation cancel,
    required DateTime nowUtc,
    required ToolExecutor tools,
  }) async {
    final ToolResult result = await tools.execute(
      ToolCall(
        id: 'news-site-${site.id ?? site.sortOrder}',
        rawName: ToolName.fetchPage.wireName,
        args: <String, Object?>{'url': site.url},
      ),
    );
    final ToolPayload? payload = result.payload;
    if (payload is! FetchPageToolPayload) {
      final AppError? error = result.error;
      final String kind = result.reason == ToolRejectionReason.budgetExhausted
          ? 'budgetExhausted'
          : error?.kind ?? result.reason?.name ?? 'failed';
      final bool timeout = error is DeadlineExceededError;
      // 只记结构性事实：站点名与失败类别，**不记**地址与页面内容（架构第 8 节）。
      diagnostics.warning(
        '必访站未取到 name=${site.name} kind=$kind',
        tag: 'news.run',
      );
      return _SiteFetchOutcome(
        result: NewsSiteFetchResult(
          name: site.name,
          url: site.url,
          status: timeout
              ? NewsSiteStatus.timeout
              : result.reason == ToolRejectionReason.budgetExhausted
              ? NewsSiteStatus.skipped
              : NewsSiteStatus.failed,
          detailKind: kind,
        ),
      );
    }
    final NewsMaterial material = buildFetchedMaterial(
      siteName: site.name,
      finalUri: payload.url,
      title: payload.title,
      text: payload.text,
      originalLength: payload.originalLength,
      truncated: payload.truncated,
      accessedAt: nowUtc,
    );
    return _SiteFetchOutcome(
      result: NewsSiteFetchResult(
        name: site.name,
        url: site.url,
        status: NewsSiteStatus.ok,
        sourceId: material.sourceId,
        charCount: payload.text.length,
      ),
      material: material,
    );
  }

  /// 保存一条失败/取消/等待记录，并返回产出。
  ///
  /// 失败也落库（架构 4.4「历史资料覆盖不完整需说明」）：用户要知道「今天生成过一次、
  /// 失败了、原因是配置缺失」，而不是看到一个和没点过一样的界面。落库时**不**把
  /// isCurrent 置真，因此上一版成功总结仍然是对外展示的版本。
  Future<NewsRunOutcome> _persistFailure({
    required NewsRunInput input,
    required NewsDayRange range,
    required DateTime nowUtc,
    required AppError error,
    required TaskStatus status,
    required NewsRunStage stage,
    required List<NewsSiteFetchResult> siteResults,
    required List<NewsMaterial> materials,
    NewsInputSnapshot? snapshot,
    NewsAggregationResult? aggregation,
    NewsInputShortfall? shortfall,
    String? providerAlias,
    String? modelId,
    int consumedTokens = 0,
    int attemptCount = 0,
    String? draftText,
    List<NewsDraftItem>? items,
  }) async {
    final NewsInputSnapshot resolved =
        snapshot ??
        _fallbackSnapshot(
          input: input,
          range: range,
          nowUtc: nowUtc,
          materials: materials,
        );
    final NewsRunRecord record = NewsRunRecord(
      localDate: resolved.localDate,
      timeZone: resolved.deviceTimeZone,
      version: await _nextVersion(resolved),
      status: status,
      snapshot: resolved,
      siteResults: siteResults,
      materials: materials,
      items: items ?? const <NewsDraftItem>[],
      createdAt: nowUtc,
      draftText: draftText,
      providerAlias: providerAlias,
      modelId: modelId,
      consumedTokens: consumedTokens,
      attemptCount: attemptCount,
      errorKind: error.kind,
      stage: stage,
    );
    final Result<NewsRunRecord> saved = await runs.append(record);
    return NewsRunOutcome(
      status: status,
      snapshot: resolved,
      record: saved.valueOrNull,
      aggregation: aggregation,
      error: error,
      shortfall: shortfall,
      stage: stage,
    );
  }

  NewsInputSnapshot _fallbackSnapshot({
    required NewsRunInput input,
    required NewsDayRange range,
    required DateTime nowUtc,
    required List<NewsMaterial> materials,
  }) => NewsInputSnapshot(
    localDate: range.localDate,
    deviceTimeZone: zone.ianaName,
    utcOffsetMinutes: range.utcOffsetMinutes,
    dayStartUtc: range.startUtc,
    dayEndUtc: range.endUtc,
    frozenAtUtc: nowUtc,
    candidates: materials,
    requiredSites: input.config.promptInput.enabledSites
        .take(settings.maxSites)
        .toList(growable: false),
    keywords: input.config.keywords,
    blockedQueryTerms: input.config.blockedQueryTerms,
    excludedTopics: input.config.excludedTopics,
    promptVersionRef: _promptVersionRef(input.config),
    promptText: input.config.resolvedPrompt,
    maxArticles: settings.maxArticles,
    maxSites: settings.maxSites,
    maxQueries: settings.maxQueries,
    singleMaterialBudget: settings.singleMaterialBudget,
    globalEnabled: input.globalEnabled,
    language: input.config.language,
  );

  void _stage(NewsRunStage stage) => onStage?.call(stage);

  static String _promptVersionRef(NewsConfigState config) {
    final String version = config.versions.isEmpty
        ? 'builtin'
        : '${config.versions.first.version}';
    return '${config.language.code}#$version';
  }
}

/// 一次站点抓取的内部结果（状态 + 可能的材料）。
final class _SiteFetchOutcome {
  const _SiteFetchOutcome({required this.result, this.material});

  final NewsSiteFetchResult result;
  final NewsMaterial? material;
}

/// 检索查询里被禁词拦下的条数（界面如实说明「有些查询没有发出去」）。
int countBlockedQueries({
  required List<String> rawQueries,
  required List<String> blockedQueryTerms,
}) {
  int count = 0;
  for (final String raw in rawQueries) {
    final String query = raw.trim().toLowerCase();
    if (query.isEmpty) {
      continue;
    }
    final bool blocked = blockedQueryTerms.any((String term) {
      final String t = term.trim().toLowerCase();
      return t.isNotEmpty && query.contains(t);
    });
    if (blocked) {
      count++;
    }
  }
  return count;
}

/// 按总字符预算裁剪材料（保留前面的材料，被舍掉的记数）。
///
/// 为什么保留**前面的**：材料的顺序是「最新事件 → 必访站 → 检索片段」，当预算不足时
/// 最有价值的是当天最新的事件，而不是检索片段。
final class MaterialBudgetOutcome {
  /// 构造结果。
  const MaterialBudgetOutcome({
    required this.materials,
    required this.droppedCount,
    required this.usedCharacters,
  });

  /// 保留的材料。
  final List<NewsMaterial> materials;

  /// 因总预算被舍掉的材料数。
  final int droppedCount;

  /// 实际使用的字符数。
  final int usedCharacters;
}

/// 应用材料总字符预算。
MaterialBudgetOutcome applyMaterialCharacterBudget({
  required List<NewsMaterial> materials,
  required int characterBudget,
}) {
  if (characterBudget <= 0) {
    return MaterialBudgetOutcome(
      materials: const <NewsMaterial>[],
      droppedCount: materials.length,
      usedCharacters: 0,
    );
  }
  final List<NewsMaterial> kept = <NewsMaterial>[];
  int used = 0;
  for (final NewsMaterial material in materials) {
    final int cost = material.excerpt.length + material.title.length;
    if (used + cost > characterBudget && kept.isNotEmpty) {
      break;
    }
    kept.add(material);
    used += cost;
  }
  return MaterialBudgetOutcome(
    materials: List<NewsMaterial>.unmodifiable(kept),
    droppedCount: materials.length - kept.length,
    usedCharacters: used,
  );
}
