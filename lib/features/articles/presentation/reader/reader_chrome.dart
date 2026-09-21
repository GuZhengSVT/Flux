// 阅读页的外围控件（T019）：完整性徽标、查找栏、目录侧栏、上下篇、时间格式。
//
// 与渲染器分开：渲染器只负责「树 → 控件」，而这些控件的状态属于**页面**（查找词、当前
// 目录项、从哪一篇来）。混在一起会让渲染器需要知道页面状态，而它应当是一个映射。
library;

import 'package:flutter/material.dart';

import 'package:flux/core/core.dart';
import 'package:flux/core/design/design_tokens.dart';
import 'package:flux/l10n/l10n.dart';

import '../../application/reader_outline.dart';

/// 本地时间格式（Y-MM-DD HH:mm）。
///
/// 自带一个而不引 intl 的 DateFormat：这里只需要一种固定形态，而 DateFormat 需要
/// locale 数据初始化，会给阅读路径加一个与产品无关的依赖。
String formatLocalTime(DateTime utc) {
  final DateTime local = utc.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  final String date = '${local.year}-${two(local.month)}-${two(local.day)}';
  return '$date ${two(local.hour)}:${two(local.minute)}';
}

/// 正文完整性徽标（架构 4.2 的四态）。
class CompletenessBadge extends StatelessWidget {
  /// 构造徽标。
  const CompletenessBadge({
    super.key,
    required this.completeness,
    required this.color,
    required this.border,
  });

  /// 四态取值。
  final BodyCompleteness completeness;

  /// 文字色。
  final Color color;

  /// 边框色。
  final Color border;

  /// 四态各自的文案。
  ///
  /// 四种都必须有：缺一种会让那个状态显示成另一个状态的名字，而「正文完整性」正是
  /// 读者判断「我看到的够不够」的依据。
  static String labelOf(AppLocalizations l10n, BodyCompleteness value) =>
      switch (value) {
        BodyCompleteness.sourceBody => l10n.readingCompletenessSourceBody,
        BodyCompleteness.summaryOnly => l10n.readingCompletenessSummaryOnly,
        BodyCompleteness.extracted => l10n.readingCompletenessExtracted,
        BodyCompleteness.unknown => l10n.readingCompletenessUnknown,
      };

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FluxSpacing.xs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FluxRadius.button),
        border: Border.all(color: border),
      ),
      child: Text(
        labelOf(l10n, completeness),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

/// 页内查找栏（架构第 7 节：页内查找独立于全库搜索）。
class FindBar extends StatelessWidget {
  /// 构造查找栏。
  const FindBar({
    super.key,
    required this.controller,
    required this.matchCount,
    required this.hasQuery,
    required this.onChanged,
    required this.onClose,
  });

  /// 输入控制器（由页面持有，关闭时清空）。
  final TextEditingController controller;

  /// 匹配数。
  final int matchCount;

  /// 是否已有查询词（区分「还没搜」与「搜了没结果」）。
  final bool hasQuery;

  /// 输入变化。
  final ValueChanged<String> onChanged;

  /// 关闭。
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FluxSpacing.md,
        vertical: FluxSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: l10n.readingFindHint,
                isDense: true,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search, size: 18),
              ),
            ),
          ),
          const SizedBox(width: FluxSpacing.xs),
          // 匹配计数只在高亮开启时显示：没有查询词时显示「0 个匹配」会被读成
          // 「这篇文章里没有那几个字」，而用户其实还没输入。
          if (hasQuery)
            Text(
              matchCount == 0
                  ? l10n.readingFindNoMatch
                  : l10n.readingFindMatchCount(1, matchCount),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          IconButton(
            tooltip: l10n.readingFindClose,
            icon: const Icon(Icons.close),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

/// 目录侧栏（h1–h3）。
class OutlinePane extends StatelessWidget {
  /// 构造目录。
  const OutlinePane({
    super.key,
    required this.outline,
    required this.onSelect,
    this.activeBlockIndex,
  });

  /// 目录项。
  final List<ReaderOutlineEntry> outline;

  /// 当前所在项（点击后由页面回填）。
  final int? activeBlockIndex;

  /// 选择某一项。
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    return Container(
      width: FluxBreakpoints.sourcePaneMax,
      padding: const EdgeInsets.symmetric(
        horizontal: FluxSpacing.sm,
        vertical: FluxSpacing.md,
      ),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(l10n.readingTocTitle, style: theme.textTheme.titleSmall),
            const SizedBox(height: FluxSpacing.xs),
            if (outline.isEmpty)
              Text(l10n.readingTocEmpty, style: theme.textTheme.labelSmall)
            else
              for (final ReaderOutlineEntry entry in outline)
                InkWell(
                  onTap: () => onSelect(entry.blockIndex),
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: (entry.level - 1) * FluxSpacing.sm,
                      top: FluxSpacing.xxs,
                      bottom: FluxSpacing.xxs,
                    ),
                    child: Text(
                      entry.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: entry.blockIndex == activeBlockIndex
                          ? theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            )
                          : theme.textTheme.bodySmall,
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// 上下篇导航条。
class NeighborBar extends StatelessWidget {
  /// 构造导航条。
  const NeighborBar({
    super.key,
    required this.snapshot,
    required this.currentId,
    required this.onNavigate,
  });

  /// 进入阅读时的筛选/排序快照。
  final ReaderSnapshot? snapshot;

  /// 当前文章 id。
  final int currentId;

  /// 跳转回调。
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ReaderSnapshot? snapshot = this.snapshot;
    final int? previous = snapshot?.previousId;
    final int? next = snapshot?.nextId;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FluxSpacing.md,
        vertical: FluxSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: <Widget>[
          TextButton.icon(
            onPressed: previous == null ? null : () => onNavigate(previous),
            icon: const Icon(Icons.arrow_back, size: 16),
            // 首篇时按钮禁用并显示边界说明：把按钮藏起来会让「上一篇」这一栏的宽度
            // 在翻到首篇时突然变，而读者正在看的是正文。
            label: Text(
              previous == null ? l10n.readingNoPrev : l10n.readingPrevArticle,
            ),
          ),
          const Spacer(),
          if (snapshot == null)
            Text(
              l10n.readingNeighborOrderNote,
              style: theme.textTheme.labelSmall,
            ),
          const Spacer(),
          TextButton.icon(
            onPressed: next == null ? null : () => onNavigate(next),
            icon: const Icon(Icons.arrow_forward, size: 16),
            label: Text(
              next == null ? l10n.readingNoNext : l10n.readingNextArticle,
            ),
          ),
        ],
      ),
    );
  }
}
