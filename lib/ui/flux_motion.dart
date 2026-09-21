// 动效时长（T012 从 lib/app/theme 下移到 lib/ui）。
//
// 为什么移动：共享控件（lib/ui）需要「跟随系统减少动态效果」的时长，但
// lib/ui 不能 import lib/app（app 会渲染 ui，反向依赖成环，见
// test/core/architecture_layering_test.dart）。因此把这个与主题无关的辅助函数
// 放到控件层，lib/app/theme 的 FluxMotionDurations 委托到它，对外 API 不变。
//
// 时长常量本身仍在 lib/core/design/design_tokens.dart 的 FluxMotion（120/160/200ms）：
// 那是产品口径；是否**实际播放**取决于系统设置，属于平台适配。
library;

import 'package:flutter/widgets.dart';

import 'package:flux/core/design/design_tokens.dart';

/// 动效时长的实际取值：尊重 SET-014（减少动态效果）。
abstract final class FluxMotionDurations {
  /// 在 [context] 下应使用的过渡时长。
  ///
  /// SET-014 的语义是「跟随系统，可强制开启」；这里先落地「跟随系统」——系统
  /// 开启减少动态效果时返回 Duration.zero。强制开启的开关属于设置项，
  /// 届时在此处叠加用户选择即可，不需要改所有调用点。
  static Duration standard(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : FluxMotion.standard;
}
