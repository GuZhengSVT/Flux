// macOS 菜单栏与窗口标题测试（T052；T049 遗留的「菜单栏（macOS 原生菜单）」项）。
//
// 两层断言，各管一件事：
//   1) **菜单结构**：挂上真实根组件，拦截 flutter/menu 通道，断言发给平台的菜单里
//      有哪些顶层菜单、哪些项、哪些带快捷键、以及英文界面下不残留中文。菜单项不在
//      widget 树里（PlatformMenuBar 不渲染任何东西），因此只能从通道数据断言。
//   2) **动作真的落地**：直接调用菜单项自己的 onSelected（平台点击时走的正是这个
//      回调），断言它落到 Provider / 存储上——否则「菜单里有个『深色』」只是装饰。
//
// 为什么不只做第一层：onSelected 为 null 的菜单项在通道数据里与正常的项几乎一样
// （都只是一个 label），只有真调用一次才能发现它什么都没做。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/app/app.dart';
import 'package:flux/app/shell/app_destination.dart';
import 'package:flux/app/shell/flux_menu_bar.dart';
import 'package:flux/l10n/l10n.dart';

import 'test_harness.dart';

/// 从通道调用里取出「发给平台的菜单项」。
///
/// 通道格式是 {windowId: [item, ...]}（见 DefaultPlatformMenuDelegate.setMenus）。
/// 本项目单窗口，因此取唯一那个 key。
List<Map<String, Object?>> menuItemsOf(MethodCall call) {
  expect(call.method, 'Menu.setMenus', reason: '菜单应通过 Menu.setMenus 发给平台');
  final Map<Object?, Object?> windows = call.arguments as Map<Object?, Object?>;
  expect(windows.keys, hasLength(1), reason: '单窗口应用只应发送一份菜单');
  final List<Object?> items = windows.values.first! as List<Object?>;
  return <Map<String, Object?>>[
    for (final Object? item in items)
      (item! as Map<Object?, Object?>).cast<String, Object?>(),
  ];
}

/// 取某个菜单项的 children（子菜单/分组）。
List<Map<String, Object?>> childrenOf(Map<String, Object?> item) {
  final Object? children = item['children'];
  if (children is! List) {
    return <Map<String, Object?>>[];
  }
  return <Map<String, Object?>>[
    for (final Object? child in children)
      (child! as Map<Object?, Object?>).cast<String, Object?>(),
  ];
}

/// 菜单项是否声明了快捷键。
///
/// 键名来自框架的序列化实现（platform_menu_bar.dart 的 _kShortcutTrigger），
/// 不是我们自造的字段；写成函数是为了不把魔法字符串散落在各处。
bool hasShortcut(Map<String, Object?> item) =>
    item['shortcutTrigger'] != null || item['shortcutCharacter'] != null;

/// 菜单项的修饰键位掩码里是否含 ⌘。
///
/// 框架把修饰键打包成一个位掩码（meta 是 1 << 0），因此不能直接比较布尔值。
bool hasMetaModifier(Map<String, Object?> item) {
  final Object? mask = item['shortcutModifiers'];
  if (mask is! int) {
    return false;
  }
  // meta = 1 << 0（见 ShortcutSerialization._shortcutModifierMeta）。
  return mask & (1 << 0) != 0;
}

/// 递归收集所有标签（用于「英文界面下不含中文」这类整体断言）。
List<String> allLabels(List<Map<String, Object?>> items) {
  final List<String> labels = <String>[];
  void walk(List<Map<String, Object?>> nodes) {
    for (final Map<String, Object?> node in nodes) {
      final Object? label = node['label'];
      if (label is String && label.isNotEmpty) {
        labels.add(label);
      }
      walk(childrenOf(node));
    }
  }

  walk(items);
  return labels;
}

/// 从当前挂载的菜单栏里取回 PlatformMenuItem 对象。
///
/// 通道数据（Map）里只有标签与快捷键，**没有回调**；要真的调用一次动作，必须拿回
/// 构建时的对象。这里从 widget 树里的 PlatformMenuBar 读取它的 menus。
List<PlatformMenuItem> mountedMenuItems(WidgetTester tester) {
  final PlatformMenuBar bar = tester.widget<PlatformMenuBar>(
    find.byType(PlatformMenuBar),
  );
  return bar.menus;
}

/// 递归查找菜单项（按标签，比 index 稳定：菜单调整不会让断言错位）。
PlatformMenuItem? findByLabel(List<PlatformMenuItem> menus, String label) {
  for (final PlatformMenuItem item in menus) {
    if (item.label == label) {
      return item;
    }
    // 只有 PlatformMenu 带子项（menus）；叶子菜单项没有子项。
    final PlatformMenuItem? nested = item is PlatformMenu
        ? findByLabel(item.menus, label)
        : null;
    if (nested != null) {
      return nested;
    }
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> menuCalls;

  setUp(() {
    menuCalls = <MethodCall>[];
    // 记录调用的同时回 null：菜单只需要「发出去」这一步。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.menu, (MethodCall call) async {
          menuCalls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.menu, null);
  });

  /// 挂上真实根组件（含菜单栏），返回最后一次发出的菜单项。
  Future<List<Map<String, Object?>>> pumpAppWithMenu(
    WidgetTester tester, {
    String language = 'zh-Hans',
  }) async {
    final TestBootstrap bootstrap = TestBootstrap();
    addTearDown(bootstrap.dispose);
    await bootstrap.seedLanguage(language);
    await bootstrap.completeOnboarding();
    await tester.pumpWidget(
      wrapRoot(child: const FluxApp(), overrides: bootstrap.overrides()),
    );
    await tester.pumpAndSettle();
    expect(menuCalls, isNotEmpty, reason: '应用启动后应把菜单发给平台');
    return menuItemsOf(menuCalls.last);
  }

  group('菜单结构（发给平台的数据）', () {
    testWidgets('三个顶层菜单：文件 / 视图 / 帮助', (WidgetTester tester) async {
      final List<Map<String, Object?>> menus = await pumpAppWithMenu(tester);
      expect(
        menus.map((Map<String, Object?> m) => m['label']).toList(),
        <String>['文件', '视图', '帮助'],
      );
    });

    testWidgets('文件菜单：刷新（⌘R）与设置（⌘,），都带快捷键且可用', (WidgetTester tester) async {
      final List<Map<String, Object?>> menus = await pumpAppWithMenu(tester);
      final List<Map<String, Object?>> items = childrenOf(menus.first);
      expect(
        items.map((Map<String, Object?> i) => i['label']).toList(),
        <String>['刷新订阅', '设置…'],
      );
      for (final Map<String, Object?> entry in items) {
        // onSelected 为空时 PlatformMenuItem.serialize 会把 enabled 写成 false，
        // 因此这条断言同时覆盖「回调忘了接」这种失效。
        expect(entry['enabled'], isTrue, reason: '菜单项应是可用项');
        expect(hasShortcut(entry), isTrue, reason: '菜单项应声明快捷键');
        expect(hasMetaModifier(entry), isTrue, reason: '菜单项应使用 ⌘ 修饰键');
      }
    });

    testWidgets('视图菜单：三去向 + 主题子菜单三档', (WidgetTester tester) async {
      final List<Map<String, Object?>> menus = await pumpAppWithMenu(tester);
      final List<Map<String, Object?>> items = childrenOf(menus[1]);
      final List<String> labels = <String>[
        for (final Map<String, Object?> entry in items)
          entry['label']! as String,
      ];
      expect(labels, <String>['今日新闻', 'RSS 阅读', '我的', '主题']);
      // 三去向各自带 ⌘1/2/3。
      for (final Map<String, Object?> entry in items.take(3)) {
        expect(entry['enabled'], isTrue);
        expect(hasMetaModifier(entry), isTrue);
        expect(hasShortcut(entry), isTrue);
      }
      // 主题是子菜单，三档与 SET-002 的取值对应。
      final Map<String, Object?> themeMenu = items.firstWhere(
        (Map<String, Object?> entry) => entry['label'] == '主题',
      );
      expect(
        childrenOf(themeMenu)
            .map((Map<String, Object?> entry) => entry['label'])
            .toList(),
        <String>['跟随系统', '浅色', '深色'],
      );
    });

    testWidgets('帮助菜单：快捷键说明（⌘/）与关于', (WidgetTester tester) async {
      final List<Map<String, Object?>> menus = await pumpAppWithMenu(tester);
      final List<Map<String, Object?>> items = childrenOf(menus[2]);
      expect(
        items.map((Map<String, Object?> i) => i['label']).toList(),
        <String>['键盘快捷键', '关于'],
      );
      expect(hasMetaModifier(items.first), isTrue, reason: '快捷键说明应是 ⌘/');
    });

    testWidgets('英文界面下菜单是英文，且不残留中文', (WidgetTester tester) async {
      final List<Map<String, Object?>> menus = await pumpAppWithMenu(
        tester,
        language: 'en',
      );
      expect(
        menus.map((Map<String, Object?> m) => m['label']).toList(),
        <String>['File', 'View', 'Help'],
      );
      final List<String> labels = allLabels(menus);
      expect(labels, contains('Refresh Feeds'));
      expect(labels, contains('Settings…'));
      // 菜单栏包在 MaterialApp 的 builder 里，而 Localizations 在 builder 结果**外面**，
      // 因此这一条是在验证「菜单自己按 SET-001 解析了语言」——写死中文或写死英文
      // 都会在这里失败。
      expect(
        labels.where((String l) => RegExp(r'[\u4e00-\u9fff]').hasMatch(l)),
        isEmpty,
        reason: '英文界面下菜单里不应出现中文',
      );
    });
  });

  group('菜单动作真的落地（调用菜单项自己的回调）', () {
    /// 用给定 l10n 构建菜单，动作记录到 calls 里。
    ({List<PlatformMenuItem> menus, List<String> calls}) buildRecordingMenus(
      AppLocalizations l10n,
    ) {
      final List<String> calls = <String>[];
      final List<PlatformMenuItem> menus = buildFluxMenus(
        l10n: l10n,
        currentTheme: kMenuThemeSystem,
        actions: FluxMenuActions(
          refreshNow: () => calls.add('refresh'),
          openSettings: () => calls.add('settings'),
          goToDestination: (AppDestination d) => calls.add('go:${d.name}'),
          setTheme: (String v) => calls.add('theme:$v'),
          showShortcutHelp: () => calls.add('help'),
        ),
      );
      return (menus: menus, calls: calls);
    }

    test('每一项都接到动作上，且各自触发正确的动作', () {
      final AppLocalizations l10n = lookupAppLocalizations(const Locale('zh'));
      final ({List<PlatformMenuItem> menus, List<String> calls}) built =
          buildRecordingMenus(l10n);

      // 逐项触发：只断言「菜单非空」无法发现某一项的回调接到了别的动作上。
      final Map<String, String> expected = <String, String>{
        l10n.menuRefresh: 'refresh',
        l10n.menuSettings: 'settings',
        l10n.navToday: 'go:today',
        l10n.navReading: 'go:reading',
        l10n.navMine: 'go:mine',
        l10n.settingsOptionFollowSystem: 'theme:system',
        l10n.settingsOptionLight: 'theme:light',
        l10n.settingsOptionDark: 'theme:dark',
        l10n.shortcutHelpTitle: 'help',
      };
      for (final MapEntry<String, String> entry in expected.entries) {
        final PlatformMenuItem? item = findByLabel(built.menus, entry.key);
        expect(item, isNotNull, reason: '菜单里缺少「${entry.key}」');
        expect(item!.onSelected, isNotNull, reason: '「${entry.key}」没有接动作');
        built.calls.clear();
        item.onSelected!();
        expect(built.calls, <String>[
          entry.value,
        ], reason: '「${entry.key}」应触发 ${entry.value}');
      }
    });

    test('主题三档写入的取值都是 SET-002 的合法值', () {
      // 菜单里写的是字符串常量；若与注册表口径不一致，点了菜单会被设置控制器当成
      // 非法值拒掉（或写进一个界面读不懂的值）。这里直接对照常量清单。
      final AppLocalizations l10n = lookupAppLocalizations(const Locale('zh'));
      final ({List<PlatformMenuItem> menus, List<String> calls}) built =
          buildRecordingMenus(l10n);
      for (final String label in <String>[
        l10n.settingsOptionFollowSystem,
        l10n.settingsOptionLight,
        l10n.settingsOptionDark,
      ]) {
        built.calls.clear();
        findByLabel(built.menus, label)!.onSelected!();
        final String value = built.calls.single.substring('theme:'.length);
        expect(<String>[
          kMenuThemeSystem,
          kMenuThemeLight,
          kMenuThemeDark,
        ], contains(value));
      }
    });

    testWidgets('主题菜单真的写入 SET-002（走真实 Provider 与存储）', (
      WidgetTester tester,
    ) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      await bootstrap.seedLanguage('zh-Hans');
      await bootstrap.completeOnboarding();
      await tester.pumpWidget(
        wrapRoot(child: const FluxApp(), overrides: bootstrap.overrides()),
      );
      await tester.pumpAndSettle();

      // 从真实挂载的菜单里取回 PlatformMenuItem 对象并调用它的回调——这与平台
      // 点击菜单时走的是同一个回调（DefaultPlatformMenuDelegate 的 handler）。
      final AppLocalizations l10n = lookupAppLocalizations(const Locale('zh'));
      final PlatformMenuItem dark = findByLabel(
        mountedMenuItems(tester),
        l10n.settingsOptionDark,
      )!;
      dark.onSelected!();
      await tester.pumpAndSettle();

      // 断言写进了存储，而不是只改了内存状态：从真实仓储重读。
      final Result<Object?> stored = await bootstrap.settingsRepository.read(
        SettingId.set002,
      );
      expect(stored.valueOrNull, 'dark', reason: '菜单选主题必须真实写入 SET-002');
    });
  });

  group('窗口标题与模板占位符（T052 修掉的真实缺陷）', () {
    test('MainMenu.xib 里不再有模板占位符 APP_NAME', () {
      // T052 修掉的一个**用户可见**缺陷：模板 xib 的标题写的是字面量 APP_NAME，
      // 而 flutter 工具只在**测试环境**替换该占位符，打包时不替换——因此此前构建
      // 出来的应用，菜单栏与窗口标题实际显示「APP_NAME」（已在编译产物
      // MainMenu.nib 里用 strings 核实，共 6 处）。
      final String xib = File('macos/Runner/Base.lproj/MainMenu.xib')
          .readAsStringSync();
      expect(
        xib.contains('APP_NAME'),
        isFalse,
        reason: 'MainMenu.xib 仍是模板占位符，构建后菜单栏与窗口标题会显示 APP_NAME',
      );
      expect(xib, contains('title="Flux"'), reason: '窗口标题应为 Flux');
    });

    test('窗口标题由 MainFlutterWindow 显式取自 CFBundleName', () {
      final String source = File('macos/Runner/MainFlutterWindow.swift')
          .readAsStringSync();
      // 断言真的读了 CFBundleName 而不是硬编码字符串：硬编码也能「非空」，
      // 但那样标题就与 Info.plist / PRODUCT_NAME 脱钩了。
      expect(
        source.contains('CFBundleName'),
        isTrue,
        reason: '窗口标题应取自 CFBundleName，与应用名保持单一来源',
      );
      expect(source.contains('self.title ='), isTrue);
    });
  });
}
