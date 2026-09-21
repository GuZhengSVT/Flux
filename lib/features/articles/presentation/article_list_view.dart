// 文章列表主体（T017，T019+ 产品化）：空态区分 + 三种卡片形态 + 虚拟化分批加载 +
// 返回锚点 + 右键菜单 + 批量操作栏。
//
// 从 reading_page.dart 拆出来：整页里有三块职责（工具栏/列表/批量栏），一个文件
// 装下会让「空态判断」与「批量范围」这两处最容易写错的逻辑埋在滚动里。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';
import 'package:flux/core/design/design_tokens.dart';
import 'package:flux/features/feeds/presentation/feed_manager_controller.dart';
import 'package:flux/l10n/l10n.dart';
import 'package:flux/ui/ui.dart';

import '../application/article_card_view.dart';
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
            ),
          );
        },
      ),
    );
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
  });

  final ArticleListEntry entry;
  final ArticleCardViewMode mode;
  final bool selected;
  final bool batchMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ArticleListController controller = ref.read(
      articleListControllerProvider.notifier,
    );

    final Widget card = FluxCard(
      selected: selected,
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
    // 把「进入时的筛选/排序快照」带进详情页：上下篇依据它，而不是在详情页按当前筛选
    // 现算（现算会让「下一篇」落到一篇与用户进来时无关的文章上，架构 4.1）。
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

  /// 右键菜单：三态直达 + 收藏 + 打开。
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
      case _ArticleMenuAction.markUnread:
        await controller.setReadingState(entry.id, ReadingState.unread);
      case _ArticleMenuAction.markRead:
        await controller.setReadingState(entry.id, ReadingState.read);
      case _ArticleMenuAction.markLater:
        await controller.setReadingState(entry.id, ReadingState.later);
      case _ArticleMenuAction.favorite:
      case _ArticleMenuAction.unfavorite:
        await controller.toggleFavorite(entry.id);
    }
  }
}

/// 右键菜单的动作。
enum _ArticleMenuAction {
  open,
  markUnread,
  markRead,
  markLater,
  favorite,
  unfavorite,
}
