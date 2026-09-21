// 应用壳测试（T011）：导航、断点、空态与降级提示。
//
// 三条规则各自来自文档，因此各自有一组断言：
//   1) 三个顶层去向（架构第 3 节：今日新闻 / RSS 阅读 / 我的）；
//   2) 600 断点决定侧边栏还是底部栏，<600 单栏、600–1099 双栏、>=1100 三栏
//      （架构第 7 节，含「宽度不足自动退回双栏」）；
//   3) 数据库不可用时明确提示，而不是静默降级（架构第 8 节不以假象代替状态）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/app/shell/app_destination.dart';
import 'package:flux/app/shell/app_shell.dart';

import 'test_harness.dart';

void main() {
  group('顶层导航', () {
    testWidgets('恰好三个去向，且标签来自本地化资源', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      await setSurfaceSize(tester, const Size(1280, 900));

      await tester.pumpWidget(
        wrapFluxApp(child: const AppShell(), overrides: bootstrap.overrides()),
      );
      await tester.pumpAndSettle();

      expect(appDestinations.length, 3);
      expect(find.text('今日新闻'), findsWidgets);
      expect(find.text('RSS 阅读'), findsWidgets);
      expect(find.text('我的'), findsWidgets);
      // 宽窗用侧边导航，不应出现底部导航栏。
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('窄窗退化为底部导航栏', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      await setSurfaceSize(tester, const Size(560, 900));

      await tester.pumpWidget(
        wrapFluxApp(child: const AppShell(), overrides: bootstrap.overrides()),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('600 是切换边界：599 用底栏、600 用侧栏', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);

      await setSurfaceSize(tester, const Size(599, 900));
      await tester.pumpWidget(
        wrapFluxApp(child: const AppShell(), overrides: bootstrap.overrides()),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);

      await setSurfaceSize(tester, const Size(600, 900));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('切换去向会显示对应页面内容', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      await setSurfaceSize(tester, const Size(1280, 900));

      await tester.pumpWidget(
        wrapFluxApp(child: const AppShell(), overrides: bootstrap.overrides()),
      );
      await tester.pumpAndSettle();

      // 初始去向为今日新闻：显示其空态标题。
      expect(find.text('今天还没有新闻'), findsOneWidget);

      // 切到 RSS 阅读：显示「无订阅」空态（架构第 7 节要求分别提示）。
      await tester.tap(find.text('RSS 阅读').first);
      await tester.pumpAndSettle();
      expect(find.text('还没有订阅'), findsOneWidget);

      // 切到「我的」：进入真正的设置页（T011 已生效的部分）。
      await tester.tap(find.text('我的').first);
      await tester.pumpAndSettle();
      expect(find.text('界面语言'), findsWidgets);
    });
  });

  group('响应式栏位（架构第 7 节）', () {
    testWidgets('<600 单栏：只有一个内容面板', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      await setSurfaceSize(tester, const Size(520, 900));

      await tester.pumpWidget(
        wrapFluxApp(child: const AppShell(), overrides: bootstrap.overrides()),
      );
      await tester.pumpAndSettle();

      expect(find.text('单栏布局（窗口宽度 <600）'), findsOneWidget);
      expect(find.text('订阅源栏'), findsNothing);
      expect(find.text('正文区'), findsNothing);
    });

    testWidgets('600–1099 双栏：来源栏 + 列表栏', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      // 侧边导航占 80 左右，因此窗口 800 时内容区约 720（>=600 但 <1100）。
      await setSurfaceSize(tester, const Size(800, 900));

      await tester.pumpWidget(
        wrapFluxApp(child: const AppShell(), overrides: bootstrap.overrides()),
      );
      await tester.pumpAndSettle();

      expect(find.text('双栏布局（600–1099）'), findsOneWidget);
      expect(find.text('订阅源栏'), findsOneWidget);
      expect(find.text('正文区'), findsNothing);
    });

    testWidgets('>=1100 三栏：来源栏 + 列表栏 + 正文区', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      await setSurfaceSize(tester, const Size(1400, 900));

      await tester.pumpWidget(
        wrapFluxApp(child: const AppShell(), overrides: bootstrap.overrides()),
      );
      await tester.pumpAndSettle();

      expect(find.text('三栏布局（≥1100）'), findsOneWidget);
      expect(find.text('订阅源栏'), findsOneWidget);
      expect(find.text('文章列表'), findsOneWidget);
      expect(find.text('正文区'), findsOneWidget);
    });

    testWidgets('内容区跨过 1100 才变三栏（侧栏占宽计入判断）', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      // 侧边导航约占 95 逻辑像素，因此窗口 1180 时内容区约 1085（<1100 双栏），
      // 窗口 1200 时内容区约 1105（>=1100 三栏）。这里正是要钉住
      // 「断点判的是内容区，不是窗口宽度」。
      await setSurfaceSize(tester, const Size(1180, 900));
      await tester.pumpWidget(
        wrapFluxApp(child: const AppShell(), overrides: bootstrap.overrides()),
      );
      await tester.pumpAndSettle();
      expect(find.text('双栏布局（600–1099）'), findsOneWidget);
      expect(find.text('正文区'), findsNothing);

      await setSurfaceSize(tester, const Size(1200, 900));
      await tester.pumpAndSettle();
      expect(find.text('三栏布局（≥1100）'), findsOneWidget);
      expect(find.text('正文区'), findsOneWidget);
    });
  });

  group('占位与降级', () {
    testWidgets('占位页明确标注占位与计划任务，不假装有数据', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      await setSurfaceSize(tester, const Size(1280, 900));

      await tester.pumpWidget(
        wrapFluxApp(child: const AppShell(), overrides: bootstrap.overrides()),
      );
      await tester.pumpAndSettle();

      expect(find.text('占位'), findsWidgets);
      expect(find.textContaining('T036–T040'), findsWidgets);
    });

    testWidgets('数据库不可用时显示降级说明', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap(degraded: true);
      addTearDown(bootstrap.dispose);
      await setSurfaceSize(tester, const Size(1280, 900));

      await tester.pumpWidget(
        wrapFluxApp(child: const AppShell(), overrides: bootstrap.overrides()),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('本地数据库打不开'), findsOneWidget);
    });

    testWidgets('正常启动不显示降级说明', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      await setSurfaceSize(tester, const Size(1280, 900));

      await tester.pumpWidget(
        wrapFluxApp(child: const AppShell(), overrides: bootstrap.overrides()),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('本地数据库打不开'), findsNothing);
    });
  });
}
