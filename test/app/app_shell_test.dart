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
import 'package:flux/ui/ui.dart';

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

    testWidgets('导航图标是 T012 的原创 SVG，不再是 Material 占位图标', (
      WidgetTester tester,
    ) async {
      // T011 用 Material 内置图标占位并注明「T012 落地时替换」。这条断言把交接
      // 钉住：若有人退回到 IconData，原创图标集就会悄悄从界面上消失，而
      // test/ui/flux_icons_test.dart 仍然全绿（那只检查资源文件，不看谁在用）。
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      await setSurfaceSize(tester, const Size(1280, 900));

      await tester.pumpWidget(
        wrapFluxApp(child: const AppShell(), overrides: bootstrap.overrides()),
      );
      await tester.pumpAndSettle();

      // 侧边导航里恰好有 3 个图标位（每个去向的 icon 与 selectedIcon 共用同一
      // 个字形的两个 SvgPicture，因此这里按「至少三个」断言而不写死数量）。
      expect(find.byType(FluxSvgIcon), findsAtLeast(3));

      for (final AppDestination destination in appDestinations) {
        expect(
          destination.icon,
          isA<FluxIcon>(),
          reason: '去向 \${destination.name} 应使用原创图标',
        );
      }
      // 三个去向必须是三个不同图标，否则导航无法区分。
      expect(
        appDestinations.map((AppDestination d) => d.icon).toSet(),
        hasLength(3),
      );
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

      // 初始去向为今日新闻：T038 起它是真实页面，没有生成过任何版本时显示
      // 「这一天还没有新闻」空态（不再有「属 T036–T040」的占位说明）。
      expect(find.text('这一天还没有新闻'), findsOneWidget);

      // 切到 RSS 阅读：显示「无订阅」空态（架构第 7 节要求分别提示）。
      await tester.tap(find.text('RSS 阅读').first);
      await tester.pumpAndSettle();
      // T016 起该去向不再是纯占位页：它有真实的刷新按钮与真实未读计数，
      // 但明确说明文章列表属 T017（不画一个看起来能用的假列表）。
      expect(find.text('刷新'), findsOneWidget);
      // T017 起它是完整的阅读页：有筛选入口，且空态按「有没有订阅」区分——
      // 这里数据库里还没有任何订阅，因此显示的是引导添加订阅的那一条。
      expect(find.text('未读'), findsWidgets);
      expect(find.text('还没有订阅'), findsOneWidget);

      // 切到「我的」：进入真正的设置页（T011 已生效的部分）。
      await tester.tap(find.text('我的').first);
      await tester.pumpAndSettle();
      expect(find.text('界面语言'), findsWidgets);
    });
  });

  group('响应式栏位（架构第 7 节）', () {
    // T038 起三个去向都是真实页面，「壳层占位页」与它的 1/2/3 栏占位面板已删除
    // （界面上写着「占位、无数据」而下面其实是能用的页面，比没有占位更糟）。
    // 断点规则本身仍由 shell_layout.dart 承载，并由 shell_layout_test.dart 逐点
    // 钉住 599/600 与 1099/1100；这里改为断言「真实页面在窄/宽窗下都能渲染」。
    testWidgets('窄窗（<600）与宽窗（>=1100）都能渲染真实页面', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);

      for (final double width in <double>[520, 800, 1400]) {
        await setSurfaceSize(tester, Size(width, 900));
        await tester.pumpWidget(
          wrapFluxApp(
            child: const AppShell(),
            overrides: bootstrap.overrides(),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('这一天还没有新闻'),
          findsOneWidget,
          reason: 'width=$width 时应渲染今日页空态',
        );
        expect(find.text('占位'), findsNothing, reason: '占位面板已删除');
      }
    });
  });

  group('降级', () {
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
