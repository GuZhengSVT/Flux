// 正文阅读页（T019）：受控文档渲染 + 目录 + 上下篇 + 页内查找 + 完整性行。
//
// 范围与边界（本页明确不做的事）：
//   * **正文来源**：T013 把清洗后的受控文档导出成**纯文本**入库（见 feed_import_builder：
//     正文哈希需要「标签属性与空白变化不算修订」这样的稳定判据）。因此阅读器对这段文本
//     再走一次 Markdown → 受控文档树的解析——同一条渲染管线，T020 的选区/复制接口不必为
//     两套来源各写一遍。落库的是文本，画出的是受控节点，中间没有 HTML 字符串。
//   * **图片是占位框**：远程图片加载、缓存与尺寸安全属 T021，本期不发起任何图片请求。
//   * **外链不打开**：外开属 T020；这里提供「复制地址」并把当前范围写在页面上。
//   * **目录只取 h1–h3**，桌面宽窗（>=1100，架构第 7 节三栏断点）显示，窄窗不显示。
//   * **上下篇依据进入时的筛选/排序快照**（架构 4.1），不按当前筛选现算。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';
import 'package:flux/core/design/design_tokens.dart';
import 'package:flux/l10n/l10n.dart';
import 'package:flux/ui/ui.dart';

import '../application/article_ports.dart';
import '../application/article_state.dart';
import '../application/reader_outline.dart';
import '../domain/markdown_to_document.dart';
import 'article_list_controller.dart';

import 'package:flutter/services.dart';

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

class _ArticleDetailPageState extends ConsumerState<ArticleDetailPage> {
  ArticleListEntry? _entry;
  DocDocument? _document;
  int? _activeOutlineBlock;
  AppError? _error;
  bool _loading = true;
  bool _findOpen = false;
  String _findQuery = '';
  final TextEditingController _findController = TextEditingController();

  /// 每个顶层块的位置 key（目录跳转用）。
  List<GlobalKey> _blockKeys = <GlobalKey>[];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _findController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<ReaderOutlineEntry> get _outline => _document == null
      ? const <ReaderOutlineEntry>[]
      : extractOutline(_document!);

  int get _matchCount => _document == null || _findQuery.isEmpty
      ? 0
      : DocDocumentView.countMatches(_document!, _findQuery);

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
          : Column(
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
        ],
        if (_document case final DocDocument document)
          _DocumentBody(
            document: document,
            blockKeys: _blockKeys,
            findQuery: _findQuery,
          )
        else
          Text(l10n.readingDetailNoBody, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

/// 详情页头部：标题 + 元信息 + 完整性 + 状态控件。
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
  });

  final DocDocument document;
  final List<GlobalKey> blockKeys;
  final String findQuery;

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
    return Column(
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
                onOpenLink: (String url) => _copyLink(context, url),
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
    );
  }

  /// 点击或右键链接都只复制地址：外开属 T020。复制而不是毫无反应——用户点了一下
  /// 至少要拿到能用的东西，否则会以为链接坏了。
  static Future<void> _copyLink(BuildContext context, String url) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: url));
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(l10n.readingLinkCopied)));
  }
}
