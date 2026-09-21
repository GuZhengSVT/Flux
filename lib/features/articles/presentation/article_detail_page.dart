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
import 'package:flux/features/feeds/application/feed_ports.dart';
import 'package:flux/features/settings/application/settings_controller.dart';
import 'package:flux/features/settings/application/settings_navigation.dart';
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
  DocDocument? get _displayDocument =>
      _showExtracted ? (_extractedDocument ?? _document) : _document;

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
    setState(() {
      _entry = entry;
      _document = document;
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

  /// 「解释」选区：入口与提示（真正的调用属 T034）。
  ///
  /// 无论 AI 是否已配置，都**不发起任何请求**：T020 的验收是「复制/查询占位可接用例，
  /// 查询未配置提示」，调 AI 是 T034。因此两条路径都给明确说明，而不是一个看起来能用
  /// 却什么都不做的按钮。
  Future<void> _explainSelection(String selection) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final SelectionExplanationRequest request =
        SelectionExplanationRequest.fromDocument(
          plainText: _document == null ? '' : articlePlainText(_document!),
          selection: selection,
        );
    if (request.selection.isEmpty) {
      return;
    }
    final bool configured = await _hasAiCredential();
    if (!mounted) {
      return;
    }
    if (!configured) {
      await showDialog<void>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: Text(l10n.readingSelectionExplainNoAiTitle),
          // 说清「将发送什么」：架构 2.3 要求首次配置逐项告知接收者，而选词解释是
          // 第一次把用户正文的一部分交给外部服务的地方。
          content: Text(l10n.readingSelectionExplainNoAiBody(1200)),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.subscriptionClose),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                // 跳设置：解释需要 AI 配置，把用户直接送到那里，而不是只留一句话。
                ref.read(settingsNavigationRequestProvider.notifier).request();
              },
              child: Text(l10n.readingSelectionExplainGoSettings),
            ),
          ],
        ),
      );
      return;
    }
    _notify(l10n.readingSelectionExplainPending);
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
        ),
      ),
    );
  }

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
