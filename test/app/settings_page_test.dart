// 设置页测试（T011）。
//
// 本文件最要紧的断言不是「控件存在」，而是三条边界：
//   1) SET-001/002 是**真的**读写设置存储（用真实仓储 + 内存库验证落库值）；
//   2) 尚未实现的 SET 项**没有任何可操作控件**（不能是「能点但无效」的假开关）；
//   3) 语言立刻切换界面、非法/未知值不改变已存值。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/app/app.dart';
import 'package:flux/core/app_metadata.dart';
import 'package:flux/core/core.dart';
import 'package:flux/features/settings/presentation/settings_page.dart';

import 'test_harness.dart';

void main() {
  group('SET-001 / SET-002 真实生效', () {
    testWidgets('切换语言会写入 SET-001 并立即切换界面文案', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      await setSurfaceSize(tester, const Size(1200, 900));
      await bootstrap.seedLanguage('zh-Hans');
      // 首次引导已完成：否则根组件停在向导，导航不存在。
      await bootstrap.completeOnboarding();

      // 用根组件渲染：这样才能验证「设置变化 → MaterialApp.locale 变化」。
      await tester.pumpWidget(
        wrapRoot(child: const FluxApp(), overrides: bootstrap.overrides()),
      );
      await tester.pumpAndSettle();

      // 切到「我的」。
      expect(find.byType(NavigationRail), findsOneWidget);
      await tester.tap(find.text('我的').first);
      await tester.pumpAndSettle();
      expect(find.text('界面语言'), findsWidgets);

      // 选择 English。
      await tester.tap(find.text('English').first);
      await tester.pumpAndSettle();

      // 界面文案立刻变成英文。
      expect(find.text('Interface language'), findsWidgets);
      expect(find.text('界面语言'), findsNothing);

      // 值真的落库了（不是只改了内存）。
      final Result<Object?> stored = await bootstrap.settingsRepository.read(
        SettingId.set001,
      );
      expect(stored.valueOrNull, 'en');
    });

    testWidgets('写回中文后界面恢复中文', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      await setSurfaceSize(tester, const Size(1200, 900));
      // 预置英文启动，再切回中文。
      await bootstrap.seedLanguage('en');
      await bootstrap.completeOnboarding();

      await tester.pumpWidget(
        wrapRoot(child: const FluxApp(), overrides: bootstrap.overrides()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mine').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('简体中文').first);
      await tester.pumpAndSettle();

      expect(find.text('界面语言'), findsWidgets);
      final Result<Object?> stored = await bootstrap.settingsRepository.read(
        SettingId.set001,
      );
      expect(stored.valueOrNull, 'zh-Hans');
    });

    testWidgets('切换主题会写入 SET-002；深色下明暗确实变化', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      await setSurfaceSize(tester, const Size(1200, 900));
      await bootstrap.seedLanguage('zh-Hans');
      await bootstrap.completeOnboarding();

      await tester.pumpWidget(
        wrapRoot(child: const FluxApp(), overrides: bootstrap.overrides()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('我的').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('深色').first);
      await tester.pumpAndSettle();

      final Result<Object?> stored = await bootstrap.settingsRepository.read(
        SettingId.set002,
      );
      expect(stored.valueOrNull, 'dark');

      // 主题真的切换了：MaterialApp 解析出的亮度为 dark。
      final MaterialApp app = tester.widget<MaterialApp>(
        find.byType(MaterialApp),
      );
      expect(app.themeMode, ThemeMode.dark);
      expect(
        Theme.of(tester.element(find.byType(SettingsPage))).brightness,
        Brightness.dark,
      );
    });

    testWidgets('主题跟随系统：platformBrightness 决定实际明暗', (
      WidgetTester tester,
    ) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      await setSurfaceSize(tester, const Size(1200, 900));
      await bootstrap.seedLanguage('zh-Hans');
      await bootstrap.seedTheme('system');
      await bootstrap.completeOnboarding();

      await tester.pumpWidget(
        wrapRoot(
          child: const FluxApp(),
          overrides: bootstrap.overrides(),
          platformBrightness: Brightness.dark,
        ),
      );
      await tester.pumpAndSettle();

      final MaterialApp app = tester.widget<MaterialApp>(
        find.byType(MaterialApp),
      );
      expect(app.themeMode, ThemeMode.system);
      // system 模式下实际生效的是 darkTheme（因为平台亮度为 dark）。
      expect(
        Theme.of(tester.element(find.byType(NavigationRail))).brightness,
        Brightness.dark,
      );
    });

    testWidgets('默认语言为跟随系统（SET-001 默认值），界面为英文回退', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      await setSurfaceSize(tester, const Size(1200, 900));
      // 默认语言为跟随系统；同时预置引导完成，直接验证「无匹配回退英文」。
      await bootstrap.completeOnboarding();

      await tester.pumpWidget(
        wrapRoot(child: const FluxApp(), overrides: bootstrap.overrides()),
      );
      await tester.pumpAndSettle();

      final MaterialApp app = tester.widget<MaterialApp>(
        find.byType(MaterialApp),
      );
      // 未设置时 locale 为 null：交给系统解析（不能预解析成某个固定语言）。
      expect(app.locale, isNull);
      // 测试环境系统语言无中文匹配，按 SET-001 回退英文。
      expect(find.text('Mine'), findsWidgets);
    });
  });

  group('不得造假功能', () {
    testWidgets('尚未实现的 SET 项只展示，没有任何可切换控件', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      // 高视口让 14 个占位项与其后的「关于」区都完成布局：ListView 惰性构建，
      // 视口外的小节不会被创建，断言也就无从谈起。
      await setSurfaceSize(tester, const Size(1200, 3000));
      await bootstrap.seedLanguage('zh-Hans');

      await tester.pumpWidget(wrapWrap(bootstrap));
      await tester.pumpAndSettle();

      // 展示 14 个未实现的阅读与外观项。
      expect(find.text('主题背景图'), findsOneWidget);
      expect(find.text('自动加载远程图片'), findsOneWidget);
      expect(find.text('即将推出'), findsNWidgets(14));

      // 全页只有两条 SegmentedButton（SET-001 语言、SET-002 主题）。
      // 多一个就说明有「看起来能用」的假开关混进来了。
      expect(find.byType(SegmentedButton<String>), findsNWidgets(2));
      // 占位项不含任何开关控件。
      expect(find.byType(Switch), findsNothing);
      expect(find.byType(Slider), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byType(Radio<String>), findsNothing);
      // 也没有任何「添加/导入/选择文件」这类假动作入口。
      expect(find.widgetWithText(FilledButton, '添加'), findsNothing);
      expect(find.text('导入 OPML'), findsNothing);
    });

    testWidgets('占位项标注对应任务号与分类', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      await setSurfaceSize(tester, const Size(1200, 3000));
      await bootstrap.seedLanguage('zh-Hans');
      await bootstrap.completeOnboarding();

      await tester.pumpWidget(wrapWrap(bootstrap));
      await tester.pumpAndSettle();

      expect(find.textContaining('SET-003'), findsOneWidget);
      expect(find.textContaining('SET-016'), findsOneWidget);
      expect(find.textContaining('设备专属'), findsWidgets);
      // SET-010 是 C 类，必须显示可同步分类。
      expect(find.textContaining('共通·可同步'), findsWidgets);
    });

    testWidgets('写入失败时显示提示且不假装成功', (WidgetTester tester) async {
      // 降级启动：设置端口写入必然失败。
      final TestBootstrap bootstrap = TestBootstrap(degraded: true);
      addTearDown(bootstrap.dispose);
      await setSurfaceSize(tester, const Size(1200, 1400));

      await tester.pumpWidget(
        wrapFluxApp(
          child: const SettingsPage(),
          overrides: bootstrap.overrides(),
        ),
      );
      await tester.pumpAndSettle();

      // 降级时设置端口只返回注册表默认值（SET-001 = system），因此界面按测试
      // 环境的系统语言渲染成英文。这里不预置语言，顺带验证「无匹配回退英文」。
      await tester.tap(find.text('简体中文').first);
      await tester.pumpAndSettle();

      // 明确提示没有保存（不静默失败），且界面语言没有真的切过去。
      expect(find.textContaining('改动没有保存'), findsWidgets);
      // 可见选中项仍是「跟随系统」：写入失败后不乐观地改内存状态。
      final SegmentedButton<String> language = tester
          .widgetList<SegmentedButton<String>>(
            find.byType(SegmentedButton<String>),
          )
          .first;
      expect(language.selected, <String>{'system'});
      // 未落库：读回仍是默认值 system（数据库不可用时读的是注册表默认值）。
      final Result<Object?> stored = await bootstrap.settingsRepository.read(
        SettingId.set001,
      );
      expect(stored.valueOrNull, 'system');
    });
  });

  group('关于区', () {
    testWidgets('显示版本、MIT 与核实过的仓库地址', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      // 关于区在页面底部，需要足够高的视口才会被 ListView 构建出来。
      await setSurfaceSize(tester, const Size(1200, 3000));
      await bootstrap.seedLanguage('zh-Hans');

      await tester.pumpWidget(wrapWrap(bootstrap));
      await tester.pumpAndSettle();

      expect(find.text('关于'), findsOneWidget);
      expect(find.textContaining(fluxAppVersion), findsWidgets);
      expect(find.textContaining('MIT'), findsWidgets);
      expect(find.text(fluxRepositoryUrl), findsOneWidget);
      expect(find.text(fluxIssueUrl), findsOneWidget);
    });
  });
}

/// 组件级包装：设置页直接用 wrapFluxApp 渲染（页面不涉及根 locale 解析）。
Widget wrapWrap(TestBootstrap bootstrap) =>
    wrapFluxApp(child: const SettingsPage(), overrides: bootstrap.overrides());
