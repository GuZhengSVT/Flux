// 大字号与窄窗回归 golden（T049，架构第 7 节「大字号允许增高，不截断操作控件」）。
//
// 为什么值得入库：这两类回归的共同特点是**不会崩、也不报错**——字号放大后卡片挤到
// 只剩下标题的一半、窄窗下操作控件被压出可视区，都只是「看起来不对」。断言能测
// 「没抛溢出异常」，测不出「控件还在不在该在的位置」；像素比对才能。
//
// 更新方式：flutter test --update-goldens test/features/articles/golden/a11y_regression_golden_test.dart
// 更新前必须人工确认：大字号下三态与收藏仍完整可见、窄窗下正文与操作控件都不被裁切。
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
    feedId = (await DriftFeedCatalogStore(db).createFeed(
      const FeedInsert(
        syncId: 'feed.a11y',
        normalizedUrl: 'https://a11y.example.com/feed.xml',
        name: 'A11y Feed',
      ),
    )).unwrap().id;
    final List<(String, ReadingState, bool)> rows =
        <(String, ReadingState, bool)>[
          (
            'Unread article with a headline long enough to wrap',
            ReadingState.unread,
            false,
          ),
          ('Read article', ReadingState.read, true),
          ('Read later article', ReadingState.later, false),
        ];
    for (final (String title, ReadingState state, bool favorite) in rows) {
      await db
          .into(db.articles)
          .insert(
            ArticlesCompanion.insert(
              feedId: Value<int?>(feedId),
              title: title,
              identityBasis: IdentityBasis.guid,
              guid: Value<String?>('guid-$title'),
              guidPresent: const Value<bool>(true),
              summary: const Value<String?>('Summary line for the card.'),
              publishedAt: Value<DateTime?>(DateTime.utc(2026, 9, 20, 12)),
              fetchedAt: Value<DateTime>(DateTime.utc(2026, 9, 20, 12)),
              readingState: Value<ReadingState>(state),
              favorite: Value<bool>(favorite),
            ),
          );
    }
  });

  tearDown(() async => bootstrap.dispose());

  Future<void> pump(
    WidgetTester tester, {
    required Size size,
    required TextScaler textScaler,
  }) async {
    await setSurfaceSize(tester, size);
    await tester.pumpWidget(
      wrapFluxApp(
        child: const Scaffold(body: ReadingPage()),
        overrides: bootstrap.overrides(),
        localeOverride: const Locale('en'),
        textScaler: textScaler,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('大字号（SET-006 上限方向）列表', (WidgetTester tester) async {
    await pump(
      tester,
      size: const Size(900, 800),
      textScaler: const TextScaler.linear(1.6),
    );
    await expectLater(
      find.byType(ReadingPage),
      matchesGoldenFile('a11y_large_text_light_en.png'),
    );
  });

  testWidgets('窄窗 599 单栏', (WidgetTester tester) async {
    await pump(
      tester,
      size: const Size(599, 800),
      textScaler: TextScaler.noScaling,
    );
    await expectLater(
      find.byType(ReadingPage),
      matchesGoldenFile('a11y_narrow_599_light_en.png'),
    );
  });
}
