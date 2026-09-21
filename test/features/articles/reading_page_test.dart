// 阅读页组件测试（T017）。
//
// 断言的层次与 T014 的订阅管理页一致：**界面确实把状态画对了、确实把动作转发了**，
// 而规则本身由 article_state_test / batch_article_actions_test 用纯 Dart 验证。
// 这里额外覆盖三条只有组件层才看得见的边界：
//   - 未读筛选下打开正文（自动标已读）之后，那一行从不读列表里消失；
//   - 批量模式下两个状态控件变只读（避免「点一下同时改状态与勾选」）；
//   - 离线刷新给出「未发起刷新」而不是「刷新完成」。
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/articles/presentation/reading_page.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/feed_catalog_store.dart';
import 'package:flux/infrastructure/local/tables/article_tables.dart';
import 'package:flux/infrastructure/network/feed_fetcher.dart';
import 'package:flux/ui/ui.dart';

import '../../app/test_harness.dart';

const String _rss = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel>
  <title>测试源</title>
  <link>https://a.example.com/</link>
  <item>
    <title>刷新后来的一篇</title>
    <link>https://a.example.com/new</link>
    <guid isPermaLink="false">g-new</guid>
    <pubDate>Sun, 20 Sep 2026 23:15:00 GMT</pubDate>
    <description>摘要</description>
    <content:encoded xmlns:content="http://purl.org/rss/1.0/modules/content/">
      <![CDATA[<p>正文内容</p>]]>
    </content:encoded>
  </item>
</channel></rss>''';

http.Response _xml(String body) => http.Response.bytes(
  utf8.encode(body),
  200,
  headers: <String, String>{'content-type': 'application/xml; charset=utf-8'},
);

/// 网络状况替身。
final class _FakeNetwork implements NetworkConditionPort {
  const _FakeNetwork({this.offline = false});

  final bool offline;

  @override
  Future<bool> isMetered() async => false;

  @override
  Future<bool> isOffline() async => offline;
}

void main() {
  late TestBootstrap bootstrap;
  late AppDatabase db;
  late DriftFeedCatalogStore catalog;
  late int feedId;

  setUp(() async {
    bootstrap = TestBootstrap();
    db = bootstrap.database;
    await db.customSelect('SELECT 1').get();
    catalog = DriftFeedCatalogStore(db);
    feedId = (await catalog.createFeed(
      const FeedInsert(
        syncId: 'feed.a',
        normalizedUrl: 'https://a.example.com/feed.xml',
        name: '测试源',
      ),
    )).unwrap().id;
  });

  tearDown(() async => bootstrap.dispose());

  /// 直接落库一篇文章（避免每个用例都走一遍抓取）。
  Future<int> seedArticle(
    String title, {
    ReadingState state = ReadingState.unread,
    bool favorite = false,
    String? body,
    int minutesAgo = 0,
    bool noPublishedAt = false,
    BodyCompleteness completeness = BodyCompleteness.unknown,
  }) => db
      .into(db.articles)
      .insert(
        ArticlesCompanion.insert(
          feedId: Value<int?>(feedId),
          title: title,
          identityBasis: IdentityBasis.guid,
          guid: Value<String?>('guid-$title'),
          guidPresent: const Value<bool>(true),
          summary: Value<String?>('摘要：$title'),
          body: Value<String?>(body),
          publishedAt: Value<DateTime?>(
            noPublishedAt
                ? null
                : DateTime.utc(
                    2026,
                    9,
                    20,
                    12,
                  ).subtract(Duration(minutes: minutesAgo)),
          ),
          fetchedAt: Value<DateTime>(
            DateTime.utc(
              2026,
              9,
              20,
              12,
            ).subtract(Duration(minutes: minutesAgo)),
          ),
          readingState: Value<ReadingState>(state),
          favorite: Value<bool>(favorite),
          bodyCompleteness: Value<BodyCompleteness>(completeness),
        ),
      );

  Future<Article> read(int id) async => await (db.select(
    db.articles,
  )..where((Articles t) => t.id.equals(id))).getSingle();

  Future<void> pump(
    WidgetTester tester, {
    FeedFetcher? fetcher,
    NetworkConditionPort network = const _FakeNetwork(),
  }) async {
    await setSurfaceSize(tester, const Size(1100, 900));
    await tester.pumpWidget(
      wrapFluxApp(
        child: const Scaffold(body: ReadingPage()),
        overrides: bootstrap.overrides(
          feedFetcher:
              fetcher ??
              HttpFeedFetcher(
                client: MockClient((http.Request request) async => _xml(_rss)),
              ),
          networkConditions: network,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 让真实事件循环跑一段再回到伪时间线。
  ///
  /// 抓取与 drift 的响应走真实异步管道，pumpAndSettle 只推进伪时间线因此等不到它们
  /// （与订阅管理页的预览是同一类假失败）。刷新时按钮会显示持续动画的加载指示器，
  /// 因此也不能只用 pumpAndSettle。
  Future<void> settleIo(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
  }

  group('列表与卡片', () {
    testWidgets('按发布时间倒序显示卡片：标题/来源/时间/一行摘要', (WidgetTester tester) async {
      await seedArticle('较新的文章', minutesAgo: 0);
      await seedArticle('较旧的文章', minutesAgo: 60);
      await pump(tester);

      expect(find.text('较新的文章'), findsOneWidget);
      expect(find.text('较旧的文章'), findsOneWidget);
      expect(find.textContaining('测试源'), findsWidgets);
      expect(find.textContaining('摘要：较新的文章'), findsOneWidget);

      // 倒序：较新的在上（用位置比较，而不是只看「都出现了」）。
      final double newer = tester.getTopLeft(find.text('较新的文章')).dy;
      final double older = tester.getTopLeft(find.text('较旧的文章')).dy;
      expect(newer, lessThan(older));
    });

    testWidgets('没有发布时间的条目明确注明「时间未知」', (WidgetTester tester) async {
      await seedArticle('无日期', noPublishedAt: true);
      await pump(tester);
      expect(find.textContaining('时间未知'), findsOneWidget);
    });

    testWidgets('筛选：未读只匹配 unread，later 在独立入口，收藏与状态无关', (
      WidgetTester tester,
    ) async {
      await seedArticle('未读的');
      await seedArticle('已读的', state: ReadingState.read);
      await seedArticle('稍后读的', state: ReadingState.later);
      await seedArticle('收藏的', state: ReadingState.read, favorite: true);
      await pump(tester);

      // 全部：四篇都在。
      for (final String title in <String>['未读的', '已读的', '稍后读的', '收藏的']) {
        expect(find.text(title), findsOneWidget);
      }

      await tester.tap(find.text('未读'));
      await tester.pumpAndSettle();
      expect(find.text('未读的'), findsOneWidget);
      expect(find.text('稍后读的'), findsNothing, reason: 'later 不属于未读');
      expect(find.text('已读的'), findsNothing);

      await tester.tap(find.text('稍后再读'));
      await tester.pumpAndSettle();
      expect(find.text('稍后读的'), findsOneWidget);
      expect(find.text('未读的'), findsNothing);

      await tester.tap(find.text('收藏'));
      await tester.pumpAndSettle();
      expect(find.text('收藏的'), findsOneWidget);
      expect(find.text('未读的'), findsNothing, reason: '收藏不等于未读');
    });

    testWidgets('无订阅与「筛选无结果」分别提示（三类空态）', (WidgetTester tester) async {
      // 先测「有订阅但没有文章」。
      await pump(tester);
      expect(find.text('这里还没有文章'), findsOneWidget);

      // 「未读」筛选为空是完成态，文案不同。
      await tester.tap(find.text('未读'));
      await tester.pumpAndSettle();
      expect(find.text('所有文章已读'), findsOneWidget);
    });

    testWidgets('分批加载：内容不足一批时不显示「加载更多」，底栏给出总数', (WidgetTester tester) async {
      for (int i = 0; i < 3; i++) {
        await seedArticle('文章$i', minutesAgo: i);
      }
      await pump(tester);
      // 每批 100 篇，3 篇一次就加载完：没有「加载更多」可点。
      expect(find.textContaining('已加载 3 / 3 篇'), findsWidgets);
      expect(find.text('加载更多'), findsNothing);
    });
  });

  group('三态与收藏（真实写入）', () {
    testWidgets('点三态控件推进状态并落库（未读 → 已读）', (WidgetTester tester) async {
      final int id = await seedArticle('待推进');
      await pump(tester);

      await tester.tap(find.byType(ReadingStateControl).first);
      await settleIo(tester);

      expect(
        (await read(id)).readingState,
        ReadingState.read,
        reason: '控件一次点击推进一档（T012 的循环交互）',
      );
    });

    testWidgets('点收藏星形只改收藏，不改阅读状态', (WidgetTester tester) async {
      final int id = await seedArticle('待收藏', state: ReadingState.later);
      await pump(tester);

      await tester.tap(find.byType(FavoriteToggle).first);
      await settleIo(tester);

      final Article after = await read(id);
      expect(after.favorite, isTrue);
      expect(after.readingState, ReadingState.later, reason: '收藏独立');
    });
  });

  group('批量模式', () {
    testWidgets('批量模式下状态控件变只读；点卡片是勾选而不是打开', (WidgetTester tester) async {
      final int id = await seedArticle('批量目标');
      await pump(tester);

      await tester.tap(find.text('批量选择'));
      await tester.pumpAndSettle();

      // 两个状态控件在批量模式下只读。
      final ReadingStateControl control = tester.widget<ReadingStateControl>(
        find.byType(ReadingStateControl).first,
      );
      expect(control.onChanged, isNull);
      final FavoriteToggle favorite = tester.widget<FavoriteToggle>(
        find.byType(FavoriteToggle).first,
      );
      expect(favorite.onChanged, isNull);

      // 点卡片是勾选：出现「已选 1 篇」，且状态没有被改动。
      await tester.tap(find.text('批量目标'));
      await tester.pumpAndSettle();
      expect(find.textContaining('已选 1 篇'), findsWidgets);
      expect((await read(id)).readingState, ReadingState.unread);
    });

    testWidgets('批量标为已读只改三态；批量加入收藏不改三态', (WidgetTester tester) async {
      final int id = await seedArticle('批量一', state: ReadingState.later);
      await pump(tester);
      await tester.tap(find.text('批量选择'));
      await tester.pumpAndSettle();
      // 范围默认「筛选结果」（当前是全部）；直接点操作。
      await tester.tap(find.text('标为已读'));
      await settleIo(tester);
      expect((await read(id)).readingState, ReadingState.read);
      expect((await read(id)).favorite, isFalse);

      await tester.tap(find.text('加入收藏'));
      await settleIo(tester);
      final Article after = await read(id);
      expect(after.favorite, isTrue);
      expect(after.readingState, ReadingState.read, reason: '收藏不改三态');
    });

    testWidgets('批量操作后可撤销，且逐行恢复到操作前的具体状态', (WidgetTester tester) async {
      // 两个混合状态：撤销必须把它们各自恢复成原样，而不是设成同一个值。
      final int unread = await seedArticle('撤销未读');
      final int later = await seedArticle('撤销稍后读', state: ReadingState.later);
      await pump(tester);

      await tester.tap(find.text('批量选择'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('标为已读'));
      await settleIo(tester);
      expect((await read(unread)).readingState, ReadingState.read);
      expect((await read(later)).readingState, ReadingState.read);

      // 提示条里带撤销动作。
      expect(find.text('撤销'), findsOneWidget);
      await tester.tap(find.text('撤销'));
      await settleIo(tester);

      expect((await read(unread)).readingState, ReadingState.unread);
      expect(
        (await read(later)).readingState,
        ReadingState.later,
        reason: '撤销恢复的是每一行各自的原值',
      );
      expect(find.textContaining('已撤销'), findsOneWidget);
    });

    testWidgets('撤销提示里的文案说明范围与动作（不是只写「操作成功」）', (WidgetTester tester) async {
      await seedArticle('文案一');
      await pump(tester);
      await tester.tap(find.text('批量选择'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('标为稍后读'));
      await settleIo(tester);

      expect(find.textContaining('已处理 1 篇'), findsOneWidget);
      expect(find.textContaining('标为稍后读'), findsWidgets);
    });
  });

  group('详情页（T019 产品化）与 SET-010', () {
    testWidgets('打开正文渲染受控文档：标题、正文与完整性徽标都在', (WidgetTester tester) async {
      await seedArticle(
        '可读文章',
        body: '这是正文纯文本。',
        completeness: BodyCompleteness.sourceBody,
      );
      await pump(tester);

      await tester.tap(find.text('可读文章'));
      await settleIo(tester);

      // 正文经 Markdown → 受控文档树渲染（T019）；页面不再有「属 T019」的占位说明，
      // 因为它已经是一个真正的阅读器。
      expect(find.textContaining('这是正文纯文本。'), findsOneWidget);
      expect(find.text('来源全文'), findsOneWidget, reason: '完整性徽标');
    });

    testWidgets('未读打开后自动标已读，返回时该行从「未读」筛选里消失', (WidgetTester tester) async {
      final int id = await seedArticle('未读待读', body: '正文');
      await pump(tester);

      // 切到未读筛选，此时这一行在列表里。
      await tester.tap(find.text('未读'));
      await tester.pumpAndSettle();
      expect(find.text('未读待读'), findsOneWidget);

      await tester.tap(find.text('未读待读'));
      await settleIo(tester);
      expect((await read(id)).readingState, ReadingState.read);

      // 返回列表：列表已重读，该行不再出现在未读筛选里。
      // 用 AppBar 的返回按钮（带「返回列表」提示）而不是 byIcon：底部的上下篇导航条
      // 也有一个 arrow_back 图标，按图标找会命中两个。
      await tester.tap(find.byTooltip('返回列表'));
      await settleIo(tester);
      expect(find.text('未读待读'), findsNothing);
      expect(find.text('所有文章已读'), findsOneWidget);
    });

    testWidgets('later 打开后仍为 later（不自动标已读）', (WidgetTester tester) async {
      final int id = await seedArticle(
        '稍后读的',
        state: ReadingState.later,
        body: '正文',
      );
      await pump(tester);

      await tester.tap(find.text('稍后读的'));
      await settleIo(tester);
      expect((await read(id)).readingState, ReadingState.later);
    });
  });

  group('刷新接线（T016）', () {
    testWidgets('顶部刷新按钮走真实抓取，新文章出现在列表里', (WidgetTester tester) async {
      int requests = 0;
      await pump(
        tester,
        fetcher: HttpFeedFetcher(
          client: MockClient((http.Request request) async {
            requests++;
            return _xml(_rss);
          }),
        ),
      );
      expect(find.text('这里还没有文章'), findsOneWidget);

      await tester.tap(find.text('刷新'));
      await settleIo(tester);

      expect(requests, 1);
      expect(find.textContaining('新增 1 篇'), findsOneWidget);
      expect(find.text('刷新后来的一篇'), findsOneWidget);
    });

    testWidgets('离线时说明「未发起刷新」而不是「刷新完成」', (WidgetTester tester) async {
      int requests = 0;
      await pump(
        tester,
        fetcher: HttpFeedFetcher(
          client: MockClient((http.Request request) async {
            requests++;
            return _xml(_rss);
          }),
        ),
        network: const _FakeNetwork(offline: true),
      );

      await tester.tap(find.text('刷新'));
      await settleIo(tester);

      expect(requests, 0, reason: '守卫必须在上网之前拦下');
      expect(find.textContaining('当前无网络'), findsOneWidget);
      expect(find.textContaining('刷新完成'), findsNothing);
    });
  });
}
