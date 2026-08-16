import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/feed.dart';
import '../providers/feed_provider.dart';
import '../theme/flux_theme.dart';

class GroupManagementScreen extends ConsumerStatefulWidget {
  const GroupManagementScreen({super.key});

  @override
  ConsumerState<GroupManagementScreen> createState() =>
      _GroupManagementScreenState();
}

class _GroupManagementScreenState extends ConsumerState<GroupManagementScreen> {
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
    final state = ref.watch(feedControllerProvider);
    final controller = ref.read(feedControllerProvider.notifier);

    int countOf(String? group) =>
        state.feeds.where((f) => f.category == group).length;

    return Scaffold(
      appBar: AppBar(title: const Text('分组管理')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          const Text('新建分组', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newGroupController,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _createGroup(),
                  decoration: const InputDecoration(
                    labelText: '分组名称',
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
          const Divider(height: 28),
          const Text('未分组', style: TextStyle(fontWeight: FontWeight.w800)),
          ListTile(
            leading: const Icon(Icons.folder_off_outlined),
            title: const Text('未分组订阅'),
            subtitle: Text('${countOf(null)} 个订阅'),
            onTap: () => Navigator.of(context).pop(),
          ),
          const Divider(height: 20),
          for (final group in state.groups) ...[
            _GroupTile(
              name: group,
              count: countOf(group),
              onRefresh: () => controller.refreshGroup(group),
              onRename: () => _promptRenameGroup(context, controller, group),
              onDelete: () => _confirmDeleteGroup(context, controller, group),
              onManage: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _GroupFeedsScreen(groupName: group),
                  ),
                );
              },
            ),
          ],
          if (state.groups.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Center(child: Text('还没有分组，先在上方创建一个。')),
            ),
        ],
      ),
    );
  }

  Future<void> _promptRenameGroup(
    BuildContext context,
    FeedController controller,
    String group,
  ) async {
    final name = await _promptText(context, '重命名分组', group);
    if (name != null && name.trim().isNotEmpty) {
      controller.renameGroup(group, name.trim());
    }
  }

  Future<void> _confirmDeleteGroup(
    BuildContext context,
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

  Future<String?> _promptText(
    BuildContext context,
    String title,
    String initial,
  ) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '请输入名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({
    required this.name,
    required this.count,
    required this.onRefresh,
    required this.onRename,
    required this.onDelete,
    required this.onManage,
  });

  final String name;
  final int count;
  final VoidCallback onRefresh;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(2),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.folder_outlined),
        title: Text(name),
        subtitle: Text('$count 个订阅'),
        onTap: onManage,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '管理订阅',
              icon: const Icon(Icons.settings_outlined),
              onPressed: onManage,
            ),
            IconButton(
              tooltip: '刷新组内订阅',
              icon: const Icon(Icons.refresh),
              onPressed: onRefresh,
            ),
            IconButton(
              tooltip: '重命名',
              icon: const Icon(Icons.drive_file_rename_outline),
              onPressed: onRename,
            ),
            IconButton(
              tooltip: '删除',
              icon: const Icon(Icons.delete_outline),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupFeedsScreen extends ConsumerWidget {
  const _GroupFeedsScreen({required this.groupName});

  final String groupName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(feedControllerProvider);
    final controller = ref.read(feedControllerProvider.notifier);
    final feeds = state.feeds.where((f) => f.category == groupName).toList();

    return Scaffold(
      appBar: AppBar(title: Text('分组：$groupName')),
      body: feeds.isEmpty
          ? const Center(child: Text('该分组暂无订阅'))
          : ListView.builder(
              itemCount: feeds.length,
              itemBuilder: (context, index) {
                final feed = feeds[index];
                return _GroupFeedTile(
                  feed: feed,
                  groups: state.groups,
                  currentGroup: groupName,
                  onRefresh: () => controller.refreshFeed(feed.id!),
                  onDelete: () => controller.deleteFeed(feed.id!),
                  onMove: (String? newGroup) =>
                      controller.updateFeedCategory(feed.id!, newGroup),
                );
              },
            ),
    );
  }
}

class _GroupFeedTile extends StatelessWidget {
  const _GroupFeedTile({
    required this.feed,
    required this.groups,
    required this.currentGroup,
    required this.onRefresh,
    required this.onDelete,
    required this.onMove,
  });

  final Feed feed;
  final List<String> groups;
  final String currentGroup;
  final VoidCallback onRefresh;
  final VoidCallback onDelete;
  final void Function(String? newGroup) onMove;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.rss_feed),
      title: Text(feed.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(feed.url, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: onRefresh,
          ),
          IconButton(
            tooltip: '移动到其他分组',
            icon: const Icon(Icons.drive_file_move_outlined),
            onPressed: () => _showMoveMenu(context),
          ),
          IconButton(
            tooltip: '删除订阅',
            icon: const Icon(Icons.delete_outline),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }

  Future<void> _showMoveMenu(BuildContext context) async {
    const ungrouped = '__ungrouped__';
    final selected = await showMenu<String>(
      context: context,
      position: const RelativeRect.fromLTRB(0, 0, 0, 0),
      items: [
        const PopupMenuItem(value: ungrouped, child: Text('未分组')),
        for (final group in groups.where((g) => g != currentGroup))
          PopupMenuItem(value: group, child: Text(group)),
      ],
    );
    if (selected == ungrouped) {
      onMove(null);
    } else if (selected != null) {
      onMove(selected);
    }
  }
}
