// 阅读统计页（T023；架构 5.3 的统计口径与第 3 节「我的 → 阅读统计」）。
//
// 三个展示口径直接对应验收条件：
//   * **热力图 0 值可辨**：0 值格子有边框、可点、有日期与分钟提示；「不在这一年」的
//     布局占位格子是透明的（无边框、不可点）。两者在同一张图里必须看起来不同；
//   * **图例与日期/分钟**：图例给出「少 → 多」的档位序列，每个格子可点出
//     「日期：N 分钟」，因此「某天到底读了多久」不需要靠颜色深浅猜；
//   * **七日柱状图有文字数据**：柱顶直接写分钟数，而不是只让用户看高度。
//
// 关于「估计值」的说明放在页面底部：架构 5.3 明确它是估计、不是精确阅读证明，
// 因此界面不能只给一个看起来很权威的数字。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';
import 'package:flux/core/design/design_tokens.dart';
import 'package:flux/l10n/l10n.dart';
import 'package:flux/ui/ui.dart';

import '../application/reading_stats_controller.dart';
import '../application/reading_stats_state.dart';
import 'heatmap_cell_tile.dart';

/// 阅读统计页。
class ReadingStatsPage extends ConsumerWidget {
  /// 构造页面。
  const ReadingStatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<ReadingStatsState> state = ref.watch(
      readingStatsControllerProvider,
    );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.statsPageTitle)),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) => _LoadFailed(
          message: error is AppError ? error.message : null,
          onRetry: () => ref.invalidate(readingStatsControllerProvider),
        ),
        data: (ReadingStatsState value) => _StatsBody(state: value),
      ),
    );
  }
}

/// 读取失败态：显示原因与重试，而不是画一张空白图表。
class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.message, required this.onRetry});

  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FluxSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: FluxSpacing.sm),
            Text(
              l10n.statsLoadFailed(message ?? ''),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: FluxSpacing.sm),
            FilledButton(onPressed: onRetry, child: Text(l10n.statsRetry)),
          ],
        ),
      ),
    );
  }
}

/// 统计页正文。
class _StatsBody extends ConsumerWidget {
  const _StatsBody({required this.state});

  final ReadingStatsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ReadingStatsController controller = ref.read(
      readingStatsControllerProvider.notifier,
    );
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: FluxSpacing.md),
      children: <Widget>[
        if (state.error case final AppError error)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: FluxSpacing.md,
              vertical: FluxSpacing.xs,
            ),
            child: StatusBanner(
              severity: StatusBannerSeverity.error,
              message: l10n.statsLoadFailed(error.message),
              action: TextButton(
                onPressed: controller.clearError,
                child: Text(l10n.subscriptionClose),
              ),
            ),
          ),
        if (!state.enabled)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: FluxSpacing.md,
              vertical: FluxSpacing.xs,
            ),
            child: StatusBanner(
              severity: StatusBannerSeverity.info,
              message: l10n.statsDisabledNotice,
            ),
          ),
        _SettingsBlock(state: state),
        _SectionTitle(
          title: l10n.statsHeatmapTitle,
          trailing: _YearSelector(state: state),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FluxSpacing.md,
            vertical: FluxSpacing.xs,
          ),
          child: _HeatmapCard(state: state),
        ),
        _SectionTitle(title: l10n.statsWeeklyTitle),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FluxSpacing.md,
            vertical: FluxSpacing.xs,
          ),
          child: _WeeklyCard(state: state),
        ),
        const SizedBox(height: FluxSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FluxSpacing.md,
            vertical: FluxSpacing.xs,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l10n.statsEstimateNote,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              const SizedBox(width: FluxSpacing.sm),
              OutlinedButton.icon(
                onPressed: () => _confirmClear(context, ref),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: Text(l10n.statsClearAction),
              ),
            ],
          ),
        ),
        const SizedBox(height: FluxSpacing.lg),
      ],
    );
  }

  /// 清空统计：先确认（架构第 7 节「危险操作显示影响并可用撤销」的同一条原则；
  /// 统计删除不可撤销，因此必须显式确认）。
  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.statsClearConfirmTitle),
        content: Text(l10n.statsClearConfirmBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.statsClearCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.statsClearConfirmYes),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    final bool ok = await ref
        .read(readingStatsControllerProvider.notifier)
        .clearHistory();
    if (!context.mounted) {
      return;
    }
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            ok ? l10n.statsClearDone(0) : l10n.statsClearFailed(''),
          ),
        ),
      );
  }
}

/// 记录开关与空闲暂停（SET-015）。
class _SettingsBlock extends ConsumerWidget {
  const _SettingsBlock({required this.state});

  final ReadingStatsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ReadingStatsController controller = ref.read(
      readingStatsControllerProvider.notifier,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FluxSpacing.md,
        vertical: FluxSpacing.xs,
      ),
      child: FluxCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    l10n.statsRecordToggleLabel,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Switch(value: state.enabled, onChanged: controller.setEnabled),
              ],
            ),
            Text(
              l10n.statsRecordToggleHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: FluxSpacing.xxs),
            Text(
              l10n.statsIdlePauseLabel(state.idleMinutes),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// 分段标题（可带右侧动作）。
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FluxSpacing.md,
        FluxSpacing.md,
        FluxSpacing.md,
        FluxSpacing.xxs,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleSmall),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// 年份选择器：选项来自**真实数据**（state.years）。
class _YearSelector extends ConsumerWidget {
  const _YearSelector({required this.state});

  final ReadingStatsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // 当前年份不在列表里时（例如今年还没数据）也把它放进去：否则选择器会显示一个
    // 与页面标题不一致的值。
    final List<int> years = <int>{...state.years, state.selectedYear}.toList()
      ..sort((int a, int b) => b.compareTo(a));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          l10n.statsYearLabel,
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(width: FluxSpacing.xxs),
        DropdownButton<int>(
          value: state.selectedYear,
          underline: const SizedBox.shrink(),
          items: <DropdownMenuItem<int>>[
            for (final int year in years)
              DropdownMenuItem<int>(value: year, child: Text('$year')),
          ],
          onChanged: (int? value) {
            if (value == null) {
              return;
            }
            ref.read(readingStatsControllerProvider.notifier).selectYear(value);
          },
        ),
      ],
    );
  }
}

/// 年度热力图卡片（GitHub 风格格子 + 图例 + 合计）。
class _HeatmapCard extends StatelessWidget {
  const _HeatmapCard({required this.state});

  final ReadingStatsState state;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final YearHeatmap heatmap = buildYearHeatmap(
      year: state.selectedYear,
      totals: state.dailyTotals,
      todayWallClock: state.todayWallClock,
    );
    final ThemeData theme = Theme.of(context);
    return FluxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.statsYearTotal(displayMinutes(heatmap.totalSeconds)),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: FluxSpacing.xxs),
          Text(
            l10n.statsActiveDays(heatmap.activeDays),
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: FluxSpacing.sm),
          if (heatmap.isEmpty)
            Text(l10n.statsHeatmapEmpty, style: theme.textTheme.bodySmall)
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _HeatmapGrid(heatmap: heatmap),
            ),
          const SizedBox(height: FluxSpacing.sm),
          _HeatmapLegend(),
        ],
      ),
    );
  }
}

/// 热力图网格（每列一周，7 行）。
class _HeatmapGrid extends StatelessWidget {
  const _HeatmapGrid({required this.heatmap});

  final YearHeatmap heatmap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final HeatmapWeek week in heatmap.weeks)
          Column(
            children: <Widget>[
              for (final HeatmapCell cell in week.days)
                HeatmapCellTile(cell: cell),
            ],
          ),
      ],
    );
  }
}

/// 图例：少 → 多。
class _HeatmapLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Text(l10n.statsHeatmapLegendLess, style: theme.textTheme.labelSmall),
        const SizedBox(width: FluxSpacing.xxs),
        for (final HeatmapLevel level in <HeatmapLevel>[
          HeatmapLevel.none,
          HeatmapLevel.low,
          HeatmapLevel.medium,
          HeatmapLevel.high,
          HeatmapLevel.max,
        ])
          HeatmapCellTile(
            cell: HeatmapCell(
              localDate: '',
              seconds: 0,
              level: level,
              // 图例格子是**示意**，不是数据：inYear 为 false 会让它变成透明占位，
              // 因此这里显式给 true，让 5 个档位的颜色都可见。
              inYear: true,
            ),
          ),
        const SizedBox(width: FluxSpacing.xxs),
        Text(l10n.statsHeatmapLegendMore, style: theme.textTheme.labelSmall),
      ],
    );
  }
}

/// 近七日柱状图卡片（柱 + 文字分钟数）。
class _WeeklyCard extends StatelessWidget {
  const _WeeklyCard({required this.state});

  final ReadingStatsState state;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final WeeklyBars weekly = buildWeeklyBars(
      totals: state.dailyTotals,
      todayWallClock: state.todayWallClock,
      weekdayLabelOf: (DateTime day) => _weekdayLabel(l10n, day),
      dateLabelOf: (DateTime day) => l10n.statsDateLabel(day.day, day.month),
    );
    return FluxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (weekly.isEmpty)
            Text(l10n.statsWeeklyEmpty, style: theme.textTheme.bodySmall)
          else
            _WeeklyBarsChart(bars: weekly),
        ],
      ),
    );
  }

  /// 星期的本地化标签。
  static String _weekdayLabel(AppLocalizations l10n, DateTime day) =>
      switch (day.weekday) {
        DateTime.monday => l10n.statsWeekdayMon,
        DateTime.tuesday => l10n.statsWeekdayTue,
        DateTime.wednesday => l10n.statsWeekdayWed,
        DateTime.thursday => l10n.statsWeekdayThu,
        DateTime.friday => l10n.statsWeekdayFri,
        DateTime.saturday => l10n.statsWeekdaySat,
        _ => l10n.statsWeekdaySun,
      };
}

/// 柱状图：柱高按最大秒数归一化，柱顶写分钟数（文字数据）。
class _WeeklyBarsChart extends StatelessWidget {
  const _WeeklyBarsChart({required this.bars});

  final WeeklyBars bars;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SizedBox(
      height: 180,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          for (final WeeklyBar bar in bars.bars)
            Expanded(
              child: _WeeklyBarColumn(
                bar: bar,
                // 归一化分母至少为 1，避免全 0 时除零（这种情况由调用方走空态，
                // 但这里不该依赖调用方）。
                maxSeconds: bars.maxSeconds == 0 ? 1 : bars.maxSeconds,
                theme: theme,
              ),
            ),
        ],
      ),
    );
  }
}

/// 一根柱（柱体 + 分钟数 + 星期/日期标签）。
class _WeeklyBarColumn extends StatelessWidget {
  const _WeeklyBarColumn({
    required this.bar,
    required this.maxSeconds,
    required this.theme,
  });

  final WeeklyBar bar;
  final int maxSeconds;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    // 柱高：有效比例映射到 4..110 的高度区间。留一个最小高度，让「读了几分钟」
    // 与「完全没读」在视觉上仍有区别（0 秒的柱子高度为 0）。
    final double ratio = bar.seconds / maxSeconds;
    final double height = bar.seconds == 0 ? 0 : (4 + ratio * 106);
    final String minutes = '${displayMinutes(bar.seconds)}';
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        Text(minutes, style: theme.textTheme.labelSmall),
        const SizedBox(height: 2),
        Container(
          height: height,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: bar.seconds == 0
                ? Colors.transparent
                : theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(FluxRadius.button / 2),
          ),
        ),
        const SizedBox(height: FluxSpacing.xxs),
        Text(
          bar.weekdayLabel,
          style: theme.textTheme.labelSmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          bar.dateLabel,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
