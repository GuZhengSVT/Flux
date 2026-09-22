// 减少动态效果的界面落点（T049；SET-014）。
//
// 为什么用一层 MediaQuery 覆盖而不是在每个动画调用点判断：
//   Flutter 的「减少动态效果」是**平台事实**，框架与所有 Material 控件都通过
//   MediaQuery.disableAnimations 读它（页面转场、涟漪、开关滑块等）。因此让 SET-014
//   的「强制开/关」也走同一条路，等于一次性覆盖了框架控件与我们自己的
//   FluxMotionDurations——不需要在每个调用点各写一次。
//
// 为什么只在「强制」时才覆盖：
//   system 档的语义就是不覆盖；把它解析成 false 会忽视系统设置（macOS 上用户开了
//   reduce motion 而我们的转场仍在播）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/motion_preference.dart';

/// 把 SET-014 合成为 MediaQuery.disableAnimations 上的覆盖。
class MotionScope extends ConsumerWidget {
  /// 构造作用域。
  const MotionScope({required this.child, super.key});

  /// 子树。
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final MotionPreference preference =
        ref.watch(motionPreferenceProvider).value ?? MotionPreference.system;
    final bool? override = preference.resolve(
      systemDisablesAnimations: MediaQuery.disableAnimationsOf(context),
    );
    if (override == null) {
      // 跟随系统：**必须原样返回子树**，不能 wrap 一层 MediaQuery——覆盖成与系统相同的
      // 值看似无害，实际上会切断子树对系统设置的后续响应（MediaQueryData 被固定成一份
      // 快照），用户在系统设置里改了之后这里不会跟着变。
      return child;
    }
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: override),
      child: child,
    );
  }
}
