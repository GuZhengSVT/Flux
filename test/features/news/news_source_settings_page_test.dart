// T036：新闻生成设置页的组件测试（设置入口 → 逐源三态 → 四个编辑器 → 固定协议 → 版本）。
//
// 这一组用例盯的是「界面会不会撒谎」这一类问题：
//   - **固定协议段只读展示**：它不是输入框，用户无从删除；
//   - **逐源开关是三态**（跟随/参与/不参与），写入的是 null/true/false 三种值；
//   - **高级覆盖模式下缺了必访站会立刻提示**（而不是保存后才发现）；
//   - **保存版本后列表里出现该版本**（可回退）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/news/presentation/news_source_settings_page.dart';
import 'package:flux/features/settings/presentation/settings_page.dart';
import 'package:flux/infrastructure/local/feed_catalog_store.dart';
import 'package:flux/infrastructure/local/news_source_config_store.dart';
import 'package:flux/infrastructure/local/database.dart';

import '../../app/test_harness.dart';

void main() {
  late TestBootstrap bootstrap;

  setUp(() async {
    bootstrap = TestBootstrap();
    await bootstrap.database.customSelect('SELECT 1').get();
  });

  tearDown(() async {
    await bootstrap.dispose();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await setSurfaceSize(tester, const Size(1200, 1200));
    await tester.pumpWidget(
      wrapFluxApp(
        overrides: bootstrap.overrides(),
        child: const NewsSourceSettingsPage(),
      ),
    );
    await tester.pumpAndSettle();
  }

  DriftNewsSourceConfigStore store() =>
      DriftNewsSourceConfigStore(bootstrap.database);

  testWidgets('设置页有「新闻生成」入口，点进去是这一页', (WidgetTester tester) async {
    await setSurfaceSize(tester, const Size(1200, 900));
    await tester.pumpWidget(
      wrapFluxApp(
        overrides: bootstrap.overrides(),
        child: const SettingsPage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('新闻生成'), findsOneWidget);
    await tester.tap(find.text('新闻生成'));
    await tester.pumpAndSettle();
    expect(find.byType(NewsSourceSettingsPage), findsOneWidget);
  });

  testWidgets('固定输出协议以只读文本展示，且不出现在任何可编辑输入框里', (WidgetTester tester) async {
    await pumpPage(tester);
    // 协议段在页面下方：先滚到它。
    await tester.scrollUntilVisible(
      find.textContaining('引用规则（不可更改）'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('引用规则（不可更改）'), findsWidgets);
    final Iterable<TextField> fields = tester.widgetList<TextField>(
      find.byType(TextField),
    );
    for (final TextField field in fields) {
      final String? text = field.controller?.text;
      expect(
        text ?? '',
        isNot(contains('引用规则')),
        reason: '固定协议段不得出现在任何可编辑输入框里',
      );
    }
  });

  testWidgets('逐源开关是三态：选「不参与新闻」写入 false 且不动订阅刷新', (WidgetTester tester) async {
    final int feedId =
        (await DriftFeedCatalogStore(bootstrap.database).createFeed(
          const FeedInsert(
            syncId: 'feed.page',
            normalizedUrl: 'https://page.example.com/feed.xml',
            name: '页面测试源',
          ),
        )).unwrap().id;
    await pumpPage(tester);
    expect(find.text('页面测试源'), findsOneWidget);
    expect(find.text('跟随订阅刷新'), findsOneWidget);

    await tester.tap(find.text('不参与新闻'));
    await tester.pumpAndSettle();

    final FeedRecord record = (await DriftFeedCatalogStore(
      bootstrap.database,
    ).findFeedById(feedId)).unwrap()!;
    expect(record.newsEnabled, isFalse);
    expect(record.enabled, isTrue, reason: '排除新闻不得关掉订阅刷新');
  });

  testWidgets('高级覆盖模式下缺必访站时立刻提示（不必等保存）', (WidgetTester tester) async {
    await bootstrap.database
        .into(bootstrap.database.newsRequiredSiteRecords)
        .insert(
          NewsRequiredSiteRecordsCompanion.insert(
            name: '必访甲站',
            url: 'https://required.example.com',
          ),
        );
    await pumpPage(tester);

    // 「高级覆盖」在页面下方（T040 新增的定时小节把它往下推了）：ListView 不构建
    // 屏外项，因此要先滚到它，否则查找会得到 0 个结果并看起来像界面错了。
    await tester.scrollUntilVisible(
      find.text('高级覆盖'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('高级覆盖'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('必访甲站'),
      findsWidgets,
      reason: '高级模式下缺了必访站必须立刻提示',
    );
  });

  testWidgets('三个列表编辑器各自独立（改关键词不动禁词）', (WidgetTester tester) async {
    await pumpPage(tester);
    expect(find.text('联网搜索关键词（SET-052）'), findsOneWidget);
    expect(find.text('禁止发送的查询词（SET-053）'), findsOneWidget);
    expect(find.text('排除的内容主题（SET-053）'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'AI 芯片');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(
      (await store().loadList(NewsListCategory.keywords)).unwrap(),
      <String>['AI 芯片'],
    );
    expect(
      (await store().loadList(NewsListCategory.blockedQueryTerms)).unwrap(),
      isEmpty,
      reason: '改关键词不得动禁词列表',
    );
  });

  testWidgets('保存为新版本后，版本列表里出现该版本', (WidgetTester tester) async {
    await pumpPage(tester);
    await tester.scrollUntilVisible(
      find.text('保存为新版本'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存为新版本'));
    await tester.pumpAndSettle();
    expect(find.textContaining('版本 1'), findsWidgets);
  });
}
