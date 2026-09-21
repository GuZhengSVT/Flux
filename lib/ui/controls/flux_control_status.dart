// 控件状态模型（T012）。
//
// 架构第 7 节要求「每页明确首次/加载/成功/空/部分失败/失败/离线/取消状态」，
// 手册 T012 要求控件的八类状态（default/hover/pressed/focus/disabled/loading/
// success/error）都有视觉与语义。
//
// 为什么把状态抽成一个共享模型，而不是每个控件自己判断：
//   - 「加载中还能不能点」「禁用时要不要报读屏」这类判断如果散落在每个控件里，
//     必然出现某个控件忘了拦截回调、或某处禁用了却不告诉读屏；
//   - 抽出后可以用一组测试对**所有**控件同时断言这八类状态，新增控件自动被覆盖。
//
// 交互状态（悬停/按下/焦点/禁用）由 [FluxStatefulTap] 从平台的 WidgetState 解析；
// 反馈状态（加载/成功/失败）由调用方显式给出，因为它们是**业务结果**，不是指针交互。
library;

// ColorScheme 在 material 里（widgets 不导出它）。
import 'package:flutter/material.dart';

import 'package:flux/core/design/design_tokens.dart';

/// 控件当前状态（架构第 7 节 + 手册 T012 的八类）。
enum FluxControlStatus {
  /// 默认：无指针悬停、无焦点、可交互。
  normal,

  /// 悬停：指针在控件上（桌面/触控板）。
  hover,

  /// 按下：指针已按下但未抬起。
  pressed,

  /// 焦点：键盘焦点在本控件上（必须可见，否则键盘用户无法定位）。
  focus,

  /// 禁用：不可交互，且必须对读屏报告为不可用。
  disabled,

  /// 加载：正在执行，重复触发必须被拦截。
  loading,

  /// 成功：刚完成一次操作，短暂反馈。
  success,

  /// 失败：操作失败，需要用户注意。
  error;

  /// 该状态下是否允许触发回调。
  ///
  /// 加载中与禁用都拦截：加载中允许再次点击会产生重复请求（例如重复标记已读），
  /// 而这在界面上看不出来。
  bool get allowsInteraction =>
      this != FluxControlStatus.disabled && this != FluxControlStatus.loading;

  /// 是否需要向读屏报告为不可用。
  bool get reportsDisabled => this == FluxControlStatus.disabled;
}

/// 操作结果反馈（与指针交互正交的一个维度）。
enum FluxControlFeedback {
  /// 无反馈。
  none,

  /// 进行中。
  loading,

  /// 成功。
  success,

  /// 失败。
  error,
}

/// 解析控件状态。
///
/// 优先级（顺序即语义，改这里等于改所有控件的状态含义）：
///   1) 禁用 —— 不可交互是最高优先的**权限**事实，覆盖一切视觉反馈；
///   2) 反馈（加载/成功/失败）—— 业务结果比指针位置更重要：手指还停在按钮上
///      时不应该把「正在发送」显示成「悬停」；
///   3) 按下 / 焦点 / 悬停 —— 指针与键盘交互态；
///   4) 默认。
FluxControlStatus resolveFluxControlStatus({
  required bool enabled,
  required bool hovered,
  required bool pressed,
  required bool focused,
  FluxControlFeedback feedback = FluxControlFeedback.none,
}) {
  if (!enabled) {
    return FluxControlStatus.disabled;
  }
  switch (feedback) {
    case FluxControlFeedback.loading:
      return FluxControlStatus.loading;
    case FluxControlFeedback.success:
      return FluxControlStatus.success;
    case FluxControlFeedback.error:
      return FluxControlStatus.error;
    case FluxControlFeedback.none:
      break;
  }
  if (pressed) {
    return FluxControlStatus.pressed;
  }
  if (focused) {
    return FluxControlStatus.focus;
  }
  if (hovered) {
    return FluxControlStatus.hover;
  }
  return FluxControlStatus.normal;
}

/// 一个状态下的视觉取值（由 token 计算，不含硬编码色值）。
@immutable
final class FluxControlVisuals {
  /// 构造视觉取值。
  const FluxControlVisuals({
    required this.status,
    required this.foreground,
    required this.background,
    required this.border,
    required this.opacity,
    required this.showsFocusRing,
    required this.showsIndicator,
  });

  /// 由状态与当前配色解析出视觉取值。
  ///
  /// 色值只来自 ColorScheme：lib/ui 不 import lib/app（app 会渲染 ui，反向依赖成环，
  /// 见 test/core/architecture_layering_test.dart）。FluxTheme 已把架构 token 映射到
  /// ColorScheme：primary=accent、tertiary=warning、error=danger、
  /// surfaceContainerHigh=selectedSurface、outline=border、onSurfaceVariant=textSecondary。
  factory FluxControlVisuals.resolve({
    required FluxControlStatus status,
    required ColorScheme scheme,
  }) {
    final Color accent = scheme.primary;
    switch (status) {
      case FluxControlStatus.normal:
        return FluxControlVisuals(
          status: status,
          foreground: scheme.onSurfaceVariant,
          background: const Color(0x00000000),
          border: const Color(0x00000000),
          opacity: 1,
          showsFocusRing: false,
          showsIndicator: false,
        );
      case FluxControlStatus.hover:
        return FluxControlVisuals(
          status: status,
          foreground: scheme.onSurface,
          background: accent.withValues(
            alpha: FluxControlTokens.hoverOverlayOpacity,
          ),
          border: const Color(0x00000000),
          opacity: 1,
          showsFocusRing: false,
          showsIndicator: false,
        );
      case FluxControlStatus.pressed:
        return FluxControlVisuals(
          status: status,
          foreground: scheme.onSurface,
          background: accent.withValues(
            alpha: FluxControlTokens.pressedOverlayOpacity,
          ),
          border: const Color(0x00000000),
          // 按下时轻微收缩由控件自身处理；这里只给颜色。
          opacity: 1,
          showsFocusRing: false,
          showsIndicator: false,
        );
      case FluxControlStatus.focus:
        return FluxControlVisuals(
          status: status,
          foreground: accent,
          background: accent.withValues(
            alpha: FluxControlTokens.hoverOverlayOpacity,
          ),
          // 焦点环必须与悬停可区分：只用底色的话，键盘用户在浅色主题下几乎看不出。
          border: accent,
          opacity: 1,
          showsFocusRing: true,
          showsIndicator: false,
        );
      case FluxControlStatus.disabled:
        return FluxControlVisuals(
          status: status,
          foreground: scheme.onSurfaceVariant,
          background: const Color(0x00000000),
          border: const Color(0x00000000),
          opacity: FluxControlTokens.disabledOpacity,
          showsFocusRing: false,
          showsIndicator: false,
        );
      case FluxControlStatus.loading:
        return FluxControlVisuals(
          status: status,
          foreground: accent,
          background: const Color(0x00000000),
          border: const Color(0x00000000),
          opacity: 1,
          showsFocusRing: false,
          showsIndicator: true,
        );
      case FluxControlStatus.success:
        return FluxControlVisuals(
          status: status,
          foreground: accent,
          background: accent.withValues(
            alpha: FluxControlTokens.hoverOverlayOpacity,
          ),
          border: const Color(0x00000000),
          opacity: 1,
          showsFocusRing: false,
          showsIndicator: false,
        );
      case FluxControlStatus.error:
        return FluxControlVisuals(
          status: status,
          foreground: scheme.error,
          background: scheme.error.withValues(
            alpha: FluxControlTokens.hoverOverlayOpacity,
          ),
          border: const Color(0x00000000),
          opacity: 1,
          showsFocusRing: false,
          showsIndicator: false,
        );
    }
  }

  /// 来源状态。
  final FluxControlStatus status;

  /// 图标/文字前景色。
  final Color foreground;

  /// 底色。
  final Color background;

  /// 边框色（焦点环用它）。
  final Color border;

  /// 整体不透明度。
  final double opacity;

  /// 是否绘制键盘焦点环。
  final bool showsFocusRing;

  /// 是否用加载指示器替换图标。
  final bool showsIndicator;
}
