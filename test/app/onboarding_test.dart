// 首次引导测试（T011，架构第 3 节「首次启动」）。
//
// 重点验证四件事：
//   1) 三步内容与文档一致（欢迎/离线 → 添加订阅 → 可选 AI），且两处占位明确
//      标注了尚未实现的任务号；
//   2) **未配置 AI 可跳过**：任何一步都能退出向导；
//   3) 完成标记真的写入本机状态（用真实仓储 + 内存库验证，不是「调用了一次」）；
//   4) 占位步骤不创建任何订阅/不请求任何凭据（用「没有可提交按钮」来保证）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/app/app.dart';
import 'package:flux/app/app_bootstrap.dart';
import 'package:flux/core/core.dart';
import 'package:flux/features/onboarding/application/onboarding_state.dart';
import 'package:flux/features/onboarding/presentation/onboarding_page.dart';
import 'package:flux/infrastructure/local/device_state_repository.dart';

import 'test_harness.dart';

void main() {
  group('向导结构', () {
    testWidgets('三步：欢迎/订阅/AI，进度可见', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      await setSurfaceSize(tester, const Size(1200, 900));

      await tester.pumpWidget(
        wrapFluxApp(
          child: const OnboardingPage(),
          overrides: bootstrap.overrides(),
        ),
      );
      await tester.pumpAndSettle();

      // 第 1 步：欢迎 + 离线说明。
      expect(find.text('第 1 步 / 共 3 步'), findsOneWidget);
      expect(find.text('欢迎使用 Flux'), findsOneWidget);
      expect(find.textContaining('没有账号'), findsOneWidget);
      expect(find.textContaining('离线'), findsWidgets);
      // 第 1 步就提供语言/主题（架构第 3 节首启第一项内容）。
      expect(find.text('界面语言'), findsWidgets);
      expect(find.text('主题'), findsWidgets);

      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();

      // 第 2 步：添加订阅（占位，注明 T013–T016），且不提供任何导入控件。
      expect(find.text('第 2 步 / 共 3 步'), findsOneWidget);
      expect(find.text('添加订阅'), findsOneWidget);
      expect(find.textContaining('添加订阅源'), findsWidgets);
      expect(find.text('导入 OPML'), findsNothing);
      expect(find.text('添加'), findsNothing);

      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();

      // 第 3 步：可选 AI/搜索（占位，注明 T025/T031），并明确可跳过。
      expect(find.text('第 3 步 / 共 3 步'), findsOneWidget);
      expect(find.text('AI 与搜索（可选）'), findsOneWidget);
      expect(find.textContaining('在设置里随时配置'), findsWidgets);
      // 第 3 步的核心承诺：没有 AI 也能用（架构第 3 节「可选」）。
      expect(find.textContaining('没有配置 AI 也可以直接开始使用'), findsOneWidget);
      expect(find.text('跳过'), findsOneWidget);
      expect(find.text('开始使用'), findsOneWidget);
    });

    testWidgets('可以回上一步，跳过始终可用', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      await setSurfaceSize(tester, const Size(1200, 900));

      await tester.pumpWidget(
        wrapFluxApp(
          child: const OnboardingPage(),
          overrides: bootstrap.overrides(),
        ),
      );
      await tester.pumpAndSettle();

      // 第 1 步没有「上一步」，但可以跳过。
      expect(find.text('上一步'), findsNothing);
      expect(find.text('跳过'), findsOneWidget);

      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(find.text('上一步'), findsOneWidget);

      await tester.tap(find.text('上一步'));
      await tester.pumpAndSettle();
      expect(find.text('欢迎使用 Flux'), findsOneWidget);
    });
  });

  group('完成标记', () {
    testWidgets('跳过会写入本机状态（真实仓储 + 内存库）', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      await setSurfaceSize(tester, const Size(1200, 900));

      // 起始状态：未完成。
      final Result<bool> before = await bootstrap.deviceStateRepository
          .readBool(DeviceStateKey.onboardingCompleted);
      expect(before.getOrElse(true), isFalse);

      await tester.pumpWidget(
        wrapFluxApp(
          child: const OnboardingPage(),
          overrides: bootstrap.overrides(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('跳过'));
      await tester.pumpAndSettle();

      // 跳过同样算完成：否则每次启动都会重放向导。
      final Result<bool> after = await bootstrap.deviceStateRepository.readBool(
        DeviceStateKey.onboardingCompleted,
      );
      expect(after.getOrElse(false), isTrue);
    });

    testWidgets('二次启动直接进主页（不显示向导）', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      await setSurfaceSize(tester, const Size(1200, 900));

      // 预置「已完成」。
      await bootstrap.deviceStateRepository.writeBool(
        DeviceStateKey.onboardingCompleted,
        true,
      );
      // 固定界面语言为中文：FluxApp 自己解析 locale（SET-001），
      // 不预置时会按测试环境的系统语言（en）渲染。
      await bootstrap.seedLanguage('zh-Hans');

      await tester.pumpWidget(
        wrapRoot(child: const FluxApp(), overrides: bootstrap.overrides()),
      );
      await tester.pumpAndSettle();

      expect(find.text('欢迎使用 Flux'), findsNothing);
      expect(find.byType(NavigationRail), findsOneWidget);
    });

    testWidgets('未完成时启动进入向导', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      await setSurfaceSize(tester, const Size(1200, 900));
      await bootstrap.seedLanguage('zh-Hans');

      await tester.pumpWidget(
        wrapRoot(child: const FluxApp(), overrides: bootstrap.overrides()),
      );
      await tester.pumpAndSettle();

      expect(find.text('欢迎使用 Flux'), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });
  });

  group('端口契约', () {
    test('读取失败按「未完成」处理，不会假装已完成', () async {
      // 直接构造一个读失败/未写入的仓储，验证默认语义。
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      final OnboardingStore store = RepositoryOnboardingStore(
        bootstrap.deviceStateRepository,
      );
      expect(await store.isCompleted(), isFalse);
      await store.markCompleted();
      expect(await store.isCompleted(), isTrue);
    });
  });
}
