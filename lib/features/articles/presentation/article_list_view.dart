// 文章列表主体（T017）：空态区分 + 卡片 + 分页 + 右键菜单 + 批量操作栏。
//
// 从 reading_page.dart 拆出来：整页里有三块职责（工具栏/列表/批量栏），一个文件
// 装下会让「空态判断」与「批量范围」这两处最容易写错的逻辑埋在滚动里。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';
import 'package:flux/core/design/design_tokens.dart';
import 'package:flux/features/feeds/presentation/feed_manager_controller.dart';
import 'package:flux/l10n/l10n.dart';
import 'package:flux/ui/ui.dart';

import 'article_detail_page.dart';
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

    return Column(
      children: <Widget>[
        // 批量操作栏放在列表**上方**。它原先在底部，实测被操作结果提示条
        // （SnackBar）盖住：用户点「标为已读」之后想接着点「加入收藏」，那一下会
        // 落在提示条上而不是按钮上——一个「点了没反应」的按钮比没有按钮更糟。
        if (state.batchMode) BatchActionBar(state: state),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(FluxSpacing.md),
            itemCount: state.entries.length,
            separatorBuilder: (BuildContext context, int index) =>
                const SizedBox(height: FluxSpacing.xs),
            itemBuilder: (BuildContext context, int index) => _ArticleCard(
              entry: state.entries[index],
              selected: state.selectedIds.contains(state.entries[index].id),
              batchMode: state.batchMode,
            ),
          ),
        ),
        ArticlePager(state: state),
      ],
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
    required this.selected,
    required this.batchMode,
  });

  final ArticleListEntry entry;
  final bool selected;
  final bool batchMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ArticleListController controller = ref.read(
      articleListControllerProvider.notifier,
    );

    final Widget card = FluxCard(
      selected: selected,
      onTap: () => _open(context, ref),
      semanticsLabel: entry.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (batchMode)
                Checkbox(
                  value: selected,
                  onChanged: (bool? _) => controller.toggleSelected(entry.id),
                ),
              Expanded(
                child: Text(
                  entry.title,
                  style: theme.textTheme.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: FluxSpacing.xxs),
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
          const SizedBox(height: FluxSpacing.xxs),
          Text(_metaLine(l10n), style: theme.textTheme.labelSmall),
          if (entry.summary case final String summary) ...<Widget>[
            const SizedBox(height: FluxSpacing.xxs),
            Text(
              summary,
              style: theme.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
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
    return '${entry.feedName} · $time';
  }

  /// 打开正文；批量模式下点卡片是勾选。
  Future<void> _open(BuildContext context, WidgetRef ref) async {
    if (batchMode) {
      // 批量选择时点到一行，用户期望的是把它加入选择，而不是跳走。
      ref.read(articleListControllerProvider.notifier).toggleSelected(entry.id);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            ArticleDetailPage(articleId: entry.id, initialTitle: entry.title),
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
