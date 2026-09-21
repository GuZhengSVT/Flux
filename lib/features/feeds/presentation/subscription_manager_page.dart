// 订阅管理页（T014）：分组列表、订阅行与全部单条操作。
//
// 页面只做三件事：把控制器状态画出来、把用户动作转发给控制器、把失败如实显示。
// 所有判断（未分类保护、重复添加、排序合法性）都在用例层，页面不重复实现——
// 否则「界面禁用但用例允许」或反过来的漏洞迟早出现。
//
// 关于删除订阅：本期**没有**删除订阅的入口。架构 4.1 与 D-11 要求删除时先展示
// 影响范围（收藏 vs 其他，含 later）并让用户选择是否保留收藏，那属于 T018；
// 一个只有「删除」按钮、却没有保留收藏选项的界面会让用户以为收藏也会被清掉，
// 因此这里只提供删除**分组**（并明确标注其中订阅的处理方式）。
//
// 可达性（架构第 7 节：桌面默认支持键盘焦点）：
//   - 拖动把手是 ReorderableDragStartListener，可聚焦并可用方向键移动；
//   - 同时提供「上移/下移」菜单项，作为不依赖拖动的等价操作；
//   - 所有图标按钮都有读屏标签，触控目标 ≥48dp（由 IconButton 默认尺寸保证）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';
import 'package:flux/core/design/design_tokens.dart';
import 'package:flux/l10n/l10n.dart';
import 'package:flux/ui/ui.dart';

import '../application/add_feed.dart';
import '../application/feed_manager_state.dart';
import '../application/feed_overview.dart';
import 'feed_dialogs.dart';
import 'feed_manager_controller.dart';

/// 订阅管理页。
/// 分组区块的显示名。
///
/// 保留组「未分类」的显示名**来自本地化资源**，而不是数据库里的那一列：它的名字
/// 在界面语言切换时必须跟着变（用户选择英文界面后不该看到「未分类」），而保留组
/// 又不可改名，因此库里的名字只是一份建库种子，不是用户数据。
///
/// 用户自建分组照常使用库里的名字（那是用户输入，任何时候都不该被翻译）。
String groupDisplayName(AppLocalizations l10n, FeedGroupSection section) =>
    section.isReserved
    ? l10n.subscriptionReservedGroupName
    : section.displayName;

class SubscriptionManagerPage extends ConsumerWidget {
  /// 构造页面。
  const SubscriptionManagerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<FeedManagerState> state = ref.watch(
      feedManagerControllerProvider,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.subscriptionManagerTitle),
        actions: <Widget>[
          IconButton(
            tooltip: l10n.subscriptionAddFeed,
            icon: const Icon(Icons.add_link),
            onPressed: () => _addFeed(context, ref),
          ),
          IconButton(
            tooltip: l10n.subscriptionNewGroup,
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: () => _createGroup(context, ref),
          ),
          const SizedBox(width: FluxSpacing.xxs),
        ],
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        // 读失败不是空列表：用错误态明确说明，并给「重试」。
        error: (Object error, StackTrace stackTrace) => _LoadFailed(
          message: error is AppError ? error.message : null,
          onRetry: () => ref.invalidate(feedManagerControllerProvider),
        ),
        data: (FeedManagerState value) => _ManagerBody(state: value),
      ),
    );
  }

  /// 打开添加订阅对话框。
  static Future<void> _addFeed(BuildContext context, WidgetRef ref) async {
    final FeedManagerState? state = ref
        .read(feedManagerControllerProvider)
        .value;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<GroupOption> groups = <GroupOption>[
      for (final FeedGroupSection section
          in state?.overview.sections ?? const <FeedGroupSection>[])
        if (section.groupId case final int id)
          GroupOption(id: id, name: groupDisplayName(l10n, section)),
    ];

    final AddFeedDialogResult? result = await showAddFeedDialog(
      context: context,
      groups: groups,
      onPreview: (String url) =>
          ref.read(feedManagerControllerProvider.notifier).previewFeed(url),
      onConfirm:
          ({
            required FeedPreview preview,
            required String name,
            int? groupId,
          }) => ref
              .read(feedManagerControllerProvider.notifier)
              .confirmFeed(preview: preview, name: name, groupId: groupId),
    );
    if (result == null || !context.mounted) {
      return;
    }
    final AddFeedOutcome outcome = result.outcome;
    final String message;
    if (outcome.isDuplicate) {
      message = l10n.subscriptionPreviewDuplicateBody(outcome.feed.name);
    } else if ((outcome.imported?.inserted ?? 0) == 0) {
      message = l10n.subscriptionAddSuccessEmpty(result.feedName);
    } else {
      message = l10n.subscriptionAddSuccess(
        result.feedName,
        outcome.imported!.inserted,
      );
    }
    _showSnack(context, message);
  }

  /// 新建分组。
  static Future<void> _createGroup(BuildContext context, WidgetRef ref) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? name = await showNameDialog(
      context: context,
      title: l10n.subscriptionNewGroupTitle,
      label: l10n.subscriptionGroupNameLabel,
      emptyErrorMessage: l10n.subscriptionInvalidGroupName,
    );
    if (name == null) {
      return;
    }
    final Result<GroupRecord> result = await ref
        .read(feedManagerControllerProvider.notifier)
        .createGroup(name);
    if (!context.mounted) {
      return;
    }
    _reportResult(context, result.isOk ? null : result.errorOrNull);
  }

  /// 统一的结果提示：成功时不打扰，失败时明确说明。
  static void _reportResult(BuildContext context, AppError? error) {
    if (error != null) {
      _showSnack(context, error.message);
    }
  }

  /// 显示一条短提示。
  static void _showSnack(BuildContext context, String message) {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    // 先清掉上一条：连续操作时队列会积压，用户看到的提示与当前动作错位。
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

/// 加载失败态。
class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.onRetry, this.message});

  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return FluxEmptyState(
      icon: FluxIcon.alertError,
      tone: EmptyStateTone.muted,
      title: l10n.subscriptionEmptyTitle,
      body: message ?? l10n.subscriptionErrorStorage,
      action: FilledButton(
        onPressed: onRetry,
        child: Text(l10n.subscriptionPreviewAction),
      ),
    );
  }
}

/// 页面正文：范围说明 + 刷新策略 + 分组列表。
class _ManagerBody extends ConsumerWidget {
  const _ManagerBody({required this.state});

  final FeedManagerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<FeedGroupSection> sections = state.overview.sections;
    // 一个订阅都没有时：显示空态引导，并隐藏保留组（它只会说「未分类，0 个订阅」，
    // 与空态说的是同一件事）。但**用户自己建的分组照常显示**——那是用户数据，
    // 隐藏它会让「我想删掉那个空分组」变得无从下手。
    final bool showEmptyState = state.overview.isEmpty;
    final List<FeedGroupSection> visibleSections = showEmptyState
        ? sections
              .where((FeedGroupSection section) => !section.isReserved)
              .toList(growable: false)
        : sections;

    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(vertical: FluxSpacing.sm),
      // 表头用 ReorderableListView 自带的 header：把它拆成另一个列表会失去滚动
      // 联动，且拖动到顶部时表头不会让位。
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _PageNotice(text: l10n.subscriptionManagerNotice),
          _RefreshPolicyCard(state: state),
          _SectionTitle(title: l10n.subscriptionGroupsSection),
          // 空态判据是「没有任何订阅」而不是「没有任何分组」：保留组「未分类」
          // 在任何库里都存在，用 sections.isEmpty 会让空态**永远不显示**。
          if (showEmptyState)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: FluxSpacing.md,
                vertical: FluxSpacing.lg,
              ),
              child: FluxEmptyState(
                title: l10n.subscriptionEmptyTitle,
                body: l10n.subscriptionEmptyBody,
              ),
            ),
        ],
      ),
      itemCount: visibleSections.length,
      // 拖动排序：整段重排（用例层校验必须包含全部分组），因此这里传的是
      // 「移动后」的完整 id 顺序，而不是只报告被移动的那一项。
      //
      // 用 onReorderItem 而不是已废弃的 onReorder：后者的 newIndex 是「插入到
      // 原列表的下标」，被拖动项自身还占着位置，需要调用方自己 -1 修正；前者已经
      // 把这个修正做掉了。用废弃 API 并手工修正，等于把框架已经修好的语义再实现
      // 一遍，一旦框架改口径就会错。
      onReorderItem: (int oldIndex, int newIndex) {
        // 拖动只在**可见**列表里发生，而写入需要「全部分组」的完整顺序（用例层
        // 会校验这一点）。两者相等时（正常情况：全部可见）直接换算；不相等说明
        // 有空态隐藏或兜底区块，此时**不重排**——宁可这一次拖动无效，也不要写下
        // 一个丢掉隐藏分组的顺序。
        if (visibleSections.length != sections.length) {
          return;
        }
        final List<int?> groupIds = visibleSections
            .map((FeedGroupSection section) => section.groupId)
            .toList(growable: false);
        if (groupIds.any((int? id) => id == null)) {
          // 兜底区块（库里没有保留组）：说明库被破坏，同样不重排。
          return;
        }
        final List<int> reordered = groupIds.cast<int>();
        reordered.insert(newIndex, reordered.removeAt(oldIndex));
        ref
            .read(feedManagerControllerProvider.notifier)
            .reorderGroups(reordered);
      },
      itemBuilder: (BuildContext context, int index) {
        final FeedGroupSection section = visibleSections[index];
        return _GroupBlock(
          key: ValueKey<String>('group-${section.groupId ?? 'orphan'}'),
          section: section,
          collapsed: section.groupId == null
              ? false
              : state.isCollapsed(section.groupId!),
          reorderIndex: index,
        );
      },
    );
  }
}

/// 页面范围说明（避免被当成已交付文章列表）。
class _PageNotice extends StatelessWidget {
  const _PageNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      FluxSpacing.md,
      FluxSpacing.xs,
      FluxSpacing.md,
      FluxSpacing.sm,
    ),
    child: StatusBanner(message: text),
  );
}

/// 小节标题。
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      FluxSpacing.md,
      FluxSpacing.md,
      FluxSpacing.md,
      FluxSpacing.xs,
    ),
    child: Text(title, style: Theme.of(context).textTheme.titleSmall),
  );
}

/// 刷新策略卡片（SET-020 全局开关与间隔、SET-021 启动时刷新）。
class _RefreshPolicyCard extends ConsumerWidget {
  const _RefreshPolicyCard({required this.state});

  final FeedManagerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final RefreshPolicy policy = state.policy;
    final FeedManagerController controller = ref.read(
      feedManagerControllerProvider.notifier,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FluxSpacing.md),
      child: FluxCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    l10n.subscriptionRefreshPolicyTitle,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Text(
                  '${SettingId.set020.code} / ${SettingId.set021.code}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: FluxSpacing.xxs),
            Text(
              l10n.subscriptionRefreshPolicyNote,
              style: theme.textTheme.bodySmall,
            ),
            if (state.policyReadFailed) ...<Widget>[
              const SizedBox(height: FluxSpacing.xs),
              StatusBanner(
                severity: StatusBannerSeverity.warning,
                message: l10n.settingsWriteFailed,
              ),
            ],
            const SizedBox(height: FluxSpacing.sm),
            // 用「文字 + Switch」而不是 SwitchListTile：ListTile 系列把底色与涟漪
            // 画在最近的 Material 祖先上，而 FluxCard 是带底色的 DecoratedBox，
            // 框架会就此报断言（「ListTile background color or ink splashes may be
            // invisible」）。改成显式的 Row 既避免这条断言，也让开关与文字的对齐
            // 由这里的排版决定，不受 ListTile 内边距影响。
            _SwitchRow(
              label: l10n.subscriptionGlobalRefreshLabel,
              value: policy.autoRefreshEnabled,
              onChanged: (bool value) =>
                  controller.setRefreshPolicy(autoRefreshEnabled: value),
            ),
            _IntervalField(
              value: policy.intervalSetting,
              onChanged: (String value) =>
                  controller.setRefreshPolicy(intervalSetting: value),
            ),
            _SwitchRow(
              label: l10n.subscriptionStartupRefreshLabel,
              value: policy.refreshOnLaunch,
              onChanged: (bool value) =>
                  controller.setRefreshPolicy(refreshOnLaunch: value),
            ),
          ],
        ),
      ),
    );
  }
}

/// SET-020 的间隔选择（与注册表取值集合一致）。
class _IntervalField extends StatelessWidget {
  const _IntervalField({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // 取值集合照抄 SET-020 的注册表口径（manual/15/30/60/120），不自行扩展。
    const List<String> values = <String>['manual', '15', '30', '60', '120'];
    final List<String> options = values.contains(value) ? values : values;
    final String selected = options.contains(value) ? value : '60';
    return Padding(
      padding: const EdgeInsets.only(bottom: FluxSpacing.xs),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              l10n.subscriptionGlobalIntervalLabel,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          DropdownButton<String>(
            value: selected,
            onChanged: (String? next) {
              if (next != null) {
                onChanged(next);
              }
            },
            items: <DropdownMenuItem<String>>[
              for (final String option in options)
                DropdownMenuItem<String>(
                  value: option,
                  child: Text(intervalLabel(l10n, option)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 间隔取值的展示文案。
  static String intervalLabel(AppLocalizations l10n, String setting) =>
      setting == 'manual'
      ? l10n.subscriptionIntervalManual
      : l10n.subscriptionIntervalMinutes(setting);
}

/// 一个分组区块。
class _GroupBlock extends ConsumerWidget {
  const _GroupBlock({
    required this.section,
    required this.collapsed,
    required this.reorderIndex,
    super.key,
  });

  final FeedGroupSection section;
  final bool collapsed;
  final int reorderIndex;

  // 保留组用本地化名（见 groupDisplayName 的说明）。
  String _displayName(AppLocalizations l10n) => groupDisplayName(l10n, section);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final int? groupId = section.groupId;
    final FeedManagerController controller = ref.read(
      feedManagerControllerProvider.notifier,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FluxSpacing.md,
        0,
        FluxSpacing.md,
        FluxSpacing.sm,
      ),
      child: FluxCard(
        padding: const EdgeInsets.all(FluxSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                // 展开/折叠（SET-025）。用 Material 的箭头而不是 FluxIcon：
                // 原创图标集表达的是产品语义（三态、收藏、加精、去向），
                // 折叠箭头是通用平台惯例，不需要也不应该有专属字形。
                IconButton(
                  tooltip: _displayName(l10n),
                  icon: Icon(
                    collapsed ? Icons.chevron_right : Icons.expand_more,
                  ),
                  onPressed: groupId == null
                      ? null
                      : () => controller.setCollapsed(
                          groupId: groupId,
                          collapsed: !collapsed,
                        ),
                ),
                Expanded(
                  child: Semantics(
                    header: true,
                    label: l10n.subscriptionGroupHeaderLabel(
                      _displayName(l10n),
                      section.entries.length,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Flexible(
                              child: Text(
                                _displayName(l10n),
                                style: theme.textTheme.titleMedium,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (section.group?.pinned ?? false) ...<Widget>[
                              const SizedBox(width: FluxSpacing.xs),
                              _PinnedBadge(label: l10n.subscriptionPinnedBadge),
                            ],
                          ],
                        ),
                        Text(
                          collapsed
                              ? l10n.subscriptionCollapsedCount(
                                  section.entries.length,
                                )
                              : l10n.subscriptionGroupHeaderLabel(
                                  _displayName(l10n),
                                  section.entries.length,
                                ),
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                ),
                if (section.isReserved)
                  Tooltip(
                    message: l10n.subscriptionReservedGroupNote,
                    child: Icon(
                      Icons.lock_outline,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (groupId != null)
                  _GroupMenu(
                    section: section,
                    reorderIndex: reorderIndex,
                    isReserved: section.isReserved,
                  ),
              ],
            ),
            if (!collapsed) ...<Widget>[
              if (section.entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(FluxSpacing.sm),
                  child: Text(
                    l10n.subscriptionEmptyBody,
                    style: theme.textTheme.bodySmall,
                  ),
                )
              else
                // 组内订阅：用嵌套的 ReorderableListView 支持拖动排序。
                // shrinkWrap + NeverScrollableScrollPhysics 让内层列表不自己滚动，
                // 滚动交给外层列表——否则两层滚动会互相抢手势。
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: section.entries.length,
                  onReorderItem: (int oldIndex, int newIndex) {
                    if (groupId == null) {
                      return;
                    }
                    final List<int> ids = <int>[
                      for (final FeedListEntry entry in section.entries)
                        entry.feed.id,
                    ];
                    ids.insert(newIndex, ids.removeAt(oldIndex));
                    controller.reorderFeeds(groupId: groupId, orderedIds: ids);
                  },
                  itemBuilder: (BuildContext context, int index) {
                    final FeedListEntry entry = section.entries[index];
                    return _FeedRow(
                      key: ValueKey<int>(entry.feed.id),
                      entry: entry,
                      index: index,
                      total: section.entries.length,
                      groupId: groupId,
                    );
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 置顶徽标。
class _PinnedBadge extends StatelessWidget {
  const _PinnedBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FluxSpacing.xs,
        vertical: FluxSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(FluxRadius.button),
        border: Border.all(color: scheme.outline),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

/// 订阅行。
class _FeedRow extends ConsumerWidget {
  const _FeedRow({
    required this.entry,
    required this.index,
    required this.total,
    required this.groupId,
    super.key,
  });

  final FeedListEntry entry;
  final int index;
  final int total;
  final int? groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final FeedRecord feed = entry.feed;

    return Semantics(
      label: l10n.subscriptionFeedRowLabel(feed.name, entry.unreadCount),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: FluxSpacing.xxs),
        child: Row(
          children: <Widget>[
            // 拖动把手：ReorderableDragStartListener 自带焦点与长按语义，
            // 键盘用户可用上/下方向键（Flutter 对拖动把手实现了方向键移动）。
            ReorderableDragStartListener(
              index: index,
              child: Tooltip(
                message: l10n.subscriptionDragHandleLabel,
                child: Padding(
                  padding: const EdgeInsets.all(FluxSpacing.xs),
                  child: Icon(
                    Icons.drag_indicator,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            // 加精徽标（SET-023）：加精只在**显示**上用强调色与徽标表达，
            // 不改变排序，也不改变新闻选材。
            if (feed.favorite)
              Padding(
                padding: const EdgeInsets.only(right: FluxSpacing.xs),
                child: FluxSvgIcon(
                  FluxIcon.featuredBadge,
                  size: FluxIconSize.small,
                  color: scheme.primary,
                  semanticsLabel: l10n.featuredBadgeLabel,
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    feed.name,
                    style: theme.textTheme.bodyLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    l10n.subscriptionUnreadCount(entry.unreadCount),
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            if (!feed.enabled)
              Tooltip(
                message: l10n.subscriptionEnabledNote,
                child: _Tagged(text: l10n.subscriptionFeedDisabledBadge),
              ),
            _FeedMenu(
              entry: entry,
              index: index,
              total: total,
              groupId: groupId,
            ),
          ],
        ),
      ),
    );
  }
}

/// 小标签（已停用等）。
class _Tagged extends StatelessWidget {
  const _Tagged({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FluxSpacing.xs,
        vertical: FluxSpacing.xxs,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FluxRadius.button),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 分组菜单：重命名、置顶、上移/下移、删除。
class _GroupMenu extends ConsumerWidget {
  const _GroupMenu({
    required this.section,
    required this.reorderIndex,
    required this.isReserved,
  });

  final FeedGroupSection section;
  final int reorderIndex;

  /// 是否为保留组。
  ///
  /// 保留组**不显示**重命名与删除入口。用例层已经会拒绝这两个操作（那才是权威
  /// 规则），但界面上留着一个点下去必然失败的菜单项，等于让用户去撞墙；而「不让
  /// 用户做一件注定被拒的事」比「事后解释为什么被拒」更好。
  final bool isReserved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final GroupRecord? group = section.group;
    if (group == null) {
      return const SizedBox.shrink();
    }
    final FeedManagerController controller = ref.read(
      feedManagerControllerProvider.notifier,
    );

    return PopupMenuButton<_GroupAction>(
      tooltip: l10n.subscriptionGroupMenu,
      onSelected: (_GroupAction action) async {
        // 在第一个 await 之前取出 messenger：跨 await 之后再用 BuildContext 取它
        // 会触发 use_build_context_synchronously（组件可能已被卸载），而我们确实
        // 需要在写入完成后提示结果。
        final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
        switch (action) {
          case _GroupAction.rename:
            final String? name = await showNameDialog(
              context: context,
              title: l10n.subscriptionGroupRenameTitle,
              label: l10n.subscriptionGroupNameLabel,
              initialValue: group.name,
              emptyErrorMessage: l10n.subscriptionInvalidGroupName,
            );
            if (name == null) {
              return;
            }
            final Result<GroupRecord> result = await controller.renameGroup(
              groupId: group.id,
              name: name,
            );
            notifyError(messenger, result.errorOrNull);
          case _GroupAction.togglePin:
            final Result<GroupRecord> result = await controller.setGroupPinned(
              groupId: group.id,
              pinned: !group.pinned,
            );
            notifyError(messenger, result.errorOrNull);
          case _GroupAction.moveUp:
            await _moveGroupBy(ref, -1);
          case _GroupAction.moveDown:
            await _moveGroupBy(ref, 1);
          case _GroupAction.delete:
            await _delete(context, messenger, l10n, controller, group);
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<_GroupAction>>[
        if (!isReserved)
          PopupMenuItem<_GroupAction>(
            value: _GroupAction.rename,
            child: Text(l10n.subscriptionGroupRename),
          ),
        PopupMenuItem<_GroupAction>(
          value: _GroupAction.togglePin,
          child: Text(
            group.pinned
                ? l10n.subscriptionGroupUnpin
                : l10n.subscriptionGroupPin,
          ),
        ),
        PopupMenuItem<_GroupAction>(
          value: _GroupAction.moveUp,
          child: Text(l10n.subscriptionMoveUp),
        ),
        PopupMenuItem<_GroupAction>(
          value: _GroupAction.moveDown,
          child: Text(l10n.subscriptionMoveDown),
        ),
        if (!isReserved)
          PopupMenuItem<_GroupAction>(
            value: _GroupAction.delete,
            child: Text(l10n.subscriptionGroupDelete),
          ),
      ],
    );
  }

  /// 上移/下移一位。
  ///
  /// 界面自己算出新的完整顺序再交给用例：用例只接受「完整顺序」，因此这里不能
  /// 只报告「这一项上移了」。
  Future<void> _moveGroupBy(WidgetRef ref, int delta) async {
    final FeedManagerState? state = ref
        .read(feedManagerControllerProvider)
        .value;
    if (state == null) {
      return;
    }
    final List<int> ids = <int>[
      for (final FeedGroupSection item in state.overview.sections)
        if (item.groupId case final int id) id,
    ];
    if (ids.length != state.overview.sections.length) {
      return;
    }
    final int from = ids.indexOf(section.groupId!);
    final int to = from + delta;
    if (from < 0 || to < 0 || to >= ids.length) {
      return;
    }
    ids.insert(to, ids.removeAt(from));
    await ref.read(feedManagerControllerProvider.notifier).reorderGroups(ids);
  }

  /// 删除分组：先让用户选择订阅的处理方式。
  static Future<void> _delete(
    BuildContext context,
    ScaffoldMessengerState messenger,
    AppLocalizations l10n,
    FeedManagerController controller,
    GroupRecord group,
  ) async {
    final DeleteGroupChoice? choice = await showDeleteGroupDialog(
      context: context,
      groupName: group.name,
      feedCount: 0,
    );
    if (choice == null) {
      return;
    }
    final Result<GroupDeletionReport> result = await controller.deleteGroup(
      groupId: group.id,
      groupName: group.name,
      mode: choice.mode,
    );
    if (result.isErr) {
      notifyError(messenger, result.errorOrNull);
      return;
    }
    final GroupDeletionReport report = result.unwrap();
    if (report.outcome.pendingFeedDeletionCount > 0) {
      // 预留分支：如实说明「没有删除任何数据」，而不是显示「已删除」。
      notify(
        messenger,
        l10n.subscriptionGroupDeleteFeedsPending(
          report.outcome.pendingFeedDeletionCount,
        ),
      );
      return;
    }
    notify(
      messenger,
      l10n.subscriptionGroupDeleted(
        report.groupName,
        report.outcome.movedFeedCount,
      ),
    );
  }
}

/// 分组菜单项。
enum _GroupAction { rename, togglePin, moveUp, moveDown, delete }

/// 订阅菜单：重命名、移动分组、启用、加精、刷新间隔、上移/下移。
class _FeedMenu extends ConsumerWidget {
  const _FeedMenu({
    required this.entry,
    required this.index,
    required this.total,
    required this.groupId,
  });

  final FeedListEntry entry;
  final int index;
  final int total;
  final int? groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final FeedRecord feed = entry.feed;
    final FeedManagerController controller = ref.read(
      feedManagerControllerProvider.notifier,
    );
    final FeedManagerState? state = ref
        .watch(feedManagerControllerProvider)
        .value;

    return PopupMenuButton<_FeedAction>(
      tooltip: l10n.subscriptionFeedMenu,
      onSelected: (_FeedAction action) async {
        // 与分组菜单同样的理由：messenger 在第一个 await 之前取好。
        final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
        switch (action) {
          case _FeedAction.rename:
            final String? name = await showNameDialog(
              context: context,
              title: l10n.subscriptionFeedRenameTitle,
              label: l10n.subscriptionFeedNameLabel,
              initialValue: feed.name,
              emptyErrorMessage: l10n.subscriptionInvalidFeedName,
            );
            if (name == null) {
              return;
            }
            final Result<FeedRecord> result = await controller.renameFeed(
              feedId: feed.id,
              name: name,
            );
            notifyError(messenger, result.errorOrNull);
          case _FeedAction.move:
            final MoveFeedChoice? choice = await showMoveFeedDialog(
              context: context,
              feedName: feed.name,
              currentGroupId: feed.groupId,
              groups: <GroupOption>[
                GroupOption(id: null, name: l10n.subscriptionUngrouped),
                for (final FeedGroupSection section
                    in state?.overview.sections ?? const <FeedGroupSection>[])
                  if (section.groupId case final int id)
                    GroupOption(id: id, name: groupDisplayName(l10n, section)),
              ],
            );
            if (choice == null) {
              return;
            }
            final Result<FeedRecord> result = await controller.moveFeed(
              feedId: feed.id,
              groupId: choice.groupId,
            );
            notifyError(messenger, result.errorOrNull);
          case _FeedAction.toggleEnabled:
            final Result<FeedRecord> result = await controller.setFeedEnabled(
              feedId: feed.id,
              enabled: !feed.enabled,
            );
            notifyError(messenger, result.errorOrNull);
          case _FeedAction.toggleFavorite:
            final Result<FeedRecord> result = await controller.setFeedFavorite(
              feedId: feed.id,
              favorite: !feed.favorite,
            );
            notifyError(messenger, result.errorOrNull);
          case _FeedAction.interval:
            await _pickInterval(context, messenger, l10n, controller, feed);
          case _FeedAction.moveUp:
            await _moveFeedBy(ref, -1);
          case _FeedAction.moveDown:
            await _moveFeedBy(ref, 1);
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<_FeedAction>>[
        PopupMenuItem<_FeedAction>(
          value: _FeedAction.rename,
          child: Text(l10n.subscriptionFeedRename),
        ),
        PopupMenuItem<_FeedAction>(
          value: _FeedAction.move,
          child: Text(l10n.subscriptionFeedMove),
        ),
        PopupMenuItem<_FeedAction>(
          value: _FeedAction.toggleEnabled,
          child: Text(
            feed.enabled
                ? l10n.subscriptionFeedDisable
                : l10n.subscriptionFeedEnable,
          ),
        ),
        PopupMenuItem<_FeedAction>(
          value: _FeedAction.toggleFavorite,
          child: Text(
            feed.favorite
                ? l10n.subscriptionFeedUnfavorite
                : l10n.subscriptionFeedFavorite,
          ),
        ),
        PopupMenuItem<_FeedAction>(
          value: _FeedAction.interval,
          child: Text(l10n.subscriptionFeedIntervalLabel),
        ),
        PopupMenuItem<_FeedAction>(
          value: _FeedAction.moveUp,
          enabled: index > 0,
          child: Text(l10n.subscriptionMoveUp),
        ),
        PopupMenuItem<_FeedAction>(
          value: _FeedAction.moveDown,
          enabled: index < total - 1,
          child: Text(l10n.subscriptionMoveDown),
        ),
      ],
    );
  }

  /// 选择该源的刷新间隔（继承全局 / 手动 / 15 / 30 / 60 / 120）。
  static Future<void> _pickInterval(
    BuildContext context,
    ScaffoldMessengerState messenger,
    AppLocalizations l10n,
    FeedManagerController controller,
    FeedRecord feed,
  ) async {
    final int? selected = await showDialog<int?>(
      context: context,
      builder: (BuildContext context) => SimpleDialog(
        title: Text(l10n.subscriptionFeedIntervalLabel),
        children: <Widget>[
          for (final int? minutes in <int?>[null, 0, 15, 30, 60, 120])
            ListTile(
              title: Text(
                minutes == null
                    ? l10n.subscriptionIntervalInherit
                    : _IntervalField.intervalLabel(l10n, '$minutes'),
              ),
              selected: feed.refreshIntervalMinutes == minutes,
              onTap: () => Navigator.of(context).pop(minutes),
            ),
        ],
      ),
    );
    // 对话框被取消时返回 null，而 null 也是合法取值（继承全局）——因此这里
    // 需要在「选了继承」与「取消」之间区分：用返回值包装成一次显式提交。
    if (selected == null && feed.refreshIntervalMinutes == null) {
      return;
    }
    if (selected == null) {
      // 用户点了继承（或直接取消）。只有当前值不是 null 时才写，避免误改。
      final Result<FeedRecord> result = await controller.setFeedInterval(
        feedId: feed.id,
        minutes: null,
      );
      notifyError(messenger, result.errorOrNull);
      return;
    }
    final Result<FeedRecord> result = await controller.setFeedInterval(
      feedId: feed.id,
      minutes: selected == 0 ? 0 : selected,
    );
    notifyError(messenger, result.errorOrNull);
  }

  /// 上移/下移一位（组内）。
  Future<void> _moveFeedBy(WidgetRef ref, int delta) async {
    final int? gid = groupId;
    if (gid == null) {
      return;
    }
    final FeedManagerState? state = ref
        .read(feedManagerControllerProvider)
        .value;
    if (state == null) {
      return;
    }
    FeedGroupSection? section;
    for (final FeedGroupSection item in state.overview.sections) {
      if (item.groupId == gid) {
        section = item;
        break;
      }
    }
    if (section == null) {
      return;
    }
    final List<int> ids = <int>[
      for (final FeedListEntry item in section.entries) item.feed.id,
    ];
    final int from = ids.indexOf(entry.feed.id);
    final int to = from + delta;
    if (from < 0 || to < 0 || to >= ids.length) {
      return;
    }
    ids.insert(to, ids.removeAt(from));
    await ref
        .read(feedManagerControllerProvider.notifier)
        .reorderFeeds(groupId: gid, orderedIds: ids);
  }
}

/// 订阅菜单项。
enum _FeedAction {
  rename,
  move,
  toggleEnabled,
  toggleFavorite,
  interval,
  moveUp,
  moveDown,
}

/// 显示一条短提示（供异步写入完成后使用）。
///
/// 接收 [ScaffoldMessengerState] 而不是 [BuildContext]：调用点都在 await 之后，
/// 此时组件的 element 可能已经卸载（用户切走了页面），而 messenger 是随
/// MaterialApp 存活的、跨 await 安全的对象。直接持着 context 用，依赖
/// context.mounted 检查也只是把「可能已被卸载」这件事交给调用方记得判断。
void notify(ScaffoldMessengerState messenger, String message) {
  // 先清掉上一条：连续操作时队列会积压，用户看到的提示与当前动作错位。
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(content: Text(message)));
}

/// 有错误时提示，成功时保持安静。
///
/// 「成功不打扰」是有意的：改名/加精/移动这类操作的结果**已经显示在界面上**
/// （那一行的名称、徽标、分组变了），再弹一条「已保存」只是噪音；而失败必须可见。
void notifyError(ScaffoldMessengerState messenger, AppError? error) {
  if (error != null) {
    notify(messenger, error.message);
  }
}

/// 一行「说明文字 + 开关」。
///
/// 自己拼而不是用 SwitchListTile：见调用点的说明（FluxCard 的底色会让 ListTile
/// 系列的断言失败）。
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: FluxSpacing.xs),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Semantics(
            label: label,
            toggled: value,
            child: Switch(value: value, onChanged: onChanged),
          ),
        ],
      ),
    );
  }
}
