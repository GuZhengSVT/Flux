// T025：AI 服务页组件测试（设置入口 → 列表 → 表单 → 删除确认 → 费用确认）。
//
// 这一组用例盯的是「界面会不会撒谎」这一类问题：
//   - 未实现的协议在选项里就标注「适配器待实现」，而不是选完才发现；
//   - Key 输入框始终遮蔽，界面不出现明文（SET-031 遮盖）；
//   - 删除前先弹确认，取消则记录仍在；
//   - 测试按钮先弹费用确认，取消则**一个请求都不发**。
//
// 页面与断言共用同一个内存库与同一个凭据端口（bootstrap 的那一份），因此
// 「界面显示的状态」与「实际落库的状态」是同一份事实，不会出现测试自说自话。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/application/model_manager.dart';
import 'package:flux/features/ai/domain/ai_model.dart';
import 'package:flux/features/ai/domain/ai_protocol.dart';
import 'package:flux/features/ai/domain/ai_provider.dart';
import 'package:flux/features/ai/presentation/ai_services_page.dart';
import 'package:flux/features/settings/presentation/settings_page.dart';
import 'package:flux/infrastructure/local/ai_model_store.dart';
import 'package:flux/infrastructure/platform/ai_credential_adapter.dart';

import '../../features/ai/fake_ai_provider.dart';
import '../../app/test_harness.dart';

void main() {
  group('设置入口与页面骨架', () {
    testWidgets('设置页有 AI 服务入口，点击进入 AI 服务页', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      await setSurfaceSize(tester, const Size(1200, 1600));

      await tester.pumpWidget(
        wrapFluxApp(
          child: const Scaffold(body: SettingsPage()),
          overrides: bootstrap.overrides(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('AI 服务'), findsWidgets);
      await tester.tap(find.text('AI 服务').first);
      await tester.pumpAndSettle();
      expect(find.byType(AiServicesPage), findsOneWidget);
    });

    testWidgets('未配置模型时明确说明还没有配置（不是空白页）', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);

      await tester.pumpWidget(
        wrapFluxApp(
          child: const AiServicesPage(),
          overrides: bootstrap.overrides(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('还没有配置任何模型'), findsOneWidget);
      expect(find.textContaining('添加模型'), findsWidgets);
    });
  });

  group('模型表单（SET-030/031/032/033）', () {
    testWidgets('新增一条模型：保存后出现在列表并落库', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      final ModelManager manager = _managerFor(bootstrap);

      await tester.pumpWidget(
        wrapFluxApp(
          child: const AiServicesPage(),
          overrides: bootstrap.overrides(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('添加模型').first);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, '提供商别名'),
        'deepseek',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Base URL'),
        'https://api.deepseek.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, '模型 ID'),
        'deepseek-chat',
      );
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing, reason: '保存成功应关闭对话框');
      expect(find.text('deepseek'), findsOneWidget);
      expect(find.textContaining('deepseek-chat'), findsWidgets);
      expect(
        (await manager.loadModels()).unwrap().single.modelId,
        'deepseek-chat',
        reason: '界面保存必须真的落库',
      );
    });

    testWidgets('协议下拉把未实现的协议标注为待实现', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);

      await tester.pumpWidget(
        wrapFluxApp(
          child: const AiServicesPage(),
          overrides: bootstrap.overrides(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加模型').first);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<AiProtocol>));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('适配器待实现'),
        findsWidgets,
        reason: '「列出这个选项」不等于「真的能用」，必须在选项里就说清',
      );
    });

    testWidgets('空别名不提交：对话框保持打开、给出提示、不落库', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      final ModelManager manager = _managerFor(bootstrap);

      await tester.pumpWidget(
        wrapFluxApp(
          child: const AiServicesPage(),
          overrides: bootstrap.overrides(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加模型').first);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Base URL'),
        'https://api.deepseek.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, '模型 ID'),
        'deepseek-chat',
      );
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget, reason: '校验失败不应关闭对话框');
      expect(find.textContaining('别名'), findsWidgets);
      expect(
        (await manager.loadModels()).unwrap(),
        isEmpty,
        reason: '非法输入不得落库',
      );
    });

    testWidgets('Key 输入框始终遮蔽，界面不出现明文，并说明只进安全存储', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);

      await tester.pumpWidget(
        wrapFluxApp(
          child: const AiServicesPage(),
          overrides: bootstrap.overrides(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加模型').first);
      await tester.pumpAndSettle();

      expect(find.text('尚未配置'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, '替换 Key'),
        'sk-secret-value-for-test',
      );
      await tester.pump();
      // 注意：obscureText 的输入框内部仍然持有那段字符串，find.text 会匹配到
      // EditableText，因此这里只断言**渲染出的 Text 控件**里没有明文——
      // 那才是「用户能读到的界面」。
      expect(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is Text && widget.data == 'sk-secret-value-for-test',
        ),
        findsNothing,
      );
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, '替换 Key'))
            .obscureText,
        isTrue,
      );
      expect(find.textContaining('安全存储'), findsWidgets);
    });
  });

  group('列表操作', () {
    testWidgets('停用开关写库，且记录仍在列表里', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      final ModelManager manager = _managerFor(bootstrap);
      await manager.saveModel(_model(alias: 'deepseek'));

      await tester.pumpWidget(
        wrapFluxApp(
          child: const AiServicesPage(),
          overrides: bootstrap.overrides(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('deepseek'), findsOneWidget);

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      expect((await manager.loadModels()).unwrap().single.enabled, isFalse);
      expect(find.text('deepseek'), findsOneWidget, reason: '停用不是删除');
    });

    testWidgets('删除先弹确认；取消则记录仍在', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      final ModelManager manager = _managerFor(bootstrap);
      await manager.saveModel(_model(alias: 'deepseek'));

      await tester.pumpWidget(
        wrapFluxApp(
          child: const AiServicesPage(),
          overrides: bootstrap.overrides(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.textContaining('删除模型'), findsWidgets);
      expect(find.textContaining('API Key 不会被删除'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      expect(
        (await manager.loadModels()).unwrap(),
        hasLength(1),
        reason: '取消后不得删除',
      );
    });

    testWidgets('确认删除后记录消失', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      final ModelManager manager = _managerFor(bootstrap);
      await manager.saveModel(_model(alias: 'deepseek'));

      await tester.pumpWidget(
        wrapFluxApp(
          child: const AiServicesPage(),
          overrides: bootstrap.overrides(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('仍然删除'));
      await tester.pumpAndSettle();

      expect((await manager.loadModels()).unwrap(), isEmpty);
      expect(find.textContaining('还没有配置任何模型'), findsOneWidget);
    });

    testWidgets('上移按钮改变故障转移顺序并落库', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      final ModelManager manager = _managerFor(bootstrap);
      await manager.saveModel(_model(alias: 'first'));
      await manager.saveModel(_model(alias: 'second'));
      // 保存后回读取得真实 id，并把顺序固定成 first, second，便于断言。
      final List<AiModel> seeded = (await manager.loadModels()).unwrap();
      await manager.reorder(<int>[
        seeded.firstWhere((AiModel m) => m.alias == 'first').id!,
        seeded.firstWhere((AiModel m) => m.alias == 'second').id!,
      ]);

      await tester.pumpWidget(
        wrapFluxApp(
          child: const AiServicesPage(),
          overrides: bootstrap.overrides(),
        ),
      );
      await tester.pumpAndSettle();

      // 每张卡有两个排序按钮（上移、下移）；索引 1 是第二张卡的上移。
      await tester.tap(find.byIcon(Icons.arrow_upward).at(1));
      await tester.pumpAndSettle();

      expect(
        (await manager.loadModels()).unwrap().map((AiModel m) => m.alias),
        <String>['second', 'first'],
      );
    });
  });

  group('费用确认（SET-042 动作）', () {
    testWidgets('点测试先弹费用确认；取消则不发任何请求', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      final FakeAiProviderFactory factory = FakeAiProviderFactory();
      final ModelManager manager = _managerFor(bootstrap, factory: factory);
      await manager.saveModel(_model(alias: 'deepseek'));
      await manager.saveCredential('deepseek', 'sk-test');

      await tester.pumpWidget(
        wrapFluxApp(
          child: const AiServicesPage(),
          overrides: bootstrap.overrides(aiProviderFactory: factory),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('测试连接'));
      await tester.pumpAndSettle();

      expect(find.text('这次测试会产生费用'), findsOneWidget);
      expect(find.textContaining('64 token'), findsOneWidget);

      // 费用对话框里的取消按钮：用「在该对话框内查找」而不是全局查找，
      // 因为表单本身也有一个「取消」。
      await tester.tap(
        find.descendant(
          of: find.widgetWithText(AlertDialog, '这次测试会产生费用'),
          matching: find.widgetWithText(TextButton, '取消'),
        ),
      );
      await tester.pumpAndSettle();
      expect(factory.createdCount, 0, reason: '用户没有确认费用时一个请求都不能发');
    });

    testWidgets('确认后发一次请求并显示耗时与 token', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      final FakeAiProviderFactory factory = FakeAiProviderFactory();
      final ModelManager manager = _managerFor(bootstrap, factory: factory);
      await manager.saveModel(_model(alias: 'deepseek'));
      await manager.saveCredential('deepseek', 'sk-test');

      await tester.pumpWidget(
        wrapFluxApp(
          child: const AiServicesPage(),
          overrides: bootstrap.overrides(aiProviderFactory: factory),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('测试连接'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认并测试'));
      await tester.pumpAndSettle();

      expect(factory.createdCount, 1, reason: '确认后只发一次');
      expect(find.textContaining('测试成功'), findsOneWidget);
      expect(find.textContaining('输入 11'), findsOneWidget);
      expect(find.textContaining('输出 5'), findsOneWidget);
    });

    testWidgets('缺 Key 时说明尚未配置，而不是发一个必然失败的请求', (WidgetTester tester) async {
      final TestBootstrap bootstrap = TestBootstrap();
      addTearDown(bootstrap.dispose);
      final FakeAiProviderFactory factory = FakeAiProviderFactory();
      final ModelManager manager = _managerFor(bootstrap, factory: factory);
      await manager.saveModel(_model(alias: 'deepseek'));

      await tester.pumpWidget(
        wrapFluxApp(
          child: const AiServicesPage(),
          overrides: bootstrap.overrides(aiProviderFactory: factory),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('测试连接'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认并测试'));
      await tester.pumpAndSettle();

      expect(find.textContaining('尚未配置 API Key'), findsOneWidget);
      expect(factory.createdCount, 0);
    });
  });
}

/// 构造一条测试用模型记录。
AiModel _model({String alias = 'deepseek'}) => AiModel(
  alias: alias,
  protocol: AiProtocol.openAiChatCompletions,
  baseUrl: 'https://api.deepseek.com',
  modelId: 'deepseek-chat',
);

/// 与页面**共用同一个内存库与同一个凭据端口**的用例。
///
/// 只用于预置数据与读取断言；页面自身由 Riverpod 容器里的实例驱动，两者读写的是
/// 同一份数据，因此「界面显示的状态」与「断言读到的状态」是同一份事实。
ModelManager _managerFor(
  TestBootstrap bootstrap, {
  AiProviderFactory? factory,
}) => ModelManager(
  store: DriftAiModelStore(bootstrap.database),
  credentials: AiCredentialStoreAdapter(bootstrap.credentialStore),
  diagnostics: const NoopDiagnosticSink(),
  providerFactory: factory,
);
