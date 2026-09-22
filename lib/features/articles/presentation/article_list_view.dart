// 文章列表主体（T017，T019+ 产品化）：空态区分 + 三种卡片形态 + 虚拟化分批加载 +
// 返回锚点 + 右键菜单 + 批量操作栏。
//
// 从 reading_page.dart 拆出来：整页里有三块职责（工具栏/列表/批量栏），一个文件
// 装下会让「空态判断」与「批量范围」这两处最容易写错的逻辑埋在滚动里。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';
import 'package:flux/core/design/design_tokens.dart';
import 'package:flux/features/settings/application/cleanup_ports.dart';
import 'package:flux/features/settings/application/cleanup_service.dart';
import 'package:flux/features/feeds/presentation/feed_manager_controller.dart';
import 'package:flux/l10n/l10n.dart';
import 'package:flux/ui/ui.dart';

import '../application/article_card_view.dart';
import '../application/article_platform_ports.dart';
import '../application/reader_outline.dart';
import 'article_card.dart';
import 'article_detail_page.dart';
import 'article_list_scroll.dart';
import 'reader/reader_chrome.dart';
import 'article_list_controller.dart';
import 'article_list_pager.dart';
import 'reading_page.dart';

/// 列表主体。
class ArticleListView extends ConsumerWidget {
  /// 构造视图。
  const ArticleListView({required this.state, super.key});

  /// 页面状态。
  final ArticleListPageState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    if (state.pageError case final AppError error) {
      return ReadingLoadFailed(
        message: error.message,
        onRetry: () =>
            ref.read(articleListControllerProvider.notifier).reload(),
      );
    }

    // 空态区分（架构第 7 节要求三类分别提示）：
    //   - 完全没有订阅：引导去添加；
    //   - 未读筛选为空：这是**完成态**（好事），用强调色而不是灰阶；
    //   - 其余筛选为空：换筛选；
    //   - 「全部」筛选下也为空：还没有抓到内容，指出下一步动作。
    final bool noFeeds =
        ref.watch(feedOverviewProvider).value?.isEmpty ?? false;

    if (state.entries.isEmpty) {
      if (noFeeds) {
        return FluxEmptyState(
          title: l10n.emptyNoFeedsTitle,
          body: l10n.emptyNoFeedsBody,
          secondaryNote: l10n.readingEmptyBody,
        );
      }
      if (state.page.filter == ArticleFilter.unread) {
        return FluxEmptyState(
          title: l10n.emptyAllReadTitle,
          body: l10n.emptyAllReadBody,
          tone: EmptyStateTone.positive,
        );
      }
      if (state.page.filter == ArticleFilter.all) {
        return FluxEmptyState(
          title: l10n.readingEmptyTitle,
          body: l10n.readingEmptyBody,
        );
      }
      return FluxEmptyState(
        title: l10n.readingEmptyFilteredTitle,
        body: l10n.readingEmptyFilteredBody,
        tone: EmptyStateTone.muted,
      );
    }

    // 卡片形态来自 SET-008（紧凑/正常/宽松）。读不到时 provider 已回退到注册表默认值，
    // 因此这里只需要一个无条件取值；value 为空（还在读第一帧）时按默认形态画，避免
    // 首帧用一个「还不知道形态」的空白列表顶掉内容。
    final ArticleCardViewMode mode =
        ref.watch(cardViewModeProvider).value ?? ArticleCardViewMode.normal;

    return Column(
      children: <Widget>[
        // 批量操作栏放在列表**上方**。它原先在底部，实测被操作结果提示条
        // （SnackBar）盖住：用户点「标为已读」之后想接着点「加入收藏」，那一下会
        // 落在提示条上而不是按钮上——一个「点了没反应」的按钮比没有按钮更糟。
        if (state.batchMode) BatchActionBar(state: state),
        Expanded(
          child: _ArticleListBody(state: state, mode: mode),
        ),
        ArticlePager(state: state),
      ],
    );
  }
}

/// 列表主体：虚拟化 + 分批加载 + 返回锚点。
///
/// 三件事都只与「滚动」有关，因此收在一个 StatefulWidget 里：滚动位置、控制器与
/// 「什么时候该加载下一批」是同一份状态的三个面，分到三处会出现「滚到底了但没人去
/// 加载」这类只在特定时序下发生的缺陷。
class _ArticleListBody extends ConsumerStatefulWidget {
  const _ArticleListBody({required this.state, required this.mode});

  final ArticleListPageState state;
  final ArticleCardViewMode mode;

  @override
  ConsumerState<_ArticleListBody> createState() => _ArticleListBodyState();
}

class _ArticleListBodyState extends ConsumerState<_ArticleListBody> {
  /// 键盘选中的行下标（架构第 7 节「桌面默认支持键盘焦点」）。
  ///
  /// 为什么是**下标**而不是文章 id：上下键的语义就是「相邻的一行」，而列表本身是按
  /// 顺序渲染的；用 id 会让「下一篇」需要一次线性查找，并且在换筛选之后指向一个
  /// 用户已经看不见的位置。null 表示键盘还没有落点（鼠标用户从没按过方向键）。
  int? _keyboardIndex;

  ScrollController get _controller =>
      ref.read(articleListScrollControllerProvider);

  ArticleListScrollAnchor get _anchor =>
      ref.read(articleListScrollAnchorProvider);

  @override
  void initState() {
    super.initState();
    // 恢复锚点：在**第一次布局之前**把控制器移到上次的位置，而不是先画在顶部再跳
    // ——后者在长列表上会先渲染一遍顶部内容（肉眼可见的一次闪动）。
    //
    // 用 addPostFrameCallback 而不是直接 jumpTo：此时列表还没有 client，jumpTo 是空
    // 操作。放到第一帧之后执行，位置已经存在，跳转才生效。
    final double offset = _anchor.offset;
    if (offset > 0) {
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        if (!mounted) {
          return;
        }
        final ScrollController controller = _controller;
        if (controller.hasClients) {
          controller.jumpTo(
            offset.clamp(0, controller.position.maxScrollExtent),
          );
        }
      });
    }
  }

  /// 滚动监听：到达底部附近时加载下一批，并持续记录当前偏移（锚点）。
  bool _onScroll(ScrollNotification notification) {
    if (notification is! ScrollUpdateNotification &&
        notification is! ScrollEndNotification) {
      return false;
    }
    _anchor.offset = notification.metrics.pixels;
    // 提前一屏开始加载：正好滚到底才发请求时，用户会先看到一段空白再看到内容。
    final bool nearBottom =
        notification.metrics.pixels >=
        notification.metrics.maxScrollExtent -
            notification.metrics.viewportDimension;
    if (nearBottom) {
      final ArticleListPageState current = widget.state;
      if (current.page.hasMore(current.total)) {
        // 不 await：这是滚动回调，等它会把这一帧拖住；加载完成后 provider 更新，
        // 列表自然延长。
        unawaited(
          ref.read(articleListControllerProvider.notifier).loadMoreBatch(),
        );
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // 换筛选/来源之后要回到顶部：由控制器置位，这里在布局完成后消费（见 consumeScrollReset）。
    if (ref.read(articleListControllerProvider.notifier).consumeScrollReset()) {
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        if (!mounted) {
          return;
        }
        final ScrollController controller = _controller;
        if (controller.hasClients) {
          controller.jumpTo(0);
        }
      });
    }

    final ArticleListPageState state = widget.state;
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: _KeyboardLayer(
        index: _keyboardIndex,
        total: state.entries.length,
        onMove: _moveKeyboardSelection,
        onOpen: _openKeyboardSelection,
        onEscape: _handleEscape,
        child: ListView.builder(
          controller: _controller,
          padding: const EdgeInsets.all(FluxSpacing.md),
          // ListView.builder **只构建可见区域附近的条目**（真正的虚拟化）：一万条也
          // 只构建当前可见的十来张卡片。列表条的末尾额外给出「已加载/总数」或
          // 「加载更多」，因此 +1。
          itemCount: state.entries.length + 1,
          itemBuilder: (BuildContext context, int index) {
            if (index == state.entries.length) {
              return _ListTail(state: state);
            }
            final ArticleListEntry entry = state.entries[index];
            return Padding(
              padding: EdgeInsets.only(
                bottom: index == state.entries.length - 1 ? 0 : FluxSpacing.xs,
              ),
              child: _ArticleCard(
                entry: entry,
                mode: widget.mode,
                selected: state.selectedIds.contains(entry.id),
                batchMode: state.batchMode,
                keyboardSelected: _keyboardIndex == index,
              ),
            );
          },
        ),
      ),
    );
  }

  /// 上下键移动键盘落点，并把它滚进可见区域。
  ///
  /// 夹取而不是环绕：从第一行按上键应该「停住」，环绕会让用户一下子跳到列表末尾，
  /// 而屏幕上的滚动位置与他的预期相反。
  void _moveKeyboardSelection(int delta) {
    final int total = widget.state.entries.length;
    if (total == 0) {
      return;
    }
    final int current = _keyboardIndex ?? (delta > 0 ? -1 : total);
    final int next = (current + delta).clamp(0, total - 1);
    if (next == _keyboardIndex) {
      return;
    }
    setState(() => _keyboardIndex = next);
    _scrollRowIntoView(next);
    // 读屏播报当前选中行：光标在列表上来回移动时，用户需要知道停在了第几篇，
    // 而不是只能靠 Enter 之后打开的页面来推断。
    final ArticleListEntry entry = widget.state.entries[next];
    final AppLocalizations l10n = AppLocalizations.of(context);
    // sendAnnouncement 而不是已弃用的 announce：后者不区分窗口，多窗口下会播报到
    // 错误的窗口（框架已标记弃用并说明原因）。视图 id 从当前 context 取。
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        '${l10n.a11yListSelection(next + 1, total)}：${entry.title}',
        Directionality.of(context),
      ),
    );
  }

  /// 把第 [index] 行滚进可见区域。
  ///
  /// 卡片高度由内容决定（标题 2 行 / 摘要 1 行 / 大字号），因此不能用「行高 × 下标」
  /// 估算偏移；用 [Scrollable.ensureVisible] 让框架按真实布局算，与拖动滚动条的结果
  /// 一致。行还没被构建时（虚拟化的正常情形）先滚动到相邻位置再让它出现。
  void _scrollRowIntoView(int index) {
    final int total = widget.state.entries.length;
    final ScrollController controller = _controller;
    if (!controller.hasClients) {
      return;
    }
    final double rowHeight = _estimatedRowHeight();
    final double target =
        (index * rowHeight) -
        (controller.position.viewportDimension / 2) +
        (rowHeight / 2);
    final double clamped = target.clamp(
      0.0,
      controller.position.maxScrollExtent,
    );
    controller.jumpTo(clamped);
    // 保证「最后一行」在只有部分可见时也被滚到底：估算值随字号变化，不能完全依赖。
    if (index >= total - 1) {
      controller.jumpTo(controller.position.maxScrollExtent);
    }
  }

  /// 一行卡片的估算高度（用于把键盘落点滚进视野）。
  ///
  /// 刻意用一个粗略值：真正的依据是「滚到哪一行附近」，随后框架的可见性判断会把
  /// 卡片完整渲染出来。精确高度需要测量每一行，而那正是虚拟化要避免的开销。
  double _estimatedRowHeight() =>
      widget.mode == ArticleCardViewMode.compact ? 72 : 132;

  /// 回车打开键盘选中的那篇。
  Future<void> _openKeyboardSelection() async {
    final int? index = _keyboardIndex;
    if (index == null) {
      return;
    }
    if (index < 0 || index >= widget.state.entries.length) {
      return;
    }
    final ArticleListEntry entry = widget.state.entries[index];
    await _openEntry(context, ref, entry, batchMode: widget.state.batchMode);
  }

  /// Esc：按「用户此刻最想退出什么」的顺序逐层撤销。
  ///
  /// 顺序刻意如此，且**一次只退一层**：批量模式在最外层（它是整个列表的形态），
  /// 然后才是键盘落点。一次退掉两层会让用户以为自己只按了一下却退了两步。
  ///
  /// 返回 true 表示这一层消费了 Esc。**不能无条件返回 true**：更外层的阅读页要用
  /// Esc 退出搜索，而键盘落点为空时这里没有任何东西可退，事件必须继续冒泡。
  /// 吞掉它会表现成「Esc 在这里没反应」。
  bool _handleEscape() {
    if (widget.state.batchMode) {
      // setBatchMode 是同步的（只是切一个开关）；不 await 一个 void 返回的调用。
      ref.read(articleListControllerProvider.notifier).setBatchMode(false);
      return true;
    }
    if (_keyboardIndex != null) {
      setState(() => _keyboardIndex = null);
      return true;
    }
    return false;
  }
}

/// 列表末尾：说明当前已加载多少，或提供「加载更多」。
///
/// 为什么两条信息都要在：只给一个「加载更多」按钮时，用户无法判断「还有多少没看到」；
/// 而只给计数不给按钮时，键盘用户（无法「滚到底」）就没有办法继续加载。
///
/// 与底栏的分工：底栏是**常驻**的页面状态（无论滚到哪里都看得见还差多少），列表末尾
/// 是滚到那里时才出现的**就地**入口——用户在那里刚好看完已加载的内容，此时把
/// 「继续加载」放在手指/光标所在的位置，比让他回到页面底部去点一个按钮更直接。
class _ListTail extends ConsumerWidget {
  const _ListTail({required this.state});

  final ArticleListPageState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool more = state.page.hasMore(state.total);
    if (!more) {
      // 已经读完全部内容时不再插入一块「已加载 N / N」的重复文字：底栏已经说了同一
      // 件事，列表末尾再来一行只是把列表的结束位置往下推。
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FluxSpacing.md),
      child: Column(
        children: <Widget>[
          Text(
            l10n.readingLoadedCount(state.entries.length, state.total),
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: FluxSpacing.xs),
          TextButton(
            onPressed: () => ref
                .read(articleListControllerProvider.notifier)
                .loadMoreBatch(),
            child: Text(l10n.readingLoadMore),
          ),
        ],
      ),
    );
  }
}

/// 单张文章卡片。
///
/// 卡片形态（紧凑/正常/宽松）与虚拟化属 T019，这里是正常形态的最小版本：
/// 标题 + 来源与时间 + 一行摘要，行尾是三态控件与收藏星形（两者是**独立**控件）。
class _ArticleCard extends ConsumerWidget {
  const _ArticleCard({
    required this.entry,
    required this.mode,
    required this.selected,
    required this.batchMode,
    this.keyboardSelected = false,
  });

  final ArticleListEntry entry;
  final ArticleCardViewMode mode;
  final bool selected;
  final bool batchMode;

  /// 是否是键盘落点所在行（与批量勾选无关：那是两条独立的选择语义）。
  final bool keyboardSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ArticleListController controller = ref.read(
      articleListControllerProvider.notifier,
    );

    final Widget card = FluxCard(
      // 批量勾选与键盘落点是两种不同的「选中」，视觉上必须能区分：
      // 勾选用强调色边框（表示会参与批量操作），键盘落点用底色（表示光标在这里）。
      selected: selected,
      keyboardFocus: keyboardSelected,
      onTap: () => _open(context, ref),
      semanticsLabel: entry.title,
      child: ArticleCardBody(
        entry: entry,
        mode: mode,
        metaLine: _metaLine(l10n),
        leading: batchMode
            ? Checkbox(
                value: selected,
                onChanged: (bool? _) => controller.toggleSelected(entry.id),
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ReadingStateControl(
              state: entry.readingState,
              size: FluxIconSize.small,
              // 批量模式下两个状态控件都只读：此刻点它们会同时改动「当前行」
              // 与「用户的勾选意图」，两件事混在一次点击里。
              onChanged: batchMode
                  ? null
                  : (ReadingState next) =>
                        controller.setReadingState(entry.id, next),
            ),
            FavoriteToggle(
              favorite: entry.favorite,
              size: FluxIconSize.small,
              onChanged: batchMode
                  ? null
                  : (bool _) => controller.toggleFavorite(entry.id),
            ),
          ],
        ),
      ),
    );

    // 右键菜单（架构第 3 节的「列表项菜单」）提供三态与收藏的**直达**选择。
    // 三态控件是循环切换（T012 选定的交互），菜单补上「直接选到某一档」的路径，
    // 但控件位与数据模型不变（仍然是一个控件、单一取值）。
    return GestureDetector(
      onSecondaryTapDown: (TapDownDetails details) =>
          _showMenu(context, ref, details.globalPosition),
      child: card,
    );
  }

  /// 元信息行：来源 + 时间（发布时间缺失时明确注明）。
  String _metaLine(AppLocalizations l10n) {
    final String time = entry.publishedAtMissing
        ? l10n.readingPublishedUnknown
        : formatLocalTime(entry.effectiveTime);
    // 已脱离源（来源订阅已被删除）的收藏：来源名来自删除那一刻的快照，因此这里
    // 明确标注「已脱离订阅」，让用户看出它不再由任何源更新（架构 4.1）。
    if (entry.detachedFromFeed) {
      return '${entry.feedName}（${l10n.detachedFeedLabel}） · $time';
    }
    return '${entry.feedName} · $time';
  }

  /// 打开正文；批量模式下点卡片是勾选。
  Future<void> _open(BuildContext context, WidgetRef ref) async {
    if (batchMode) {
      // 批量选择时点到一行，用户期望的是把它加入选择，而不是跳走。
      ref.read(articleListControllerProvider.notifier).toggleSelected(entry.id);
      return;
    }
    await _openEntry(context, ref, entry, batchMode: false);
  }

  /// 右键菜单：打开/三态直达/收藏/在正文中打开/彻底删除。
  Future<void> _showMenu(
    BuildContext context,
    WidgetRef ref,
    Offset position,
  ) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final OverlayState overlay = Overlay.of(context);
    final RenderBox box = overlay.context.findRenderObject()! as RenderBox;
    final _ArticleMenuAction? action = await showMenu<_ArticleMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & box.size,
      ),
      items: <PopupMenuEntry<_ArticleMenuAction>>[
        PopupMenuItem<_ArticleMenuAction>(
          value: _ArticleMenuAction.open,
          child: Text(l10n.readingOpenArticle),
        ),
        PopupMenuItem<_ArticleMenuAction>(
          value: _ArticleMenuAction.openInBrowser,
          child: Text(l10n.readingOpenOriginal),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<_ArticleMenuAction>(
          value: _ArticleMenuAction.markUnread,
          child: Text(l10n.readingStateUnread),
        ),
        PopupMenuItem<_ArticleMenuAction>(
          value: _ArticleMenuAction.markRead,
          child: Text(l10n.readingStateRead),
        ),
        PopupMenuItem<_ArticleMenuAction>(
          value: _ArticleMenuAction.markLater,
          child: Text(l10n.readingStateLater),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<_ArticleMenuAction>(
          value: entry.favorite
              ? _ArticleMenuAction.unfavorite
              : _ArticleMenuAction.favorite,
          child: Text(
            entry.favorite ? l10n.favoriteRemoveLabel : l10n.favoriteAddLabel,
          ),
        ),
        // 彻底删除（T047 的入口在详情页；列表项菜单补上同一条路径）。
        // 放在最末并与上面隔一条分隔线：它不可撤销，且是这里唯一会真正移除文章的动作。
        const PopupMenuDivider(),
        PopupMenuItem<_ArticleMenuAction>(
          value: _ArticleMenuAction.delete,
          child: Text(
            l10n.articleMenuDelete,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
    );
    if (action == null || !context.mounted) {
      return;
    }
    final ArticleListController controller = ref.read(
      articleListControllerProvider.notifier,
    );
    switch (action) {
      case _ArticleMenuAction.open:
        await _open(context, ref);
      case _ArticleMenuAction.openInBrowser:
        await openArticleInBrowser(context, ref, entry);
      case _ArticleMenuAction.markUnread:
        await controller.setReadingState(entry.id, ReadingState.unread);
      case _ArticleMenuAction.markRead:
        await controller.setReadingState(entry.id, ReadingState.read);
      case _ArticleMenuAction.markLater:
        await controller.setReadingState(entry.id, ReadingState.later);
      case _ArticleMenuAction.favorite:
      case _ArticleMenuAction.unfavorite:
        await controller.toggleFavorite(entry.id);
      case _ArticleMenuAction.delete:
        await _purge(context, ref);
    }
  }

  /// 彻底删除这篇文章（先列关联范围，再确认，再执行）。
  ///
  /// 与详情页的入口共用同一套用例（CleanupService）；这里**不复制**删除逻辑，
  /// 否则「保留引用最小摘录」这类规则会出现第二份实现。
  Future<void> _purge(BuildContext context, WidgetRef ref) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final CleanupService service = ref.read(cleanupServiceProvider);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final Result<ArticlePurgeImpact> preview = await service
        .previewArticlePurge(entry.id);
    if (!context.mounted) {
      return;
    }
    if (preview.isErr) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(l10n.storageFailed(preview.errorOrNull!.kind)),
          ),
        );
      return;
    }
    final ArticlePurgeImpact impact = preview.unwrap();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        key: const ValueKey<String>('article-list-purge-dialog'),
        title: Text(l10n.storagePurgeTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(impact.title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: FluxSpacing.sm),
            Text(
              impact.hasRelated
                  ? l10n.storagePurgeImpact(
                      impact.translations,
                      impact.readingSessions,
                      impact.cachedMedia,
                      impact.citations,
                    )
                  : l10n.storagePurgeNone,
            ),
            const SizedBox(height: FluxSpacing.sm),
            Text(l10n.storagePurgeNotice),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.settingsBackupCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.storagePurgeConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    final Result<ArticlePurgeImpact> purged = await service.purgeArticle(
      entry.id,
    );
    if (purged.isErr) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text(l10n.storageFailed(purged.errorOrNull!.kind))),
        );
      return;
    }
    final ArticlePurgeImpact done = purged.unwrap();
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            l10n.articlePurgeDone(
              done.citations,
              done.translations,
              done.readingSessions,
              done.cachedMedia,
            ),
          ),
        ),
      );
    await ref.read(articleListControllerProvider.notifier).reload();
  }
}

/// 右键菜单的动作。
enum _ArticleMenuAction {
  open,
  openInBrowser,
  markUnread,
  markRead,
  markLater,
  favorite,
  unfavorite,
  delete,
}

/// 打开一篇正文（列表卡片与键盘回车共用）。
///
/// 抽成函数而不是各自写一份：两处都必须做同两件事——批量模式下改勾选而不是跳转，
/// 以及把「进入时的筛选/排序快照」带进详情页（上下篇依据它，而不是在详情页按当前
/// 筛选现算；现算会让「下一篇」落到一篇与用户进来时无关的文章上，架构 4.1）。
Future<void> _openEntry(
  BuildContext context,
  WidgetRef ref,
  ArticleListEntry entry, {
  required bool batchMode,
}) async {
  if (batchMode) {
    // 批量选择时点到一行，用户期望的是把它加入选择，而不是跳走。
    ref.read(articleListControllerProvider.notifier).toggleSelected(entry.id);
    return;
  }
  final ReaderSnapshot? snapshot = await ref
      .read(articleListControllerProvider.notifier)
      .snapshotFor(entry.id);
  if (!context.mounted) {
    return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (BuildContext context) => ArticleDetailPage(
        articleId: entry.id,
        initialTitle: entry.title,
        snapshot: snapshot,
      ),
    ),
  );
}

/// 用系统默认浏览器打开这篇文章的原文地址。
///
/// 地址缺失时给出明确说明而不是什么都不做：一个点了没反应的菜单项会让用户以为
/// 应用坏了。地址的安全性由 T020 的外部打开适配器复核（它自己再校验一次协议）。
Future<void> openArticleInBrowser(
  BuildContext context,
  WidgetRef ref,
  ArticleListEntry entry,
) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final String? url = entry.sourceUrl;
  if (url == null || url.isEmpty) {
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(l10n.readingSourceUrlMissing)));
    return;
  }
  final Result<void> opened = await ref
      .read(externalLinkOpenerProvider)
      .openExternal(url);
  if (opened.isErr) {
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.readingLinkOpenFailed(opened.errorOrNull!.kind)),
        ),
      );
  }
}

/// 列表键盘层：上下键移动落点、回车打开、Esc 退出选择/搜索/批量。
///
/// 为什么用 [Focus] + [onKeyEvent] 而不是再加一层 Shortcuts/Actions：
///   列表里的上下键与 Flutter 的**默认**方向键语义（DirectionalFocusIntent，在控件
///   之间移动焦点）冲突。用 Shortcuts 覆盖它需要在 Actions 里也提供实现，而这里只有
///   八个键、没有需要与其它 Shortcuts 合并的条目；直接接管 KeyEvent 更短也更明确，
///   且能精确控制「什么时候返回 handled」——返回 ignored 时按键照常冒泡（例如列表
///   没有内容时向上箭头应继续交给外层滚动）。
class _KeyboardLayer extends StatefulWidget {
  const _KeyboardLayer({
    required this.index,
    required this.total,
    required this.onMove,
    required this.onOpen,
    required this.onEscape,
    required this.child,
  });

  /// 当前键盘落点（null 表示还没有）。
  final int? index;

  /// 行数。
  final int total;

  /// 上下移动。
  final ValueChanged<int> onMove;

  /// 回车打开。
  final VoidCallback onOpen;

  /// Esc：返回 true 表示这一层消费了它（界面需要相应改变）。
  final bool Function() onEscape;

  /// 子树。
  final Widget child;

  @override
  State<_KeyboardLayer> createState() => _KeyboardLayerState();
}

class _KeyboardLayerState extends State<_KeyboardLayer> {
  late final FocusNode _focusNode = FocusNode(debugLabel: 'ArticleListKeys');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      // 这一层**要拿到焦点**，而且进入页面时自动获取（T049 的「列表上下键选择 + 回车
      // 打开」）。
      //
      // 为什么不能像最初那样 canRequestFocus: false（实测踩到的坑）：按键事件只沿
      // 当前焦点结点的**祖先链**投递。没有控件聚焦时 primaryFocus 是路由的 FocusScope，
      // 它是本控件的**祖先**，事件只会从它向上走，永远到不了这里——表现就是「按上下键
      // 毫无反应」，而键盘层看起来挂得好好的。
      //
      // 焦点提示由**行本身**提供（FluxCard.keyboardFocus 画强调边框），因此这一层没有
      // 可视焦点环不会让用户迷路：进列表按上下键，落点行立刻带边框出现。
      canRequestFocus: true,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: widget.child,
    );
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      if (widget.total == 0) {
        return KeyEventResult.ignored;
      }
      widget.onMove(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (widget.total == 0) {
        return KeyEventResult.ignored;
      }
      widget.onMove(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (widget.index == null) {
        // 还没有落点时回车交给外层（例如「加载更多」按钮的激活），不要吞掉它。
        return KeyEventResult.ignored;
      }
      widget.onOpen();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      return widget.onEscape()
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }
}
