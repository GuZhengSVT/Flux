// 热力图格子（T023）。
//
// 单独一个控件而不是在页面里内联一段 Container：格子是**可悬停/长按查看日期与分钟**
// 的交互元素，而验收条件明写「0 值可辨、图例、点击/悬停显示日期+分钟」。把交互与
// 配色收在一处，页面只管排布。
//
// 三条视觉规则（对应验收条件）：
//   * **0 值**（当天没有记录）：有底色、有边框，提示「日期：0 分钟」；
//   * **不在这一年/未来的格子**（inYear = false）：透明、无边框——它是布局留白，
//     不是数据。与 0 值必须一眼可分（否则用户会以为日历缺角）；
//   * **图例格子**（localDate 为空）：与 0 值同样显示，但不挂提示（没有日期可显示）。
library;

import 'package:flutter/material.dart';

import 'package:flux/core/core.dart';
import 'package:flux/l10n/l10n.dart';

/// 一个热力图格子。
class HeatmapCellTile extends StatelessWidget {
  /// 构造格子。
  const HeatmapCellTile({required this.cell, super.key, this.size = 12});

  /// 数据。
  final HeatmapCell cell;

  /// 边长。
  final double size;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    if (!cell.inYear) {
      // 布局占位：保持与真实格子相同的尺寸，但完全透明。用透明而不是「更浅的灰」，
      // 是为了让「没发生」与「发生了但为 0」在色阶上是两件不同的事。
      return SizedBox(width: size + 2, height: size + 2);
    }
    final Widget tile = Container(
      width: size,
      height: size,
      margin: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: colorForHeatmapLevel(cell.level, scheme),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: scheme.outlineVariant, width: 0.5),
      ),
    );
    if (cell.localDate.isEmpty) {
      // 图例格子：没有日期，不挂提示。
      return tile;
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String tooltip = l10n.statsHeatmapCellTooltip(
      cell.localDate,
      displayMinutes(cell.seconds),
    );
    // Tooltip 同时覆盖「悬停」（桌面鼠标）与「长按」（触控）两条路径；
    // 这就是验收条件里「点击/悬停显示日期+分钟」的落点。
    return Tooltip(
      message: tooltip,
      child: Semantics(label: tooltip, child: tile),
    );
  }
}

/// 档位 → 颜色。
///
/// 0 值用 surfaceContainerHighest（有底色、可见）；其余档位用主色按透明度递增。
/// 不用「灰阶深浅」是因为深色主题下灰阶的方向要反过来，而主色在两种主题里都已经
/// 与底色有足够对比（主题由 FluxTheme 按 token 生成，accent 对两套底色都校验过）。
Color colorForHeatmapLevel(HeatmapLevel level, ColorScheme scheme) =>
    switch (level) {
      HeatmapLevel.none => scheme.surfaceContainerHighest,
      HeatmapLevel.low => scheme.primary.withValues(alpha: 0.25),
      HeatmapLevel.medium => scheme.primary.withValues(alpha: 0.45),
      HeatmapLevel.high => scheme.primary.withValues(alpha: 0.7),
      HeatmapLevel.max => scheme.primary,
    };
