import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/feed.dart';
import '../providers/feed_provider.dart';
import '../theme/flux_theme.dart';
import '../widgets/text_prompt.dart';
import 'add_feed_screen.dart';

class SubscriptionManagementScreen extends ConsumerStatefulWidget {
  const SubscriptionManagementScreen({super.key});

  @override
  ConsumerState<SubscriptionManagementScreen> createState() =>
      _SubscriptionManagementScreenState();
}

class _SubscriptionManagementScreenState
    extends ConsumerState<SubscriptionManagementScreen> {
  final _newGroupController = TextEditingController();

  @override
  void dispose() {
    _newGroupController.dispose();
    super.dispose();
  }

  void _createGroup() {
    final name = _newGroupController.text.trim();
    if (name.isEmpty) {
      return;
    }
    ref.read(feedControllerProvider.notifier).createGroup(name);
    _newGroupController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dropdownColor = isDark ? FluxColors.darkRaised : FluxColors.bone;
    final state = ref.watch(feedControllerProvider);
    final controller = ref.read(feedControllerProvider.notifier);

    final ungrouped = state.feeds
        .where((f) => f.category == null || f.category!.trim().isEmpty)
        .toList();
    final grouped = <String, List<Feed>>{
      for (final group in state.groups)
        group: state.feeds.where((f) => f.category == group).toList(),
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('订阅管理'),
        actions: [
          IconButton(
            tooltip: '添加订阅',
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AddFeedScreen()),
            ),
          ),
        ],
      ),
      body: ColoredBox(
        color: isDark
            ? FluxColors.darkSurface.withValues(alpha: 0.50)
            : FluxColors.bone.withValues(alpha: 0.50),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<FeedSort>(
                      initialValue: state.feedSort,
                      dropdownColor: dropdownColor,
                      decoration: const InputDecoration(
                        labelText: '订阅排序',
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: FeedSort.name,
                          child: Text('按名称'),
                        ),
                        DropdownMenuItem(
                          value: FeedSort.lastUpdated,
                          child: Text('按最近更新'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          controller.setFeedSort(value);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<TimeRange>(
                      initialValue: state.feedTimeRange,
                      dropdownColor: dropdownColor,
                      decoration: const InputDecoration(
                        labelText: '时间筛选',
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: TimeRange.all,
                          child: Text('全部'),
                        ),
                        DropdownMenuItem(
                          value: TimeRange.today,
                          child: Text('今日'),
                        ),
                        DropdownMenuItem(
                          value: TimeRange.week,
                          child: Text('本周'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          controller.setFeedTimeRange(value);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newGroupController,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _createGroup(),
                      decoration: const InputDecoration(
                        labelText: '新建分组',
                        hintText: '例如：技术',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: _createGroup,
                      icon: const Icon(Icons.add),
                      label: const Text('添加'),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _GroupBlock(
                    name: '未分组',
                    feeds: ungrouped,
                    canEdit: false,
                    onMoveFeed: (feedId, groupName) =>
                        controller.updateFeedCategory(feedId, groupName),
                    onRefreshFeed: (feedId) => controller.refreshFeed(feedId),
                    onToggleFavorite: (feedId) =>
                        controller.toggleFeedFavorite(feedId),
                    onTogglePinned: (feedId) =>
                        controller.toggleFeedPinned(feedId),
                    onSetRating: (feedId, rating) =>
                        controller.setFeedRating(feedId, rating),
                    onRenameFeed: (feedId, title) =>
                        controller.renameFeed(feedId, title),
                    onEditUrl: (feedId, url) =>
                        controller.updateFeedUrl(feedId, url),
                    onDeleteFeed: (feedId) => controller.deleteFeed(feedId),
                  ),
                  for (final group in state.groups)
                    _GroupBlock(
                      name: group,
                      feeds: grouped[group] ?? const [],
                      canEdit: true,
                      onMoveFeed: (feedId, groupName) =>
                          controller.updateFeedCategory(feedId, groupName),
                      onRefreshGroup: () => controller.refreshGroup(group),
                      onRenameGroup: () =>
                          _promptRenameGroup(controller, group),
                      onDeleteGroup: () =>
                          _confirmDeleteGroup(controller, group),
                      onRefreshFeed: (feedId) => controller.refreshFeed(feedId),
                      onToggleFavorite: (feedId) =>
                          controller.toggleFeedFavorite(feedId),
                      onTogglePinned: (feedId) =>
                          controller.toggleFeedPinned(feedId),
                      onSetRating: (feedId, rating) =>
                          controller.setFeedRating(feedId, rating),
                      onRenameFeed: (feedId, title) =>
                          controller.renameFeed(feedId, title),
                      onEditUrl: (feedId, url) =>
                          controller.updateFeedUrl(feedId, url),
                      onDeleteFeed: (feedId) => controller.deleteFeed(feedId),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _promptRenameGroup(
    FeedController controller,
    String group,
  ) async {
    final name = await showTextPrompt(context, title: '重命名分组', initial: group);
    if (name != null && name.trim().isNotEmpty) {
      controller.renameGroup(group, name.trim());
    }
  }

  Future<void> _confirmDeleteGroup(
    FeedController controller,
    String group,
  ) async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除分组“$group”'),
        content: const Text('请选择删除方式：'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('keep'),
            child: const Text('仅删除分组'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('delete'),
            child: const Text(
              '同时删除订阅',
              style: TextStyle(color: FluxColors.red),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (action == 'keep') {
      controller.deleteGroup(group);
    } else if (action == 'delete') {
      controller.deleteGroupWithOption(group, deleteFeeds: true);
    }
  }
}

class _GroupBlock extends StatelessWidget {
  const _GroupBlock({
    required this.name,
    required this.feeds,
    required this.canEdit,
    required this.onMoveFeed,
    required this.onRefreshFeed,
    required this.onToggleFavorite,
    required this.onTogglePinned,
    required this.onSetRating,
    required this.onRenameFeed,
    required this.onEditUrl,
    required this.onDeleteFeed,
    this.onRefreshGroup,
    this.onRenameGroup,
    this.onDeleteGroup,
  });

  final String name;
  final List<Feed> feeds;
  final bool canEdit;
  final void Function(int feedId, String? groupName) onMoveFeed;
  final ValueChanged<int> onRefreshFeed;
  final ValueChanged<int> onToggleFavorite;
  final ValueChanged<int> onTogglePinned;
  final void Function(int feedId, int rating) onSetRating;
  final void Function(int feedId, String title) onRenameFeed;
  final void Function(int feedId, String url) onEditUrl;
  final ValueChanged<int> onDeleteFeed;
  final VoidCallback? onRefreshGroup;
  final VoidCallback? onRenameGroup;
  final VoidCallback? onDeleteGroup;

  @override
  Widget build(BuildContext context) {
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) =>
          onMoveFeed(details.data, name == '未分组' ? null : name),
      builder: (context, candidate, rejected) {
        final highlight = candidate.isNotEmpty;
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            border: Border.all(
              color: highlight
                  ? FluxColors.red
                  : Theme.of(context).dividerColor,
              width: highlight ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _GroupHeader(
                name: name,
                count: feeds.length,
                canEdit: canEdit,
                onRefreshGroup: onRefreshGroup,
                onRenameGroup: onRenameGroup,
                onDeleteGroup: onDeleteGroup,
              ),
              if (feeds.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('该分组暂无订阅，可拖入订阅'),
                )
              else
                for (final feed in feeds)
                  _DraggableFeedTile(
                    feed: feed,
                    onRefresh: () => onRefreshFeed(feed.id!),
                    onToggleFavorite: () => onToggleFavorite(feed.id!),
                    onTogglePinned: () => onTogglePinned(feed.id!),
                    onSetRating: (rating) => onSetRating(feed.id!, rating),
                    onRename: () => _promptRename(context, feed),
                    onEditUrl: () => _promptEditUrl(context, feed),
                    onDelete: () => onDeleteFeed(feed.id!),
                  ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _promptRename(BuildContext context, Feed feed) async {
    final title = await showTextPrompt(
      context,
      title: '重命名订阅',
      initial: feed.title,
    );
    if (title != null && title.trim().isNotEmpty) {
      onRenameFeed(feed.id!, title.trim());
    }
  }

  Future<void> _promptEditUrl(BuildContext context, Feed feed) async {
    final url = await showTextPrompt(context, title: '订阅链接', initial: feed.url);
    if (url != null && url.trim().isNotEmpty) {
      onEditUrl(feed.id!, url.trim());
    }
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.name,
    required this.count,
    required this.canEdit,
    this.onRefreshGroup,
    this.onRenameGroup,
    this.onDeleteGroup,
  });

  final String name;
  final int count;
  final bool canEdit;
  final VoidCallback? onRefreshGroup;
  final VoidCallback? onRenameGroup;
  final VoidCallback? onDeleteGroup;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          Text(
            '$count 个订阅',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (canEdit) ...[
            IconButton(
              tooltip: '刷新组内订阅',
              icon: const Icon(Icons.refresh),
              onPressed: onRefreshGroup,
            ),
            IconButton(
              tooltip: '重命名分组',
              icon: const Icon(Icons.drive_file_rename_outline),
              onPressed: onRenameGroup,
            ),
            IconButton(
              tooltip: '删除分组',
              icon: const Icon(Icons.delete_outline),
              onPressed: onDeleteGroup,
            ),
          ],
        ],
      ),
    );
  }
}

class _DraggableFeedTile extends StatelessWidget {
  const _DraggableFeedTile({
    required this.feed,
    required this.onRefresh,
    required this.onToggleFavorite,
    required this.onTogglePinned,
    required this.onSetRating,
    required this.onRename,
    required this.onEditUrl,
    required this.onDelete,
  });

  final Feed feed;
  final VoidCallback onRefresh;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTogglePinned;
  final ValueChanged<int> onSetRating;
  final VoidCallback onRename;
  final VoidCallback onEditUrl;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tile = ListTile(
      leading: const Icon(Icons.drag_indicator, color: FluxColors.concrete),
      minLeadingWidth: 32,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      title: Row(
        children: [
          if (feed.isPinned) ...[
            const Icon(Icons.push_pin, size: 16, color: FluxColors.red),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              feed.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (feed.rating > 0)
            Text(
              '★' * feed.rating,
              style: const TextStyle(color: FluxColors.red, fontSize: 12),
            ),
        ],
      ),
      subtitle: Text(feed.url, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: PopupMenuButton<String>(
        tooltip: '更多操作',
        onSelected: (value) {
          switch (value) {
            case 'favorite':
              onToggleFavorite();
            case 'pinned':
              onTogglePinned();
            case 'refresh':
              onRefresh();
            case 'rating':
              _showRatingSubmenu(context);
            case 'rename':
              onRename();
            case 'editUrl':
              onEditUrl();
            case 'delete':
              onDelete();
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'favorite',
            child: Text(feed.isFavorite ? '取消收藏' : '收藏'),
          ),
          PopupMenuItem(
            value: 'pinned',
            child: Text(feed.isPinned ? '取消置顶' : '置顶'),
          ),
          const PopupMenuItem(value: 'refresh', child: Text('刷新')),
          PopupMenuItem(
            value: 'rating',
            child: const SizedBox(
              width: 150,
              child: Row(
                children: [
                  Icon(Icons.grade_outlined, size: 20),
                  SizedBox(width: 12),
                  Text('分级'),
                  Spacer(),
                  Icon(Icons.chevron_right, size: 18),
                ],
              ),
            ),
          ),
          const PopupMenuItem(value: 'rename', child: Text('重命名')),
          const PopupMenuItem(value: 'editUrl', child: Text('修改链接')),
          const PopupMenuItem(value: 'delete', child: Text('删除')),
        ],
      ),
    );

    return Draggable<int>(
      data: feed.id!,
      feedback: Material(
        elevation: 4,
        child: SizedBox(
          width: 280,
          child: ListTile(
            leading: const Icon(Icons.rss_feed),
            title: Text(
              feed.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: tile),
      child: tile,
    );
  }

  Future<void> _showRatingSubmenu(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    final selected = await showMenu<int>(
      context: context,
      position: RelativeRect.fromLTRB(
        origin.dx,
        origin.dy,
        origin.dx,
        origin.dy,
      ),
      items: const [
        PopupMenuItem(value: 0, child: Text('不分级')),
        PopupMenuItem(value: 1, child: Text('★ 1')),
        PopupMenuItem(value: 2, child: Text('★★ 2')),
        PopupMenuItem(value: 3, child: Text('★★★ 3')),
        PopupMenuItem(value: 4, child: Text('★★★★ 4')),
        PopupMenuItem(value: 5, child: Text('★★★★★ 5')),
      ],
    );
    if (selected != null) {
      onSetRating(selected);
    }
  }
}
