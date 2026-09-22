// 桌面键盘层（T049，架构第 7 节「桌面默认支持键盘焦点、右键、菜单与快捷键」）。
//
// 为什么把「意图」与「按键」分开写：
//   按键是平台习惯（macOS 用 ⌘），意图是产品动作（切到某个去向）。把 ⌘1 直接绑在
//   回调上，就没法在测试里断言「按了 ⌘1 之后去向变了」以外的任何东西，也无法在
//   将来为别的平台换一套按键而不动逻辑。因此这里定义 Intent，由壳层用 Actions 落实。
//
// 为什么放在 lib/app/shell 而不是 lib/ui：
//   这些意图的操作对象是**应用壳**（当前去向、壳层弹层），共享控件层不该知道「去向」
//   的存在。lib/ui 只见 token 与控件，依赖方向保持 app → ui → core。
//
// Esc 的归属值得单独说明：DismissIntent 是 Flutter 的既有意图（工具栏、路由、
// 菜单都响应它），因此这里**不新造一个「关闭」意图**，而是复用 DismissIntent ——
// 否则「Esc 关掉菜单」与「Esc 关掉我们的弹层」会变成两条不同的路径，用户按同一个
// 键却得到两套行为顺序。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/design/design_tokens.dart';
import 'package:flux/l10n/l10n.dart';

import 'app_destination.dart';

/// 「打开快捷键说明」的请求（T049）。
///
/// 为什么不是直接在这里 showDialog：应用级 Shortcuts 位于 **MaterialApp 之上**，
/// 它的 context 上方没有 Navigator（对话框需要）。因此这里只置一个请求，由壳层
/// （在 Navigator 内部）监听并弹出——与 T020 的「去设置」、T049 的「在库中检索」
/// 是同一条路线，features/app 两侧不互相伸手。
final class ShortcutHelpRequest extends Notifier<bool> {
  @override
  bool build() => false;

  /// 请求一次。
  void request() => state = true;

  /// 壳层消费后清空（留着它会让用户之后每次点别的都重新弹出面板）。
  void consume() {
    if (state) {
      state = false;
    }
  }
}

/// 请求 Provider。
final NotifierProvider<ShortcutHelpRequest, bool> shortcutHelpRequestProvider =
    NotifierProvider<ShortcutHelpRequest, bool>(ShortcutHelpRequest.new);

/// 切到某个顶层去向（⌘1/⌘2/⌘3）。
class SwitchDestinationIntent extends Intent {
  /// 构造意图。
  const SwitchDestinationIntent(this.destination);

  /// 目标去向。
  final AppDestination destination;
}

/// 打开快捷键说明面板（⌘/）。
class ShowShortcutHelpIntent extends Intent {
  /// 构造意图。
  const ShowShortcutHelpIntent();
}

/// 快捷键说明里的一行。
///
/// 用「文案构建函数」而不是直接存字符串：面板与测试都要在**当前语言**下取值，
/// 存字符串就必须在构造时拿到 l10n，而构造发生在没有 BuildContext 的地方。
final class ShortcutHelpEntry {
  /// 构造一条说明。
  const ShortcutHelpEntry({required this.group, required this.label});

  /// 分组标题。
  final String Function(AppLocalizations l10n) group;

  /// 按键与说明。
  final String Function(AppLocalizations l10n) label;
}

/// 说明面板内容（顺序即展示顺序）。
///
/// 单独列出来是为了让测试能逐条断言「面板里说了哪几条」，而不是断言「对话框非空」。
const List<ShortcutHelpEntry> shortcutHelpEntries = <ShortcutHelpEntry>[
  ShortcutHelpEntry(group: _navGroup, label: _navToday),
  ShortcutHelpEntry(group: _navGroup, label: _navReading),
  ShortcutHelpEntry(group: _navGroup, label: _navMine),
  ShortcutHelpEntry(group: _listGroup, label: _listMove),
  ShortcutHelpEntry(group: _listGroup, label: _listOpen),
  ShortcutHelpEntry(group: _closeGroup, label: _closeLayer),
  ShortcutHelpEntry(group: _otherGroup, label: _helpOpen),
];

String _navGroup(AppLocalizations l10n) => l10n.shortcutGroupNavigation;
String _listGroup(AppLocalizations l10n) => l10n.shortcutGroupList;
String _closeGroup(AppLocalizations l10n) => l10n.shortcutGroupClose;
String _otherGroup(AppLocalizations l10n) => l10n.shortcutGroupOther;
String _navToday(AppLocalizations l10n) => l10n.shortcutNavToday;
String _navReading(AppLocalizations l10n) => l10n.shortcutNavReading;
String _navMine(AppLocalizations l10n) => l10n.shortcutNavMine;
String _listMove(AppLocalizations l10n) => l10n.shortcutListMove;
String _listOpen(AppLocalizations l10n) => l10n.shortcutListOpen;
String _closeLayer(AppLocalizations l10n) => l10n.shortcutCloseLayer;
String _helpOpen(AppLocalizations l10n) => l10n.shortcutHelpOpen;

/// 壳层默认快捷键。
///
/// 用 ⌘（meta）而不是 Ctrl：本项目当前只有 macOS（D-02），⌘1/⌘2/⌘3 与 ⌘/ 是
/// 桌面上的既有习惯。换平台时在这里补一份映射即可，意图与 Actions 不用改。
Map<ShortcutActivator, Intent> appShortcuts() => <ShortcutActivator, Intent>{
  const SingleActivator(LogicalKeyboardKey.digit1, meta: true):
      const SwitchDestinationIntent(AppDestination.today),
  const SingleActivator(LogicalKeyboardKey.digit2, meta: true):
      const SwitchDestinationIntent(AppDestination.reading),
  const SingleActivator(LogicalKeyboardKey.digit3, meta: true):
      const SwitchDestinationIntent(AppDestination.mine),
  const SingleActivator(LogicalKeyboardKey.slash, meta: true):
      const ShowShortcutHelpIntent(),
};

/// 应用级快捷键作用域。
///
/// 必须挂在 **MaterialApp 之上**，这是实测出来的硬约束：按键事件从当前焦点结点沿
/// **祖先链**向上找处理者，而没有控件聚焦时 primaryFocus 就是路由里的那个
/// FocusScopeNode。挂在 AppShell（路由的**后代**）上时，事件永远走不到它——现象是
/// 「⌘2 毫无反应」，而 Shortcuts 看起来挂得好好的。
///
/// 两个动作由调用方注入而不是在这里 read Provider：这一层在 Navigator 之上，需要
/// 「去哪儿」与「谁来弹面板」这样的**编排**，而编排属于 app.dart（组合根的邻居）。
/// 注入回调同时避免了 app_shortcuts ↔ app_shell 的相互 import。
class AppShortcutScope extends StatelessWidget {
  /// 构造作用域。
  const AppShortcutScope({
    required this.onSwitchDestination,
    required this.onShowShortcutHelp,
    required this.child,
    super.key,
  });

  /// 切换去向。
  final ValueChanged<AppDestination> onSwitchDestination;

  /// 打开快捷键说明。
  final VoidCallback onShowShortcutHelp;

  /// 子树（通常是 MaterialApp）。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: appShortcuts(),
      child: Actions(
        actions: <Type, Action<Intent>>{
          SwitchDestinationIntent: CallbackAction<SwitchDestinationIntent>(
            onInvoke: (SwitchDestinationIntent intent) {
              onSwitchDestination(intent.destination);
              return null;
            },
          ),
          ShowShortcutHelpIntent: CallbackAction<ShowShortcutHelpIntent>(
            onInvoke: (ShowShortcutHelpIntent _) {
              onShowShortcutHelp();
              return null;
            },
          ),
        },
        child: child,
      ),
    );
  }
}

/// 快捷键说明面板。
///
/// 用 AlertDialog 而不是自绘浮层：Esc 关闭、点击遮罩关闭、焦点陷阱（Tab 不会跑到
/// 背后的页面上）都由框架的模态路由提供，自己搭一套必然漏掉其中之一。
class ShortcutHelpDialog extends StatelessWidget {
  /// 构造面板。
  const ShortcutHelpDialog({super.key});

  /// 显示面板。
  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    builder: (BuildContext context) => const ShortcutHelpDialog(),
  );

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    // 按分组折叠显示：同一个分组的多次出现只显示一次标题。
    final List<Widget> rows = <Widget>[];
    String? lastGroup;
    for (final ShortcutHelpEntry entry in shortcutHelpEntries) {
      final String group = entry.group(l10n);
      if (group != lastGroup) {
        lastGroup = group;
        rows.add(
          Padding(
            padding: const EdgeInsets.only(
              top: FluxSpacing.sm,
              bottom: FluxSpacing.xxs,
            ),
            child: Text(group, style: theme.textTheme.titleSmall),
          ),
        );
      }
      rows.add(
        Padding(
          padding: const EdgeInsets.only(left: FluxSpacing.sm, bottom: 2),
          child: Text(entry.label(l10n), style: theme.textTheme.bodyMedium),
        ),
      );
    }
    return AlertDialog(
      key: const ValueKey<String>('shortcut-help-dialog'),
      title: Text(l10n.shortcutHelpTitle),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ...rows,
              const SizedBox(height: FluxSpacing.sm),
              Text(l10n.shortcutHelpFooter, style: theme.textTheme.labelSmall),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.subscriptionClose),
        ),
      ],
    );
  }
}
