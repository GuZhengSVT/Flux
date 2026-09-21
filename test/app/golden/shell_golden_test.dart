// 壳层 golden（T011 验收要求：浅深两套主题的壳 golden 入库）。
//
// 为什么 golden 值得入库：
//   主题 token 是「数值对但整体观感错」的典型场景——对比度够、色值对，
//   仍可能出现面板分界看不清、文字与底色同色的情况。golden 把整屏渲染结果钉住，
//   任何 token/布局回归都会以像素差异暴露，而不是等到人工看截图才发现。
//
// 更新方式：flutter test --update-goldens test/app/golden/shell_golden_test.dart
// 更新前必须人工确认截图符合架构第 7 节，而不是「跑一下让它变成绿的」。
//
// 注意：golden 对字体渲染敏感。测试环境使用 Ahem 字体（方块字形），
// 因此这里断言的是**布局与配色结构**，不是文案本身；文案正确性由
// app_shell_test / settings_page_test 的文本断言负责。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/app/shell/app_destination.dart';
import 'package:flux/app/shell/app_shell.dart';
import 'package:flux/features/onboarding/presentation/onboarding_page.dart';

import '../test_harness.dart';

void main() {
  group('壳 golden', () {
    testWidgets('浅色中文：宽窗三栏壳', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      await setSurfaceSize(tester, const Size(1400, 900));

      await tester.pumpWidget(
        wrapFluxApp(
          child: const AppShell(),
          overrides: bootstrap.overrides(),
          localeOverride: const Locale('zh'),
          themeMode: ThemeMode.light,
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(AppShell),
        matchesGoldenFile('shell_light_zh_wide.png'),
      );
    });

    testWidgets('深色英文：宽窗三栏壳', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      await setSurfaceSize(tester, const Size(1400, 900));

      await tester.pumpWidget(
        wrapFluxApp(
          child: const AppShell(),
          overrides: bootstrap.overrides(),
          localeOverride: const Locale('en'),
          themeMode: ThemeMode.dark,
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(AppShell),
        matchesGoldenFile('shell_dark_en_wide.png'),
      );
    });

    testWidgets('浅色中文：窄窗单栏（底栏导航）', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      await setSurfaceSize(tester, const Size(520, 900));

      await tester.pumpWidget(
        wrapFluxApp(
          child: const AppShell(),
          overrides: bootstrap.overrides(),
          localeOverride: const Locale('zh'),
          themeMode: ThemeMode.light,
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(AppShell),
        matchesGoldenFile('shell_light_zh_narrow.png'),
      );
    });

    testWidgets('深色英文：设置页（含占位项与关于区）', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      // 高视口：让占位项与关于区都进入渲染范围。
      await setSurfaceSize(tester, const Size(1200, 1800));

      await tester.pumpWidget(
        wrapFluxApp(
          child: const AppShell(),
          overrides: bootstrap.overrides(),
          localeOverride: const Locale('en'),
          themeMode: ThemeMode.dark,
        ),
      );
      await tester.pumpAndSettle();
      // 切到「我的」。
      await tester.tap(find.text('Mine').first);
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(AppShell),
        matchesGoldenFile('settings_dark_en.png'),
      );
    });

    testWidgets('浅色中文：首启向导第一步', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      await setSurfaceSize(tester, const Size(1200, 900));

      await tester.pumpWidget(
        wrapFluxApp(
          child: const OnboardingPage(),
          overrides: bootstrap.overrides(),
          localeOverride: const Locale('zh'),
          themeMode: ThemeMode.light,
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(OnboardingPage),
        matchesGoldenFile('onboarding_step1_light_zh.png'),
      );
    });
  });

  test('去向清单稳定（防止导航项被静默增删）', () {
    expect(appDestinations, <AppDestination>[
      AppDestination.today,
      AppDestination.reading,
      AppDestination.mine,
    ]);
  });
}
