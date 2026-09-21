// T011 证据采集：在真实 macOS 上驱动真实应用，逐个状态停留，供外部截图。
//
// 为什么需要它：
//   本机的 macOS 辅助功能权限被禁用：合成鼠标事件与 AppleScript 窗口脚本都被系统
//   拒绝（屏幕角落会出现 universalAccessAuthWarn），因此**不能**用脚本去点击真
//   实窗口来切换页面。这个用例把「切换页面」交给 Flutter 自己的测试框架（组件级
//   手势不受系统辅助功能限制），真实窗口随之显示对应页面，外部再用
//   screencapture 按窗口 id 抓图（-l 参数只抓该窗口，不受其他窗口遮挡影响）。
//
// 协调方式：每进入一个状态就把状态名写进证据目录并停留若干秒；外部脚本轮询该
// 文件，命中后截图。路径取应用支持目录，应用能写、宿主机脚本也能读。
//
// **每个状态是一个独立 testWidgets**，不复用同一个用例。原因不是风格：
//   同一个用例里第二次 pumpWidget 会复用 element 树与 ProviderContainer，
//   实测表现为「设置成英文后界面仍是中文」。分开后每个用例都是全新容器与全新
//   数据库目录，状态之间不可能互相污染。
//
// 运行：flutter test integration_test/t011_evidence_test.dart -d macos
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flux/app/app.dart';
import 'package:flux/app/app_bootstrap.dart';
import 'package:flux/app/app_providers.dart';
import 'package:flux/core/core.dart';

/// 每个状态停留的时长：要覆盖外部脚本的轮询间隔与截图耗时。
const Duration stateHold = Duration(seconds: 6);

/// 证据目录名（位于应用支持目录下）。
const String evidenceDirName = 'flux-t011-evidence';

/// 需要外部 screencapture 抓真实窗口的状态名。
const List<String> screenshotStates = <String>[
  'onboarding_step1_light_zh',
  'shell_today_light_zh_wide',
  'shell_reading_light_zh_wide',
  'settings_light_zh_wide',
  'shell_today_dark_en_wide',
  'settings_dark_en_wide',
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory evidenceDir;
  AppBootstrapResult? bootstrap;
  int stateIndex = 0;

  setUpAll(() async {
    final Directory support = await getApplicationSupportDirectory();
    evidenceDir = Directory('${support.path}/$evidenceDirName');
    if (evidenceDir.existsSync()) {
      evidenceDir.deleteSync(recursive: true);
    }
    evidenceDir.createSync(recursive: true);
  });

  tearDown(() async {
    await bootstrap?.dispose();
    bootstrap = null;
  });

  tearDownAll(() {
    File('${evidenceDir.path}/done.txt').writeAsStringSync(
      jsonEncode(<String, Object?>{
        'states': screenshotStates,
        'narrowWindowNote':
            'macOS 上无法出现 <600 的内容宽度：架构第 7 节要求最小窗 720x560，'
            '且本机辅助功能权限被禁用（无法用脚本缩放真实窗口）。单栏布局由 '
            'test/app/app_shell_test.dart 与 golden shell_light_zh_narrow.png 覆盖。',
      }),
    );
  });

  /// 用指定语言/主题与引导状态装配真实应用（真实数据库，落在独立子目录）。
  Future<void> pumpApp(
    WidgetTester tester, {
    required String language,
    required String theme,
    required bool onboardingDone,
  }) async {
    stateIndex += 1;
    final Directory dataDir = Directory('${evidenceDir.path}/data-$stateIndex');
    dataDir.createSync(recursive: true);

    final AppBootstrapResult current = await bootstrapApp(
      dataDirectoryOverride: dataDir,
    );
    bootstrap = current;

    final Result<Object?> languageWrite = await current.settingsStore
        .writeSetting(SettingId.set001, language);
    expect(languageWrite.isOk, isTrue, reason: '写入 SET-001 失败');
    final Result<Object?> themeWrite = await current.settingsStore.writeSetting(
      SettingId.set002,
      theme,
    );
    expect(themeWrite.isOk, isTrue, reason: '写入 SET-002 失败');
    if (onboardingDone) {
      await current.onboardingStore.markCompleted();
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: bootstrapOverrides(current),
        child: const FluxApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 把一个状态名写给外部脚本，并停留等待截图。
  Future<void> announce(WidgetTester tester, String state) async {
    File('${evidenceDir.path}/state.txt')
        .writeAsStringSync(jsonEncode(<String, Object?>{'state': state}));
    // 停留期间持续 pump：窗口必须保持可绘制，截图才有内容。
    final DateTime deadline = DateTime.now().add(stateHold);
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  testWidgets('1 首启向导第一步（浅色 + 中文）', (WidgetTester tester) async {
    await pumpApp(
      tester,
      language: 'zh-Hans',
      theme: 'light',
      onboardingDone: false,
    );
    expect(find.text('欢迎使用 Flux'), findsOneWidget);
    await announce(tester, 'onboarding_step1_light_zh');
  });

  testWidgets('2 今日页（浅色 + 中文，宽窗三栏）', (WidgetTester tester) async {
    await pumpApp(
      tester,
      language: 'zh-Hans',
      theme: 'light',
      onboardingDone: true,
    );
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('今天还没有新闻'), findsOneWidget);
    await announce(tester, 'shell_today_light_zh_wide');
  });

  testWidgets('3 RSS 阅读页（浅色 + 中文，无订阅空态）', (WidgetTester tester) async {
    await pumpApp(
      tester,
      language: 'zh-Hans',
      theme: 'light',
      onboardingDone: true,
    );
    await tester.tap(find.text('RSS 阅读').first);
    await tester.pumpAndSettle();
    expect(find.text('还没有订阅'), findsOneWidget);
    await announce(tester, 'shell_reading_light_zh_wide');
  });

  testWidgets('4 设置页（浅色 + 中文）', (WidgetTester tester) async {
    await pumpApp(
      tester,
      language: 'zh-Hans',
      theme: 'light',
      onboardingDone: true,
    );
    await tester.tap(find.text('我的').first);
    await tester.pumpAndSettle();
    expect(find.text('界面语言'), findsWidgets);
    await announce(tester, 'settings_light_zh_wide');
  });

  testWidgets('5 今日页（深色 + 英文）', (WidgetTester tester) async {
    await pumpApp(tester, language: 'en', theme: 'dark', onboardingDone: true);
    expect(find.text('No news for today yet'), findsOneWidget);
    await announce(tester, 'shell_today_dark_en_wide');
  });

  testWidgets('6 设置页（深色 + 英文）', (WidgetTester tester) async {
    await pumpApp(tester, language: 'en', theme: 'dark', onboardingDone: true);
    await tester.tap(find.text('Mine').first);
    await tester.pumpAndSettle();
    expect(find.text('Interface language'), findsWidgets);
    await announce(tester, 'settings_dark_en_wide');
  });

  testWidgets('7 窄窗单栏（<600 逻辑像素）：仅断言，不产出截图', (WidgetTester tester) async {
    // 为什么这个用例**不**截图（这是一次实测纠正）：
    //   把 tester.view.physicalSize 设为 560 只改变 Flutter 的逻辑视口，
    //   **不会**改变真实 macOS 窗口大小。于是 screencapture 抓到的是上一个状态
    //   遗留的画面——实测该 PNG 与「深色+英文设置页」字节完全相同，属于误导性
    //   证据。宁可少一张图，也不留一张看起来对、实际是旧画面的图。
    //
    //   窄窗单栏的可见证据由以下两处提供（都是真实渲染结果）：
    //     1) test/app/app_shell_test.dart：<600 时只有一个内容面板，无来源栏/正文栏；
    //     2) test/app/golden/shell_light_zh_narrow.png：真实渲染的单栏壳 golden。
    //   之所以无法在真实窗口上做出 <600：架构第 7 节要求桌面最小窗 720×560，
    //   本项目据此设置了 macOS 窗口 contentMinSize=720；本机辅助功能权限又被
    //   禁用，无法用脚本缩放窗口做对照。
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(560, 800);
    addTearDown(tester.view.reset);

    await pumpApp(
      tester,
      language: 'zh-Hans',
      theme: 'light',
      onboardingDone: true,
    );
    expect(find.text('单栏布局（窗口宽度 <600）'), findsOneWidget);
    // 单栏时不应出现来源栏与正文栏（它们只在双栏/三栏存在）。
    expect(find.text('订阅源栏'), findsNothing);
    expect(find.text('正文区'), findsNothing);
    // 窄窗退化为底部导航栏（架构第 7 节 600 断点）。
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });
}
