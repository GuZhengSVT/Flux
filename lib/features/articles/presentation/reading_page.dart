// RSS 阅读页（T017）：文章列表 + 筛选 + 分页 + 批量操作 + 顶部刷新。
//
// 为什么这一页由 T017 交付而不是 T019：
//   架构 4.1 把「三态、收藏、筛选、批量操作」列为 F-STATE（T017），把「卡片形态、
//   虚拟化、目录、上下篇」列为列表/正文产品化（T019）。本页因此刻意用**最朴素的
//   卡片**：标题 + 来源 + 时间 + 一行摘要。它是一张能真正操作数据的列表，而不是
//   最终视觉稿——把朴素版做对（状态、筛选、分页、范围）比先画好看更符合依赖顺序。

// 与订阅管理页一致的三条约束：
//   1) 读失败显示错误态与重试，不显示空列表（空列表会被读成「文章没了」）；
//   2) 写入后重读，不打补丁；
//   3) 没有订阅与「筛选无结果」分别提示（架构第 7 节要求三类空态区分）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';
import 'package:flux/core/design/design_tokens.dart';
import 'package:flux/features/feeds/application/refresh_providers.dart';
import 'package:flux/features/feeds/application/feed_overview.dart';
import 'package:flux/features/feeds/presentation/feed_manager_controller.dart';
import 'package:flux/features/feeds/presentation/refresh_outcome_text.dart';
import 'package:flux/l10n/l10n.dart';
import 'package:flux/ui/ui.dart';

import '../application/article_list_state.dart';
import '../application/article_search_state.dart';
import 'article_list_controller.dart';
import 'article_list_view.dart';
import 'article_search_view.dart';

/// RSS 阅读页。
class ReadingPage extends ConsumerWidget {
  /// 构造页面。
  const ReadingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<ArticleListPageState> state = ref.watch(
      articleListControllerProvider,
    );
    final ArticleSearchState search = ref.watch(searchControllerProvider);
    // 「是否处于搜索模式」由查询框是否有内容/是否聚焦决定：查询词非空即进入搜索结果，
    // 清空即回到浏览列表。用查询词而不是一个独立的开关状态，是因为用户的心智模型就是
    // 「我输入了词 → 看到结果；我清空 → 回到列表」。
    final bool searching = search.query.trim().isNotEmpty || search.searched;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _ReadingToolbar(),
        const _SearchBar(),
        if (state.value?.actionError case final AppError error)
          StatusBanner(
            severity: StatusBannerSeverity.error,
            message: l10n.readingActionError(error.message),
            action: TextButton(
              onPressed: () => ref
                  .read(articleListControllerProvider.notifier)
                  .clearActionError(),
              child: Text(l10n.subscriptionClose),
            ),
          ),
        Expanded(
          child: searching
              ? ArticleSearchView(state: search)
              : state.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (Object error, StackTrace stackTrace) =>
                      ReadingLoadFailed(
                        message: error is AppError ? error.message : null,
                        onRetry: () =>
                            ref.invalidate(articleListControllerProvider),
                      ),
                  data: (ArticleListPageState value) =>
                      ArticleListView(state: value),
                ),
        ),
      ],
    );
  }
}

/// 全库检索输入框（T022）。
///
/// 放在工具栏**下方**而不是嵌进工具栏：工具栏已经有一排按钮（刷新/筛选/批量/来源），
/// 再塞一个输入框会让它在窄窗上被挤成一条缝。单独一行既保证输入宽度，也让「搜索」
/// 这件事在视觉上有自己的位置。
///
/// 为什么用 TextField 的 onChanged 而不是 onSubmitted：本地检索没有往返成本，
/// 边输入边出结果是用户对本地搜索的预期（这也让「无结果」更快被发现）。
/// 防抖在控制器里做（180 ms），不在这里。
class _SearchBar extends ConsumerStatefulWidget {
  const _SearchBar();

  @override
  ConsumerState<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends ConsumerState<_SearchBar> {
  late final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ArticleSearchState state = ref.watch(searchControllerProvider);
    // 外部清空（例如点「关闭搜索」）时同步输入框：不监听的话输入框里会留着上一个词，
    // 而结果已经回到浏览列表——两边看起来在打架。
    if (_controller.text != state.query) {
      _controller.value = TextEditingValue(
        text: state.query,
        selection: TextSelection.collapsed(offset: state.query.length),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FluxSpacing.md,
        vertical: FluxSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _controller,
              onChanged: ref.read(searchControllerProvider.notifier).setQuery,
              textInputAction: TextInputAction.search,
              onSubmitted: (String _) =>
                  ref.read(searchControllerProvider.notifier).run(),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 18),
                labelText: l10n.searchFieldLabel,
                hintText: l10n.searchFieldHint,
                border: const OutlineInputBorder(),
                suffixIcon: state.query.isEmpty
                    ? null
                    : IconButton(
                        iconSize: 18,
                        tooltip: l10n.searchClear,
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _controller.clear();
                          ref.read(searchControllerProvider.notifier).clear();
                        },
                      ),
              ),
            ),
          ),
          const SizedBox(width: FluxSpacing.xs),
          // 范围切换：架构 4.2 要求「全部 / 当前筛选」两种范围都要可用。
          SegmentedButton<SearchScope>(
            segments: <ButtonSegment<SearchScope>>[
              ButtonSegment<SearchScope>(
                value: SearchScope.all,
                label: Text(l10n.searchScopeAll),
              ),
              ButtonSegment<SearchScope>(
                value: SearchScope.currentFilter,
                label: Text(l10n.searchScopeFiltered),
              ),
            ],
            selected: <SearchScope>{state.scope},
            onSelectionChanged: (Set<SearchScope> selection) => ref
                .read(searchControllerProvider.notifier)
                .setScope(scope: selection.first),
          ),
        ],
      ),
    );
  }
}

/// 顶部工具栏：刷新 + 筛选 + 批量开关。
class _ReadingToolbar extends ConsumerWidget {
  const _ReadingToolbar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ArticleListPageState? state = ref
        .watch(articleListControllerProvider)
        .value;
    final bool running =
        ref.watch(refreshControllerProvider).value?.running ?? false;
    final ArticleListState page = state?.page ?? const ArticleListState();

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FluxSpacing.md,
        vertical: FluxSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: FluxSpacing.sm,
        runSpacing: FluxSpacing.xs,
        children: <Widget>[
          // 刷新按钮：手动全量刷新（T016）。
          FilledButton.icon(
            onPressed: running ? null : () => _refresh(context, ref),
            icon: running
                ? const FluxLoadingIndicator(size: 16)
                : const Icon(Icons.refresh, size: 18),
            label: Text(running ? l10n.readingRefreshing : l10n.readingRefresh),
          ),
          // 筛选：四个入口与架构 4.1 一致（later 是**独立**入口，不混进未读）。
          SegmentedButton<ArticleFilter>(
            segments: <ButtonSegment<ArticleFilter>>[
              ButtonSegment<ArticleFilter>(
                value: ArticleFilter.all,
                label: Text(l10n.readingFilterAll),
              ),
              ButtonSegment<ArticleFilter>(
                value: ArticleFilter.unread,
                label: Text(l10n.readingFilterUnread),
              ),
              ButtonSegment<ArticleFilter>(
                value: ArticleFilter.later,
                label: Text(l10n.readingFilterLater),
              ),
              ButtonSegment<ArticleFilter>(
                value: ArticleFilter.favorite,
                label: Text(l10n.readingFilterFavorite),
              ),
            ],
            selected: <ArticleFilter>{page.filter},
            showSelectedIcon: false,
            onSelectionChanged: (Set<ArticleFilter> selection) => ref
                .read(articleListControllerProvider.notifier)
                .setFilter(selection.first),
          ),
          // 批量模式开关。
          TextButton.icon(
            onPressed: state == null
                ? null
                : () => ref
                      .read(articleListControllerProvider.notifier)
                      .setBatchMode(!state.batchMode),
            icon: Icon(
              state?.batchMode ?? false ? Icons.close : Icons.checklist,
              size: 18,
            ),
            label: Text(
              state?.batchMode ?? false
                  ? l10n.readingBatchExit
                  : l10n.readingBatchEnter,
            ),
          ),
          // 来源筛选（按订阅）：「未读」筛选常常需要再按来源收窄。架构 4.1 的来源
          // 详情页（T019）会在三栏布局里做同一件事，本任务先用一个下拉提供该能力。
          _FeedFilter(state: state),
        ],
      ),
    );
  }

  /// 手动刷新并按结果给出提示。
  static Future<void> _refresh(BuildContext context, WidgetRef ref) async {
    final RefreshStatus status = await ref
        .read(refreshControllerProvider.notifier)
        .refreshNow();
    if (!context.mounted) {
      return;
    }
    final String message = describeRefreshOutcome(
      AppLocalizations.of(context),
      status,
    );
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
    // 刷新后重读列表：新文章要立刻出现，而不是等用户切页。
    await ref.read(articleListControllerProvider.notifier).reload();
  }
}

/// 来源筛选下拉。
class _FeedFilter extends ConsumerWidget {
  const _FeedFilter({required this.state});

  final ArticleListPageState? state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<FeedOverview> overview = ref.watch(feedOverviewProvider);
    final List<FeedFilterOption> options = <FeedFilterOption>[
      for (final FeedGroupSection section
          in overview.value?.sections ?? const <FeedGroupSection>[])
        for (final FeedListEntry entry in section.entries)
          FeedFilterOption(feedId: entry.feed.id, name: entry.feed.name),
    ];
    if (options.isEmpty) {
      // 没有订阅时不显示一个只有「全部来源」一项的下拉：那会让用户以为筛选坏了。
      return const SizedBox.shrink();
    }
    final int? current = state?.page.feedId;
    // 当前选中的来源可能已被删除（T018 的删除、或同步落地）：此时回退到「全部来源」
    // 而不是把一个不存在的值交给 DropdownButton——那会直接抛断言。
    final int? value = options.any((FeedFilterOption o) => o.feedId == current)
        ? current
        : null;
    return DropdownButton<int?>(
      value: value,
      hint: Text(l10n.readingFeedFilterAll),
      items: <DropdownMenuItem<int?>>[
        DropdownMenuItem<int?>(
          value: null,
          child: Text(l10n.readingFeedFilterAll),
        ),
        for (final FeedFilterOption option in options)
          DropdownMenuItem<int?>(
            value: option.feedId,
            child: Text(option.name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (int? next) =>
          ref.read(articleListControllerProvider.notifier).setFeedFilter(next),
    );
  }
}

/// 列表读取失败的界面（工具栏与列表正文共用）。
class ReadingLoadFailed extends StatelessWidget {
  /// 构造失败界面。
  const ReadingLoadFailed({required this.onRetry, this.message, super.key});

  /// 重试回调。
  final VoidCallback onRetry;

  /// 读取失败的原因（已脱敏）；为空时用一条通用说明。
  final String? message;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return FluxEmptyState(
      icon: FluxIcon.inboxEmpty,
      title: l10n.readingLoadFailed(message ?? l10n.settingsWriteFailed),
      body: l10n.readingEmptyBody,
      action: FilledButton(
        onPressed: onRetry,
        child: Text(l10n.readingRefresh),
      ),
    );
  }
}
