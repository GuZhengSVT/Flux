// 分页条与批量操作栏（T017）。
//
// 与列表分开的理由：批量操作栏承载着本任务最容易写错的三条规则（范围语义、
// 收藏只在显式操作里改变、空范围不谎报成功），把它们隔离在一个 200 行的文件里
// 比埋在一张长页面的中部更容易被 review 到。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';
import 'package:flux/core/design/design_tokens.dart';
import 'package:flux/l10n/l10n.dart';

import '../application/batch_article_actions.dart';
import 'article_list_controller.dart';

/// 底部分页条。
class ArticlePager extends ConsumerWidget {
  /// 构造分页条。
  const ArticlePager({required this.state, super.key});

  /// 页面状态。
  final ArticleListPageState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ArticleListController controller = ref.read(
      articleListControllerProvider.notifier,
    );
    final int pages = state.page.pageCount(state.total);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FluxSpacing.md,
        vertical: FluxSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              l10n.readingPageIndicator(
                state.page.page + 1,
                pages,
                state.total,
              ),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          TextButton(
            onPressed: state.page.hasPrevious
                ? () => controller.goToPage(state.page.page - 1)
                : null,
            child: Text(l10n.readingPreviousPage),
          ),
          TextButton(
            onPressed: state.page.hasNext(state.total)
                ? () => controller.goToPage(state.page.page + 1)
                : null,
            child: Text(l10n.readingNextPage),
          ),
        ],
      ),
    );
  }
}

/// 批量操作栏。
///
/// 范围选择（架构 4.1 的「全部 / 筛选结果 / 所选行」）在这里落地为**显式**的三选一，
/// 而不是由按钮文案暗示：
///   - 有勾选时默认「所选行」（用户先勾选再操作是主路径）；
///   - 没有勾选时默认「当前筛选结果」（比「全部」安全：用户此刻看到的就是筛选后的
///     这一批）。
///
/// 「全部文章」没有被放进默认路径：它在未读筛选下会改到用户根本看不到的文章，
/// 那正是「范围必须在操作前可见」这条要求要防的事。
class BatchActionBar extends ConsumerWidget {
  /// 构造操作栏。
  const BatchActionBar({required this.state, super.key});

  /// 页面状态。
  final ArticleListPageState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ArticleListController controller = ref.read(
      articleListControllerProvider.notifier,
    );
    // 范围选择是**显式**的三选一（架构 4.1 的「全部 / 筛选结果 / 所选行」），
    // 而不是由按钮文案暗示：用户必须能看见「这次会改到哪些文章」。
    // 默认值按「有勾选就用勾选，否则用当前筛选结果」——「全部文章」不在默认路径上，
    // 因为它在未读筛选下会改到用户根本看不到的文章。
    final BatchScope scope =
        state.scope ??
        (state.selectedIds.isEmpty ? BatchScope.filtered : BatchScope.selected);
    // 范围文案：把「这次会改到哪些文章」写在按钮旁边，而不是让用户猜。
    final String scopeText = scope == BatchScope.selected
        ? l10n.readingBatchScopeSelected(state.selectedIds.length)
        : l10n.readingBatchScopeFiltered;

    return Container(
      padding: const EdgeInsets.all(FluxSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: FluxSpacing.sm,
            runSpacing: FluxSpacing.xs,
            children: <Widget>[
              Text(
                l10n.readingBatchSelectedCount(state.selectedIds.length),
                style: Theme.of(context).textTheme.labelMedium,
              ),
              TextButton(
                onPressed: controller.toggleSelectPage,
                child: Text(l10n.readingBatchSelectPage),
              ),
              Text(
                '${l10n.readingBatchScopeLabel}：$scopeText',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: FluxSpacing.xxs),
          // 三个范围各自是一个可选项，并且**每次都显示会作用到多少篇**：
          // 「全部文章」在未读筛选下是一个容易误点的高风险选项，因此它的文案里
          // 带上「全部」字样，而不是让用户从上下文猜。
          SegmentedButton<BatchScope>(
            segments: <ButtonSegment<BatchScope>>[
              ButtonSegment<BatchScope>(
                value: BatchScope.selected,
                label: Text(
                  l10n.readingBatchScopeSelected(state.selectedIds.length),
                ),
              ),
              ButtonSegment<BatchScope>(
                value: BatchScope.filtered,
                label: Text(l10n.readingBatchScopeFiltered),
              ),
              ButtonSegment<BatchScope>(
                value: BatchScope.all,
                label: Text(l10n.readingBatchScopeAll),
              ),
            ],
            selected: <BatchScope>{scope},
            showSelectedIcon: false,
            onSelectionChanged: (Set<BatchScope> selection) =>
                controller.setScope(selection.first),
          ),
          const SizedBox(height: FluxSpacing.xxs),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: FluxSpacing.xs,
            runSpacing: FluxSpacing.xxs,
            children: <Widget>[
              // 三态批量：**不触碰收藏**。
              TextButton(
                onPressed: () => _run(
                  context,
                  () => controller.batchSetReadingState(
                    scope: scope,
                    value: ReadingState.read,
                  ),
                  l10n,
                  ref,
                  l10n.readingActionMarkRead,
                ),
                child: Text(l10n.readingBatchMarkRead),
              ),
              TextButton(
                onPressed: () => _run(
                  context,
                  () => controller.batchSetReadingState(
                    scope: scope,
                    value: ReadingState.unread,
                  ),
                  l10n,
                  ref,
                  l10n.readingActionMarkUnread,
                ),
                child: Text(l10n.readingBatchMarkUnread),
              ),
              TextButton(
                onPressed: () => _run(
                  context,
                  () => controller.batchSetReadingState(
                    scope: scope,
                    value: ReadingState.later,
                  ),
                  l10n,
                  ref,
                  l10n.readingActionMarkLater,
                ),
                child: Text(l10n.readingBatchMarkLater),
              ),
              const SizedBox(width: FluxSpacing.xs),
              // 收藏只在**这两个**显式操作里改变（手册 6.3）。
              TextButton(
                onPressed: () => _run(
                  context,
                  () =>
                      controller.batchSetFavorite(scope: scope, favorite: true),
                  l10n,
                  ref,
                  l10n.readingActionFavorite,
                ),
                child: Text(l10n.readingBatchFavorite),
              ),
              TextButton(
                onPressed: () => _run(
                  context,
                  () => controller.batchSetFavorite(
                    scope: scope,
                    favorite: false,
                  ),
                  l10n,
                  ref,
                  l10n.readingActionUnfavorite,
                ),
                child: Text(l10n.readingBatchUnfavorite),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 执行一次批量操作并如实提示结果。
  ///
  /// 提示条里带**撤销**动作（架构第 7 节「危险操作显示影响和可用撤销」）：
  ///   - 提示条内容说明影响范围（多少篇、做了什么），而不是一句「操作成功」；
  ///   - 「撤销」按钮按快照逐行恢复操作之前的具体状态，因此对一批混合状态的文章
  ///     也能真正回到原样；
  ///   - 撤销之后再点撤销不会重复写库（句柄已失效）。
  static Future<void> _run(
    BuildContext context,
    Future<BatchActionReport?> Function() action,
    AppLocalizations l10n,
    WidgetRef ref,
    String actionLabel,
  ) async {
    final BatchActionReport? report = await action();
    if (!context.mounted) {
      return;
    }
    // 空范围**不谎报成功**：说清「没有可操作的文章」，而不是「已处理 0 篇」
    // （后者会被读成「做过一次但没生效」）。
    if (report == null || report.isEmptyScope) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(l10n.readingBatchEmptyScope)));
      return;
    }
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.readingUndoMessage(report.applied, actionLabel)),
          action: SnackBarAction(
            label: l10n.readingUndoAction,
            onPressed: () => _undo(context, ref, l10n),
          ),
          // 撤销窗口给足时间：这是一个需要用户读完提示再决定的动作，
          // 4 秒默认时长在中文提示下常常来不及。
          duration: const Duration(seconds: 8),
        ),
      );
  }

  /// 执行撤销。
  static Future<void> _undo(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final Result<int> restored = await ref
        .read(articleListControllerProvider.notifier)
        .undoLastBatchAction();
    if (!context.mounted) {
      return;
    }
    final String message = restored.isOk
        ? l10n.readingUndoDone(restored.unwrap())
        // 撤销失败必须**明确说失败**：显示「已撤销」而库里没变会让用户以为状态回去了。
        : l10n.readingUndoFailed(restored.errorOrNull!.message);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
