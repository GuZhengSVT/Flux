// 正文阅读页（T019）：受控文档渲染 + 目录 + 上下篇 + 页内查找 + 完整性行。
//
// 范围与边界（本页明确不做的事）：
//   * **正文来源**：T013 把清洗后的受控文档导出成**纯文本**入库（见 feed_import_builder：
//     正文哈希需要「标签属性与空白变化不算修订」这样的稳定判据）。因此阅读器对这段文本
//     再走一次 Markdown → 受控文档树的解析——同一条渲染管线，T020 的选区/复制接口不必为
//     两套来源各写一遍。落库的是文本，画出的是受控节点，中间没有 HTML 字符串。
//   * **图片**（T020）：受 SET-012 控制是否自动加载；点击打开查看器（全屏/缩放/Esc），
//     可从查看器保存到系统选择的位置。缓存、可控 MIME 与解码限额属 T021。
//   * **外链**（T020）：点击先出面板显示完整地址 + 复制/打开；打开交给系统默认浏览器。
//     协议校验复用渲染层的 isSafeDocUrl（不在这里另写一套判断）。
//   * **选区**（T020）：正文包在 SelectionArea 里（桌面单块选择 + 系统菜单），另提供
//     「复制全文」与选区的「解释」入口。解释本身属 T034，本轮只做入口与提示，不发起调用。
//   * **目录只取 h1–h3**，桌面宽窗（>=1100，架构第 7 节三栏断点）显示，窄窗不显示。
//   * **上下篇依据进入时的筛选/排序快照**（架构 4.1），不按当前筛选现算。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';
import 'package:flux/core/design/design_tokens.dart';
import 'package:flux/features/ai/application/ai_availability.dart';
import 'package:flux/features/ai/application/model_manager_controller.dart';
import 'package:flux/features/ai/application/vision_ports.dart';
import 'package:flux/features/ai/application/visual_router.dart';
import 'package:flux/features/ai/domain/ai_model.dart';
import 'package:flux/features/ai/domain/ai_message.dart';
import 'package:flux/features/ai/domain/vision_consent.dart';
import 'package:flux/features/ai/domain/vision_routing.dart';
import 'package:flux/features/feeds/application/feed_ports.dart';
import 'package:flux/features/settings/application/settings_controller.dart';
import 'package:flux/features/settings/application/settings_navigation.dart';
import 'package:flux/features/settings/application/settings_store.dart';
import 'package:flux/features/statistics/application/reading_session_tracker.dart';
import 'package:flux/features/statistics/application/reading_stats_ports.dart';
import 'package:flux/features/statistics/presentation/session_interaction_listener.dart';
import 'package:flux/l10n/l10n.dart';
import 'package:flux/ui/ui.dart';

import '../application/article_ports.dart';
import '../application/article_extraction_ports.dart';
import '../application/fetch_original_article.dart';
import '../application/article_platform_ports.dart';
import '../application/article_state.dart';
import '../application/article_text_actions.dart';
import '../application/article_ai_providers.dart';
import '../application/article_ai_text_tasks.dart';
import '../application/article_translation_providers.dart';
import '../application/article_translation_tasks.dart';
import '../application/article_vision_analysis.dart';
import '../application/reader_outline.dart';
import '../domain/markdown_to_document.dart';
import 'article_list_controller.dart';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter/services.dart';

import 'reader/link_panel.dart';
import 'reader/doc_renderer.dart';
import 'reader/doc_theme.dart';
import 'reader/reader_chrome.dart';
import 'translation_panel.dart';

/// 正文阅读页。
class ArticleDetailPage extends ConsumerStatefulWidget {
  /// 构造页面。
  const ArticleDetailPage({
    required this.articleId,
    super.key,
    this.initialTitle,
    this.snapshot,
  });

  /// 文章 id。
  final int articleId;

  /// 列表已有的标题（先渲染出来，避免打开瞬间出现一块空白）。
  final String? initialTitle;

  /// 进入时的筛选/排序快照（上下篇依据它，架构 4.1）。
  ///
  /// 为 null 时上下篇**不可用并在页面上说明**，而不是按当前筛选现算：现算会让「下一篇」
  /// 落到一篇与用户进来时无关的文章上（筛选在阅读期间可能已经变了）。
  final ReaderSnapshot? snapshot;

  @override
  ConsumerState<ArticleDetailPage> createState() => _ArticleDetailPageState();
}

class _ArticleDetailPageState extends ConsumerState<ArticleDetailPage>
    with WidgetsBindingObserver {
  /// 阅读会话追踪（T023）。null 表示本次打开还没有开始追踪（或追踪不可用）。
  ///
  /// 生命周期绑定在**这个页面**上：会话的语义是「这一次阅读」，页面销毁即结束。
  /// 因此不需要一个全局单例，也不需要担心两个页面同时计数——一次只会有一个详情页
  /// 处于前台。
  ReadingSessionTracker? _sessionTracker;

  /// 秒级心跳（驱动空闲判定与周期落库）。
  Timer? _sessionHeartbeat;

  ArticleListEntry? _entry;
  DocDocument? _document;

  /// 已保存的提取正文（T024）。null 表示这篇文章还没有提取过。
  ExtractedArticleBody? _extraction;

  /// 当前显示的是提取正文还是源正文。
  ///
  /// 默认显示**源正文**：获取全文是用户主动请求的动作，但「换掉我原本在读的东西」
  /// 不该是它的默认后果。用户点一下切换才看提取版（两份都保留，可来回切）。
  bool _showExtracted = false;

  /// 正在获取原站全文。
  bool _fetchingOriginal = false;

  /// 最近一次获取的结果提示（成功/付费墙/过短/失败）。
  String? _fetchNotice;

  /// 最近一次失败的原因（用于显示外开入口）。
  AppError? _fetchError;

  int? _activeOutlineBlock;
  AppError? _error;
  bool _loading = true;
  bool _findOpen = false;
  String _findQuery = '';
  bool _autoLoadImages = true;
  final TextEditingController _findController = TextEditingController();
  final GlobalKey _selectionAreaKey = GlobalKey();

  /// 当前选中的文本。
  ///
  /// 用 ValueNotifier 而不是一个普通字段：选区菜单的构建发生在 SelectionArea 的闭包里，
  /// 它需要读到**最新**的选区。一个 setState 驱动的字段也能工作，但那会让每次拖动选区
  /// 都重建整篇正文（拖动是连续事件）；ValueNotifier 让读取与正文重建解耦。
  final ValueNotifier<String> _selection = ValueNotifier<String>('');

  /// 正在进行/已完成的图像分析状态（T033）。null 表示没有面板。
  VisionPanelState? _visionPanel;

  /// 进行中的图像分析取消信号；非空表示正在跑。
  AiCancellation? _visionCancellation;

  /// AI 摘要面板状态（T034）。null 表示没有面板。
  AiSummaryState? _summary;

  /// 选词解释浮层状态（T034）。null 表示没有浮层。
  SelectionExplainState? _explanation;

  /// 当前文章的源正文（摘要与解释都用它作为材料）。
  ///
  /// 名字里带 source：页面上还有一个 `_body(l10n)` 方法负责构建正文视图，同名会让
  /// 「读源码正文」在调用点变得歧义（Dart 里字段会遮蔽同名方法）。
  String? _sourceBody;

  /// 已存在的 AI 摘要（打开文章时读一次）。
  AiSummaryRecord? _savedAiSummary;

  /// 翻译面板状态（T035）。null 表示没有面板。
  TranslationPanelState? _translation;

  /// 已保存的译文（按目标语言；打开文章时读一次）。
  ArticleTranslation? _savedTranslation;

  /// 当前是否显示译文（false = 显示原文；切换**不删任何一份**）。
  bool _showTranslation = false;

  /// 当前译文对应的源正文摘要（用于判断是否已过期）。
  String? _translationSourceDigest;

  /// 本次会话解析出的翻译目标语言（SET-011；打开文章时读一次）。
  String? _resolvedTargetLanguage;

  /// 每个顶层块的位置 key（目录跳转用）。
  List<GlobalKey> _blockKeys = <GlobalKey>[];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(_loadImageSetting());
    // 读一份可能已存在的提取正文（只读，不抓取）。
    unawaited(_loadExtraction());
    // 会话追踪：详情页是「一次阅读」的唯一入口，因此开始/结束都挂在这里。
    unawaited(_startSessionTracking());
    WidgetsBinding.instance.addObserver(this);
  }

  /// 读已保存的提取正文（T024）。
  ///
  /// 只读不抓：**打开文章不会触发任何网络请求**。抓取只发生在用户点「获取原站全文」
  /// 的那一刻（架构 4.2 的「无自动/后台/批量」）。
  Future<void> _loadExtraction() async {
    final Result<ExtractedArticleBody?> saved = await ref
        .read(articleExtractionProvider)
        .readExtraction(widget.articleId);
    if (!mounted) {
      return;
    }
    setState(() => _extraction = saved.valueOrNull);
  }

  /// 用户点击「获取原站全文」。
  ///
  /// 这是**唯一**会发起网页请求的入口。失败不改动任何已存正文（架构 4.2），提示里
  /// 始终带一个「在浏览器打开」的出口。
  Future<void> _fetchOriginal() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? sourceUrl = _entry?.sourceUrl;
    setState(() {
      _fetchingOriginal = true;
      _fetchNotice = null;
      _fetchError = null;
    });
    final Result<FetchOriginalResult> result = await ref
        .read(fetchOriginalArticleProvider)
        .call(articleId: widget.articleId, sourceUrl: sourceUrl);
    if (!mounted) {
      return;
    }
    if (result.isErr) {
      setState(() {
        _fetchingOriginal = false;
        _fetchError = result.errorOrNull;
      });
      return;
    }
    final FetchOriginalResult outcome = result.unwrap();
    final List<String> notes = <String>[];
    switch (outcome.outcome) {
      case FetchOriginalOutcome.ok:
        notes.add(
          l10n.readingFetchFullTextDone(outcome.extraction!.text.length),
        );
        // 付费墙与「正文过短」是**提示**：抓到的东西已经保存了，但用户要知道它可能
        // 不完整，或者原站本来就需要登录。
        if (outcome.paywallHint) {
          notes.add(l10n.readingFetchFullTextPaywall);
        }
      case FetchOriginalOutcome.noContent:
        notes.add(l10n.readingFetchFullTextShort);
        if (outcome.paywallHint) {
          notes.add(l10n.readingFetchFullTextPaywall);
        }
      case FetchOriginalOutcome.failed:
        notes.add(
          l10n.readingFetchFullTextFailed(
            outcome.error?.message ?? l10n.readingFetchFullTextNoUrl,
          ),
        );
    }
    await _loadExtraction();
    if (!mounted) {
      return;
    }
    setState(() {
      _fetchingOriginal = false;
      _fetchNotice = notes.join('\n');
      _fetchError = outcome.error;
      // 成功时自动切到提取正文：用户刚要的就是它。失败时不动当前显示。
      if (outcome.outcome == FetchOriginalOutcome.ok) {
        _showExtracted = true;
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 失焦/锁屏/后台一律暂停累计（架构 5.3）。inactive 在 macOS 上会在窗口失去焦点时
    // 触发，而 paused/hidden 覆盖锁屏与后台；三者都按「不可见」处理。
    switch (state) {
      case AppLifecycleState.resumed:
        _sessionTracker?.onVisibilityChanged(true);
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _sessionTracker?.onVisibilityChanged(false);
    }
  }

  /// 开始记录本次阅读（T023）。
  ///
  /// 页面一出现就开始，不等正文加载完成：「打开详情页并看着它」正是架构所说的前台可见
  /// 且活跃状态。SET-015 关闭时 tracker 内部不会累计任何时间，也不需要在这里分支。
  Future<void> _startSessionTracking() async {
    final ReadingSessionTracker tracker = ReadingSessionTracker(
      articleId: widget.articleId,
      stats: ref.read(readingStatsProvider),
      settings: ref.read(settingsStoreProvider),
      clock: ref.read(statsClockProvider),
      zone: ref.read(sessionZoneProvider),
      diagnostics: ref.read(diagnosticSinkProvider),
    );
    _sessionTracker = tracker;
    await tracker.start();
    if (!mounted) {
      return;
    }
    // 心跳间隔取 1 秒：空闲阈值最小是 1 分钟，1 秒的粒度足以在阈值到达时就停住；
    // 周期落库由 tracker 自己按 flushInterval（30 秒）判断，因此这个定时器只是
    // 「叫醒它」——它不做任何计时决策。
    _sessionHeartbeat = Timer.periodic(const Duration(seconds: 1), (Timer _) {
      unawaited(_sessionTracker?.tick() ?? Future<void>.value());
    });
  }

  /// 读取 SET-012（是否自动加载远程图片）。
  ///
  /// 默认按**开**渲染（与设置注册表的默认值一致）：读设置是一次异步往返，先按「不加载」
  /// 渲染会在图片本该出现的地方闪一下占位框，而绝大多数用户的设置就是开。
  Future<void> _loadImageSetting() async {
    final Result<Object?> value = await ref
        .read(settingsStoreProvider)
        .readSetting(SettingId.set012);
    if (!mounted) {
      return;
    }
    final Object? raw = value.valueOrNull;
    setState(() {
      _autoLoadImages = raw is bool
          ? raw
          : SettingRegistry.findById(SettingId.set012)?.defaultValue == true;
    });
  }

  @override
  void dispose() {
    _findController.dispose();
    _scrollController.dispose();
    _selection.dispose();
    _sessionHeartbeat?.cancel();
    // stop() 是异步的（要落库），而 dispose 不能 await。这里 fire-and-forget：
    // tracker 的写入走自己的端口，不依赖本页面的 element 树，因此在页面销毁后仍然
    // 能完成。丢掉这一次收尾的后果也只是「最后一段要在下一次 flush 时才落库」——
    // 而周期 flush 已经把绝大部分时间写进去了。
    unawaited(_sessionTracker?.stop() ?? Future<void>.value());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 提取正文在界面上的文档表示（每次读时解析：提取正文比源正文小得多，
  /// 而缓存两份文档只会让「切换后忘了同步」成为一个可能的缺陷）。
  DocDocument? get _extractedDocument {
    final ExtractedArticleBody? extraction = _extraction;
    if (extraction == null || extraction.body.trim().isEmpty) {
      return null;
    }
    return parseMarkdownToDocument(extraction.body);
  }

  /// 当前实际显示的文档（源正文或提取正文）。
  ///
  /// 两份**都保留**：切换只是改显示，不删任何东西，用户可以随时切回原文对照
  /// （架构 4.2 的「失败保留原内容」与「原文始终保留」）。
  DocDocument? get _displayDocument {
    final DocDocument? base = _showExtracted
        ? (_extractedDocument ?? _document)
        : _document;
    if (!_showTranslation || base == null) {
      return base;
    }
    final ArticleTranslation? translation = _savedTranslation;
    if (translation == null) {
      return base;
    }
    // 译文按段落回填到**同一棵**文档树：未翻译或失败的段显示原文（架构 4.2）。
    // 回填是渲染期的一次纯函数调用，源正文与译文存储都不因此改动。
    return applyTranslation(base, translation);
  }

  /// 当前译文是否与正文不同步（界面据此标注「对应上一版正文」）。
  bool get _translationStale {
    final ArticleTranslation? translation = _savedTranslation;
    final String? digest = _translationSourceDigest;
    return translation != null &&
        digest != null &&
        translation.isStaleFor(digest);
  }

  /// 目标语言的显示名（SET-011 的 translationTarget 由设置读出）。
  ///
  /// 读不到设置时按注册表默认（简体中文）显示：这不是「猜语言」，而是与 SET 默认值
  /// 完全一致的显示——真正的目标语言由翻译调用时的设置值决定。
  String get _targetLanguageLabel {
    final TranslationLanguage? language = TranslationLanguage.fromCode(
      _translationTargetLanguage,
    );
    return language?.displayName ?? TranslationLanguage.chinese.displayName;
  }

  /// 本次会话读到的目标语言（打开文章时由 translationSettingsProvider 填入）。
  String get _translationTargetLanguage =>
      _resolvedTargetLanguage ?? TranslationLanguage.chinese.code;

  /// 译文生成时间的显示文本（YYYY-MM-DD；无译文时为空串）。
  String get _translationDateLabel {
    final DateTime? at = _savedTranslation?.createdAt;
    if (at == null) {
      return '';
    }
    final DateTime utc = at.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')}';
  }

  List<ReaderOutlineEntry> get _outline => _displayDocument == null
      ? const <ReaderOutlineEntry>[]
      : extractOutline(_displayDocument!);

  int get _matchCount => _displayDocument == null || _findQuery.isEmpty
      ? 0
      : DocDocumentView.countMatches(_displayDocument!, _findQuery);

  Future<void> _load() async {
    final ArticleCatalogStore store = ref.read(articleCatalogProvider);
    final Result<ArticleListEntry?> found = await store.findArticle(
      widget.articleId,
    );
    if (!mounted) {
      return;
    }
    if (found.isErr) {
      setState(() {
        _error = found.errorOrNull;
        _loading = false;
      });
      return;
    }
    final ArticleListEntry? entry = found.valueOrNull;
    final Result<String?> body = entry == null
        ? const Ok<String?>(null)
        : await store.readArticleBody(entry.id);
    if (!mounted) {
      return;
    }
    final String? raw = body.valueOrNull;
    // 空正文保持 null 而不是解析成空文档：两者的界面含义不同——「没有正文」要说明
    // 「源只提供了摘要」，而「解析出空文档」看起来像渲染失败。
    final DocDocument? document = raw == null || raw.trim().isEmpty
        ? null
        : parseMarkdownToDocument(raw);
    // 已存在的 AI 摘要（T034）：只读一次，供摘要面板与「AI 摘要」标注使用。
    final Result<AiSummaryRecord?> savedAiSummary = entry == null
        ? const Ok<AiSummaryRecord?>(null)
        : await store.readAiSummary(entry.id);
    // 已存在的译文（T035）：按当前目标语言只读一次。读不到目标语言时**不读译文**
    // （而不是随便挑一份），否则用户会看到一份语言不对的译文而没有线索。
    final TranslationSettings translationSettings = await ref.read(
      translationSettingsProvider.future,
    );
    _resolvedTargetLanguage = translationSettings.targetLanguage;
    final ArticleTranslationStore translations = ref.read(
      articleTranslationStoreProvider,
    );
    final Result<ArticleTranslation?> savedTranslation = entry == null
        ? const Ok<ArticleTranslation?>(null)
        : await translations.find(
            articleId: entry.id,
            targetLanguage: translationSettings.targetLanguage,
          );
    if (!mounted) {
      return;
    }
    setState(() {
      _entry = entry;
      _document = document;
      _sourceBody = raw;
      _savedAiSummary = savedAiSummary.valueOrNull;
      _savedTranslation = savedTranslation.valueOrNull;
      _translationSourceDigest = raw == null || raw.trim().isEmpty
          ? null
          : translationDigestOf(raw);
      _loading = false;
      _blockKeys = List<GlobalKey>.generate(
        document?.children.length ?? 0,
        (int _) => GlobalKey(),
      );
    });

    if (entry == null) {
      return;
    }

    // SET-010：成功显示正文后，unread → read；later 与 read 不动。
    final bool autoMark = await ref.read(autoMarkReadProvider.future);
    if (!mounted) {
      return;
    }
    final Result<ArticleStateChange> change = await MarkReadOnOpenUseCase(
      articles: store,
    )(articleId: widget.articleId, autoMarkEnabled: autoMark);
    if (!mounted || change.isErr) {
      return;
    }
    if (change.unwrap().changed) {
      // 列表面向「未读」筛选，因此状态变化后需要重读，让刚才那行从筛选结果里退出。
      await ref.read(articleListControllerProvider.notifier).reload();
    }
  }

  void _toggleFind() {
    setState(() {
      _findOpen = !_findOpen;
      if (!_findOpen) {
        // 关闭查找时清空查询：留着上一次的关键词会让下一次打开时正文仍处于高亮态，
        // 而用户已经忘了自己搜过什么。
        _findQuery = '';
        _findController.clear();
      }
    });
  }

  void _scrollToBlock(int blockIndex) {
    if (blockIndex < 0 || blockIndex >= _blockKeys.length) {
      return;
    }
    final BuildContext? target = _blockKeys[blockIndex].currentContext;
    if (target == null) {
      return;
    }
    Scrollable.ensureVisible(
      target,
      duration: FluxMotion.standard,
      alignment: 0.05,
    );
    setState(() => _activeOutlineBlock = blockIndex);
  }

  /// 打开快照里的相邻文章（替换当前页而不是压栈：连续翻篇不该把返回栈堆成一条长链）。
  Future<void> _navigateTo(int articleId) async {
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            ArticleDetailPage(articleId: articleId, snapshot: widget.snapshot),
      ),
    );
  }

  /// 复制全文：把受控文档压平成纯文本（读者要的是文字，不是渲染结构）。
  Future<void> _copyAllPlainText() async {
    // 复制的是**当前显示的**那一份：用户看到提取正文时复制原文会让他以为复制坏了。
    final DocDocument? document = _displayDocument;
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (document == null) {
      _notify(l10n.readingCopyAllEmpty);
      return;
    }
    final String text = articlePlainText(document);
    if (text.trim().isEmpty) {
      // 有文档但压平后为空（例如只剩一张没有替代文字的图）：如实说没有可复制的内容，
      // 而不是复制一个空字符串并提示「已复制」。
      _notify(l10n.readingCopyAllEmpty);
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    _notify(l10n.readingCopyAllDone(text.length));
  }

  /// 「摘要」按钮：为当前文章生成 AI 摘要（T034）。
  ///
  /// 三条行为与架构条文对应：
  ///   1) **不覆盖源摘要**：结果写 ai_summary 三列（仓储只写这三列），源摘要在；
  ///   2) **长文标截断**（SET-061）：面板说明「正文已截断」；
  ///   3) **取消不改原文**：取消只中止生成，正文一个字都不变。
  Future<void> _summarizeArticle() async {
    final AiSummaryState? current = _summary;
    if (current is AiSummaryRunning) {
      return;
    }
    final Result<List<AiModel>> models = await ref
        .read(modelManagerProvider)
        .loadEnabledModels();
    if (!mounted) {
      return;
    }
    if (models.isErr || models.valueOrNull!.isEmpty) {
      // 没有可用模型：走与「未配置 AI」同一条路径（提示 + 去设置），而不是发起一次注定
      // 失败的请求。
      await _showAiNotConfigured(
        AppLocalizations.of(context).readingSummaryNoModelBody,
      );
      return;
    }
    final AiCancellation cancellation = AiCancellation();
    setState(() => _summary = AiSummaryRunning(cancellation: cancellation));
    final ArticleSummaryOutcome outcome = await ref
        .read(articleSummaryServiceProvider)
        .summarize(
          taskId: 'article-summary-${widget.articleId}',
          body: _bodyText(),
          models: models.valueOrNull!,
          cancellation: cancellation,
        );
    if (!mounted) {
      return;
    }
    if (outcome.summary case final AiSummaryRecord record) {
      final Result<void> saved = await ref
          .read(articleCatalogProvider)
          .saveAiSummary(articleId: widget.articleId, summary: record);
      if (!mounted) {
        return;
      }
      setState(() {
        _summary = saved.isErr
            ? AiSummaryFailed(error: saved.errorOrNull!)
            : AiSummaryDone(record: record, truncated: outcome.truncated);
      });
      return;
    }
    setState(() {
      _summary = outcome.skippedReason != null
          ? const AiSummarySkipped()
          : AiSummaryFailed(error: outcome.error!);
    });
  }

  /// 取消进行中的摘要生成。
  void _cancelSummary() {
    final AiSummaryState? current = _summary;
    if (current is AiSummaryRunning) {
      current.cancellation.cancel(reason: 'userCancelled');
      // 取消**不改原文**，也不写库：只把面板收回。
      setState(() => _summary = null);
      _notify(AppLocalizations.of(context).readingSummaryCancelled);
    }
  }

  /// 「翻译」按钮：分段翻译当前正文（T035）。
  ///
  /// 五条与架构 4.2 对应的行为：
  ///   1) **summaryOnly 不提供全文翻译**：源只给了摘要时直接说明「仅摘要」，不把摘要
  ///      当成正文去翻（那是把一段摘要当全文，用户会以为读到了全文的译文）；
  ///   2) **逐段调用 + 进度**：面板显示已完成 x/y 段；
  ///   3) **取消保留已完成段**：取消后未完成的段显示原文；
  ///   4) **部分成功**：失败段可单独重试（_retryFailedTranslation），不重跑全部；
  ///   5) **原文永远保留**：只写译文结构，源正文列不动。
  Future<void> _translateArticle({Set<int>? onlyFailed}) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TranslationPanelState? current = _translation;
    if (current is TranslationRunning) {
      return;
    }
    // 架构 4.2：源只提供了摘要时不提供「全文翻译」。
    if (_entry?.bodyCompleteness == BodyCompleteness.summaryOnly) {
      setState(
        () => _translation = const TranslationSkipped(
          reason: TranslationSkipReason.summaryOnly,
        ),
      );
      return;
    }
    final DocDocument? document = _showExtracted
        ? (_extractedDocument ?? _document)
        : _document;
    if (document == null || _bodyText() == null) {
      setState(
        () => _translation = const TranslationSkipped(
          reason: TranslationSkipReason.noBody,
        ),
      );
      return;
    }
    final Result<List<AiModel>> models = await ref
        .read(modelManagerProvider)
        .loadEnabledModels();
    if (!mounted) {
      return;
    }
    if (models.isErr || models.valueOrNull!.isEmpty) {
      await _showAiNotConfigured(l10n.readingTranslateNoModelBody);
      return;
    }
    final TranslationSettings settings = await ref.read(
      translationSettingsProvider.future,
    );
    final AiCancellation cancellation = AiCancellation();
    setState(
      () => _translation = TranslationRunning(
        cancellation: cancellation,
        translated: onlyFailed == null
            ? 0
            : (_savedTranslation?.translatedCount ?? 0),
        failed: onlyFailed == null ? 0 : (_savedTranslation?.failedCount ?? 0),
        total: _savedTranslation?.totalCount ?? 0,
      ),
    );
    final String bodyText = _bodyText()!;
    final TranslationOutcome outcome = await ref
        .read(translationServiceProvider)
        .translate(
          articleId: widget.articleId,
          document: document,
          targetLanguage: settings.targetLanguage,
          models: models.valueOrNull!,
          sourceDigest: translationDigestOf(bodyText),
          sourceLength: bodyText.runes.length,
          existing: onlyFailed == null ? null : _savedTranslation,
          onlyFailed: onlyFailed,
          cancellation: cancellation,
          onProgress: (TranslationProgress progress) {
            if (!mounted) {
              return;
            }
            setState(
              () => _translation = TranslationRunning(
                cancellation: cancellation,
                translated: progress.translated,
                failed: progress.failed,
                total: progress.total,
              ),
            );
          },
        );
    if (!mounted) {
      return;
    }
    if (outcome.translation case final ArticleTranslation translation) {
      // 落库失败也**不**把译文面板变成失败：译文已经产出，用户可以看它；但界面只在
      // 写入成功后才说「已保存」，不谎报持久化。
      final Result<ArticleTranslation> saved = await ref
          .read(articleTranslationStoreProvider)
          .save(translation);
      if (!mounted) {
        return;
      }
      setState(() {
        _savedTranslation = saved.isOk
            ? saved.valueOrNull
            : _savedTranslation?.copyWith(segments: translation.segments);
        _showTranslation = true;
        _translation = TranslationFinished(
          translated: translation.translatedCount,
          failed: translation.failedCount,
          total: translation.totalCount,
          cancelled: outcome.cancelled,
          saveFailed: saved.isErr,
        );
      });
      return;
    }
    setState(() {
      _translation = outcome.error != null
          ? TranslationFailed(error: outcome.error!)
          : TranslationSkipped(
              reason: outcome.skippedReason ?? TranslationSkipReason.noBody,
            );
    });
  }

  /// 只重试失败的段（架构 4.2「只重试失败段」，不重跑全部）。
  Future<void> _retryFailedTranslation() async {
    final ArticleTranslation? translation = _savedTranslation;
    if (translation == null) {
      await _translateArticle();
      return;
    }
    final Set<int> failed = <int>{
      for (final TranslationSegment segment in translation.segments)
        if (segment.status == TranslationSegmentStatus.failed) segment.index,
    };
    if (failed.isEmpty) {
      return;
    }
    await _translateArticle(onlyFailed: failed);
  }

  /// 取消进行中的翻译（已完成段保留）。
  void _cancelTranslation() {
    final TranslationPanelState? current = _translation;
    if (current is TranslationRunning) {
      current.cancellation.cancel(reason: 'userCancelled');
      // 不写库、不改原文：面板保留已完成段的进度，让用户看到「取消发生在哪里」。
      setState(
        () => _translation = TranslationFinished(
          translated: current.translated,
          failed: current.failed,
          total: current.total,
          cancelled: true,
        ),
      );
      _notify(AppLocalizations.of(context).readingTranslateCancelled);
    }
  }

  /// 切换原文/译文（**原文始终保留**，切换只改变显示）。
  void _toggleTranslation() {
    setState(() => _showTranslation = !_showTranslation);
  }

  /// 当前显示用的正文文本（源正文或提取正文，与渲染那一份一致）。
  String? _bodyText() {
    if (_showExtracted) {
      final ExtractedArticleBody? extraction = _extraction;
      if (extraction != null) {
        return extraction.body;
      }
    }
    return _sourceBody;
  }

  /// 未配置 AI / 没有可用模型时的提示（含「去设置」）。
  Future<void> _showAiNotConfigured(String body) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.readingSelectionExplainNoAiTitle),
        content: Text(body),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.subscriptionClose),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              ref.read(settingsNavigationRequestProvider.notifier).request();
            },
            child: Text(l10n.readingSelectionExplainGoSettings),
          ),
        ],
      ),
    );
  }

  /// 选词解释：真实调用（T034；替换 T020 的「本轮只做入口」占位）。
  Future<void> _explainSelection(String selection) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final SelectionExplanationInput input = buildSelectionExplanationInput(
      plainText: _document == null ? '' : articlePlainText(_document!),
      selection: selection,
    );
    if (input.selection.isEmpty) {
      return;
    }
    final bool configured = await _hasAiCredential();
    if (!mounted) {
      return;
    }
    if (!configured) {
      await _showAiNotConfigured(l10n.readingSelectionExplainNoAiBody(1200));
      return;
    }
    final Result<List<AiModel>> models = await ref
        .read(modelManagerProvider)
        .loadEnabledModels();
    if (!mounted) {
      return;
    }
    if (models.isErr || models.valueOrNull!.isEmpty) {
      await _showAiNotConfigured(l10n.readingSummaryNoModelBody);
      return;
    }
    setState(
      () => _explanation = SelectionExplainRunning(
        selection: input.selection,
        cancellation: AiCancellation(),
      ),
    );
    final AiCancellation cancellation =
        (_explanation! as SelectionExplainRunning).cancellation;
    final SelectionExplainOutcome outcome = await ref
        .read(selectionExplainServiceProvider)
        .explain(
          taskId: 'article-explain-${widget.articleId}',
          plainText: _document == null ? '' : articlePlainText(_document!),
          selection: selection,
          models: models.valueOrNull!,
          cancellation: cancellation,
        );
    if (!mounted) {
      return;
    }
    // 失败与取消**都不改动正文**（架构 4.2）：结果只落在这个浮层里。
    setState(() {
      _explanation = outcome.ok
          ? SelectionExplainDone(
              selection: input.selection,
              text: outcome.text!,
              contextTruncated: outcome.contextTruncated,
              sentCharacters: outcome.sentCharacters,
            )
          : SelectionExplainFailed(
              selection: input.selection,
              error: outcome.error,
            );
    });
  }

  /// 关闭解释浮层（不改原文）。
  void _closeExplanation() {
    final SelectionExplainState? current = _explanation;
    if (current is SelectionExplainRunning) {
      current.cancellation.cancel(reason: 'userCancelled');
    }
    setState(() => _explanation = null);
  }

  /// AI 是否已配置。
  ///
  /// 走 [AiAvailability] 端口而不是自己在详情页里查 Keychain：完整的提供商/模型配置
  /// 属 T025/T030，而「能不能解释」这个判断在 T034 接上真实调用之后仍然要用同一份
  /// 答案，现在写死在这里会变成第二套判断。
  Future<bool> _hasAiCredential() async {
    try {
      return await ref.read(aiAvailabilityProvider).isConfigured();
    } on Exception {
      // 探针失败按「未配置」处理：解释入口是可选功能，探针异常不该让正文读不了。
      return false;
    }
  }

  /// 记录选区（供「解释」入口使用）。
  void _onSelectionChanged(SelectedContent? content) {
    _selection.value = content?.plainText ?? '';
  }

  /// 被拒绝的协议名（面板上显示「已拦截：xxx」）。
  ///
  /// 与渲染层用同一条判据 [isSafeDocUrl]，因此两处不会对同一个地址给出不同结论。
  /// 取协议名的目的是让提示**具体**：只说「已拦截」会让用户以为是网络问题。
  static String _blockedScheme(String url) {
    final int colon = url.indexOf(':');
    if (colon <= 0) {
      return url;
    }
    return url.substring(0, colon);
  }

  /// 打开链接面板（先显示地址，再决定复制或打开）。
  ///
  /// 安全判定在这里做**最后一次**（渲染层已经拒绝过的链接根本不会走到这里，因为被拒绝
  /// 的链接渲染成不可点的文本）。这次判定的意义是兜底：地址可能来自渲染之外的路径
  /// （将来的「原文链接」按钮、分享面板），而把一个 file: 交给系统启动器就不再受本应用
  /// 控制了。
  Future<void> _openLinkPanel(String url) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool safe = isSafeDocUrl(url);
    final LinkPanelResult? result = await showDialog<LinkPanelResult>(
      context: context,
      builder: (BuildContext context) =>
          LinkPanel(url: url, blockedReason: safe ? null : _blockedScheme(url)),
    );
    if (result == null || !mounted) {
      return;
    }
    switch (result.action) {
      case LinkPanelAction.copy:
        await Clipboard.setData(ClipboardData(text: result.url));
        if (mounted) {
          _notify(l10n.readingLinkCopied);
        }
      case LinkPanelAction.open:
        final Result<bool> opened = await ref
            .read(externalLinkOpenerProvider)
            .openExternal(result.url);
        if (!mounted) {
          return;
        }
        if (opened.isErr) {
          _notify(l10n.readingLinkOpenFailed(opened.errorOrNull!.message));
        }
    }
  }

  /// 打开图片查看器。
  ///
  /// 保存与分享回调**闭包捕获详情页的 ref/context**，因此提示条落在详情页上：查看器是
  /// 一个独立的页面，它的 ScaffoldMessenger 会随它一起销毁，把「已保存到 …」显示在即将
  /// 消失的页面上，用户看不到。
  Future<void> _openImageViewer(String url, String alt) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => ImageViewerPage(
          url: url,
          alt: alt,
          onSave: () => _saveImage(url),
          onShare: () => _shareText(url),
          // T033：分析入口在查看器上，结果落在详情页的底部面板。
          onAnalyze: () async {
            Navigator.of(context).maybePop();
            await _analyzeImage(url, alt);
          },
        ),
      ),
    );
  }

  /// 「分析这张图」（T033）。
  ///
  /// 三条与架构条文对应的行为：
  ///   1) **首次发送前告知**：链路返回 needsConsent 时弹对话框说明「图像将发送至 <端点>」，
  ///      用户确认后带 VisionSendConfirmation 重跑一次，并把确认记录落本机（架构第 8 节）；
  ///   2) **没有视觉模型时跳过而不失败**：面板显示明确的跳过说明，正文与其它功能不受影响；
  ///   3) **取消不改原文**：取消只中止分析，面板给出「已取消」并保留原样。
  Future<void> _analyzeImage(String url, String alt) async {
    final String ref = _visionRefFor(url);
    final ArticleVisionAnalyzer analyzer = _visionAnalyzer();
    final AiCancellation cancellation = AiCancellation();
    setState(() {
      _visionCancellation = cancellation;
      _visionPanel = VisionPanelRunning(imageRef: ref);
    });
    ArticleVisionInsight insight = await analyzer.analyze(
      imageUrl: url,
      imageRef: ref,
      cancellation: cancellation,
    );
    if (!mounted) {
      return;
    }
    // 首次发送告知：弹对话框，确认后带凭据重跑。取消时**一个字节都没有发出**。
    if (insight case ArticleVisionInsightNeedsConsent(:final String endpoint)) {
      final bool agreed = await _confirmVisionSend(endpoint);
      if (!mounted) {
        return;
      }
      if (!agreed) {
        setState(() {
          _visionCancellation = null;
          _visionPanel = const VisionPanelResult(
            imageRef: '',
            insight: ArticleVisionInsightSkipped(
              reason: ArticleVisionSkipReason.disabledBySetting,
              detail: 'userDeclined',
            ),
          );
        });
        return;
      }
      setState(() => _visionPanel = VisionPanelRunning(imageRef: ref));
      insight = await analyzer.analyze(
        imageUrl: url,
        imageRef: ref,
        confirmation: VisionSendConfirmation(
          acknowledgedAtUtc: DateTime.now().toUtc(),
        ),
        cancellation: cancellation,
      );
      if (!mounted) {
        return;
      }
    }
    setState(() {
      _visionCancellation = null;
      _visionPanel = VisionPanelResult(imageRef: ref, insight: insight);
    });
  }

  /// 首次发送告知对话框：返回用户是否同意。
  ///
  /// 说清三件事，缺一不可：发给谁（端点）、发什么（这张图片）、以及「只保存在本机、端点
  /// 变化会再问一次」。只说「是否允许发送图片」会让用户无法判断这次数据出境的去向。
  Future<bool> _confirmVisionSend(String endpoint) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool? agreed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.visionConsentTitle),
        content: Text(l10n.visionConsentBody(endpoint)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.visionConsentCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.visionConsentConfirm),
          ),
        ],
      ),
    );
    return agreed ?? false;
  }

  /// 取消进行中的图像分析（取消**不改动正文**）。
  void _cancelVisionAnalysis() {
    final AiCancellation? cancellation = _visionCancellation;
    if (cancellation == null) {
      return;
    }
    cancellation.cancel(reason: 'userCancelled');
    final VisionPanelState? panel = _visionPanel;
    setState(() {
      _visionCancellation = null;
      _visionPanel = VisionPanelResult(
        imageRef: panel is VisionPanelRunning ? panel.imageRef : '',
        insight: const ArticleVisionInsightSkipped(
          reason: ArticleVisionSkipReason.imageUnavailable,
          detail: 'cancelled',
        ),
      );
    });
    _notify(AppLocalizations.of(context).visionAnalysisCancelled);
  }

  /// 图像分析用例（由 Provider 组装）。
  ArticleVisionAnalyzer _visionAnalyzer() => ArticleVisionAnalyzer(
    analyzeImage: AnalyzeImageUseCase(ref.read(visualRouterProvider)),
    settingsWriter: _writeVisionEnabled,
  );

  /// 把 SET-065 的开关位写回 true（只覆盖开关位）。
  ///
  /// 先读现值再合并：SET-065 是复合项，整项覆盖会把用户设过的数量与单图上限抹成默认值——
  /// 那正是架构 5.3 禁止的「一次功能动作消费用户配置」。读不到现值时按**注册表默认值**合并
  /// （它们本来就是默认值，所以这是如实的结果，而不是猜）。
  Future<Result<void>> _writeVisionEnabled(bool enabled) async {
    final SettingsStore store = ref.read(settingsStoreProvider);
    final Result<Object?> current = await store.readSetting(SettingId.set065);
    final Object? raw = current.isOk ? current.valueOrNull : null;
    final ImageInputLimits limits = ImageInputLimits.fromSetting(raw);
    final Result<Object?> written = await store.writeSetting(
      SettingId.set065,
      <String, Object?>{
        'enabled': enabled,
        'maxImages': limits.maxImages,
        'maxImageMiB': limits.maxImageMiB,
      },
    );
    // 写设置返回的是「写进去的值」，这里只关心成败。
    return written.isErr ? Err<void>(written.errorOrNull!) : okUnit();
  }

  /// 为一张图取一个稳定的客户端引用（同一地址得到同一引用）。
  ///
  /// 用地址摘要而不是自增序号：引用会进任务 id（诊断里能看到「哪张图」），而序号在每次
  /// 打开文章时都从头开始，两条历史记录看起来会是同一张图。
  static String _visionRefFor(String url) =>
      'article-${sha256HexOfString(url.trim()).substring(0, 12)}';

  /// 保存图片（下载 + 让用户选位置）。
  Future<void> _saveImage(String url) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Result<String?> saved = await ref
        .read(imageSaveServiceProvider)
        .saveImage(url: url, suggestedName: _suggestedImageName(url));
    if (!mounted) {
      return;
    }
    if (saved.isErr) {
      _notify(l10n.readingImageSaveFailed(saved.errorOrNull!.message));
      return;
    }
    if (saved.valueOrNull case final String path) {
      _notify(l10n.readingImageSavedTo(path));
    }
    // 用户取消（Ok(null)）不提示：取消是正常动作，弹一句「未保存」会被读成失败。
  }

  /// 分享（不可用时回退复制）。
  Future<void> _shareText(String text) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final SystemShareService share = ref.read(systemShareServiceProvider);
    if (!await share.isAvailable()) {
      // 架构 4.2：系统分享不可用时回退复制。先复制再提示，让用户拿到东西。
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        _notify(l10n.readingShareUnavailable);
      }
      return;
    }
    final Result<bool> shared = await share.shareText(text);
    if (!mounted) {
      return;
    }
    if (shared.isErr) {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        _notify(l10n.readingShareFailed);
      }
      return;
    }
    if (shared.unwrap()) {
      _notify(l10n.readingShareDone);
    }
  }

  /// 从地址推一个保存用的文件名。
  ///
  /// 只取路径最后一段并做最小清洗：**不**用远端提供的文件名直接拼路径（架构 5.1：
  /// 不以外部标题直接拼路径），路径穿越与非法字符都在这里挡掉。
  static String _suggestedImageName(String url) {
    final Uri? uri = Uri.tryParse(url);
    final String last = uri == null || uri.pathSegments.isEmpty
        ? ''
        : uri.pathSegments.last;
    final String cleaned = last.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (cleaned.isEmpty || !cleaned.contains('.')) {
      return 'flux-image.jpg';
    }
    return cleaned;
  }

  /// 统一的操作提示（同一时刻只留一条）。
  void _notify(String message) {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _entry?.title ?? widget.initialTitle ?? l10n.readingOpenArticle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        leading: IconButton(
          tooltip: l10n.readingBackToList,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: <Widget>[
          // 复制全文：桌面用户没有「全选正文再复制」的便捷路径（正文里有多块，且
          // SelectionArea 的全选会把标题与元信息一起带上），因此给一个明确的按钮。
          IconButton(
            tooltip: l10n.readingCopyAll,
            icon: const Icon(Icons.copy_all),
            onPressed: _copyAllPlainText,
          ),
          // 「摘要」（T034）：为这篇文章生成 AI 摘要；**不覆盖**源摘要。
          IconButton(
            tooltip: l10n.readingSummaryAction,
            icon: const Icon(Icons.summarize_outlined),
            onPressed: _summarizeArticle,
          ),
          // 「翻译」（T035）：分段翻译当前正文；**原文始终保留**，只写译文结构。
          IconButton(
            tooltip: l10n.readingTranslateAction,
            icon: const Icon(Icons.translate),
            onPressed: _translateArticle,
          ),
          IconButton(
            tooltip: _findOpen ? l10n.readingFindClose : l10n.readingFindOpen,
            icon: Icon(_findOpen ? Icons.search_off : Icons.search),
            onPressed: _toggleFind,
          ),
          const SizedBox(width: FluxSpacing.xxs),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          // 交互监听包在最外层：指针与键盘都要刷新「最后活跃」，从而让空闲暂停
          // 只在用户真的离开（而不是页面开着）时生效（T023 的活跃判定）。
          : SessionInteractionListener(
              onInteraction: () => _sessionTracker?.onInteraction(),
              child: Column(
                children: <Widget>[
                  if (_findOpen)
                    FindBar(
                      controller: _findController,
                      matchCount: _matchCount,
                      hasQuery: _findQuery.isNotEmpty,
                      onChanged: (String value) =>
                          setState(() => _findQuery = value),
                      onClose: _toggleFind,
                    ),
                  // 图像分析结果面板（T033）：浮在正文上方的一块可关闭区域，正文本身不动。
                  if (_visionPanel case final VisionPanelState panel)
                    VisionAnalysisPanel(
                      state: panel,
                      onCancel: _cancelVisionAnalysis,
                      onClose: () => setState(() => _visionPanel = null),
                    ),
                  // AI 摘要面板（T034）：不覆盖源摘要，关闭面板也不改正文。
                  if (_summary case final AiSummaryState summaryState)
                    AiSummaryPanel(
                      state: summaryState,
                      sourceSummary: _entry?.summary,
                      onCancel: _cancelSummary,
                      onClose: () => setState(() => _summary = null),
                    ),
                  // 选词解释浮层（T034）：取消/失败都不改原文。
                  if (_explanation case final SelectionExplainState explanation)
                    SelectionExplainPanel(
                      state: explanation,
                      onClose: _closeExplanation,
                    ),
                  // 翻译面板（T035）：进度/完成/失败/跳过 + 原文/译文切换 + 重试失败段。
                  if (_translation case final TranslationPanelState translation)
                    ArticleTranslationPanelView(
                      state: translation,
                      onCancel: _cancelTranslation,
                      onRetryFailed: _retryFailedTranslation,
                      onToggle: _toggleTranslation,
                      showingTranslation: _showTranslation,
                      targetLanguageLabel: _targetLanguageLabel,
                      generatedAtLabel: _translationDateLabel,
                      modelLabel: _savedTranslation?.modelLabel,
                      stale: _translationStale,
                      truncated: _savedTranslation?.hasTruncatedSource ?? false,
                      hasTranslation:
                          (_savedTranslation?.translatedCount ?? 0) > 0,
                      onClose: () => setState(() => _translation = null),
                    ),
                  Expanded(
                    child: LayoutBuilder(
                      builder:
                          (BuildContext context, BoxConstraints constraints) {
                            // 桌面宽窗（与架构第 7 节三栏断点一致）显示目录侧栏；窄窗不显示
                            // ——把正文挤到 500 宽以下去换一个目录，读者会先把目录关掉。
                            final bool wide =
                                constraints.maxWidth >=
                                FluxBreakpoints.threeColumn;
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Expanded(child: _body(l10n)),
                                if (wide)
                                  OutlinePane(
                                    outline: _outline,
                                    activeBlockIndex: _activeOutlineBlock,
                                    onSelect: _scrollToBlock,
                                  ),
                              ],
                            );
                          },
                    ),
                  ),
                  NeighborBar(
                    snapshot: widget.snapshot,
                    currentId: widget.articleId,
                    onNavigate: _navigateTo,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _body(AppLocalizations l10n) {
    final ThemeData theme = Theme.of(context);
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(
        horizontal: FluxSpacing.xl,
        vertical: FluxSpacing.lg,
      ),
      children: <Widget>[
        if (_error case final AppError error)
          StatusBanner(
            severity: StatusBannerSeverity.error,
            message: l10n.readingActionError(error.message),
          ),
        if (_entry case final ArticleListEntry entry) ...<Widget>[
          _Header(entry: entry),
          // AI 摘要（T034）：与源摘要**分列显示**并标注来源与生成时间。有 AI 摘要时
          // 放在最上面，因为它是针对全文的（信息量最大）；源摘要仍在下面，没有被覆盖。
          if (_savedAiSummary case final AiSummaryRecord aiSummary)
            _AiSummaryCard(record: aiSummary),
          if (entry.bodyCompleteness == BodyCompleteness.summaryOnly)
            // 「仅摘要」必须明说：架构 4.2 明确不把源内 content 字段绝对当全文，
            // 而读者看到一段像正文的文字时无从分辨它是不是全文。
            Padding(
              padding: const EdgeInsets.only(bottom: FluxSpacing.md),
              child: StatusBanner(
                severity: StatusBannerSeverity.info,
                message: l10n.readingCompletenessSummaryOnlyNotice,
              ),
            ),
          if (entry.awaitingBodySync)
            // 「正文尚未同步」（T045）：这一行是远端状态到达时落下的占位行（本机还没抓到
            // 这篇的正文），与「正文为空」「仅摘要」是三件不同的事。必须作为**独立状态**
            // 显示出来，否则用户看到一片空白会以为源的内容坏了或提取失败，而实际上只要刷新
            // 这个源就会补齐。
            Padding(
              key: const ValueKey<String>('detail-body-not-synced'),
              padding: const EdgeInsets.only(bottom: FluxSpacing.md),
              child: StatusBanner(
                severity: StatusBannerSeverity.info,
                message: l10n.readingBodyNotSyncedNotice,
              ),
            ),
          // T024：主动获取原站全文的入口与状态提示。放在正文**之前**：它是「要不要
          // 换一份正文来读」的决定，读者应当先看到这个选择，而不是读到一半才发现。
          _FetchOriginalBar(
            entry: entry,
            hasExtraction: _extraction != null,
            showingExtracted: _showExtracted,
            fetching: _fetchingOriginal,
            notice: _fetchNotice,
            failed: _fetchError != null,
            onFetch: _fetchOriginal,
            onToggle: () => setState(() => _showExtracted = !_showExtracted),
            onOpenExternal: entry.sourceUrl == null
                ? null
                : () => _openLinkPanel(entry.sourceUrl!),
          ),
        ],
        if (_displayDocument case final DocDocument document)
          _DocumentBody(
            document: document,
            blockKeys: _blockKeys,
            findQuery: _findQuery,
            autoLoadImages: _autoLoadImages,
            selectionAreaKey: _selectionAreaKey,
            selection: _selection,
            onSelectionChanged: _onSelectionChanged,
            onOpenLink: _openLinkPanel,
            onOpenImage: _openImageViewer,
            onExplainSelection: _explainSelection,
          )
        else
          Text(l10n.readingDetailNoBody, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

/// 详情页头部：标题 + 元信息 + 完整性 + 状态控件。
/// 主动获取原站全文的入口条（T024）。
///
/// 三个状态各对应一种用户动作，且**失败时始终给出外开入口**（架构 4.2）：
///   * 未提取：显示「获取原站全文」按钮 + 一句说明它只在点击时抓取；
///   * 已提取：显示原文/提取正文的切换（两份都保留），并保留「重新获取」；
///   * 抓取中：按钮禁用并显示进度，避免重复点击发起第二次请求。
///
/// 为什么把「只在点击时抓取」写在界面上：这是产品对用户的承诺（无自动/后台/批量抓取），
/// 让它在按钮旁边可见，用户不必去读文档才敢点。
class _FetchOriginalBar extends StatelessWidget {
  const _FetchOriginalBar({
    required this.entry,
    required this.hasExtraction,
    required this.showingExtracted,
    required this.fetching,
    required this.failed,
    required this.onFetch,
    required this.onToggle,
    this.notice,
    this.onOpenExternal,
  });

  final ArticleListEntry entry;
  final bool hasExtraction;
  final bool showingExtracted;
  final bool fetching;
  final bool failed;
  final String? notice;
  final VoidCallback onFetch;
  final VoidCallback onToggle;
  final VoidCallback? onOpenExternal;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: FluxSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (fetching) ...<Widget>[
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: FluxSpacing.xs),
                Text(
                  l10n.readingFetchFullTextLoading,
                  style: theme.textTheme.labelSmall,
                ),
              ] else ...<Widget>[
                FilledButton.tonalIcon(
                  onPressed: onFetch,
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: Text(
                    hasExtraction
                        ? l10n.readingFetchFullTextAction
                        : l10n.readingFetchFullTextAction,
                  ),
                ),
                if (hasExtraction) ...<Widget>[
                  const SizedBox(width: FluxSpacing.xs),
                  // 切换按钮的文字说明**将会切到哪一份**，而不是当前显示的是哪一份：
                  // 按钮描述动作。
                  OutlinedButton.icon(
                    onPressed: onToggle,
                    icon: const Icon(Icons.compare_arrows, size: 18),
                    label: Text(
                      showingExtracted
                          ? l10n.readingFetchFullTextViewOriginal
                          : l10n.readingFetchFullTextViewExtracted,
                    ),
                  ),
                ],
              ],
            ],
          ),
          const SizedBox(height: FluxSpacing.xxs),
          Text(
            l10n.readingFetchFullTextButtonHint,
            style: theme.textTheme.labelSmall,
          ),
          if (notice case final String message)
            Padding(
              padding: const EdgeInsets.only(top: FluxSpacing.xs),
              child: StatusBanner(
                severity: failed
                    ? StatusBannerSeverity.warning
                    : StatusBannerSeverity.info,
                message: message,
                action: onOpenExternal == null
                    ? null
                    : TextButton(
                        onPressed: onOpenExternal,
                        child: Text(l10n.readingFetchFullTextOpenExternal),
                      ),
              ),
            ),
          // 「只做 HTTP 抓取与静态解析」这句在失败时最需要出现：用户看到失败提示时，
          // 最容易怀疑「是不是这个应用在偷偷做别的事」。
          if (failed)
            Padding(
              padding: const EdgeInsets.only(top: FluxSpacing.xxs),
              child: Text(
                l10n.readingFetchFullTextNoScript,
                style: theme.textTheme.labelSmall,
              ),
            ),
        ],
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.entry});

  final ArticleListEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final DocTheme docTheme = DocTheme.fromPalette(
      theme.brightness == Brightness.dark
          ? FluxPalette.dark
          : FluxPalette.light,
    );
    final ArticleListController controller = ref.read(
      articleListControllerProvider.notifier,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          entry.title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontSize: FluxTypography.detailTitleMin,
            height: 1.3,
          ),
        ),
        const SizedBox(height: FluxSpacing.xs),
        Wrap(
          spacing: FluxSpacing.xs,
          runSpacing: FluxSpacing.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text(_metaLine(l10n), style: theme.textTheme.labelSmall),
            CompletenessBadge(
              completeness: entry.bodyCompleteness,
              color: docTheme.textSecondary,
              border: docTheme.border,
            ),
            if (entry.awaitingBodySync)
              // 与列表卡片同一个徽标：进详情页之后「正文尚未同步」这个状态仍要可见，
              // 否则读者只看到一片空白正文而不知道原因。
              Text(
                l10n.readingBodyNotSyncedBadge,
                key: const ValueKey<String>('detail-body-not-synced-badge'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: docTheme.textSecondary,
                ),
              ),
          ],
        ),
        const SizedBox(height: FluxSpacing.sm),
        Row(
          children: <Widget>[
            ReadingStateControl(
              state: entry.readingState,
              size: FluxIconSize.small,
              onChanged: (ReadingState next) =>
                  controller.setReadingState(entry.id, next),
            ),
            const SizedBox(width: FluxSpacing.xs),
            FavoriteToggle(
              favorite: entry.favorite,
              size: FluxIconSize.small,
              onChanged: (bool _) => controller.toggleFavorite(entry.id),
            ),
          ],
        ),
        const Divider(height: FluxSpacing.lg),
      ],
    );
  }

  String _metaLine(AppLocalizations l10n) {
    final String time = entry.publishedAtMissing
        ? l10n.readingPublishedUnknown
        : formatLocalTime(entry.effectiveTime);
    final String source = entry.author == null || entry.author!.isEmpty
        ? entry.feedName
        : l10n.readingByAuthor(entry.author!, entry.feedName);
    final String detached = entry.detachedFromFeed
        ? '（${l10n.detachedFeedLabel}）'
        : '';
    return '$source$detached · $time';
  }
}

/// 正文主体（受控文档渲染）。
class _DocumentBody extends StatelessWidget {
  const _DocumentBody({
    required this.document,
    required this.blockKeys,
    required this.findQuery,
    required this.autoLoadImages,
    required this.selectionAreaKey,
    required this.selection,
    required this.onSelectionChanged,
    required this.onOpenLink,
    required this.onOpenImage,
    required this.onExplainSelection,
  });

  final DocDocument document;
  final List<GlobalKey> blockKeys;
  final String findQuery;
  final bool autoLoadImages;
  final GlobalKey selectionAreaKey;
  final ValueListenable<String> selection;
  final ValueChanged<SelectedContent?> onSelectionChanged;
  final void Function(String url) onOpenLink;
  final void Function(String url, String alt) onOpenImage;
  final Future<void> Function(String selection) onExplainSelection;

  @override
  Widget build(BuildContext context) {
    final DocTypography typography = DocTypography(
      baseSize: FluxTypography.bodyFontSize,
      theme: DocTheme.fromPalette(
        Theme.of(context).brightness == Brightness.dark
            ? FluxPalette.dark
            : FluxPalette.light,
      ),
    );
    final AppLocalizations l10n = AppLocalizations.of(context);
    // SelectionArea：桌面上的**单块选择**（架构 4.2 与 D-15：跨块选择属后续阶段）。
    // 系统菜单（复制/全选）由 contextMenuBuilder 交给平台默认实现，只额外挂上我们自己的
    // 「解释」入口——复制与全选是用户已经熟悉的动作，不该被我们重写。
    return SelectionArea(
      key: selectionAreaKey,
      onSelectionChanged: onSelectionChanged,
      contextMenuBuilder:
          (BuildContext context, SelectableRegionState selectableRegionState) {
            // 先用框架的默认菜单（它给出**当前平台**正确的复制/全选等项，含标签文案与
            // 顺序），再在末尾追加我们自己的「解释」。
            //
            // 为什么不自己拼一个只有复制+解释的菜单：那会丢掉平台习惯的动作（macOS 上
            // 是「拷贝」，Android 上有「全选」等），而复制本身也不该由我们重写——选区
            // 的分段与换行拼接由框架决定，自己拼出来的结果与系统菜单不一致。
            final List<ContextMenuButtonItem> items = <ContextMenuButtonItem>[
              ...selectableRegionState.contextMenuButtonItems,
            ];
            final String selected = selection.value;
            if (selected.trim().isNotEmpty) {
              items.add(
                ContextMenuButtonItem(
                  label: l10n.readingSelectionExplain,
                  onPressed: () {
                    // 先收起菜单再开对话框：菜单是 overlay，留着它会让对话框与它
                    // 重叠，且选中态一直是「正在选择」的样子。
                    selectableRegionState.hideToolbar();
                    onExplainSelection(selected);
                  },
                ),
              );
            }
            return AdaptiveTextSelectionToolbar.buttonItems(
              anchors: selectableRegionState.contextMenuAnchors,
              buttonItems: items,
            );
          },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < document.children.length; i++)
            KeyedSubtree(
              key: blockKeys.length > i ? blockKeys[i] : null,
              child: Padding(
                padding: blockPadding(document.children[i], typography),
                child: BlockView(
                  node: document.children[i],
                  typography: typography,
                  onCopyLink: (String url) => _copyLink(context, url),
                  onOpenLink: onOpenLink,
                  onOpenImage: onOpenImage,
                  autoLoadImages: autoLoadImages,
                  findQuery: findQuery.isEmpty ? null : findQuery,
                ),
              ),
            ),
          if (findQuery.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: FluxSpacing.sm),
              child: Text(
                l10n.readingFindScopeNote(findQuery),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
        ],
      ),
    );
  }

  /// 右键链接只复制地址（点击由面板处理：面板上也提供复制）。
  static Future<void> _copyLink(BuildContext context, String url) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: url));
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(l10n.readingLinkCopied)));
  }
}

/// AI 摘要卡片（正文顶部的「AI 摘要」标注，T034）。
///
/// 与源摘要**分开显示**：AI 摘要明确标出「AI 摘要」与模型与时间，源摘要仍在详情页的
/// 元信息里——用户因此能分辨哪句话是谁写的（架构 4.2「原文始终保留」）。
class _AiSummaryCard extends StatelessWidget {
  /// 构造卡片。
  const _AiSummaryCard({required this.record});

  /// 摘要记录。
  final AiSummaryRecord record;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: FluxSpacing.md),
      padding: const EdgeInsets.all(FluxSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(FluxRadius.card),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.readingAiSummaryLabel(
              record.modelLabelText,
              record.generatedAt.toLocal().toIso8601String().substring(0, 10),
            ),
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: FluxSpacing.xs),
          Text(record.text, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// AI 摘要面板（T034）：进行中 / 成功 / 失败 / 跳过四种状态。
class AiSummaryPanel extends StatelessWidget {
  /// 构造面板。
  const AiSummaryPanel({
    super.key,
    required this.state,
    required this.onCancel,
    required this.onClose,
    this.sourceSummary,
  });

  /// 面板状态。
  final AiSummaryState state;

  /// 取消进行中的生成。
  final VoidCallback onCancel;

  /// 关闭面板。
  final VoidCallback onClose;

  /// 源摘要（用于说明「AI 摘要不覆盖它」）。
  final String? sourceSummary;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final bool running = state is AiSummaryRunning;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        FluxSpacing.md,
        FluxSpacing.sm,
        FluxSpacing.md,
        0,
      ),
      padding: const EdgeInsets.all(FluxSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(FluxRadius.card),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(l10n.readingSummaryTitle, style: theme.textTheme.titleSmall),
              const Spacer(),
              if (running)
                TextButton(
                  onPressed: onCancel,
                  child: Text(l10n.readingSummaryCancelAction),
                ),
              IconButton(
                tooltip: l10n.visionAnalysisClose,
                icon: const Icon(Icons.close, size: 18),
                onPressed: onClose,
              ),
            ],
          ),
          if (running)
            Row(
              children: <Widget>[
                const FluxLoadingIndicator(size: 16),
                const SizedBox(width: FluxSpacing.sm),
                Expanded(child: Text(l10n.readingSummaryRunning)),
              ],
            )
          else
            _summaryBody(l10n, theme),
        ],
      ),
    );
  }

  Widget _summaryBody(AppLocalizations l10n, ThemeData theme) =>
      switch (state) {
        AiSummaryDone(:final AiSummaryRecord record, :final bool truncated) =>
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SelectableText(record.text),
              if (truncated) ...<Widget>[
                const SizedBox(height: FluxSpacing.xs),
                // SET-061：正文被截断必须说明，否则用户会把摘要当成对全文的概括。
                Text(
                  l10n.readingSummaryTruncatedNotice,
                  style: theme.textTheme.labelSmall,
                ),
              ],
              if (sourceSummary?.trim().isNotEmpty ?? false) ...<Widget>[
                const SizedBox(height: FluxSpacing.xs),
                Text(
                  l10n.readingSummarySourceKept,
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ],
          ),
        AiSummaryFailed(:final AppError? error) => Text(
          error == null
              ? l10n.readingSummaryNoModelBody
              : l10n.readingSummaryFailed(error.kind),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
        AiSummarySkipped() => Text(
          l10n.readingSummaryNoBody,
          style: theme.textTheme.bodyMedium,
        ),
        AiSummaryRunning() => const SizedBox.shrink(),
      };
}

/// 选词解释浮层（T034）：结果只在这里显示，**不改动原文**。
class SelectionExplainPanel extends StatelessWidget {
  /// 构造浮层。
  const SelectionExplainPanel({
    super.key,
    required this.state,
    required this.onClose,
  });

  /// 浮层状态。
  final SelectionExplainState state;

  /// 关闭浮层。
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        FluxSpacing.md,
        FluxSpacing.sm,
        FluxSpacing.md,
        0,
      ),
      padding: const EdgeInsets.all(FluxSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(FluxRadius.card),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l10n.readingSelectionExplainTitle(state.selection),
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: l10n.visionAnalysisClose,
                icon: const Icon(Icons.close, size: 18),
                onPressed: onClose,
              ),
            ],
          ),
          switch (state) {
            SelectionExplainRunning() => Row(
              children: <Widget>[
                const FluxLoadingIndicator(size: 16),
                const SizedBox(width: FluxSpacing.sm),
                Expanded(child: Text(l10n.readingSelectionExplainRunning)),
              ],
            ),
            SelectionExplainDone(
              :final String text,
              :final bool contextTruncated,
              :final int sentCharacters,
            ) =>
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SelectableText(text),
                  const SizedBox(height: FluxSpacing.xs),
                  // 说清「发了多少」与「上下文截过」：这是数据出境的可见性，不是细节。
                  Text(
                    contextTruncated
                        ? l10n.readingSelectionExplainSentTruncated(
                            sentCharacters,
                          )
                        : l10n.readingSelectionExplainSent(sentCharacters),
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            SelectionExplainFailed(:final AppError? error) => Text(
              error == null
                  ? l10n.readingSelectionExplainFailedUnknown
                  : l10n.readingSummaryFailed(error.kind),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          },
        ],
      ),
    );
  }
}

/// AI 摘要面板的状态（T034）。
sealed class AiSummaryState {
  /// 构造状态。
  const AiSummaryState();
}

/// 正在生成。
final class AiSummaryRunning extends AiSummaryState {
  /// 构造状态。
  const AiSummaryRunning({required this.cancellation});

  /// 取消信号。
  final AiCancellation cancellation;
}

/// 生成成功。
final class AiSummaryDone extends AiSummaryState {
  /// 构造状态。
  const AiSummaryDone({required this.record, required this.truncated});

  /// 生成的摘要。
  final AiSummaryRecord record;

  /// 正文是否被截断（SET-061）。
  final bool truncated;
}

/// 生成失败。
final class AiSummaryFailed extends AiSummaryState {
  /// 构造状态。
  const AiSummaryFailed({this.error});

  /// 失败原因；null 表示「没有可用模型」这类配置问题。
  final AppError? error;
}

/// 跳过（没有正文可总结）。
final class AiSummarySkipped extends AiSummaryState {
  /// 构造状态。
  const AiSummarySkipped();
}

/// 选词解释浮层的状态（T034）。
sealed class SelectionExplainState {
  /// 构造状态。
  const SelectionExplainState({required this.selection});

  /// 用户选中的文本。
  final String selection;
}

/// 正在解释。
final class SelectionExplainRunning extends SelectionExplainState {
  /// 构造状态。
  const SelectionExplainRunning({
    required super.selection,
    required this.cancellation,
  });

  /// 取消信号。
  final AiCancellation cancellation;
}

/// 解释成功。
final class SelectionExplainDone extends SelectionExplainState {
  /// 构造状态。
  const SelectionExplainDone({
    required super.selection,
    required this.text,
    required this.contextTruncated,
    required this.sentCharacters,
  });

  /// 解释文本。
  final String text;

  /// 上下文是否被截断（最少上下文的上限被触发）。
  final bool contextTruncated;

  /// 实际发送的字符数。
  final int sentCharacters;
}

/// 解释失败（不改原文）。
final class SelectionExplainFailed extends SelectionExplainState {
  /// 构造状态。
  const SelectionExplainFailed({required super.selection, this.error});

  /// 失败原因。
  final AppError? error;
}

/// 图像分析结果面板（T033）。
///
/// 放在正文上方而不是弹一个对话框：结果是「关于这篇文章里这张图」的一段内容，用户常常要
/// 边看正文边读它；对话框会挡住正文，而且关掉之后就没有了。
///
/// 三种结局各自有明确的呈现（架构 4.3 与第 8 节）：
///   - 成功：描述文本 + 数据去向（发送至哪个端点）+ 降采样说明；
///   - 跳过：**不是错误**（没有视觉模型 / 图片拿不到），用中性样式并说明文本链路不受影响；
///   - 失败：错误样式与可核对的原因。
class VisionAnalysisPanel extends StatelessWidget {
  /// 构造面板。
  const VisionAnalysisPanel({
    super.key,
    required this.state,
    required this.onCancel,
    required this.onClose,
  });

  /// 面板状态。
  final VisionPanelState state;

  /// 取消进行中的分析。
  final VoidCallback onCancel;

  /// 关闭面板。
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final bool running = state is VisionPanelRunning;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        FluxSpacing.md,
        FluxSpacing.sm,
        FluxSpacing.md,
        0,
      ),
      padding: const EdgeInsets.all(FluxSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(FluxRadius.card),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(l10n.visionAnalysisTitle, style: theme.textTheme.titleSmall),
              const Spacer(),
              if (running)
                TextButton(
                  onPressed: onCancel,
                  child: Text(l10n.visionAnalysisCancelAction),
                ),
              IconButton(
                tooltip: l10n.visionAnalysisClose,
                icon: const Icon(Icons.close, size: 18),
                onPressed: onClose,
              ),
            ],
          ),
          if (running)
            Row(
              children: <Widget>[
                const FluxLoadingIndicator(size: 16),
                const SizedBox(width: FluxSpacing.sm),
                Expanded(child: Text(l10n.visionAnalysisRunning)),
              ],
            )
          else if (state case VisionPanelResult(
            :final ArticleVisionInsight insight,
          ))
            _ResultBody(insight: insight),
        ],
      ),
    );
  }
}

/// 结果正文（按结局分支）。
class _ResultBody extends StatelessWidget {
  /// 构造正文。
  const _ResultBody({required this.insight});

  /// 结局。
  final ArticleVisionInsight insight;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    switch (insight) {
      case ArticleVisionInsightText(
        :final String text,
        :final bool downsampled,
        :final String? endpoint,
      ):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SelectableText(text),
            if (downsampled) ...<Widget>[
              const SizedBox(height: FluxSpacing.xs),
              // 「降采样仍说明」（架构 4.3）：不说的话用户会以为模型看到的是原图。
              Text(
                l10n.visionAnalysisDownsampled,
                style: theme.textTheme.labelSmall,
              ),
            ],
            if (endpoint case final String value) ...<Widget>[
              const SizedBox(height: FluxSpacing.xs),
              Text(
                l10n.visionAnalysisSentTo(value),
                style: theme.textTheme.labelSmall,
              ),
            ],
          ],
        );
      case ArticleVisionInsightSkipped(:final ArticleVisionSkipReason reason):
        // 跳过用中性说明：它不是错误，把它画成错误会让用户去排查一个并不存在的问题。
        return Text(_skipText(l10n, reason), style: theme.textTheme.bodyMedium);
      case ArticleVisionInsightFailed(:final AppError error):
        return Text(
          l10n.visionAnalysisFailed(error.kind),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.error,
          ),
        );
      case ArticleVisionInsightNeedsConsent():
        // 需要告知时面板不呈现结论（对话框由页面负责）；如实说明当前没有结论。
        return Text(
          l10n.visionAnalysisImageUnavailable,
          style: theme.textTheme.bodyMedium,
        );
    }
  }

  static String _skipText(
    AppLocalizations l10n,
    ArticleVisionSkipReason reason,
  ) => switch (reason) {
    ArticleVisionSkipReason.noVisionModel => l10n.visionAnalysisNoModel,
    ArticleVisionSkipReason.disabledBySetting => l10n.visionAnalysisDisabled,
    ArticleVisionSkipReason.imageUnavailable =>
      l10n.visionAnalysisImageUnavailable,
  };
}
