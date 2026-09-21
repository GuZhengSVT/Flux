// 壳层布局决策（T011，架构第 7 节）。
//
// 抽成纯函数而不是写在 build 里，原因很具体：架构第 7 节同时给了**断点**
// （600 / 1100）和**栏宽约束**（来源 220、列表 300、正文至少 560），两条规则
// 叠在一起。写在 build 里的 if 无法被单独验证，而这类「临界宽度」逻辑恰恰是
// 最容易悄悄失效的部分（例如把 1100 改成 1080 后行为看起来「差不多」）。
//
// 注意一个容易误读的点：按文档给的栏宽，1100 断点本身已经保证正文余量
// 1100-220-300 = 580 ≥ 560，因此「余量不足」在标准栏宽下**不会**在 1100 处触发。
// 保留这条判断是因为它约束的是「将来调整栏宽时不得挤压正文」，并且它对更窄的
// 输入（例如手工传入 1080）是有效的——见 test/app/shell_layout_test.dart。
library;

import 'package:flux/core/design/design_tokens.dart';

/// 内容区的分栏形态。
enum ShellPaneLayout {
  /// 单栏（窗口逻辑宽度 <600）。
  single,

  /// 双栏（600–1099）。
  double,

  /// 三栏（>=1100，且正文余量足够）。
  triple,
}

/// 按内容区逻辑宽度决定分栏形态。
///
/// [width] 是**内容区**宽度（已扣掉侧边导航），不是窗口宽度：断点描述的是
/// 内容如何分栏，用窗口宽度判断会在有侧栏时把 600 判早。
ShellPaneLayout resolvePaneLayout(
  double width, {
  double sourcePaneWidth = FluxBreakpoints.sourcePaneWidth,
  double listPaneWidth = FluxBreakpoints.listPaneWidth,
  double bodyPaneMin = FluxBreakpoints.bodyPaneMin,
}) {
  if (width >= FluxBreakpoints.threeColumn &&
      width - sourcePaneWidth - listPaneWidth >= bodyPaneMin) {
    return ShellPaneLayout.triple;
  }
  // 三栏条件不满足但宽度已过 600：退回双栏（架构第 7 节「不足自动退回双栏」）。
  if (width >= FluxBreakpoints.twoColumn) {
    return ShellPaneLayout.double;
  }
  return ShellPaneLayout.single;
}

/// 双栏时来源栏的宽度（受可用宽度限制，避免窄窗下把列表挤没）。
double resolveSourcePaneWidth(double width) {
  if (width < FluxBreakpoints.twoColumn) {
    return 0;
  }
  // 双栏下不占用超过三分之一宽度：800 宽的内容区里 240 仍留出 560 给列表。
  const double preferred = FluxBreakpoints.sourcePaneMax;
  final double cap = width / 3;
  return preferred < cap ? preferred : cap;
}
