import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/article.dart';
import '../models/feed.dart';
import '../providers/feed_provider.dart';
import '../providers/settings_provider.dart';
import '../theme/flux_theme.dart';
import '../widgets/article_list_tile.dart';
import '../widgets/lazy_network_image.dart';
import 'add_feed_screen.dart';
import 'article_reader_screen.dart';
import 'settings_screen.dart';
import 'subscription_management_screen.dart';

/// 桌面布局切换到移动布局的最小宽度阈值。
const double _kCompactWidth = 900;

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final GlobalKey<ScaffoldState> _mobileScaffoldKey =
      GlobalKey<ScaffoldState>();
  int _navIndex = 0;
  int _selectedIndex = 0;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onNavSelected(int index) {
    setState(() {
      _navIndex = index;
      _selectedIndex = 0;
    });
    final controller = ref.read(feedControllerProvider.notifier);
    // 切换顶部导航时清除已选订阅/分组，回到全局视图。
    controller.selectFeed(null);
    controller.setFilter(FeedFilter.values[index]);
  }

  void _openAddFeed() {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const AddFeedScreen()));
  }

  void _openSettings() {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  }

  void _focusSearch() {
    _searchFocusNode.requestFocus();
  }

  void _openArticle(Article article, String feedTitle) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ArticleReaderScreen(article: article, feedTitle: feedTitle),
      ),
    );
  }

  Future<void> _showArticleMenu(
    BuildContext context,
    Offset position,
    Article article,
    String feedTitle,
  ) async {
    final controller = ref.read(feedControllerProvider.notifier);
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'read',
          child: Text(article.isRead ? '标记为未读' : '标记为已读'),
        ),
        PopupMenuItem(
          value: 'favorite',
          child: Text(article.isFavorite ? '取消收藏' : '收藏'),
        ),
        PopupMenuItem(
          value: 'later',
          child: Text(article.isReadLater ? '取消稍后读' : '稍后读'),
        ),
        if (article.link != null)
          PopupMenuItem(value: 'open', child: const Text('打开原文')),
      ],
    );
    if (!context.mounted) {
      return;
    }
    switch (action) {
      case 'read':
        controller.markRead(article, !article.isRead);
      case 'favorite':
        controller.toggleFavorite(article);
      case 'later':
        controller.toggleReadLater(article);
      case 'open':
        if (article.link != null) {
          final uri = Uri.tryParse(article.link!);
          if (uri != null) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        }
    }
  }

  void _moveSelection(int delta, int length) {
    if (length == 0) {
      return;
    }
    setState(() {
      _selectedIndex = (_selectedIndex + delta + length) % length;
    });
  }

  void _openSelected(FeedLibraryState state) {
    if (state.articles.isEmpty) {
      return;
    }
    final index = _selectedIndex.clamp(0, state.articles.length - 1);
    final article = state.articles[index];
    _openArticle(article, _feedTitle(state.feeds, article.feedId));
  }

  String _feedTitle(List<Feed> feeds, int feedId) {
    for (final feed in feeds) {
      if (feed.id == feedId) {
        return feed.title;
      }
    }
    return '';
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    // 正在搜索框输入时不要拦截字母键。
    final focus = FocusManager.instance.primaryFocus;
    if (focus != null &&
        focus.context != null &&
        focus.context!.widget is EditableText) {
      return KeyEventResult.ignored;
    }

    final state = ref.read(feedControllerProvider);
    final controller = ref.read(feedControllerProvider.notifier);
    switch (event.logicalKey) {
      case LogicalKeyboardKey.keyJ:
        _moveSelection(1, state.articles.length);
        break;
      case LogicalKeyboardKey.keyK:
        _moveSelection(-1, state.articles.length);
        break;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        _openSelected(state);
        break;
      case LogicalKeyboardKey.keyR:
        controller.refreshAll();
        break;
      case LogicalKeyboardKey.keyM:
        controller.markAllRead();
        break;
      case LogicalKeyboardKey.slash:
        _focusSearch();
        break;
      case LogicalKeyboardKey.keyN:
        _openAddFeed();
        break;
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(feedControllerProvider);
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(feedControllerProvider.notifier);

    final articles = state.articles;
    final selectedIndex = articles.isEmpty
        ? 0
        : _selectedIndex.clamp(0, articles.length - 1);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < _kCompactWidth;
        return Focus(
          autofocus: true,
          onKeyEvent: _handleKeyEvent,
          child: isCompact
              ? _buildMobile(
                  context,
                  state,
                  settings,
                  controller,
                  selectedIndex,
                )
              : _buildDesktop(
                  context,
                  state,
                  settings,
                  controller,
                  selectedIndex,
                ),
        );
      },
    );
  }

  // ============================ 桌面布局 ============================

  Widget _buildDesktop(
    BuildContext context,
    FeedLibraryState state,
    SettingsState settings,
    FeedController controller,
    int selectedIndex,
  ) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _navIndex,
            onDestinationSelected: _onNavSelected,
            labelType: NavigationRailLabelType.all,
            leading: const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                'Flux',
                style: TextStyle(
                  color: FluxColors.red,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.rss_feed),
                label: Text('全部'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.mark_email_unread_outlined),
                selectedIcon: Icon(Icons.mark_email_unread),
                label: Text('未读'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.star_outline),
                selectedIcon: Icon(Icons.star),
                label: Text('收藏'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.bookmark_border),
                selectedIcon: Icon(Icons.bookmark),
                label: Text('稍后读'),
              ),
            ],
            trailing: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: IconButton(
                tooltip: '设置',
                icon: const Icon(Icons.settings_outlined),
                onPressed: _openSettings,
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          SizedBox(
            width: 260,
            child: _FeedSidebar(
              feeds: state.feeds,
              groups: state.groups,
              selectedFeedId: state.selectedFeedId,
              selectedGroup: state.selectedGroup,
              loading: state.loading,
              onSelectFeed: controller.selectFeed,
              onSelectGroup: controller.selectGroup,
              onAddFeed: _openAddFeed,
              onDeleteFeed: controller.deleteFeed,
              onRefreshAll: controller.refreshAll,
              onRefreshFeed: controller.refreshFeed,
              onRenameFeed: controller.renameFeed,
              onUpdateFeedCategory: controller.updateFeedCategory,
              onUpdateFeedUrl: controller.updateFeedUrl,
              onRenameGroup: controller.renameGroup,
              onDeleteGroup: controller.deleteGroup,
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: ArticleListPanel(
              state: state,
              showThumbnails: settings.showThumbnails,
              searchController: _searchController,
              searchFocusNode: _searchFocusNode,
              selectedIndex: selectedIndex,
              onSearchChanged: controller.setQuery,
              onArticleTap: (article, feedTitle, index) {
                setState(() => _selectedIndex = index);
                _openArticle(article, feedTitle);
              },
              onReadToggle: controller.markRead,
              onFavoriteToggle: controller.toggleFavorite,
              onMarkAllRead: controller.markAllRead,
              articleTimeRange: state.articleTimeRange,
              onArticleTimeRangeChanged: controller.setArticleTimeRange,
              articleSort: state.articleSort,
              onArticleSortChanged: controller.setArticleSort,
              articleLayout: state.articleLayout,
              onArticleLayoutChanged: controller.setArticleLayout,
              onArticleSecondaryTap: (article, feedTitle, index, pos) =>
                  _showArticleMenu(context, pos, article, feedTitle),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddFeed,
        backgroundColor: FluxColors.red,
        foregroundColor: Colors.white,
        tooltip: '添加订阅',
        child: const Icon(Icons.add),
      ),
    );
  }

  // ============================ 移动布局 ============================

  Widget _buildMobile(
    BuildContext context,
    FeedLibraryState state,
    SettingsState settings,
    FeedController controller,
    int selectedIndex,
  ) {
    return Scaffold(
      key: _mobileScaffoldKey,
      appBar: AppBar(
        title: const Text('Flux'),
        leading: IconButton(
          tooltip: '订阅源',
          icon: const Icon(Icons.menu),
          onPressed: () => _mobileScaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          IconButton(
            tooltip: '添加订阅',
            icon: const Icon(Icons.add),
            onPressed: _openAddFeed,
          ),
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: controller.setQuery,
              decoration: const InputDecoration(
                hintText: '搜索文章',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
        ),
      ),
      drawer: Drawer(
        child: _FeedSidebar(
          feeds: state.feeds,
          groups: state.groups,
          selectedFeedId: state.selectedFeedId,
          selectedGroup: state.selectedGroup,
          loading: state.loading,
          onSelectFeed: (feedId) {
            controller.selectFeed(feedId);
            Navigator.of(context).pop();
          },
          onSelectGroup: (group) {
            controller.selectGroup(group);
            Navigator.of(context).pop();
          },
          onAddFeed: () {
            Navigator.of(context).pop();
            _openAddFeed();
          },
          onDeleteFeed: controller.deleteFeed,
          onRefreshAll: controller.refreshAll,
          onRefreshFeed: controller.refreshFeed,
          onRenameFeed: controller.renameFeed,
          onUpdateFeedCategory: controller.updateFeedCategory,
          onUpdateFeedUrl: controller.updateFeedUrl,
          onRenameGroup: controller.renameGroup,
          onDeleteGroup: controller.deleteGroup,
        ),
      ),
      body: ArticleListPanel(
        state: state,
        showThumbnails: settings.showThumbnails,
        searchController: _searchController,
        searchFocusNode: _searchFocusNode,
        selectedIndex: selectedIndex,
        onSearchChanged: controller.setQuery,
        onArticleTap: (article, feedTitle, index) {
          setState(() => _selectedIndex = index);
          _openArticle(article, feedTitle);
        },
        onReadToggle: controller.markRead,
        onFavoriteToggle: controller.toggleFavorite,
        onMarkAllRead: controller.markAllRead,
        articleTimeRange: state.articleTimeRange,
        onArticleTimeRangeChanged: controller.setArticleTimeRange,
        articleSort: state.articleSort,
        onArticleSortChanged: controller.setArticleSort,
        articleLayout: state.articleLayout,
        onArticleLayoutChanged: controller.setArticleLayout,
        // 移动端长按文章，快速切换已读/未读。
        onArticleLongPress: (article) =>
            controller.markRead(article, !article.isRead),
        onArticleSecondaryTap: (article, feedTitle, index, pos) =>
            _showArticleMenu(context, pos, article, feedTitle),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        onDestinationSelected: _onNavSelected,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.rss_feed), label: '全部'),
          NavigationDestination(
            icon: Icon(Icons.mark_email_unread_outlined),
            selectedIcon: Icon(Icons.mark_email_unread),
            label: '未读',
          ),
          NavigationDestination(
            icon: Icon(Icons.star_outline),
            selectedIcon: Icon(Icons.star),
            label: '收藏',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmark_border),
            selectedIcon: Icon(Icons.bookmark),
            label: '稍后读',
          ),
        ],
      ),
    );
  }
}

/// 订阅源侧边栏：桌面端作为左侧固定栏，移动端放在 Drawer 内。
class _FeedSidebar extends StatelessWidget {
  const _FeedSidebar({
    required this.feeds,
    required this.groups,
    required this.selectedFeedId,
    required this.selectedGroup,
    required this.loading,
    required this.onSelectFeed,
    required this.onSelectGroup,
    required this.onAddFeed,
    required this.onDeleteFeed,
    required this.onRefreshAll,
    required this.onRefreshFeed,
    required this.onRenameFeed,
    required this.onUpdateFeedCategory,
    required this.onUpdateFeedUrl,
    required this.onRenameGroup,
    required this.onDeleteGroup,
  });

  final List<Feed> feeds;
  final List<String> groups;
  final int? selectedFeedId;
  final String? selectedGroup;
  final bool loading;
  final ValueChanged<int?> onSelectFeed;
  final ValueChanged<String> onSelectGroup;
  final VoidCallback onAddFeed;
  final ValueChanged<int> onDeleteFeed;
  final VoidCallback onRefreshAll;
  final ValueChanged<int> onRefreshFeed;
  final void Function(int feedId, String title) onRenameFeed;
  final void Function(int feedId, String? category) onUpdateFeedCategory;
  final void Function(int feedId, String url) onUpdateFeedUrl;
  final void Function(String oldName, String newName) onRenameGroup;
  final void Function(String groupName) onDeleteGroup;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<Feed>>{};
    for (final feed in feeds) {
      final key = (feed.category == null || feed.category!.trim().isEmpty)
          ? '未分组'
          : feed.category!;
      groups.putIfAbsent(key, () => []).add(feed);
    }

    final groupNames = groups.keys.toList()
      ..sort((a, b) {
        if (a == '未分组') return 1;
        if (b == '未分组') return -1;
        return a.compareTo(b);
      });

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 8, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'FEEDS',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '订阅管理',
                  icon: const Icon(Icons.tune),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SubscriptionManagementScreen(),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '刷新全部',
                  icon: loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  onPressed: loading ? null : onRefreshAll,
                ),
                IconButton(
                  tooltip: '添加订阅',
                  icon: const Icon(Icons.add),
                  onPressed: onAddFeed,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.all_inbox),
            title: const Text('全部订阅'),
            selected:
                selectedFeedId == null &&
                (selectedGroup == null || selectedGroup!.isEmpty),
            onTap: () => onSelectFeed(null),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              children: [
                for (final groupName in groupNames) ...[
                  _buildGroupHeader(
                    context,
                    groupName,
                    groups[groupName]!.length,
                    selected:
                        selectedGroup ==
                        (groupName == '未分组' ? '__ungrouped__' : groupName),
                  ),
                  for (final feed in groups[groupName]!)
                    _buildFeedTile(context, feed),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupHeader(
    BuildContext context,
    String name,
    int count, {
    required bool selected,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) =>
          _showGroupMenu(context, details.globalPosition, name),
      child: ListTile(
        dense: true,
        selected: selected,
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: selected
                ? FluxColors.red
                : Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w800 : null,
          ),
        ),
        trailing: Text(
          '$count',
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        onTap: () => onSelectGroup(name == '未分组' ? '__ungrouped__' : name),
      ),
    );
  }

  Widget _buildFeedTile(BuildContext context, Feed feed) {
    return GestureDetector(
      onSecondaryTapDown: (details) =>
          _showFeedMenu(context, details.globalPosition, feed),
      child: ListTile(
        dense: true,
        leading: Icon(feed.iconUrl == null ? Icons.rss_feed : Icons.web_asset),
        title: Text(feed.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        selected: selectedFeedId == feed.id,
        onTap: () => onSelectFeed(feed.id),
        onLongPress: () => _confirmDelete(context, feed),
      ),
    );
  }

  Future<void> _showFeedMenu(
    BuildContext context,
    Offset position,
    Feed feed,
  ) async {
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: const [
        PopupMenuItem(value: 'manage', child: Text('管理')),
        PopupMenuItem(value: 'refresh', child: Text('刷新')),
        PopupMenuItem(value: 'rename', child: Text('重命名')),
        PopupMenuItem(value: 'editUrl', child: Text('查看/修改链接')),
        PopupMenuItem(value: 'move', child: Text('移动到分组...')),
        PopupMenuItem(value: 'delete', child: Text('删除')),
      ],
    );
    if (!context.mounted || feed.id == null) {
      return;
    }
    switch (action) {
      case 'manage':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const SubscriptionManagementScreen(),
          ),
        );
      case 'refresh':
        onRefreshFeed(feed.id!);
      case 'rename':
        final title = await _promptText(context, '重命名订阅', feed.title);
        if (title != null && title.trim().isNotEmpty) {
          onRenameFeed(feed.id!, title.trim());
        }
      case 'editUrl':
        final url = await _promptText(context, '订阅链接', feed.url);
        if (url != null && url.trim().isNotEmpty) {
          onUpdateFeedUrl(feed.id!, url.trim());
        }
      case 'move':
        await _promptMoveGroup(context, feed);
      case 'delete':
        await _confirmDelete(context, feed);
    }
  }

  Future<void> _showGroupMenu(
    BuildContext context,
    Offset position,
    String groupName,
  ) async {
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(value: 'rename', child: Text('重命名分组')),
        PopupMenuItem(value: 'delete', child: Text('删除分组')),
      ],
    );
    if (!context.mounted || groupName == '未分组') {
      return;
    }
    switch (action) {
      case 'rename':
        final newName = await _promptText(context, '重命名分组', groupName);
        if (newName != null && newName.trim().isNotEmpty) {
          onRenameGroup(groupName, newName.trim());
        }
      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('删除分组'),
            content: Text('确定删除分组“$groupName”？订阅不会删除，只会移到未分组。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text(
                  '删除',
                  style: TextStyle(color: FluxColors.red),
                ),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          onDeleteGroup(groupName);
        }
    }
  }

  Future<void> _promptMoveGroup(BuildContext context, Feed feed) async {
    const ungrouped = '__ungrouped__';
    const newGroup = '__new__';
    final selected = await showMenu<String>(
      context: context,
      position: const RelativeRect.fromLTRB(0, 0, 0, 0),
      items: [
        const PopupMenuItem(value: ungrouped, child: Text('未分组')),
        for (final group in groups)
          if (group != feed.category)
            PopupMenuItem(value: group, child: Text(group)),
        const PopupMenuItem(value: newGroup, child: Text('新建分组...')),
      ],
    );
    if (!context.mounted || feed.id == null) {
      return;
    }
    if (selected == ungrouped) {
      onUpdateFeedCategory(feed.id!, null);
    } else if (selected == newGroup) {
      final name = await _promptText(context, '新建分组', '');
      if (name != null && name.trim().isNotEmpty) {
        onUpdateFeedCategory(feed.id!, name.trim());
      }
    } else if (selected != null) {
      onUpdateFeedCategory(feed.id!, selected);
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

  Future<void> _confirmDelete(BuildContext context, Feed feed) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除订阅'),
        content: Text('确定删除“${feed.title}”？该订阅下的所有文章也会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除', style: TextStyle(color: FluxColors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true && feed.id != null) {
      onDeleteFeed(feed.id!);
    }
  }
}

/// 文章列表面板：桌面端带标题栏与搜索框，移动端仅展示正文列表。
///
/// [withHeader] 为 true 时渲染标题与搜索框（桌面端），否则由移动端在
/// AppBar 下方承载搜索框，这里只渲染文章列表与错误提示。
class ArticleListPanel extends StatelessWidget {
  const ArticleListPanel({
    super.key,
    required this.state,
    required this.showThumbnails,
    required this.searchController,
    required this.searchFocusNode,
    required this.selectedIndex,
    required this.onSearchChanged,
    required this.onArticleTap,
    required this.onReadToggle,
    required this.onFavoriteToggle,
    required this.onMarkAllRead,
    required this.articleTimeRange,
    required this.onArticleTimeRangeChanged,
    required this.articleSort,
    required this.onArticleSortChanged,
    required this.articleLayout,
    required this.onArticleLayoutChanged,
    this.onArticleLongPress,
    this.onArticleSecondaryTap,
    this.withHeader = true,
  });

  final FeedLibraryState state;
  final bool showThumbnails;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final int selectedIndex;
  final ValueChanged<String> onSearchChanged;
  final void Function(Article article, String feedTitle, int index)
  onArticleTap;
  final void Function(Article article, bool read) onReadToggle;
  final ValueChanged<Article> onFavoriteToggle;
  final VoidCallback onMarkAllRead;
  final TimeRange articleTimeRange;
  final ValueChanged<TimeRange> onArticleTimeRangeChanged;
  final ArticleSort articleSort;
  final ValueChanged<ArticleSort> onArticleSortChanged;
  final ArticleLayout articleLayout;
  final ValueChanged<ArticleLayout> onArticleLayoutChanged;
  final ValueChanged<Article>? onArticleLongPress;
  final void Function(
    Article article,
    String feedTitle,
    int index,
    Offset position,
  )?
  onArticleSecondaryTap;
  final bool withHeader;

  @override
  Widget build(BuildContext context) {
    final header = switch (state.filter) {
      FeedFilter.all => '全部文章',
      FeedFilter.unread => '未读',
      FeedFilter.favorites => '收藏',
      FeedFilter.readLater => '稍后读',
    };

    return Column(
      children: [
        if (withHeader) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Text(
                      header,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  if (state.articles.isNotEmpty)
                    TextButton.icon(
                      onPressed: onMarkAllRead,
                      icon: const Icon(Icons.done_all, size: 18),
                      label: const Text('全部已读'),
                    ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 110,
                    child: DropdownButtonFormField<TimeRange>(
                      initialValue: articleTimeRange,
                      decoration: const InputDecoration(
                        labelText: '时间',
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
                          onArticleTimeRangeChanged(value);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 130,
                    child: DropdownButtonFormField<ArticleSort>(
                      initialValue: articleSort,
                      decoration: const InputDecoration(
                        labelText: '排序',
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: ArticleSort.newestFirst,
                          child: Text('最新在前'),
                        ),
                        DropdownMenuItem(
                          value: ArticleSort.oldestFirst,
                          child: Text('最早在前'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          onArticleSortChanged(value);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 120,
                    child: DropdownButtonFormField<ArticleLayout>(
                      initialValue: articleLayout,
                      decoration: const InputDecoration(
                        labelText: '显示',
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: ArticleLayout.single,
                          child: Text('单列'),
                        ),
                        DropdownMenuItem(
                          value: ArticleLayout.double,
                          child: Text('双列'),
                        ),
                        DropdownMenuItem(
                          value: ArticleLayout.masonry,
                          child: Text('瀑布流'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          onArticleLayoutChanged(value);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: searchController,
                      focusNode: searchFocusNode,
                      onChanged: onSearchChanged,
                      decoration: const InputDecoration(
                        hintText: '搜索文章',
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ] else ...[
          // 移动端在文章列表顶部提供“全部已读”入口和时间筛选。
          if (state.articles.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton.icon(
                  onPressed: onMarkAllRead,
                  icon: const Icon(Icons.done_all, size: 18),
                  label: const Text('全部已读'),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  SizedBox(
                    width: 120,
                    child: DropdownButtonFormField<TimeRange>(
                      initialValue: articleTimeRange,
                      decoration: const InputDecoration(
                        labelText: '时间',
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
                          onArticleTimeRangeChanged(value);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 130,
                    child: DropdownButtonFormField<ArticleSort>(
                      initialValue: articleSort,
                      decoration: const InputDecoration(
                        labelText: '排序',
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: ArticleSort.newestFirst,
                          child: Text('最新在前'),
                        ),
                        DropdownMenuItem(
                          value: ArticleSort.oldestFirst,
                          child: Text('最早在前'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          onArticleSortChanged(value);
                        }
                      },
                    ),
                  ),
                  PopupMenuButton<ArticleLayout>(
                    tooltip: '显示模式',
                    icon: const Icon(Icons.view_module_outlined),
                    onSelected: onArticleLayoutChanged,
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: ArticleLayout.single,
                        child: Text('单列'),
                      ),
                      PopupMenuItem(
                        value: ArticleLayout.double,
                        child: Text('双列'),
                      ),
                      PopupMenuItem(
                        value: ArticleLayout.masonry,
                        child: Text('瀑布流'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
        const Divider(height: 1),
        if (state.error != null)
          MaterialBanner(
            content: Text(state.error!),
            leading: const Icon(Icons.error_outline, color: FluxColors.red),
            actions: [TextButton(onPressed: () {}, child: const Text('知道了'))],
          ),
        Expanded(
          child: state.loading && state.articles.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : state.articles.isEmpty
              ? const _EmptyState()
              : _buildArticleBody(context),
        ),
      ],
    );
  }

  Widget _buildArticleBody(BuildContext context) {
    switch (articleLayout) {
      case ArticleLayout.single:
        return ListView.builder(
          itemCount: state.articles.length,
          itemBuilder: (context, index) {
            final article = state.articles[index];
            return _buildArticleTile(
              context,
              article,
              index,
              selected: index == selectedIndex,
            );
          },
        );
      case ArticleLayout.double:
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            // 双列卡片高度，保证文字区域更充裕。
            mainAxisExtent: 150,
          ),
          itemCount: state.articles.length,
          itemBuilder: (context, index) {
            final article = state.articles[index];
            return _buildDoubleArticleCard(context, article, index);
          },
        );
      case ArticleLayout.masonry:
        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final columns = width >= 1400
                ? 4
                : width >= 1000
                ? 3
                : 2;
            return MasonryGridView.count(
              padding: const EdgeInsets.all(12),
              crossAxisCount: columns,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              itemCount: state.articles.length,
              itemBuilder: (context, index) {
                final article = state.articles[index];
                return _buildMasonryArticleCard(context, article, index);
              },
            );
          },
        );
    }
  }

  String _articleSummary(Article article) {
    return (article.summary ?? article.contentHtml ?? '')
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Widget _buildDoubleArticleCard(
    BuildContext context,
    Article article,
    int index,
  ) {
    final feedTitle = _feedTitle(state.feeds, article.feedId);
    final groupName = _feedGroup(state.feeds, article.feedId);
    final summary = _articleSummary(article);

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: InkWell(
        onTap: () => onArticleTap(article, feedTitle, index),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      article.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                    if (summary.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            feedTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ),
                        if (groupName != null)
                          Text(
                            groupName,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(color: FluxColors.red),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (article.imageUrl != null)
              SizedBox(
                width: 110,
                child: LazyNetworkImage(
                  url: article.imageUrl!,
                  width: 110,
                  height: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMasonryArticleCard(
    BuildContext context,
    Article article,
    int index,
  ) {
    final feedTitle = _feedTitle(state.feeds, article.feedId);
    final groupName = _feedGroup(state.feeds, article.feedId);
    final summary = _articleSummary(article);

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: InkWell(
        onTap: () => onArticleTap(article, feedTitle, index),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (article.imageUrl != null)
              ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: 80,
                  maxHeight: 320,
                ),
                child: LazyNetworkImage(
                  url: article.imageUrl!,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    article.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  if (summary.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      summary,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          feedTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                      if (groupName != null)
                        Text(
                          groupName,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: FluxColors.red),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArticleTile(
    BuildContext context,
    Article article,
    int index, {
    bool selected = false,
    bool compact = false,
  }) {
    final feedTitle = _feedTitle(state.feeds, article.feedId);
    final groupName = _feedGroup(state.feeds, article.feedId);
    return ArticleListTile(
      article: article,
      feedTitle: feedTitle,
      groupName: groupName,
      showThumbnail: showThumbnails && !compact,
      selected: selected,
      onTap: () => onArticleTap(article, feedTitle, index),
      onLongPress: onArticleLongPress == null
          ? null
          : () => onArticleLongPress!(article),
      onSecondaryTap: onArticleSecondaryTap == null
          ? null
          : (pos) => onArticleSecondaryTap!(article, feedTitle, index, pos),
      onReadToggle: () => onReadToggle(article, !article.isRead),
      onFavoriteToggle: () => onFavoriteToggle(article),
    );
  }

  String _feedTitle(List<Feed> feeds, int feedId) {
    for (final feed in feeds) {
      if (feed.id == feedId) {
        return feed.title;
      }
    }
    return '';
  }

  String? _feedGroup(List<Feed> feeds, int feedId) {
    for (final feed in feeds) {
      if (feed.id == feedId) {
        final group = feed.category;
        return (group == null || group.trim().isEmpty) ? null : group;
      }
    }
    return null;
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Flux',
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.w900,
              letterSpacing: 8,
              color: FluxColors.red,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无文章\n请先添加 RSS 订阅',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
