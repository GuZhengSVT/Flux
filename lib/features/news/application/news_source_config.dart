// 新闻来源配置的用例层（T036；SET-050–055、架构 4.4）。
//
// 这一层把「三个列表 + 必访站 + prompt 版本」拼成一个可保存、可核对的状态，并回答两个
// 界面必须如实显示的问题：
//
//   1) **当前用哪段 prompt 去请求**（[NewsConfigState.resolvePrompt]）：组合模式走
//      composeNewsPrompt，高级覆盖模式走用户文本 + 无条件附加的协议段；
//   2) **高级模式缺了什么**（[NewsPromptDiff]）：必访站逐站检查，缺哪几个就说哪几个。
//
// 「必访任务不静默消失」因此不是一条注释里的承诺：差异检查是**每次保存与切换模式时都跑**
// 的函数，而它返回的缺失站点列表直接驱动界面提示。
library;

import 'package:flux/core/core.dart';

/// 新闻来源配置的当前状态（界面据它渲染，用例据它组合 prompt）。
final class NewsConfigState {
  /// 构造状态。
  const NewsConfigState({
    required this.globalEnabled,
    required this.requiredSites,
    required this.keywords,
    required this.blockedQueryTerms,
    required this.excludedTopics,
    required this.mode,
    required this.taskInstruction,
    required this.outputSpec,
    required this.advancedPrompt,
    required this.versions,
    this.language = NewsPromptLanguage.chinese,
    this.loadFailure,
  });

  /// SET-050 的总开关。
  final bool globalEnabled;

  /// 必访问网站（SET-051）。
  final List<NewsRequiredSite> requiredSites;

  /// 搜索关键词（SET-052）。
  final List<String> keywords;

  /// 禁止发送的查询词（SET-053 之一）。
  final List<String> blockedQueryTerms;

  /// 排除的内容主题（SET-053 之二）。
  final List<String> excludedTopics;

  /// 总 prompt 模式（SET-055）。
  final NewsPromptMode mode;

  /// 任务说明（用户可改部分；空串表示用内置）。
  final String taskInstruction;

  /// 输出规范（用户可改部分，不含协议段；空串表示用内置）。
  final String outputSpec;

  /// 高级覆盖模式的总 prompt。
  final String advancedPrompt;

  /// prompt 版本列表（按版本号倒序）。
  final List<NewsPromptVersion> versions;

  /// 生成语言。
  final NewsPromptLanguage language;

  /// 读取失败的原因；非空表示当前显示的是保守初值而不是已保存配置。
  final AppError? loadFailure;

  /// 组装组合用的输入。
  NewsPromptInput get promptInput => NewsPromptInput(
    language: language,
    taskInstruction: taskInstruction,
    outputSpec: outputSpec,
    requiredSites: requiredSites,
    keywords: keywords,
    blockedQueryTerms: blockedQueryTerms,
    excludedTopics: excludedTopics,
  );

  /// 组合结果（界面展示「组合后是什么样」）。
  ComposedNewsPrompt get composed => composeNewsPrompt(promptInput);

  /// **实际会发给模型的 prompt**（两种模式在此汇合，协议段永远在）。
  String get resolvedPrompt => resolveNewsPrompt(
    mode: mode,
    input: promptInput,
    advancedPrompt: advancedPrompt,
  );

  /// 高级覆盖模式的差异（组合模式下返回无警告的结果）。
  NewsPromptDiff get diff => mode == NewsPromptMode.advancedOverride
      ? newsPromptDiff(
          advancedPrompt: advancedPrompt,
          requiredSites: requiredSites,
        )
      : const NewsPromptDiff(
          missingSites: <NewsRequiredSite>[],
          hasCitationProtocol: true,
        );

  /// 当前生效的任务说明（用户值优先）。
  String get effectiveTaskInstruction => promptInput.effectiveTaskInstruction;

  /// 当前生效的输出规范（用户值优先，**不含协议段**）。
  String get effectiveOutputSpec => promptInput.effectiveOutputSpec;

  /// 当前协议段。
  String get citationProtocol => newsCitationProtocol(language);

  /// 逐源开关之外的选材规则：查询是否会被发出去。
  List<String> get effectiveQueries => buildNewsSearchQueries(
    keywords: keywords,
    blockedQueryTerms: blockedQueryTerms,
  );

  /// 复制并覆盖部分字段。
  NewsConfigState copyWith({
    bool? globalEnabled,
    List<NewsRequiredSite>? requiredSites,
    List<String>? keywords,
    List<String>? blockedQueryTerms,
    List<String>? excludedTopics,
    NewsPromptMode? mode,
    String? taskInstruction,
    String? outputSpec,
    String? advancedPrompt,
    List<NewsPromptVersion>? versions,
    NewsPromptLanguage? language,
    AppError? loadFailure,
    bool clearLoadFailure = false,
  }) => NewsConfigState(
    globalEnabled: globalEnabled ?? this.globalEnabled,
    requiredSites: requiredSites ?? this.requiredSites,
    keywords: keywords ?? this.keywords,
    blockedQueryTerms: blockedQueryTerms ?? this.blockedQueryTerms,
    excludedTopics: excludedTopics ?? this.excludedTopics,
    mode: mode ?? this.mode,
    taskInstruction: taskInstruction ?? this.taskInstruction,
    outputSpec: outputSpec ?? this.outputSpec,
    advancedPrompt: advancedPrompt ?? this.advancedPrompt,
    versions: versions ?? this.versions,
    language: language ?? this.language,
    loadFailure: clearLoadFailure ? null : (loadFailure ?? this.loadFailure),
  );

  /// 保守初值：读取未完成/失败时用它渲染（**不是**「已保存的配置」）。
  static NewsConfigState initial({
    NewsPromptLanguage language = NewsPromptLanguage.chinese,
    AppError? loadFailure,
  }) => NewsConfigState(
    globalEnabled: true,
    requiredSites: const <NewsRequiredSite>[],
    keywords: const <String>[],
    blockedQueryTerms: const <String>[],
    excludedTopics: const <String>[],
    mode: NewsPromptMode.composed,
    taskInstruction: '',
    outputSpec: '',
    advancedPrompt: '',
    versions: const <NewsPromptVersion>[],
    language: language,
    loadFailure: loadFailure,
  );
}

/// 一次保存 prompt 的结果。
final class NewsPromptSaveOutcome {
  /// 构造结果。
  const NewsPromptSaveOutcome({this.version, this.error});

  /// 保存成功后的新版本。
  final NewsPromptVersion? version;

  /// 失败原因。
  final AppError? error;

  /// 是否成功。
  bool get ok => version != null;
}

/// 新闻来源配置的用例。
final class NewsSourceConfigService {
  /// 构造用例。
  const NewsSourceConfigService({required this.store, required this.clock});

  /// 存储端口。
  final NewsSourceConfigStore store;

  /// 时钟（版本时间）。
  final Clock clock;

  /// 读取全部配置。
  ///
  /// 任意一项读失败都**返回失败**而不是「用默认值继续」：这不是一次可容忍的降级——把读
  /// 失败显示成空列表会让用户以为自己的必访站被清空了，进而「重新填一遍」。
  Future<Result<NewsConfigState>> load({
    required bool globalEnabled,
    NewsPromptLanguage language = NewsPromptLanguage.chinese,
  }) async {
    final Result<List<NewsRequiredSite>> sites = await store
        .loadRequiredSites();
    if (sites.isErr) {
      return Err<NewsConfigState>(sites.errorOrNull!);
    }
    final Result<List<String>> keywords = await store.loadList(
      NewsListCategory.keywords,
    );
    if (keywords.isErr) {
      return Err<NewsConfigState>(keywords.errorOrNull!);
    }
    final Result<List<String>> blocked = await store.loadList(
      NewsListCategory.blockedQueryTerms,
    );
    if (blocked.isErr) {
      return Err<NewsConfigState>(blocked.errorOrNull!);
    }
    final Result<List<String>> topics = await store.loadList(
      NewsListCategory.excludedTopics,
    );
    if (topics.isErr) {
      return Err<NewsConfigState>(topics.errorOrNull!);
    }
    final Result<List<NewsPromptVersion>> versions = await store
        .loadPromptVersions(language.code);
    if (versions.isErr) {
      return Err<NewsConfigState>(versions.errorOrNull!);
    }
    final List<NewsPromptVersion> history = versions.valueOrNull!;
    // 最新一版就是当前配置；没有历史时用内置模板（空串 = 用内置）。
    final NewsPromptVersion? latest = history.isEmpty ? null : history.first;
    return Ok<NewsConfigState>(
      NewsConfigState(
        globalEnabled: globalEnabled,
        requiredSites: sites.valueOrNull!,
        keywords: keywords.valueOrNull!,
        blockedQueryTerms: blocked.valueOrNull!,
        excludedTopics: topics.valueOrNull!,
        mode: latest?.mode ?? NewsPromptMode.composed,
        taskInstruction: latest?.taskInstruction ?? '',
        outputSpec: latest?.outputSpec ?? '',
        advancedPrompt: latest?.advancedPrompt ?? '',
        versions: history,
        language: language,
      ),
    );
  }

  /// 保存一个 prompt 新版本（SET-055「每次保存新版本，可回退」）。
  ///
  /// 版本号按现有最大值 +1 计算；版本列表由调用方从 [load] 得到。
  Future<NewsPromptSaveOutcome> savePromptVersion({
    required NewsConfigState state,
    required NewsPromptMode mode,
    required String taskInstruction,
    required String outputSpec,
    required String advancedPrompt,
    String? note,
  }) async {
    final NewsPromptVersion version = NewsPromptVersion(
      version: nextNewsPromptVersion(state.versions),
      mode: mode,
      taskInstruction: taskInstruction.trim(),
      outputSpec: outputSpec.trim(),
      advancedPrompt: advancedPrompt.trim(),
      createdAt: clock.now(),
      language: state.language,
      note: note,
    );
    final Result<NewsPromptVersion> saved = await store.savePromptVersion(
      version,
    );
    if (saved.isErr) {
      return NewsPromptSaveOutcome(error: saved.errorOrNull);
    }
    return NewsPromptSaveOutcome(version: version);
  }

  /// 版本列表加进一个新版本（界面本地更新，避免为一次保存重读全部）。
  static List<NewsPromptVersion> withVersion(
    List<NewsPromptVersion> existing,
    NewsPromptVersion version,
  ) => <NewsPromptVersion>[version, ...existing];
}
