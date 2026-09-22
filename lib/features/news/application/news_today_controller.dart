// 今日新闻页的控制器（T038 的最小可用界面；架构 4.4 的日期/进度/结果/版本）。
//
// 职责：把「日期 → 版本列表 → 当前版本」与「一次生成的阶段进度」拼成界面可直接渲染的状态，
// 并把「生成」需要的两次异步读取（配置、上限）收拢在这里。
//
// 四条刻意的设计：
//
//   1) **阶段进度来自编排层的真实回调**（[NewsRunStage]）。界面不自己编造阶段顺序：进度条
//      上显示的顺序就是实际执行顺序，不会出现「界面说正在核验、实际还在抓网页」。
//   2) **历史归属「日期 + 当时的时区」**，不是「日期」。用户旅行后旧记录仍按当时的本地日期
//      可查（架构 4.4「历史结果保存日期+时区，旅行后可查旧记录而不重写日期」）；拿现在的
//      设备时区去查一条在别处生成的记录会查不到，而界面只能显示「这一天没有记录」。
//   3) **生成前必须确认费用**由界面负责（控制器只执行）：一次生成会发多次检索与模型调用，
//      当天已有成功版本时确认框额外说明「这是再一次生成」。
//   4) **失败不清空已有版本**。生成失败时页面保留上一次成功版本与它的条目，只在顶部显示
//      失败原因（架构 4.4「取消/失败保留上次成功版本」）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/application/ai_task_providers.dart';
import 'package:flux/features/ai/application/model_manager.dart'
    show SettingsReader;
import 'package:flux/features/ai/domain/ai_message.dart';
import 'package:flux/features/articles/application/article_ports.dart'
    show articleCatalogProvider;
import 'package:flux/features/articles/application/article_ai_providers.dart'
    show summaryZoneProvider;

import 'news_run_providers.dart';
import 'news_run_service.dart';
import 'news_source_config.dart';
import 'news_source_providers.dart';

/// 今日页的状态。
final class NewsTodayState {
  /// 构造状态。
  const NewsTodayState({
    required this.localDate,
    this.today,
    this.recentDates = const <String>[],
    this.current,
    this.versions = const <NewsRunRecord>[],
    this.dates = const <NewsRunDateRef>[],
    this.stage,
    this.sites = const <NewsSiteFetchResult>[],
    this.plannedSites = const <NewsRequiredSite>[],
    this.clearedArticleIds = const <int>{},
    this.generating = false,
    this.cancelling = false,
    this.lastError,
  });

  /// 当前展示的本地日期。
  final String localDate;

  /// 设备时区下的「今天」日期键（近 7 天条带与「是否是历史」的判定基准）。
  ///
  /// 与 [localDate] 分开：用户翻到 9-01 时**今天仍然是 9-22**，用 [localDate] 当
  /// 「今天」会让「补看历史」看起来像「今天就是 9-01」。
  final String? today;

  /// 近 7 天的日期键（含今天，日期倒序），供顶部条带渲染。
  final List<String> recentDates;

  /// 当前展示版本（没有成功版本时为 null）。
  final NewsRunRecord? current;

  /// 该日期该时区的全部版本（版本号倒序）。
  final List<NewsRunRecord> versions;

  /// 有记录的「日期 + 时区」组合（日期倒序）。
  final List<NewsRunDateRef> dates;

  /// 生成中的当前阶段；不在生成时为 null。
  final NewsRunStage? stage;

  /// 本次生成**实时**到达的必访站结果（逐站进度）。
  ///
  /// 与版本记录里的 siteResults 的区别：这是运行中的即时状态，不依赖一次数据库往返。
  /// 生成结束后由版本记录接管（两者内容一致，但来源不同：前者是回调，后者是落库事实）。
  final List<NewsSiteFetchResult> sites;

  /// 本次生成**计划**访问的必访站（进度里显示「待获取」的那些）。
  ///
  /// 没有它的话，进度条只能显示「已经回来的站点」，用户在慢站卡住时会看到一片空白，
  /// 无法区分「还没轮到」「正在抓」「被跳过了」。
  final List<NewsRequiredSite> plannedSites;

  /// 被引用的本机文章里**正文已被清理**的那些 id（T039 的「原文已清理」说明）。
  ///
  /// 判据是「文章还在、正文没了」：架构 5.3 的清理只释放正文、保留身份与状态。因此
  /// 「正文为空的已存在文章」与「源只给了摘要」是两件事，前者要说明「原文已清理」。
  final Set<int> clearedArticleIds;

  /// 是否正在生成。
  final bool generating;

  /// 是否已请求取消（取消信号已发出、任务尚未收尾）。
  ///
  /// 单独一个状态而不是把 [generating] 直接置假：取消**不是瞬时**的（要等当前尝试
  /// 收到取消回调），提前把按钮切回「生成」会让用户在任务仍在跑时看到「没在生成」。
  final bool cancelling;

  /// 最近一次失败原因。
  final AppError? lastError;

  /// 当天是否已经有成功版本（决定确认框的措辞与「再次生成」提示）。
  bool get hasSuccessVersion => current != null;

  /// 可切换的历史版本数（多于一个时才显示版本切换）。
  bool get hasMultipleVersions => versions.length > 1;

  /// 该日期最新的一条记录（**不分状态**：失败/取消/中断也在其中）。
  ///
  /// 为什么与 [current]（成功版本）分开：用户需要知道「今天试过一次、失败了、原因是
  /// 配置缺失」，而 [current] 为 null 时只有这一条线索能说出来。
  NewsRunRecord? get latest => versions.isEmpty ? null : versions.first;

  /// 展示的日期是否就是今天。
  bool get isToday => today == null || today == localDate;

  /// 计划中的必访站里，还没有结果的那些（进度里显示为「待获取」）。
  List<NewsRequiredSite> get pendingSites {
    if (!generating) {
      return const <NewsRequiredSite>[];
    }
    final Set<String> done = <String>{
      for (final NewsSiteFetchResult site in sites) site.url,
    };
    return <NewsRequiredSite>[
      for (final NewsRequiredSite site in plannedSites)
        if (!done.contains(site.url)) site,
    ];
  }

  /// 当前版本的引用里，有多少条对应的本机正文已被清理。
  int get clearedCitationCount {
    final NewsRunRecord? record = current;
    if (record == null || clearedArticleIds.isEmpty) {
      return 0;
    }
    return <int>{
      for (final NewsMaterial material in record.materials)
        if (material.articleId case final int id)
          if (clearedArticleIds.contains(id)) id,
    }.length;
  }

  /// 当前版本所属时区（历史查询用它，避免用现在的设备时区）。
  String? get activeTimeZone =>
      current?.timeZone ?? (versions.isEmpty ? null : versions.first.timeZone);

  /// 复制并覆盖部分字段。
  NewsTodayState copyWith({
    String? localDate,
    String? today,
    List<String>? recentDates,
    NewsRunRecord? current,
    List<NewsRunRecord>? versions,
    List<NewsRunDateRef>? dates,
    NewsRunStage? stage,
    bool clearStage = false,
    List<NewsSiteFetchResult>? sites,
    List<NewsRequiredSite>? plannedSites,
    Set<int>? clearedArticleIds,
    bool? generating,
    bool? cancelling,
    AppError? lastError,
    bool clearError = false,
  }) => NewsTodayState(
    localDate: localDate ?? this.localDate,
    today: today ?? this.today,
    recentDates: recentDates ?? this.recentDates,
    current: current ?? this.current,
    versions: versions ?? this.versions,
    dates: dates ?? this.dates,
    stage: clearStage ? null : (stage ?? this.stage),
    sites: sites ?? this.sites,
    plannedSites: plannedSites ?? this.plannedSites,
    clearedArticleIds: clearedArticleIds ?? this.clearedArticleIds,
    generating: generating ?? this.generating,
    cancelling: cancelling ?? this.cancelling,
    lastError: clearError ? null : (lastError ?? this.lastError),
  );
}

/// 今日页控制器。
final class NewsTodayController extends AsyncNotifier<NewsTodayState> {
  /// 生成用的取消信号（用户点「取消」时触发）。
  AiCancellation? _cancellation;

  @override
  Future<NewsTodayState> build() async {
    final SessionLocalZone zone = ref.watch(summaryZoneProvider);
    final String today = localDateKey(
      zone.toLocal(ref.watch(aiTaskClockProvider).now()),
    );
    return _load(
      localDate: today,
      timeZone: zone.ianaName,
      today: today,
      recentDates: recentDateKeys(today),
    );
  }

  /// 切换展示日期（默认查「当前设备时区」下的记录，并在必要时回退到该日期的其它时区）。
  Future<void> selectDate(String localDate) async {
    final NewsTodayState? current = state.value;
    state = AsyncData<NewsTodayState>(
      (current ?? NewsTodayState(localDate: localDate)).copyWith(
        localDate: localDate,
        clearError: true,
      ),
    );
    state = AsyncData<NewsTodayState>(
      await _load(
        localDate: localDate,
        timeZone: ref.read(summaryZoneProvider).ianaName,
        today: current?.today,
        recentDates: current?.recentDates ?? recentDateKeys(localDate),
      ),
    );
  }

  /// 删除一个非当前的历史版本（T039 的版本管理）。
  ///
  /// 失败原因（当前版本不可删、版本不存在）原样透出到界面：把「不能删」渲染成
  /// 「删除成功」会让用户以为旧稿没了，下次打开又看到它。
  Future<Result<void>> deleteVersion(int version) async {
    final NewsTodayState? current = state.value;
    final String? timeZone = current?.activeTimeZone;
    if (current == null || timeZone == null) {
      return Err<void>(
        ValidationError(field: 'newsRun.version', reason: '当前没有可操作的历史版本'),
      );
    }
    final Result<void> deleted = await ref
        .read(newsRunStoreProvider)
        .deleteVersion(
          localDate: current.localDate,
          timeZone: timeZone,
          version: version,
        );
    if (deleted.isErr) {
      state = AsyncData<NewsTodayState>(
        current.copyWith(lastError: deleted.errorOrNull),
      );
      return deleted;
    }
    state = AsyncData<NewsTodayState>(
      await _load(
        localDate: current.localDate,
        timeZone: timeZone,
        today: current.today,
        recentDates: current.recentDates,
      ),
    );
    return okUnit();
  }

  /// 把某个历史版本切为当前展示版本（用户手动回退，架构 4.4 的版本切换）。
  Future<void> selectVersion(int version) async {
    final NewsTodayState? current = state.value;
    final String? timeZone = current?.activeTimeZone;
    if (current == null || timeZone == null) {
      return;
    }
    final Result<void> result = await ref
        .read(newsRunStoreProvider)
        .setCurrentVersion(
          localDate: current.localDate,
          timeZone: timeZone,
          version: version,
        );
    if (result.isErr) {
      state = AsyncData<NewsTodayState>(
        current.copyWith(lastError: result.errorOrNull),
      );
      return;
    }
    state = AsyncData<NewsTodayState>(
      await _load(localDate: current.localDate, timeZone: timeZone),
    );
  }

  /// 取消正在进行的生成。
  void cancel() {
    final AiCancellation? cancellation = _cancellation;
    if (cancellation == null || cancellation.isCancelled) {
      return;
    }
    cancellation.cancel(reason: '用户取消');
    final NewsTodayState? current = state.value;
    if (current != null) {
      state = AsyncData<NewsTodayState>(current.copyWith(cancelling: true));
    }
  }

  /// 生成当天（或当前所选日期）的新闻。
  Future<NewsRunOutcome?> generate() async {
    final NewsTodayState? existing = state.value;
    final SessionLocalZone zone = ref.read(summaryZoneProvider);
    final String date =
        existing?.localDate ??
        localDateKey(zone.toLocal(ref.read(aiTaskClockProvider).now()));
    state = AsyncData<NewsTodayState>(
      (existing ?? NewsTodayState(localDate: date)).copyWith(
        generating: true,
        cancelling: false,
        clearStage: true,
        clearError: true,
      ),
    );
    final AiCancellation cancellation = AiCancellation();
    _cancellation = cancellation;

    // 配置与总开关：与 T036 的设置页读同一份来源（组合 prompt、必访站、关键词、禁词）。
    final bool globalEnabled = await ref.read(newsGlobalEnabledProvider.future);
    final NewsPromptLanguage language = await ref.read(
      newsPromptLanguageProvider.future,
    );
    final Result<NewsConfigState> config = await ref
        .read(newsSourceConfigServiceProvider)
        .load(globalEnabled: globalEnabled, language: language);
    if (config.isErr) {
      _cancellation = null;
      state = AsyncData<NewsTodayState>(
        (state.value ?? NewsTodayState(localDate: date)).copyWith(
          generating: false,
          cancelling: false,
          lastError: config.errorOrNull,
        ),
      );
      return null;
    }

    // 计划中的必访站先显示出来（进度里「待获取」的那几个）：慢站卡住时用户能看出
    // 「还有两个没轮到」，而不是面对一片空白。
    final NewsConfigState resolved = config.valueOrNull!;
    state = AsyncData<NewsTodayState>(
      (state.value ?? NewsTodayState(localDate: date)).copyWith(
        sites: const <NewsSiteFetchResult>[],
        plannedSites: resolved.promptInput.enabledSites,
      ),
    );

    final NewsRunService service = await ref.read(
      newsRunServiceBuilderProvider,
    )(zone: zone, onStage: _onStage, onSiteResult: _onSiteResult);
    final NewsRunOutcome outcome = await service.run(
      NewsRunInput(
        taskId:
            'news-$date-${ref.read(aiTaskClockProvider).now().microsecondsSinceEpoch}',
        config: resolved,
        globalEnabled: globalEnabled,
        cancellation: cancellation,
        regenerate: existing?.hasSuccessVersion ?? false,
      ),
    );
    _cancellation = null;
    final NewsTodayState? beforeReload = state.value;
    final NewsTodayState reloaded = await _load(
      localDate: outcome.snapshot.localDate,
      timeZone: outcome.snapshot.deviceTimeZone,
      today: beforeReload?.today ?? date,
      recentDates: beforeReload?.recentDates,
    );
    state = AsyncData<NewsTodayState>(
      reloaded.copyWith(
        generating: false,
        cancelling: false,
        clearStage: true,
        sites: const <NewsSiteFetchResult>[],
        plannedSites: const <NewsRequiredSite>[],
        lastError: outcome.ok ? null : outcome.error,
        clearError: outcome.ok,
      ),
    );
    return outcome;
  }

  void _onStage(NewsRunStage stage) {
    final NewsTodayState? current = state.value;
    if (current == null) {
      return;
    }
    state = AsyncData<NewsTodayState>(current.copyWith(stage: stage));
  }

  void _onSiteResult(NewsSiteFetchResult result) {
    final NewsTodayState? current = state.value;
    if (current == null) {
      return;
    }
    state = AsyncData<NewsTodayState>(
      current.copyWith(sites: <NewsSiteFetchResult>[...current.sites, result]),
    );
  }

  /// 读某一天某时区的版本。
  ///
  /// [timeZone] 为 null 时表示「先用当前设备时区问一次，没记录再按日期索引找当时那个时区」
  /// （见 [NewsRunStore.listDateRefs] 的说明）。
  Future<NewsTodayState> _load({
    required String localDate,
    required String? timeZone,
    String? today,
    List<String>? recentDates,
  }) async {
    final NewsRunStore store = ref.read(newsRunStoreProvider);
    final Result<List<NewsRunDateRef>> refs = await store.listDateRefs();
    final List<NewsRunDateRef> dates = refs.isOk
        ? refs.valueOrNull!
        : const <NewsRunDateRef>[];
    String? zone = timeZone;
    if (zone == null) {
      // 该日期在历史里的实际时区（可能不止一个；取最新的那条）。
      for (final NewsRunDateRef ref in dates) {
        if (ref.localDate == localDate) {
          zone = ref.timeZone;
          break;
        }
      }
    }
    zone ??= ref.read(summaryZoneProvider).ianaName;
    final Result<List<NewsRunRecord>> versions = await store.loadVersions(
      localDate: localDate,
      timeZone: zone,
    );
    if (versions.isErr) {
      return NewsTodayState(
        localDate: localDate,
        today: today,
        recentDates: recentDates ?? recentDateKeys(localDate),
        dates: dates,
        lastError: versions.errorOrNull,
      );
    }
    final Result<NewsRunRecord?> current = await store.loadCurrent(
      localDate: localDate,
      timeZone: zone,
    );
    return NewsTodayState(
      localDate: localDate,
      today: today,
      recentDates: recentDates ?? recentDateKeys(localDate),
      current: current.isOk ? current.valueOrNull : null,
      versions: versions.valueOrNull!,
      dates: dates,
      clearedArticleIds: await _probeClearedArticles(
        current.isOk ? current.valueOrNull : null,
      ),
    );
  }

  /// 探测当前版本的引用里，哪些本机文章的正文已被清理（架构 5.3 的「只释放正文」）。
  ///
  /// 判据刻意**不是**「正文为空」：源只提供摘要的文章（`bodyCompleteness == summaryOnly`）
  /// 本来就没有正文，把它说成「原文已清理」是在指责一次并不存在的清理。真正的判据是
  /// 「源本应提供正文（完整性是 sourceBody/extracted）而正文为空」。
  ///
  /// 探测失败按「无法判断」处理（返回空集合，不显示说明）：把一次读取失败说成「原文已清理」
  /// 会让用户以为自己的内容被删了。
  Future<Set<int>> _probeClearedArticles(NewsRunRecord? record) async {
    if (record == null) {
      return const <int>{};
    }
    final Set<int> candidates = <int>{
      for (final NewsMaterial material in record.materials)
        if (material.articleId case final int id) id,
    };
    if (candidates.isEmpty) {
      return const <int>{};
    }
    final Set<int> cleared = <int>{};
    try {
      final ArticleCatalogStore catalog = ref.read(articleCatalogProvider);
      for (final int articleId in candidates) {
        final Result<ArticleListEntry?> entry = await catalog.findArticle(
          articleId,
        );
        if (entry.isErr || entry.valueOrNull == null) {
          // 文章确实不存在（例如被彻底删除）与「读取失败」都不在这里下结论。
          continue;
        }
        // 只对「本应存在正文」的行下结论：summaryOnly 是源只给了摘要（本来就没有正文），
        // unknown 是导入时判不出来。把这两种说成「原文已清理」都是在报告一次并未发生的清理。
        final BodyCompleteness completeness =
            entry.valueOrNull!.bodyCompleteness;
        if (completeness != BodyCompleteness.sourceBody &&
            completeness != BodyCompleteness.extracted) {
          continue;
        }
        final Result<String?> body = await catalog.readArticleBody(articleId);
        if (body.isOk &&
            (body.valueOrNull == null || body.valueOrNull!.isEmpty)) {
          cleared.add(articleId);
        }
      }
    } on Object {
      // 探测失败按「无法判断」处理（不显示说明，也不报错）：把它显示成「原文已清理」
      // 会让用户以为自己内容被删了，而这是一次读取问题。**刻意不在这里读诊断端口**：
      // 诊断端口本身可能也读不到，那样会让一次可选的说明变成一个页面级错误。
      return const <int>{};
    }
    return cleared;
  }
}

/// 近 [days] 天的日期键（含 [endDate]，倒序），供今日页顶部条带渲染。
///
/// 纯字符串到日期的往返（复用 [localDateKey]），**不读系统时区**：用 DateTime.parse
/// 再按 UTC 字段加减天数，因此「近 7 天」在设备跨时区时仍然是同一组日期键。
List<String> recentDateKeys(String endDate, {int days = 7}) {
  final DateTime? parsed = DateTime.tryParse(endDate);
  if (parsed == null || days <= 0) {
    return <String>[endDate];
  }
  final List<String> keys = <String>[];
  for (int i = 0; i < days; i++) {
    keys.add(
      localDateKey(DateTime.utc(parsed.year, parsed.month, parsed.day - i)),
    );
  }
  return List<String>.unmodifiable(keys);
}

/// 今日页状态 Provider。
final AsyncNotifierProvider<NewsTodayController, NewsTodayState>
newsTodayControllerProvider =
    AsyncNotifierProvider<NewsTodayController, NewsTodayState>(
      NewsTodayController.new,
    );

/// 今日页的费用确认需要读上限（SET-060）：用只读的设置端口，不给界面写入口。
final Provider<SettingsReader> newsSettingsReaderProvider =
    Provider<SettingsReader>(
      (Ref ref) => throw StateError(
        'newsSettingsReaderProvider 未被组合根覆盖：见 lib/app/app_providers.dart',
      ),
    );
