// macOS 原生菜单栏（T052；T049 遗留的「菜单栏」项，架构第 7 节「桌面默认支持键盘
// 焦点、右键、菜单与快捷键」）。
//
// 为什么用 Flutter 的 PlatformMenuBar 而不是在 macOS 侧写 Swift 菜单：
//   PlatformMenuBar 把菜单交给**系统**渲染（走 flutter/menu 通道），因此菜单在系统
//   菜单栏里、能响应系统的键盘导航与辅助功能；同时菜单项的动作仍写在 Dart 里，能直接
//   读 Provider。若在 Swift 侧搭一套菜单，就得再开一条通道把「用户点了视图 → 今日」
//   送回 Dart——多一条跨语言边界，且菜单项的启用/文案无法随应用状态实时变化。
//
// 为什么拆成「纯构建函数 + 薄壳」：
//   PlatformMenuBar 不渲染任何 widget，菜单项的**回调**只存在于 PlatformMenuItem
//   对象上。若把菜单构建写在 build 里，测试就只能断言「通道上发了哪些标签」，测不到
//   「点了深色真的写了 SET-002」。把构建抽成 buildFluxMenus(...) 后，测试可以直接
//   拿到菜单项并调用它的 onSelected——与平台点击走的是同一个回调。
//
// 为什么菜单是**最小集**（文件/视图/帮助）：
//   T052 的目标是「窗口标题与菜单栏最小集」，不是把应用所有动作搬进菜单。菜单项一旦
//   加进去就是长期承诺（用户会依赖 Cmd+R）。这里只放界面上已有、且快捷键已实现的动作，
//   不与 T049 的应用级快捷键冲突。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/features/feeds/application/refresh_providers.dart';
import 'package:flux/features/settings/application/settings_controller.dart';
import 'package:flux/features/settings/application/settings_navigation.dart';
import 'package:flux/l10n/l10n.dart';

import 'app_destination.dart';
import 'app_shortcuts.dart';
// 当前去向的 Provider 住在 app_shell。它只在「壳层需要落实菜单动作」时被读一次，
// 依赖方向是 menu → shell 的单向引用（app_shell 不 import 本文件，app.dart 同时
// 引用两者），没有成环。
import 'app_shell.dart';

/// 主题菜单三档对应的 SET-002 存储值。
///
/// 与设置页共用同一套取值（注册表口径）。写成常量而不是引用设置页的私有列表，
/// 是为了让菜单模块不必依赖设置页的展示层；测试会断言这三个值都能被设置控制器接受。
const String kMenuThemeSystem = 'system';
const String kMenuThemeLight = 'light';
const String kMenuThemeDark = 'dark';

/// 菜单动作的落地回调。
///
/// 用一组具名回调而不是直接把 WidgetRef 传进构建函数：构建函数因此变成**纯函数**，
/// 测试可以注入记录用的假回调，逐项断言「点这一项会触发哪个动作」，不需要搭 Provider
/// 容器；真实调用点（[FluxMenuBar]）再把它们接到 Provider 上。
class FluxMenuActions {
  /// 构造动作集合。
  const FluxMenuActions({
    required this.refreshNow,
    required this.openSettings,
    required this.goToDestination,
    required this.setTheme,
    required this.showShortcutHelp,
  });

  /// 刷新全部订阅（与阅读页的刷新按钮同一用例）。
  final VoidCallback refreshNow;

  /// 打开设置页。
  final VoidCallback openSettings;

  /// 切换到某个顶层去向。
  final ValueChanged<AppDestination> goToDestination;

  /// 写入 SET-002。
  final ValueChanged<String> setTheme;

  /// 弹出快捷键说明。
  final VoidCallback showShortcutHelp;
}

/// 构建完整的菜单项列表（纯函数，可在测试里直接调用）。
///
/// [currentTheme] 用于把当前生效的主题档在菜单里标出来（tooltip）。
List<PlatformMenuItem> buildFluxMenus({
  required AppLocalizations l10n,
  required FluxMenuActions actions,
  required String currentTheme,
}) {
  return <PlatformMenuItem>[
    PlatformMenu(
      label: l10n.menuFile,
      menus: <PlatformMenuItem>[
        PlatformMenuItem(
          label: l10n.menuRefresh,
          onSelected: actions.refreshNow,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyR, meta: true),
        ),
        PlatformMenuItem(
          label: l10n.menuSettings,
          onSelected: actions.openSettings,
          // macOS 惯例：设置用 Cmd+,。
          shortcut: const SingleActivator(LogicalKeyboardKey.comma, meta: true),
        ),
      ],
    ),
    PlatformMenu(
      label: l10n.menuView,
      menus: <PlatformMenuItem>[
        PlatformMenuItem(
          label: l10n.navToday,
          onSelected: () => actions.goToDestination(AppDestination.today),
          shortcut: const SingleActivator(
            LogicalKeyboardKey.digit1,
            meta: true,
          ),
        ),
        PlatformMenuItem(
          label: l10n.navReading,
          onSelected: () => actions.goToDestination(AppDestination.reading),
          shortcut: const SingleActivator(
            LogicalKeyboardKey.digit2,
            meta: true,
          ),
        ),
        PlatformMenuItem(
          label: l10n.navMine,
          onSelected: () => actions.goToDestination(AppDestination.mine),
          shortcut: const SingleActivator(
            LogicalKeyboardKey.digit3,
            meta: true,
          ),
        ),
        PlatformMenu(
          label: l10n.menuTheme,
          menus: <PlatformMenuItem>[
            PlatformMenuItem(
              label: l10n.settingsOptionFollowSystem,
              onSelected: () => actions.setTheme(kMenuThemeSystem),
              tooltip: currentTheme == kMenuThemeSystem
                  ? l10n.settingsOptionFollowSystem
                  : null,
            ),
            PlatformMenuItem(
              label: l10n.settingsOptionLight,
              onSelected: () => actions.setTheme(kMenuThemeLight),
              tooltip: currentTheme == kMenuThemeLight
                  ? l10n.settingsOptionLight
                  : null,
            ),
            PlatformMenuItem(
              label: l10n.settingsOptionDark,
              onSelected: () => actions.setTheme(kMenuThemeDark),
              tooltip: currentTheme == kMenuThemeDark
                  ? l10n.settingsOptionDark
                  : null,
            ),
          ],
        ),
      ],
    ),
    PlatformMenu(
      label: l10n.menuHelp,
      menus: <PlatformMenuItem>[
        PlatformMenuItem(
          label: l10n.shortcutHelpTitle,
          onSelected: actions.showShortcutHelp,
          shortcut: const SingleActivator(LogicalKeyboardKey.slash, meta: true),
        ),
        PlatformMenuItem(
          label: l10n.settingsSectionAbout,
          onSelected: actions.openSettings,
        ),
      ],
    ),
  ];
}

/// 应用级菜单栏。
///
/// 挂在 MaterialApp 的 builder 里（见 app.dart）。它在 Flutter 层面不渲染任何东西，
/// 只把菜单描述发给平台；因此这里读 Provider 只是为了拿到「当前语言」与「当前主题」。
class FluxMenuBar extends ConsumerWidget {
  /// 构造菜单栏。
  const FluxMenuBar({required this.child, super.key});

  /// 子树（MaterialApp）。
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SettingsState settings =
        ref.watch(settingsControllerProvider).value ?? SettingsState.initial();
    // 这一层在 MaterialApp 的 **builder** 里，而 MaterialApp 的 Localizations 是
    // 包在 builder 结果**外面**的（见 WidgetsApp.build 的 title ?? result），因此
    // 这里 AppLocalizations.of(context) 拿不到值，必须按当前语言自己解析。
    final AppLocalizations l10n = lookupAppLocalizations(
      AppLanguageSetting.resolveLocale(settings.language) ?? fallbackLocale,
    );

    final FluxMenuActions actions = FluxMenuActions(
      refreshNow: () =>
          ref.read(refreshControllerProvider.notifier).refreshNow(),
      // 设置需要 Navigator（push 路由），而这一层在它之上；因此只置一个请求，
      // 由应用壳（在 Navigator 内部）落实——与 T020 建立的路线一致。
      openSettings: () =>
          ref.read(settingsNavigationRequestProvider.notifier).request(),
      goToDestination: (AppDestination destination) =>
          ref.read(selectedDestinationProvider.notifier).state = destination,
      setTheme: (String value) =>
          ref.read(settingsControllerProvider.notifier).setTheme(value),
      showShortcutHelp: () =>
          ref.read(shortcutHelpRequestProvider.notifier).request(),
    );

    return PlatformMenuBar(
      menus: buildFluxMenus(
        l10n: l10n,
        actions: actions,
        currentTheme: settings.theme,
      ),
      child: child,
    );
  }
}
