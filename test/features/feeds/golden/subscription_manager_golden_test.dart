// 订阅管理页 golden（T014 验收要求：浅深两套主题各一张）。
//
// 为什么值得入库：订阅管理页是本项目第一个「有真实数据、有分组归属、有徽标」的页面，
// 最容易出现的不是崩溃而是一眼看不出但确实错的东西——分组卡片与订阅行的层次糊在
// 一起、加精徽标与分组置顶徽标看起来像同一件事、深色下分隔线消失。golden 把整屏
// 渲染结果钉住，任何 token / 排版回归都会以像素差异暴露。
//
// 更新方式：flutter test --update-goldens test/features/feeds/golden/subscription_manager_golden_test.dart
// 更新前必须人工确认截图符合架构第 7 节，而不是「跑一下让它变成绿的」。
//
// 注意：golden 对字体渲染敏感。测试环境使用 Ahem 字体（方块字形），因此这里断言的是
// **布局与配色结构**，不是文案本身；文案正确性由 subscription_manager_page_test 负责。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/feeds/presentation/subscription_manager_page.dart';
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

  /// 造一份有分组、有加精、有停用、有未读的数据：空页面看不出版式问题。
  Future<void> seed() async {
    final GroupRecord tech = (await catalog.createGroup(
      syncId: 'group.tech',
      name: 'Tech',
      sortOrder: 1,
    )).unwrap();
    final GroupRecord pinned = (await catalog.createGroup(
      syncId: 'group.pinned',
      name: 'Pinned',
      sortOrder: 2,
    )).unwrap();
    await catalog.setGroupPinned(groupId: pinned.id, pinned: true);

    await catalog.createFeed(
      FeedInsert(
        syncId: 'feed.a',
        normalizedUrl: 'https://a.example.com/feed.xml',
        name: 'Example Blog',
        groupId: tech.id,
      ),
    );
    final FeedRecord featured = (await catalog.createFeed(
      FeedInsert(
        syncId: 'feed.b',
        normalizedUrl: 'https://b.example.com/feed.xml',
        name: 'Featured Feed',
        groupId: tech.id,
      ),
    )).unwrap();
    await catalog.setFeedFavorite(feedId: featured.id, favorite: true);

    final FeedRecord paused = (await catalog.createFeed(
      FeedInsert(
        syncId: 'feed.c',
        normalizedUrl: 'https://c.example.com/feed.xml',
        name: 'Paused Feed',
        groupId: pinned.id,
      ),
    )).unwrap();
    await catalog.setFeedEnabled(feedId: paused.id, enabled: false);
  }

  Future<void> pump(WidgetTester tester, {required ThemeMode mode}) async {
    await setSurfaceSize(tester, const Size(900, 700));
    await tester.pumpWidget(
      wrapFluxApp(
        child: const SubscriptionManagerPage(),
        overrides: bootstrap.overrides(),
        themeMode: mode,
        localeOverride: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('订阅管理页 golden', () {
    testWidgets('浅色：分组、置顶、加精与停用徽标', (WidgetTester tester) async {
      await seed();
      await pump(tester, mode: ThemeMode.light);

      await expectLater(
        find.byType(SubscriptionManagerPage),
        matchesGoldenFile('subscription_manager_light_en.png'),
      );
    });

    testWidgets('深色：同一份数据的层次与对比度', (WidgetTester tester) async {
      await seed();
      await pump(tester, mode: ThemeMode.dark);

      await expectLater(
        find.byType(SubscriptionManagerPage),
        matchesGoldenFile('subscription_manager_dark_en.png'),
      );
    });
  });
}
