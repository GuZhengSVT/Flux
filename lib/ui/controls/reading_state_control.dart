// 阅读状态三态控件（T012，架构 4.1/F-STATE、D-10 与第 7 节美术标准）。
//
// 本控件存在的**唯一**理由就是把一条产品规则变成结构上的不可能：
//
//   「单一阅读字段 readingState = unread / read / later；不存在『已读且稍后再读』
//     的双状态。收藏 favorite 独立。」
//
// 因此这里刻意**不**做成三个独立开关（那正是双状态的形状），而是一个控件位内的
// 单一取值选择器：一个控件位、一个当前值、点按/回车在三个值之间循环。
//
// 为什么用「循环」而不是弹出菜单：
//   - 架构第 7 节要求「状态三选一占一个控件位置」。循环切换在列表项这种密集场景
//     下不需要额外的浮层与第二焦点管理，键盘用户一次回车即可推进；
//   - 同时提供 semanticsHint 说明循环顺序，并播报切换结果，避免「按了但不知道变成
//     什么」——这是循环式控件最常见的可访问性问题。
//
// 收藏（FavoriteToggle）是**另一个**控件：它不与三态共享控件位，也不改变三态。
library;

import 'package:flutter/material.dart';

import 'package:flux/core/core.dart';
import 'package:flux/core/design/design_tokens.dart';
import 'package:flux/l10n/l10n.dart';

import '../icons/flux_icons.dart';
import 'flux_control_status.dart';
import 'flux_loading_indicator.dart';
import 'flux_stateful_tap.dart';

/// 三态取值 → 图标。
///
/// 每个取值都有独立图形（环+点 / 环+勾 / 环+钟）：只靠颜色区分三态对色觉障碍
/// 用户不可用，而只靠文字会撑开密集列表的行高。
FluxIcon readingStateIcon(ReadingState state) => switch (state) {
  ReadingState.unread => FluxIcon.stateUnread,
  ReadingState.read => FluxIcon.stateRead,
  ReadingState.later => FluxIcon.stateLater,
};

/// 三态取值 → 本地化文案。
String readingStateLabel(AppLocalizations l10n, ReadingState state) =>
    switch (state) {
      ReadingState.unread => l10n.readingStateUnread,
      ReadingState.read => l10n.readingStateRead,
      ReadingState.later => l10n.readingStateLater,
    };

/// 循环顺序：未读 → 已读 → 稍后再读 → 未读。
///
/// 顺序是产品决定，不是实现细节（键盘用户会形成肌肉记忆），因此抽成常量并有测试
/// 钉住。
const List<ReadingState> readingStateCycle = <ReadingState>[
  ReadingState.unread,
  ReadingState.read,
  ReadingState.later,
];

/// 返回循环中的下一个状态。
ReadingState nextReadingState(ReadingState current) {
  final int index = readingStateCycle.indexOf(current);
  // indexOf 对合法枚举值必不为 -1；取模只是为了让「未来新增取值却忘改本表」
  // 退化为顺序推进，而不是抛异常让整页崩掉。
  return readingStateCycle[(index + 1) % readingStateCycle.length];
}

/// 阅读状态三态控件：**一个控件位**内切换 unread / read / later。
class ReadingStateControl extends StatelessWidget {
  /// 构造三态控件。
  const ReadingStateControl({
    required this.state,
    super.key,
    this.onChanged,
    this.enabled = true,
    this.feedback = FluxControlFeedback.none,
    this.size = FluxIconSize.regular,
    this.showLabel = false,
    this.focusNode,
    this.autofocus = false,
    this.debugStatusOverride,
    this.debugLoadingTurns,
  });

  /// 当前状态。控件不持有状态：三态属于文章实体，由上层与存储决定。
  final ReadingState state;

  /// 切换回调。未提供时控件只读（例如列表项里的展示态）。
  final ValueChanged<ReadingState>? onChanged;

  /// 是否启用。
  final bool enabled;

  /// 业务反馈（加载/成功/失败）。
  final FluxControlFeedback feedback;

  /// 图标尺寸档位。
  final FluxIconSize size;

  /// 是否在图标旁显示当前状态文字（详情页用；列表里关闭以保持行高）。
  final bool showLabel;

  /// 外部焦点节点。
  final FocusNode? focusNode;

  /// 是否自动获取焦点。
  final bool autofocus;

  /// 测试/截图用：钉住状态。
  final FluxControlStatus? debugStatusOverride;

  /// 测试/截图用：把加载指示器的旋转相位钉住（golden 需要确定性画面）。
  ///
  /// 生产代码不得传这个参数：真实加载必须是动的，静止的指示器会让用户以为卡死。
  final double? debugLoadingTurns;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String valueLabel = readingStateLabel(l10n, state);
    // 标签里同时给出「这是什么控件」与「当前值」，因为读屏用户进入列表项时
    // 听到的是一串控件，只报当前值无法知道它属于哪个维度。
    final String semanticsLabel = '${l10n.readingStateLabel}：$valueLabel';

    return FluxStatefulTap(
      semanticsLabel: semanticsLabel,
      semanticsHint: l10n.readingStateControlHint,
      tooltip: l10n.readingStateControlHint,
      focusNode: focusNode,
      autofocus: autofocus,
      enabled: enabled,
      feedback: feedback,
      debugStatusOverride: debugStatusOverride,
      // 只有上层给了回调才可交互：展示态（只读列表）不该看起来能点。
      onPressed: onChanged == null
          ? null
          : () => onChanged!(nextReadingState(state)),
      borderRadius: BorderRadius.circular(FluxRadius.button),
      padding: const EdgeInsets.symmetric(horizontal: FluxSpacing.xs),
      builder:
          (
            BuildContext context,
            FluxControlStatus status,
            FluxControlVisuals visuals,
          ) {
            final Widget iconWidget = status == FluxControlStatus.loading
                ? FluxLoadingIndicator(
                    size: size.logicalSize,
                    color: visuals.foreground,
                    debugTurns: debugLoadingTurns,
                  )
                : FluxSvgIcon(
                    readingStateIcon(state),
                    size: size,
                    color: visuals.foreground,
                    excludeFromSemantics: true,
                  );
            if (!showLabel) {
              return iconWidget;
            }
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                iconWidget,
                const SizedBox(width: FluxSpacing.xs),
                Text(
                  valueLabel,
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: visuals.foreground),
                ),
              ],
            );
          },
    );
  }
}

/// 收藏星形开关（T012，架构 4.1「收藏独立」）。
///
/// 与三态控件的分工是刻意的：
///   - 三态用一个控件位、循环切换，表达「互斥的单一取值」；
///   - 收藏是**独立布尔**，因此用独立的星形开关，只表达 on/off。
///
/// 两者在同一行并排时（文章详情）不会互相影响：本控件从不为三态调用回调，
/// 也不读三态值——它拿不到那个值，因此不可能「顺手」改掉它。
class FavoriteToggle extends StatelessWidget {
  /// 构造收藏开关。
  const FavoriteToggle({
    required this.favorite,
    super.key,
    this.onChanged,
    this.enabled = true,
    this.feedback = FluxControlFeedback.none,
    this.size = FluxIconSize.regular,
    this.showLabel = false,
    this.focusNode,
    this.autofocus = false,
    this.debugStatusOverride,
    this.debugLoadingTurns,
  });

  /// 是否已收藏。
  final bool favorite;

  /// 切换回调；未提供时只读。
  final ValueChanged<bool>? onChanged;

  /// 是否启用。
  final bool enabled;

  /// 业务反馈。
  final FluxControlFeedback feedback;

  /// 图标尺寸档位。
  final FluxIconSize size;

  /// 是否显示文字标签。
  final bool showLabel;

  /// 外部焦点节点。
  final FocusNode? focusNode;

  /// 是否自动获取焦点。
  final bool autofocus;

  /// 测试/截图用：钉住状态。
  final FluxControlStatus? debugStatusOverride;

  /// 测试/截图用：把加载指示器的旋转相位钉住（同 [ReadingStateControl]）。
  final double? debugLoadingTurns;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String action = favorite
        ? l10n.favoriteRemoveLabel
        : l10n.favoriteAddLabel;

    return FluxStatefulTap(
      semanticsLabel: '${l10n.favoriteToggleLabel}：$action',
      semanticsHint: l10n.favoriteToggleHint,
      tooltip: action,
      focusNode: focusNode,
      autofocus: autofocus,
      enabled: enabled,
      feedback: feedback,
      debugStatusOverride: debugStatusOverride,
      onPressed: onChanged == null ? null : () => onChanged!(!favorite),
      borderRadius: BorderRadius.circular(FluxRadius.button),
      padding: const EdgeInsets.symmetric(horizontal: FluxSpacing.xs),
      builder:
          (
            BuildContext context,
            FluxControlStatus status,
            FluxControlVisuals visuals,
          ) {
            // 已收藏时保持强调色，与状态反馈色区分：否则「成功反馈」与「已收藏」
            // 会是同一个颜色，用户无法判断是刚操作成功还是本来就是收藏。
            final Color iconColor = favorite
                ? Theme.of(context).colorScheme.primary
                : visuals.foreground;
            final Widget iconWidget = status == FluxControlStatus.loading
                ? FluxLoadingIndicator(
                    size: size.logicalSize,
                    color: iconColor,
                    debugTurns: debugLoadingTurns,
                  )
                : FluxSvgIcon(
                    favorite ? FluxIcon.starFilled : FluxIcon.star,
                    size: size,
                    color: iconColor,
                    excludeFromSemantics: true,
                  );
            if (!showLabel) {
              return iconWidget;
            }
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                iconWidget,
                const SizedBox(width: FluxSpacing.xs),
                Text(
                  action,
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: visuals.foreground),
                ),
              ],
            );
          },
    );
  }
}

/// 加精徽标（T012，SET-023）。
///
/// 加精是**来源**属性（影响显示与强调），与文章的收藏不是同一件事，因此：
///   - 图形用盾形而非星形，避免与收藏混淆；
///   - 本控件不可交互：加精由订阅管理（T014）设置，文章列表里只做标记展示。
class FeaturedBadge extends StatelessWidget {
  /// 构造徽标。
  const FeaturedBadge({
    super.key,
    this.size = FluxIconSize.small,
    this.showLabel = false,
  });

  /// 图标尺寸档位。
  final FluxIconSize size;

  /// 是否显示文字标签。
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    // 用 warning（由 FluxTheme 映射到 tertiary）：加精是「强调」，不是错误也不是
    // 主操作，因此不能与 danger / primary 共用颜色。
    final Color color = scheme.tertiary;
    final Widget iconWidget = FluxSvgIcon(
      FluxIcon.featuredBadge,
      size: size,
      color: color,
      excludeFromSemantics: true,
    );
    // 整块作为**一个**语义节点，内部图形与文字都排除出语义树：
    // 否则读屏会把同一件事念两遍（图标标签 + 文字），合成结果形如「加精 加精」。
    return Semantics(
      label: l10n.featuredBadgeLabel,
      container: true,
      child: ExcludeSemantics(
        child: showLabel
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  iconWidget,
                  const SizedBox(width: FluxSpacing.xxs),
                  Text(
                    l10n.featuredBadgeLabel,
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: color),
                  ),
                ],
              )
            : iconWidget,
      ),
    );
  }
}
