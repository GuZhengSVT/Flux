// 去向占位页（T011）。
//
// 为什么占位页要写得这么「啰嗦」：M0 阶段最容易出的错不是崩溃，而是**看起来像
// 已经实现了**。一个漂亮的空列表会被当成「功能缺失」而不是「尚未开始」，也会让
// 后续任务在验收时无法判断自己是否真的做完了。因此每页明确写出：
//   1) 当前是占位，没有数据、没有交互；
//   2) 负责实现它的任务号；
//   3) 该去向在架构第 3 节里的目标内容（让占位与产品定义对得上）。
//
// 同时这里**切实验证**了架构第 7 节的设备布局要求：按窗口逻辑宽度呈现
// 1 / 2 / 3 栏结构。本期内容区是占位面板，但分栏逻辑本身是真实实现的。
library;

import 'package:flutter/material.dart';

import 'package:flux/core/design/design_tokens.dart';
import 'package:flux/features/settings/presentation/settings_page.dart';
import 'package:flux/l10n/l10n.dart';
import 'package:flux/ui/ui.dart';

import '../theme/flux_theme.dart';
import 'app_destination.dart';
import 'shell_layout.dart';

/// 按去向渲染占位页；「我的」直接指向真正的设置页（T011 已实现的部分）。
class PlaceholderDestinationPage extends StatelessWidget {
  /// 构造占位页。
  const PlaceholderDestinationPage({super.key, required this.destination});

  /// 当前去向。
  final AppDestination destination;

  @override
  Widget build(BuildContext context) {
    return switch (destination) {
      AppDestination.mine => const SettingsPage(),
      AppDestination.today => const _ShellPlaceholderPage(
        titleKey: _PlaceholderTitle.today,
        emptyState: _EmptyStateKind.today,
      ),
      AppDestination.reading => const _ShellPlaceholderPage(
        titleKey: _PlaceholderTitle.reading,
        emptyState: _EmptyStateKind.noFeeds,
      ),
    };
  }
}

/// 哪个去向（决定标题与目标内容说明）。
enum _PlaceholderTitle { today, reading }

/// 展示哪个空态。
enum _EmptyStateKind { today, noFeeds, allRead, noResults }

/// 壳层占位页：标题 + 空态 + 分栏占位结构。
class _ShellPlaceholderPage extends StatelessWidget {
  const _ShellPlaceholderPage({
    required this.titleKey,
    required this.emptyState,
  });

  final _PlaceholderTitle titleKey;
  final _EmptyStateKind emptyState;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String title = switch (titleKey) {
      _PlaceholderTitle.today => l10n.navToday,
      _PlaceholderTitle.reading => l10n.navReading,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _PageHeader(title: title, badge: l10n.placeholderBadge),
        Expanded(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              return _ResponsivePlaceholderBody(
                constraints: constraints,
                emptyState: emptyState,
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 页面头部：标题、占位标记、壳层说明。
class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.title, required this.badge});

  final String title;
  final String badge;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final FluxColors colors = FluxColors.of(context);
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FluxSpacing.lg,
        vertical: FluxSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(title, style: theme.textTheme.titleLarge),
                const SizedBox(height: FluxSpacing.xxs),
                Text(
                  l10n.milestoneShellNotice,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: FluxSpacing.sm),
          _Badge(text: badge),
        ],
      ),
    );
  }
}

/// 小号标记（占位/即将推出）。
class _Badge extends StatelessWidget {
  const _Badge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final FluxColors colors = FluxColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FluxSpacing.xs,
        vertical: FluxSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: colors.selectedSurface,
        borderRadius: BorderRadius.circular(FluxRadius.button),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: colors.textSecondary),
      ),
    );
  }
}

/// 按断点呈现 1 / 2 / 3 栏占位结构。
class _ResponsivePlaceholderBody extends StatelessWidget {
  const _ResponsivePlaceholderBody({
    required this.constraints,
    required this.emptyState,
  });

  final BoxConstraints constraints;
  final _EmptyStateKind emptyState;

  @override
  Widget build(BuildContext context) {
    final double width = constraints.maxWidth;
    final AppLocalizations l10n = AppLocalizations.of(context);

    // 分栏形态由 shell_layout.dart 的纯函数判定：三栏要同时满足 >=1100 与
    // 正文余量 >=560，不足则退回双栏（架构第 7 节）。判断逻辑可单独测试，
    // 因此这里只消费结果。
    final ShellPaneLayout layout = resolvePaneLayout(width);
    final bool threeColumn = layout == ShellPaneLayout.triple;
    final bool twoColumn = layout != ShellPaneLayout.single;

    final String layoutLabel = switch (layout) {
      ShellPaneLayout.triple => l10n.layoutBreakpointTriple,
      ShellPaneLayout.double => l10n.layoutBreakpointDouble,
      ShellPaneLayout.single => l10n.layoutBreakpointSingle,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _LayoutLabel(text: layoutLabel),
        Expanded(
          child: threeColumn
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    SizedBox(
                      width: FluxBreakpoints.sourcePaneWidth,
                      child: _PanePlaceholder(
                        title: l10n.layoutPaneSource,
                        tasks: 'T013–T016',
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    SizedBox(
                      width: FluxBreakpoints.listPaneWidth,
                      child: _PanePlaceholder(
                        title: l10n.layoutPaneList,
                        tasks: 'T017–T019',
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: _PanePlaceholder(
                        title: l10n.layoutPaneBody,
                        tasks: 'T019–T024',
                        emptyState: emptyState,
                      ),
                    ),
                  ],
                )
              : twoColumn
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    SizedBox(
                      width: resolveSourcePaneWidth(width),
                      child: _PanePlaceholder(
                        title: l10n.layoutPaneSource,
                        tasks: 'T013–T016',
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: _PanePlaceholder(
                        title: l10n.layoutPaneList,
                        tasks: 'T017–T019',
                        emptyState: emptyState,
                      ),
                    ),
                  ],
                )
              : _PanePlaceholder(
                  title: l10n.layoutPaneList,
                  tasks: 'T017–T019',
                  emptyState: emptyState,
                ),
        ),
      ],
    );
  }
}

/// 当前布局模式标注（让宽/窄窗行为可被截图核对）。
class _LayoutLabel extends StatelessWidget {
  const _LayoutLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final FluxColors colors = FluxColors.of(context);
    return Container(
      width: double.infinity,
      color: colors.selectedSurface,
      padding: const EdgeInsets.symmetric(
        horizontal: FluxSpacing.lg,
        vertical: FluxSpacing.xs,
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: colors.textSecondary),
      ),
    );
  }
}

/// 单个占位面板。
class _PanePlaceholder extends StatelessWidget {
  const _PanePlaceholder({
    required this.title,
    required this.tasks,
    this.emptyState,
  });

  final String title;
  final String tasks;
  final _EmptyStateKind? emptyState;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final FluxColors colors = FluxColors.of(context);
    final ThemeData theme = Theme.of(context);
    return Container(
      color: colors.background,
      padding: const EdgeInsets.all(FluxSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
              const SizedBox(width: FluxSpacing.xs),
              _Badge(text: l10n.placeholderBadge),
            ],
          ),
          const SizedBox(height: FluxSpacing.xs),
          Expanded(
            child: emptyState == null
                ? _PaneTaskNote(tasks: tasks)
                : _EmptyStateBlock(kind: emptyState!, tasks: tasks),
          ),
        ],
      ),
    );
  }
}

/// 空态占位（无订阅/全部已读/无结果/今日无新闻）。
///
/// T012 起改用共享的 [FluxEmptyState]：本文件原先自己拼「图标 + 标题 + 说明」，
/// 而架构第 7 节要求这三类空态分别提示且样式一致。用共享组件之后，空态的图形、
/// 字号、间距与后续页面（同为 T012 起的控件层）自动一致，不需要逐页对齐；
/// 「计划任务」说明仍作为 secondaryNote 传入，占位页的诚实标注没有丢。
class _EmptyStateBlock extends StatelessWidget {
  const _EmptyStateBlock({required this.kind, required this.tasks});

  final _EmptyStateKind kind;
  final String tasks;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    final (String title, String body, EmptyStateTone tone) = switch (kind) {
      _EmptyStateKind.today => (
        l10n.todayEmptyTitle,
        l10n.todayEmptyBody,
        EmptyStateTone.neutral,
      ),
      _EmptyStateKind.noFeeds => (
        l10n.emptyNoFeedsTitle,
        l10n.emptyNoFeedsBody,
        EmptyStateTone.neutral,
      ),
      // 「全部已读」是完成态：用强调色而不是灰阶，否则用户会把它读成「出错了」。
      _EmptyStateKind.allRead => (
        l10n.emptyAllReadTitle,
        l10n.emptyAllReadBody,
        EmptyStateTone.positive,
      ),
      _EmptyStateKind.noResults => (
        l10n.emptyNoResultsTitle,
        l10n.emptyNoResultsBody,
        EmptyStateTone.muted,
      ),
    };

    return FluxEmptyState(
      title: title,
      body: body,
      tone: tone,
      secondaryNote: l10n.placeholderPageBody(tasks),
    );
  }
}

/// 「计划任务」说明行。
class _PaneTaskNote extends StatelessWidget {
  const _PaneTaskNote({required this.tasks});

  final String tasks;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Text(
      l10n.placeholderPageBody(tasks),
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: FluxColors.of(context).warning),
    );
  }
}
