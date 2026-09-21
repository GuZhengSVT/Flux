// T031：搜索服务页组件测试（设置入口 → 列表 → 表单 → 发送确认）。
//
// 这一组用例盯的是「界面会不会撒谎」这一类问题：
//   - Key 输入框始终遮蔽，界面不出现明文（SET-039 遮盖）；
//   - **没有凭据时测试按钮是禁用的**（Tavily/Brave），SearXNG 则可用；
//   - 测试按钮先弹费用与数据发送确认，取消则**一个请求都不发**；
//   - 删除前先弹确认，取消则记录仍在；
//   - 未配置时明确说明还没有配置（不是空白页）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/domain/search_protocol.dart';
import 'package:flux/features/ai/domain/search_provider.dart';
import 'package:flux/features/ai/domain/search_result.dart';
import 'package:flux/features/ai/domain/search_service.dart';
import 'package:flux/features/ai/domain/search_service_store.dart';
import 'package:flux/features/ai/presentation/search_services_page.dart';
import 'package:flux/features/settings/presentation/settings_page.dart';
import 'package:flux/infrastructure/local/search_service_store.dart';

import '../../app/test_harness.dart';

/// 记录检索次数的假工厂（页面测试只需要「有没有发出去」这一个事实）。
final class _PageFactory implements SearchProviderFactory {
  int searches = 0;

  @override
  Result<SearchProvider> create({
    required SearchProtocol protocol,
    required String baseUrl,
    required String apiKey,
    Duration timeout = const Duration(seconds: 20),
    int maxResults = 10,
    bool allowPrivateEndpoint = false,
  }) => Ok<SearchProvider>(_PageProvider(this, protocol));
}

final class _PageProvider implements SearchProvider {
  _PageProvider(this._factory, this._protocol);

  final _PageFactory _factory;
  final SearchProtocol _protocol;

  @override
  String get providerId => _protocol.id;

  @override
  Future<Result<SearchResponse>> search(SearchRequest query) async {
    _factory.searches++;
    return Ok<SearchResponse>(
      SearchResponse(
        provider: _protocol.id,
        query: query.text,
        results: const <SearchResult>[],
      ),
    );
  }
}

void main() {
  Future<SearchService> seed(
    TestBootstrap bootstrap, {
    String label = 'tavily-main',
    SearchProtocol protocol = SearchProtocol.tavily,
    String baseUrl = 'https://api.example.com',
  }) async {
    final SearchServiceStore store = DriftSearchServiceStore(
      bootstrap.database,
    );
    return (await store.insert(
      SearchService(label: label, protocol: protocol, baseUrl: baseUrl),
    )).unwrap();
  }

  testWidgets('设置页有搜索服务入口，点击进入搜索服务页', (WidgetTester tester) async {
    final TestBootstrap bootstrap = TestBootstrap();
    addTearDown(bootstrap.dispose);
    await setSurfaceSize(tester, const Size(1200, 1800));

    await tester.pumpWidget(
      wrapFluxApp(
        child: const Scaffold(body: SettingsPage()),
        overrides: bootstrap.overrides(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('搜索服务'), findsWidgets);
    await tester.tap(find.text('搜索服务').first);
    await tester.pumpAndSettle();
    expect(find.byType(SearchServicesPage), findsOneWidget);
  });

  testWidgets('未配置时明确说明还没有配置（不是空白页）', (WidgetTester tester) async {
    final TestBootstrap bootstrap = TestBootstrap();
    addTearDown(bootstrap.dispose);

    await tester.pumpWidget(
      wrapFluxApp(
        child: const SearchServicesPage(),
        overrides: bootstrap.overrides(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('还没有配置任何搜索服务'), findsOneWidget);
  });

  testWidgets('列表显示协议、端点与预算；Tavily 缺凭据时测试按钮禁用', (WidgetTester tester) async {
    final TestBootstrap bootstrap = TestBootstrap();
    addTearDown(bootstrap.dispose);
    await seed(bootstrap);
    await setSurfaceSize(tester, const Size(1200, 1400));

    await tester.pumpWidget(
      wrapFluxApp(
        child: const SearchServicesPage(),
        overrides: bootstrap.overrides(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('tavily-main'), findsOneWidget);
    expect(find.text('Tavily'), findsOneWidget);
    expect(find.text('https://api.example.com/search'), findsOneWidget);
    expect(find.textContaining('尚未配置凭据'), findsOneWidget);

    // 缺凭据 → 禁用：找不到可点的测试按钮。
    final Finder testButton = find.widgetWithText(TextButton, '测试');
    expect(testButton, findsOneWidget);
    expect(
      tester.widget<TextButton>(testButton).onPressed,
      isNull,
      reason: 'Tavily 没有 Key 必然 401，按钮必须禁用而不是让用户白点一次',
    );
  });

  testWidgets('SearXNG 不要求凭据：测试按钮可用', (WidgetTester tester) async {
    final TestBootstrap bootstrap = TestBootstrap();
    addTearDown(bootstrap.dispose);
    await seed(
      bootstrap,
      label: 'self-hosted',
      protocol: SearchProtocol.searxng,
      baseUrl: 'https://search.example.com',
    );
    await setSurfaceSize(tester, const Size(1200, 1400));

    await tester.pumpWidget(
      wrapFluxApp(
        child: const SearchServicesPage(),
        overrides: bootstrap.overrides(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('SearXNG（自建实例）'), findsOneWidget);
    final Finder testButton = find.widgetWithText(TextButton, '测试');
    expect(tester.widget<TextButton>(testButton).onPressed, isNotNull);
  });

  testWidgets('测试前弹费用与数据发送确认；取消则一个请求都不发', (WidgetTester tester) async {
    final TestBootstrap bootstrap = TestBootstrap();
    addTearDown(bootstrap.dispose);
    final _PageFactory factory = _PageFactory();
    await seed(bootstrap);
    await setSurfaceSize(tester, const Size(1200, 1400));

    await tester.pumpWidget(
      wrapFluxApp(
        child: const SearchServicesPage(),
        overrides: bootstrap.overrides(searchProviderFactory: factory),
      ),
    );
    await tester.pumpAndSettle();

    // 先在对话框里保存凭据，让测试按钮可用。
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'API Key / 实例认证'),
      'fixture-key',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    // 关闭对话框（取消按钮）。
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    final Finder testButton = find.widgetWithText(TextButton, '测试');
    expect(
      tester.widget<TextButton>(testButton).onPressed,
      isNotNull,
      reason: '保存凭据后测试按钮应可用',
    );
    await tester.tap(testButton);
    await tester.pumpAndSettle();

    // 确认框出现（标题），内容说明端点与费用。
    expect(find.text('发送一次真实检索？'), findsOneWidget);
    expect(find.textContaining('https://api.example.com/search'), findsWidgets);

    // 取消 → 不发请求。
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    expect(factory.searches, 0, reason: '取消确认后不得发出任何检索请求');
  });

  testWidgets('删除前先弹确认；取消则记录仍在', (WidgetTester tester) async {
    final TestBootstrap bootstrap = TestBootstrap();
    addTearDown(bootstrap.dispose);
    await seed(bootstrap);
    await setSurfaceSize(tester, const Size(1200, 1400));

    await tester.pumpWidget(
      wrapFluxApp(
        child: const SearchServicesPage(),
        overrides: bootstrap.overrides(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.textContaining('删除搜索服务'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    // 记录仍在（取消没有删掉任何东西）。
    expect(find.text('tavily-main'), findsOneWidget);
    final List<SearchService> remaining = (await DriftSearchServiceStore(
      bootstrap.database,
    ).loadAll()).unwrap();
    expect(remaining, hasLength(1));
  });

  testWidgets('Key 输入框始终遮蔽（SET-039 遮盖）', (WidgetTester tester) async {
    final TestBootstrap bootstrap = TestBootstrap();
    addTearDown(bootstrap.dispose);
    await seed(bootstrap);

    await tester.pumpWidget(
      wrapFluxApp(
        child: const SearchServicesPage(),
        overrides: bootstrap.overrides(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();

    final TextField keyField = tester.widget<TextField>(
      find.widgetWithText(TextField, 'API Key / 实例认证'),
    );
    expect(keyField.obscureText, isTrue, reason: '凭据输入必须遮蔽');
  });

  testWidgets('新建表单：协议下拉切换会替换默认端点，但不代填 Key', (WidgetTester tester) async {
    final TestBootstrap bootstrap = TestBootstrap();
    addTearDown(bootstrap.dispose);
    await setSurfaceSize(tester, const Size(1200, 1400));

    await tester.pumpWidget(
      wrapFluxApp(
        child: const SearchServicesPage(),
        overrides: bootstrap.overrides(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加搜索服务'));
    await tester.pumpAndSettle();

    // 默认是 Tavily 的预设端点。
    expect(find.text('https://api.tavily.com'), findsOneWidget);

    // 切到 Brave：端点应替换为 Brave 的默认值。
    await tester.tap(find.byType(DropdownButtonFormField<SearchProtocol>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Brave Search').last);
    await tester.pumpAndSettle();
    expect(find.text('https://api.search.brave.com'), findsOneWidget);
    // Key 输入框仍然为空（不代填）。
    final TextField keyField = tester.widget<TextField>(
      find.widgetWithText(TextField, 'API Key / 实例认证'),
    );
    expect(keyField.controller!.text, isEmpty);
  });
}
