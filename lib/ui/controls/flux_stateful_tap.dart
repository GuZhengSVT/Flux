// 可交互控件基座（T012）。
//
// 为什么所有图标按钮都走这一个基座，而不是各用 InkWell/GestureDetector：
//   1) 架构第 7 节要求「桌面默认支持键盘焦点」「手机触控目标至少 48dp」
//      「图标有读屏标签」。这三条必须**无差别**成立；散落的实现一定会漏掉其中一条
//      （最常见的漏法是：视觉上禁用了，但 onTap 仍然被调用，或者禁用时读屏仍报可点）；
//   2) 八类状态需要一致的视觉：把状态解析集中在 resolveFluxControlStatus 与
//      FluxControlVisuals，控件只负责摆放内容；
//   3) 加载中必须拦截重复触发。这是真实缺陷来源：用户连点两次「标为已读」会发出
//      两个请求，而界面上看不出区别。
//
// 键盘：Enter 与 Space 都触发（桌面用户对这两者的预期不同，只支持一个会显得「键坏了」）。
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flux/core/design/design_tokens.dart';

import '../flux_motion.dart';
import 'flux_control_status.dart';

/// 一个带完整状态、焦点、触控目标与语义的可交互区域。
///
/// [builder] 收到当前状态与由 token 解析出的视觉取值，因此子控件（图标、文字）
/// 与底色/焦点环用的是同一份状态，不会出现「底色变了但图标没变色」。
class FluxStatefulTap extends StatefulWidget {
  /// 构造基座。
  const FluxStatefulTap({
    required this.builder,
    required this.semanticsLabel,
    super.key,
    this.onPressed,
    this.enabled = true,
    this.feedback = FluxControlFeedback.none,
    this.semanticsHint,
    this.tooltip,
    this.focusNode,
    this.autofocus = false,
    this.minTouchTarget = FluxIconTokens.minTouchTarget,
    this.borderRadius,
    this.padding = EdgeInsets.zero,
    this.renderBackground = true,
    this.debugStatusOverride,
  });

  /// 内容构造器；status 为解析后的状态，visuals 为对应视觉取值。
  final Widget Function(
    BuildContext context,
    FluxControlStatus status,
    FluxControlVisuals visuals,
  )
  builder;

  /// 点击/键盘激活回调；为空或 [enabled] 为假时控件不可交互。
  final VoidCallback? onPressed;

  /// 是否启用（disabled 状态的来源）。
  final bool enabled;

  /// 业务反馈（加载/成功/失败）。
  final FluxControlFeedback feedback;

  /// 读屏标签。必需：架构第 7 节要求图标有读屏标签。
  final String semanticsLabel;

  /// 读屏提示（例如「循环切换未读、已读、稍后再读」）。
  final String? semanticsHint;

  /// 鼠标悬停提示（桌面）；为空时不显示。
  final String? tooltip;

  /// 外部焦点节点（用于在列表里做焦点顺序控制）。
  final FocusNode? focusNode;

  /// 是否自动获取焦点。
  final bool autofocus;

  /// 最小命中区域边长（架构第 7 节：48dp）。
  final double minTouchTarget;

  /// 圆角；为空时用按钮圆角 token。
  final BorderRadius? borderRadius;

  /// 内边距。
  final EdgeInsetsGeometry padding;

  /// 是否绘制状态底色（纯图标可关掉，例如夹在文字行里的状态点）。
  final bool renderBackground;

  /// 测试/截图用：把状态钉在指定值。
  ///
  /// 存在的理由：八类状态的**视觉**需要一张可复核的图（真实指针悬停/按下无法
  /// 在同一张截图里同时呈现）。生产代码不得传这个参数。
  final FluxControlStatus? debugStatusOverride;

  @override
  State<FluxStatefulTap> createState() => _FluxStatefulTapState();
}

class _FluxStatefulTapState extends State<FluxStatefulTap> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;
  FocusNode? _internalFocusNode;

  FocusNode get _focusNode =>
      widget.focusNode ??
      (_internalFocusNode ??= FocusNode(debugLabel: 'FluxStatefulTap'));

  @override
  void dispose() {
    _internalFocusNode?.dispose();
    super.dispose();
  }

  /// 是否可交互：显式启用、有回调、且当前状态允许。
  bool get _interactive =>
      widget.enabled && widget.onPressed != null && _status.allowsInteraction;

  FluxControlStatus get _status =>
      widget.debugStatusOverride ??
      resolveFluxControlStatus(
        enabled: widget.enabled && widget.onPressed != null,
        hovered: _hovered,
        pressed: _pressed,
        focused: _focused,
        feedback: widget.feedback,
      );

  void _activate() {
    if (!_interactive) {
      return;
    }
    widget.onPressed!.call();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      // 无论是否可交互都返回 handled：否则回车会冒泡到外层，触发**别的**动作，
      // 这在禁用态下尤其危险（用户以为按钮没反应，实际执行了别的命令）。
      _activate();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final FluxControlStatus status = _status;
    final FluxControlVisuals visuals = FluxControlVisuals.resolve(
      status: status,
      scheme: Theme.of(context).colorScheme,
    );
    final Duration duration = FluxMotionDurations.standard(context);

    Widget content = widget.builder(context, status, visuals);
    if (widget.padding != EdgeInsets.zero) {
      content = Padding(padding: widget.padding, child: content);
    }

    final Widget box = AnimatedContainer(
      duration: duration,
      constraints: BoxConstraints(
        minWidth: widget.minTouchTarget,
        minHeight: widget.minTouchTarget,
      ),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: widget.renderBackground ? visuals.background : null,
        borderRadius:
            widget.borderRadius ?? BorderRadius.circular(FluxRadius.button),
        // 焦点环用边框绘制：不使用 InkWell 的涟漪，避免在低饱和风格里出现与
        // 主题无关的 splash 色。
        border: visuals.showsFocusRing
            ? Border.all(
                color: visuals.border,
                width: FluxControlTokens.focusRingWidth,
              )
            : null,
      ),
      child: Opacity(opacity: visuals.opacity, child: content),
    );

    final Widget withFocus = Focus(
      focusNode: _focusNode,
      canRequestFocus: widget.enabled && widget.onPressed != null,
      autofocus: widget.autofocus,
      onFocusChange: (bool value) => setState(() => _focused = value),
      onKeyEvent: _handleKey,
      child: box,
    );

    final Widget withGesture = GestureDetector(
      behavior: HitTestBehavior.opaque,
      // 手势自身不产生语义节点：语义只由外层 Semantics 提供，否则读屏会读到
      // 两个同名的可点节点。
      excludeFromSemantics: true,
      onTapDown: widget.enabled
          ? (TapDownDetails _) => setState(() => _pressed = true)
          : null,
      onTapUp: widget.enabled
          ? (TapUpDetails _) => setState(() => _pressed = false)
          : null,
      onTapCancel: widget.enabled
          ? () => setState(() => _pressed = false)
          : null,
      onTap: _activate,
      child: withFocus,
    );

    final Widget withMouse = MouseRegion(
      cursor: _interactive
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (PointerEnterEvent _) => setState(() => _hovered = true),
      onExit: (PointerExitEvent _) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: withGesture,
    );

    // 语义与命中测试来自同一个 _interactive：读屏报出的可点状态与真实可点状态
    // 必须一致，否则用户在读屏里「点得动」但实际没反应。
    Widget result = Semantics(
      container: true,
      button: true,
      enabled: _interactive,
      focusable: true,
      focused: _focused,
      label: widget.semanticsLabel,
      hint: widget.semanticsHint,
      onTap: _interactive ? _activate : null,
      child: withMouse,
    );

    if (widget.tooltip case final String tooltip) {
      result = Tooltip(message: tooltip, child: result);
    }

    return result;
  }
}
