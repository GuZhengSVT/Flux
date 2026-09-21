// OPML 页 golden（T015：浅深两套主题各一张）。
//
// 为什么值得入库：导入预览是一张**逐行明细**的清单（序号 + 名称 + 地址 + 状态徽标），
// 最容易出现的不是崩溃而是「一眼看不出但确实错」的东西——序号列与名称列挤在一起、
// 状态徽标与正文同色导致读不出状态、深色下分组提示消失。golden 把整屏钉住，
// token / 排版回归会以像素差异暴露。
//
// 更新方式：flutter test --update-goldens test/features/feeds/golden/opml_page_golden_test.dart
// 更新前必须人工确认截图符合架构第 7 节，而不是「跑一下让它变成绿的」。
//
// 注意：测试环境使用 Ahem 字体（方块字形），因此这里断言的是**布局与配色结构**，
// 不是文案本身；文案正确性由 l10n 与用例层测试负责。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/feeds/presentation/opml_controller.dart';
import 'package:flux/features/feeds/presentation/opml_page.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/feed_catalog_store.dart';

import '../../../app/test_harness.dart';

void main() {
  late TestBootstrap bootstrap;
  late AppDatabase db;
  late DriftFeedCatalogStore catalog;

  setUp(() async {
    bootstrap = TestBootstrap();
    db = bootstrap.database;
    await db.customSelect('SELECT 1').get();
    catalog = DriftFeedCatalogStore(db);
  });
  tearDown(() async => bootstrap.dispose());

  Future<void> pump(WidgetTester tester, {required ThemeMode mode}) async {
    await setSurfaceSize(tester, const Size(900, 900));
    await tester.pumpWidget(
      wrapFluxApp(
        child: const OpmlPage(),
        overrides: bootstrap.overrides(),
        themeMode: mode,
        localeOverride: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('OPML 页 golden', () {
    testWidgets('浅色：空态（导入区 + 分组策略 + 导出区）', (WidgetTester tester) async {
      await pump(tester, mode: ThemeMode.light);

      await expectLater(
        find.byType(OpmlPage),
        matchesGoldenFile('opml_page_light_en.png'),
      );
    });

    testWidgets('深色：同一布局的层次与对比度', (WidgetTester tester) async {
      await pump(tester, mode: ThemeMode.dark);

      await expectLater(
        find.byType(OpmlPage),
        matchesGoldenFile('opml_page_dark_en.png'),
      );
    });

    testWidgets('浅色：有预览明细（含重复、无效与分组提示）', (WidgetTester tester) async {
      // 先落一份已有订阅，让预览里出现「重复」；文件里再带上无效项与分组，
      // 三种状态各出现一次，版式差异才看得出来。
      await catalog.createFeed(
        const FeedInsert(
          syncId: 'feed.dup',
          normalizedUrl: 'https://feeds.example.com/dup.xml',
          name: 'Already Subscribed',
        ),
      );
      const String document = '''<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0"><head><title>My Feeds</title></head><body>
  <outline text="Tech">
    <outline type="rss" text="New Feed" xmlUrl="https://feeds.example.com/new.xml"/>
    <outline type="rss" text="Already Subscribed" xmlUrl="https://feeds.example.com/dup.xml"/>
    <outline type="rss" text="Broken" xmlUrl="not-a-url"/>
  </outline>
</body></opml>''';

      await setSurfaceSize(tester, const Size(900, 900));
      await tester.pumpWidget(
        wrapFluxApp(
          child: const OpmlPage(),
          overrides: bootstrap.overrides(),
          localeOverride: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      final BuildContext context = tester.element(find.byType(OpmlPage));
      await tester.runAsync(
        () =>
            ProviderScope.containerOf(context)
                .read(opmlImportControllerProvider.notifier)
                .previewDocument(document, fileName: 'my-feeds.opml'),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(OpmlPage),
        matchesGoldenFile('opml_page_preview_light_en.png'),
      );
    });
  });
}
