// 通用容器类控件（T012）：空态、状态横幅、统一卡片。
//
// 这三个解决的是同一类问题：**同一种语义在不同页面被画出不同样子**。
// 具体到本项目已经能预见的场景：
//   - 空态：架构第 7 节要求「筛选无结果、无订阅、所有文章已读分别提示」，如果每个
//     页面自己拼「图标+标题+说明」，必然出现一个页面有操作按钮、另一个没有，
//     用户无法判断「这里是不是本来就该有按钮」；
//   - 状态横幅：离线、部分失败、降级启动都有话要说，但它们**不是**同一种严重性。
//     用一个组件区分 info/warning/error，避免有人为了省事把所有提示都刷成红色；
//   - 卡片：架构第 7 节为列表卡片定义了三种形态（紧凑/正常/宽松）与桌面瀑布流宽度，
//     但它们的边框、圆角、内边距必须一致，否则混排时看起来像两套设计。
library;

import 'package:flutter/material.dart';

import 'package:flux/core/design/design_tokens.dart';

import '../icons/flux_icons.dart';

/// 统一卡片容器（架构第 7 节：卡片圆角 12、无大面积阴影、靠边框与底色区分）。
///
/// 刻意不暴露 elevation：低饱和极简风格里阴影会与背景色的低对比度打架，
/// 出现「卡片边缘发灰」的观感；需要提升层次时用底色（surface）与边框表达。
class FluxCard extends StatelessWidget {
  /// 构造卡片。
  const FluxCard({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(FluxSpacing.md),
    this.onTap,
    this.semanticsLabel,
    this.selected = false,
    this.keyboardFocus = false,
    this.borderRadius,
  });

  /// 内容。
  final Widget child;

  /// 内边距。
  final EdgeInsetsGeometry padding;

  /// 点击回调；为空时卡片不可交互（不显示指针手势，也不进焦点顺序）。
  final VoidCallback? onTap;

  /// 读屏标签（整卡可点时必需，否则读屏只念出内部零散文字）。
  final String? semanticsLabel;

  /// 是否选中（用 selectedSurface 与强调色边框表达，不使用阴影）。
  final bool selected;

  /// 是否是键盘当前落点（T049）。
  ///
  /// 与 [selected] 分开：勾选表示「会参与批量操作」，键盘落点表示「光标停在这里」。
  /// 两者在列表里可能同时存在，用同一套视觉会让用户分不清「我选了哪些」与
  /// 「回车会打开哪一篇」。
  final bool keyboardFocus;

  /// 圆角覆盖；默认用卡片 token。
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final BorderRadius radius =
        borderRadius ?? BorderRadius.circular(FluxRadius.card);

    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: selected || keyboardFocus
            ? scheme.surfaceContainerHigh
            : scheme.surface,
        borderRadius: radius,
        border: Border.all(
          color: keyboardFocus
              ? scheme.primary
              : (selected ? scheme.primary : scheme.outline),
          width: keyboardFocus ? FluxControlTokens.focusRingWidth : 1,
        ),
      ),
      child: child,
    );

    if (onTap == null) {
      return content;
    }

    content = Semantics(
      button: true,
      label: semanticsLabel,
      child: Material(
        color: const Color(0x00000000),
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          // InkWell 的涟漪色取自主题 primary，与设计 token 一致；不用 splashFactory
          // 关闭它，是因为点击反馈是桌面用户判断「点到了」的主要依据。
          child: content,
        ),
      ),
    );
    return content;
  }
}

/// 空态严重性（决定图标与强调程度）。
enum EmptyStateTone {
  /// 中性：还没有内容，属于正常初始状态。 */
  neutral,

  /// 完成态：内容都处理完了（例如所有文章已读）。用强调色，是「好事」。 */
  positive,

  /// 受限态：因为筛选/搜索条件或未配置能力而空。 */
  muted,
}

/// 统一空态组件（图标 + 标题 + 说明 + 可选动作）。
///
/// [action] 为空时**不渲染**任何按钮区域：一个永远是灰阶的禁用按钮比没有按钮更
/// 让人困惑，用户会以为「再等等就能点」。
class FluxEmptyState extends StatelessWidget {
  /// 构造空态。
  const FluxEmptyState({
    required this.title,
    required this.body,
    super.key,
    this.icon = FluxIcon.inboxEmpty,
    this.tone = EmptyStateTone.neutral,
    this.action,
    this.secondaryNote,
  });

  /// 标题（来自 l10n）。
  final String title;

  /// 说明。
  final String body;

  /// 图形。
  final FluxIcon icon;

  /// 严重性。
  final EmptyStateTone tone;

  /// 可选动作按钮；为空时不渲染按钮区。
  final Widget? action;

  /// 可选补充说明（例如「计划任务：T013–T016」）。
  final String? secondaryNote;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color iconColor = switch (tone) {
      EmptyStateTone.neutral => scheme.onSurfaceVariant,
      EmptyStateTone.positive => scheme.primary,
      EmptyStateTone.muted => scheme.onSurfaceVariant,
    };

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(FluxSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: FluxBreakpoints.maxBodyWidth,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // 空态图形是装饰：标题已经表达了同样信息，重复播报会让读屏更啰嗦。
              FluxSvgIcon(
                icon,
                size: FluxIconSize.regular,
                color: iconColor,
                excludeFromSemantics: true,
              ),
              const SizedBox(height: FluxSpacing.sm),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: FluxSpacing.xs),
              Text(
                body,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (secondaryNote case final String note) ...<Widget>[
                const SizedBox(height: FluxSpacing.xs),
                Text(
                  note,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (action case final Widget actionWidget) ...<Widget>[
                const SizedBox(height: FluxSpacing.lg),
                actionWidget,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 状态横幅严重性（T012：info / warning / error）。
enum StatusBannerSeverity {
  /// 信息：说明当前情况，不需要用户做任何事。 */
  info,

  /// 警告：功能受限，用户可能需要处理。 */
  warning,

  /// 错误：操作失败或当前状态不可用。 */
  error,
}

/// 状态横幅（图标 + 文案 + 可选动作）。
///
/// 与 [FluxEmptyState] 的分工：空态占据**整个内容区**（没有内容可显示），
/// 横幅是**局部**提示（内容还在，只是要说明一件事），因此横幅不居中、不撑满高度。
class StatusBanner extends StatelessWidget {
  /// 构造横幅。
  const StatusBanner({
    required this.message,
    super.key,
    this.severity = StatusBannerSeverity.info,
    this.title,
    this.action,
  });

  /// 主文案。
  final String message;

  /// 严重性。
  final StatusBannerSeverity severity;

  /// 可选标题（用于「部分失败」这类需要区分标题与明细的场合）。 */
  final String? title;

  /// 可选动作（例如「重试」）。
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    // 三档严重性映射到 token：
    //   info → 强调色（primary=accent）
    //   warning → tertiary（FluxTheme 把架构的 warning 映射到这里，因为没有官方槽位）
    //   error → danger
    // 只用这三档，不引入第四套颜色。
    final Color accent = switch (severity) {
      StatusBannerSeverity.info => scheme.primary,
      StatusBannerSeverity.warning => scheme.tertiary,
      StatusBannerSeverity.error => scheme.error,
    };
    final FluxIcon icon = switch (severity) {
      StatusBannerSeverity.info => FluxIcon.alertInfo,
      StatusBannerSeverity.warning => FluxIcon.alertWarning,
      StatusBannerSeverity.error => FluxIcon.alertError,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(FluxSpacing.sm),
      decoration: BoxDecoration(
        // 底色用强调色的低透明度叠加，而不是纯色块：横幅经常出现在正文上方，
        // 高饱和底色会把注意力从内容上拉走。
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(FluxRadius.card),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          FluxSvgIcon(
            icon,
            size: FluxIconSize.small,
            color: accent,
            excludeFromSemantics: true,
          ),
          const SizedBox(width: FluxSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (title case final String bannerTitle) ...<Widget>[
                  Text(
                    bannerTitle,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: FluxSpacing.xxs),
                ],
                // 文案用 onSurface 而不是 accent：强调色的对比度只对「关键控件」
                // 满足 3:1，普通文字需要 4.5:1（架构第 7 节），正文色才安全。
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          if (action case final Widget actionWidget) ...<Widget>[
            const SizedBox(width: FluxSpacing.xs),
            actionWidget,
          ],
        ],
      ),
    );
  }
}
