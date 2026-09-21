// 阅读页 golden（T017：浅深两套主题各一张）。
//
// 为什么值得入库：本页是**第一个真正渲染文章数据的列表**，而它最容易出的错不是崩溃，
// 是「一眼看不出但确实错」的东西——两行卡片挤在一起、来源与时间同色读不出层次、
// 收藏星形与三态图标在深色底上看不清、筛选条把标题挤出可视区。golden 把整屏钉住，
// token 与排版回归会以像素差异暴露。
//
// 更新方式：flutter test --update-goldens test/features/articles/golden/reading_page_golden_test.dart
// 更新前必须人工确认截图符合架构第 7 节，而不是「跑一下让它变成绿的」。
//
// 注意：测试环境使用 Ahem 字体（方块字形），因此这里断言的是**布局与配色结构**，
// 不是文案本身；文案正确性由 reading_page_test 与 l10n 测试负责。
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/articles/presentation/reading_page.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/feed_catalog_store.dart';

import '../../../app/test_harness.dart';

void main() {
  late TestBootstrap bootstrap;
  late AppDatabase db;
  late int feedId;

  setUp(() async {
    bootstrap = TestBootstrap();
    db = bootstrap.database;
    await db.customSelect('SELECT 1').get();
    final DriftFeedCatalogStore catalog = DriftFeedCatalogStore(db);
    feedId = (await catalog.createFeed(
      const FeedInsert(
        syncId: 'feed.a',
        normalizedUrl: 'https://a.example.com/feed.xml',
        name: 'Example Blog',
      ),
    )).unwrap().id;
    await catalog.createFeed(
      const FeedInsert(
        syncId: 'feed.b',
        normalizedUrl: 'https://b.example.com/feed.xml',
        name: 'Another Feed',
      ),
    );

    // 覆盖四种可见状态：未读、已读、稍后读、收藏（含一节没有发布时间的）。
    final List<(String, ReadingState, bool, bool)> rows =
        <(String, ReadingState, bool, bool)>[
          (
            'Unread article with a longer headline',
            ReadingState.unread,
            false,
            false,
          ),
          ('Read article', ReadingState.read, false, false),
          ('Read later article', ReadingState.later, false, false),
          ('Favorited article', ReadingState.unread, true, false),
          ('Article without a publish date', ReadingState.unread, false, true),
        ];
    for (final (String title, ReadingState state, bool favorite, bool undated)
        in rows) {
      await db
          .into(db.articles)
          .insert(
            ArticlesCompanion.insert(
              feedId: feedId,
              title: title,
              identityBasis: IdentityBasis.guid,
              guid: Value<String?>('guid-$title'),
              guidPresent: const Value<bool>(true),
              summary: const Value<String?>('Summary line for the card.'),
              publishedAt: Value<DateTime?>(
                undated ? null : DateTime.utc(2026, 9, 20, 12),
              ),
              fetchedAt: Value<DateTime>(DateTime.utc(2026, 9, 20, 12)),
              readingState: Value<ReadingState>(state),
              favorite: Value<bool>(favorite),
            ),
          );
    }
  });

  tearDown(() async => bootstrap.dispose());

  Future<void> pump(WidgetTester tester, {required ThemeMode mode}) async {
    await setSurfaceSize(tester, const Size(900, 700));
    await tester.pumpWidget(
      wrapFluxApp(
        child: const Scaffold(body: ReadingPage()),
        overrides: bootstrap.overrides(),
        themeMode: mode,
        localeOverride: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('阅读页 golden', () {
    testWidgets('浅色', (WidgetTester tester) async {
      await pump(tester, mode: ThemeMode.light);
      await expectLater(
        find.byType(ReadingPage),
        matchesGoldenFile('reading_page_light_en.png'),
      );
    });

    testWidgets('深色', (WidgetTester tester) async {
      await pump(tester, mode: ThemeMode.dark);
      await expectLater(
        find.byType(ReadingPage),
        matchesGoldenFile('reading_page_dark_en.png'),
      );
    });

    testWidgets('批量模式（选择与范围可见）', (WidgetTester tester) async {
      await pump(tester, mode: ThemeMode.light);
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(ReadingPage),
        matchesGoldenFile('reading_page_batch_light_en.png'),
      );
    });
  });
}
