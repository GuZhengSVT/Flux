// 阅读活跃度监听（T023）。
//
// 「有交互（指针/键盘）刷新 lastActive」这条规则需要一个观察点。用 Listener +
// Focus(widgets) 的组合而不是在正文里散落回调：
//   * Listener 覆盖鼠标移动/按下/滚轮（桌面上的主要活动形式）；
//   * Focus 覆盖键盘（滚动阅读时用户也可能只用翻页键）；
// 两者都只做一件事——把「有人在这里」这个事实转成一个回调。判定与计时都在
// ReadingSessionTracker 里，因此这个控件可以在测试里被替换成直接调回调。
//
// 为什么用 Listener 而不是 GestureDetector：GestureDetector 会参与手势竞技场，
// 正文里的选区、链接点击、图片点击都已经是手势；再叠一层会改变它们的行为（例如
// 吞掉拖选）。Listener 在命中测试阶段就拿到事件，不参与竞技场，因此对已有交互无影响。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show KeyDownEvent, KeyEvent;

/// 把指针/键盘活动转成一次「用户还在看」的通知。
class SessionInteractionListener extends StatelessWidget {
  /// 构造监听。
  const SessionInteractionListener({
    required this.child,
    required this.onInteraction,
    super.key,
  });

  /// 子控件。
  final Widget child;

  /// 发生交互时调用。
  final VoidCallback onInteraction;

  @override
  Widget build(BuildContext context) {
    return Listener(
      // 只关心「有没有活动」，不关心具体是哪种事件；用 opaque 之外的默认行为即可
      // （hitTestBehavior 不设置时，Listener 只在子控件命中时收到事件，正是我们要的：
      // 点在页面外不应算作「在读这篇文章」）。
      onPointerDown: (_) => onInteraction(),
      onPointerMove: (_) => onInteraction(),
      onPointerSignal: (_) => onInteraction(),
      child: Focus(
        // Focus 只用于接收键盘事件：canRequestFocus 为 false 避免它自己进入焦点
        // 顺序（那会让 Tab 键在这里停一下，而用户看不到任何焦点提示）。
        canRequestFocus: false,
        onKeyEvent: (FocusNode node, KeyEvent event) {
          if (event is KeyDownEvent) {
            onInteraction();
          }
          return KeyEventResult.ignored;
        },
        child: child,
      ),
    );
  }
}
