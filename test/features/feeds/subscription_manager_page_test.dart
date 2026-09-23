// 订阅管理页的组件测试（T014）。
//
// 覆盖手册点名的关键界面行为：
//   - 添加流程：输入地址 → 预览 → 确认，成功提示带导入篇数；失败显示原因；
//   - 重复地址：预览直接说明「已订阅」，确认按钮不再是「确认添加」；
//   - 分组折叠（SET-025）：折叠后订阅行隐藏、数量提示出现，且状态落本机存储；
//   - 未分类保护：界面上没有「删除分组」选项，重命名入口也不存在；
//   - 加精徽章：加精订阅显示徽标，未加精不显示；
//   - 停用徽章与未读数占位显示真实数值；
//   - 排序可达性：拖动把手存在且有序（架构第 7 节要求桌面键盘可用）。
//
// 用真实内存库 + 真实 drift 实现（与生产只差存储介质），因此不联网、无替身假象。
library;

import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/feeds/presentation/subscription_manager_page.dart';
import 'package:flux/features/feeds/presentation/opml_page.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/feed_catalog_store.dart';
import 'package:flux/infrastructure/local/feed_store_adapter.dart';
import 'package:flux/infrastructure/local/group_collapse_repository.dart';
import 'package:flux/infrastructure/local/settings_repository.dart';
import 'package:flux/infrastructure/local/tables/article_tables.dart';
import 'package:flux/infrastructure/network/feed_fetcher.dart';

import '../../app/test_harness.dart';

const String _rss = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel>
  <title>示例订阅</title>
  <item>
    <title>一篇文章</title>
    <link>https://feeds.example.com/1</link>
    <guid isPermaLink="false">g1</guid>
  </item>
</channel></rss>''';

http.Response _xml(String body) => http.Response.bytes(
  utf8.encode(body),
  200,
  headers: <String, String>{'content-type': 'application/xml'},
);

void main() {
  late TestBootstrap bootstrap;
  late AppDatabase db;
  late DriftFeedCatalogStore catalog;
  late GroupCollapseRepository collapse;

  setUp(() async {
    bootstrap = TestBootstrap();
    db = bootstrap.database;
    await db.customSelect('SELECT 1').get();
    catalog = DriftFeedCatalogStore(db);
    collapse = GroupCollapseRepository(db);
  });
  tearDown(() async => bootstrap.dispose());

  /// 生成 overrides。
  ///
  /// 全部端口都由组合根那一套接好（订阅/分组、文章写入、折叠状态、诊断、设置都
  /// 指向同一个内存库），只把**抓取端口**换成按 URL 返回固定响应的替身。
  /// 因此这里覆盖的就是生产装配路径上的那个位置，而不是另起一套接线。
  List<Override> overrides({
    Map<String, http.Response> routes = const <String, http.Response>{},
  }) => bootstrap.overrides(
    feedFetcher: HttpFeedFetcher(
      client: MockClient((http.Request request) async {
        final http.Response? response = routes[request.url.toString()];
        return response ?? http.Response('not found', 404);
      }),
    ),
  );

  /// 渲染订阅管理页。
  Future<void> pumpPage(
    WidgetTester tester, {
    Map<String, http.Response> routes = const <String, http.Response>{},
  }) async {
    await setSurfaceSize(tester, const Size(1000, 900));
    await tester.pumpWidget(
      wrapFluxApp(
        child: const SubscriptionManagerPage(),
        overrides: overrides(routes: routes),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 让**真实事件循环**跑一小段，再回到测试的伪时间线完成布局。
  ///
  /// 为什么 pumpAndSettle 不够：它只推进测试的伪时间线（定时器与帧），而抓取层
  /// 的响应流来自 http 客户端的真实异步管道；伪时间线推进不会让它完成。实测表现
  /// 是「预览永远不出现、也没有错误」，正是本助手要消除的假失败。真实网络不会
  /// 遇到这个问题（生产里事件循环本来就是真实的）。
  Future<void> settleFetch(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
  }

  /// 建一个订阅（直接落库，避免每个用例都走一遍对话框）。
  ///
  /// 显示名与地址分开成 [name] 与 [slug]：地址用 ASCII，避免中文被百分号编码后
  /// 在不同代码路径上呈现不同形态，让「重复匹配」的断言依赖业务规则而不是编码细节。
  Future<int> seedFeed({
    required String name,
    String? slug,
    int? groupId,
    bool favorite = false,
    bool enabled = true,
  }) async {
    final String path = slug ?? name;
    final FeedRecord created = (await catalog.createFeed(
      FeedInsert(
        syncId: 'feed.$path',
        normalizedUrl: 'https://feeds.example.com/$path.xml',
        name: name,
        groupId: groupId,
      ),
    )).unwrap();
    if (favorite) {
      await catalog.setFeedFavorite(feedId: created.id, favorite: true);
    }
    if (!enabled) {
      await catalog.setFeedEnabled(feedId: created.id, enabled: false);
    }
    return created.id;
  }

  Future<GroupRecord> uncategorized() async {
    final Result<GroupRecord?> found = await catalog.findGroupBySyncId(
      groupUncategorizedSyncId,
    );
    return found.valueOrNull!;
  }

  group('页面结构', () {
    testWidgets('显示标题、范围说明与刷新策略区（SET-020/021）', (WidgetTester tester) async {
      // 先建一个订阅：一个都没有时页面显示空态引导，保留组卡片会被隐藏（见页面里
      // showEmptyState 的说明），而本用例要断言的是有订阅时的常规结构。
      await seedFeed(name: '源一');
      await pumpPage(tester);

      expect(find.text('订阅管理'), findsWidgets);
      expect(find.textContaining('本页管理订阅与分组'), findsOneWidget);
      expect(find.text('刷新策略'), findsOneWidget);
      expect(find.textContaining('自动刷新在后台按计划执行'), findsOneWidget);
      expect(find.text('全局自动刷新'), findsOneWidget);
      expect(find.text('启动时刷新'), findsOneWidget);
      // 保留组（未分类）在有订阅时作为归属区块出现。它的显示名来自 l10n 而不是
      // 库里的种子文本，因此界面语言切换时这个名字会跟着变。
      expect(find.text('未分类'), findsWidgets);
    });

    testWidgets('没有订阅时显示空态而不是空列表', (WidgetTester tester) async {
      await pumpPage(tester);

      expect(find.text('还没有订阅'), findsOneWidget);
      expect(find.textContaining('也可以批量导入与导出'), findsOneWidget);
    });

    testWidgets('刷新策略三项真实落库（SET-020/021）', (WidgetTester tester) async {
      await pumpPage(tester);

      // 关闭全局自动刷新。
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      final SettingsRepository settings = SettingsRepository(db);
      final Result<Object?> stored = await settings.read(SettingId.set020);
      expect(stored.isOk, isTrue);
      final Map<Object?, Object?> value =
          stored.unwrap()! as Map<Object?, Object?>;
      expect(value['enabled'], isFalse);
      expect(value['intervalMinutes'], '60', reason: '只改开关不改变间隔');
    });
  });

  group('添加订阅流程', () {
    testWidgets('地址 → 预览 → 确认：入库并提示导入篇数', (WidgetTester tester) async {
      await pumpPage(
        tester,
        routes: <String, http.Response>{
          'https://feeds.example.com/new.xml': _xml(_rss),
        },
      );

      await tester.tap(find.byTooltip('添加订阅'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, '订阅地址'),
        'https://feeds.example.com/new.xml',
      );
      await tester.tap(find.text('预览'));
      await settleFetch(tester);

      // 预览显示标题、格式与条目数。
      expect(find.text('预览结果'), findsOneWidget);
      expect(find.text('示例订阅'), findsWidgets);
      expect(find.text('RSS 2.0'), findsOneWidget);
      expect(find.text('1 篇文章'), findsOneWidget);
      // 规范化地址是匹配依据，必须可见（否则用户无法理解「为什么说是重复」）。
      expect(find.text('规范化地址'), findsOneWidget);

      await tester.tap(find.text('确认添加'));
      await tester.pumpAndSettle();

      // 对话框关闭，列表出现新源，提示带篇数。
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('示例订阅'), findsOneWidget);
      expect(find.textContaining('已添加「示例订阅」，导入 1 篇文章'), findsOneWidget);

      // 真的落库了。
      final List<FeedRecord> feeds = (await catalog.listFeeds()).unwrap();
      expect(feeds, hasLength(1));
      expect(feeds.single.normalizedUrl, 'https://feeds.example.com/new.xml');
      expect(await db.select(db.articles).get(), hasLength(1));
    });

    testWidgets('预览失败显示类型化原因（解析失败），且不写入任何数据', (WidgetTester tester) async {
      await pumpPage(
        tester,
        routes: <String, http.Response>{
          'https://feeds.example.com/html': http.Response.bytes(
            utf8.encode('<html><body>网页</body></html>'),
            200,
            headers: <String, String>{'content-type': 'text/html'},
          ),
        },
      );

      await tester.tap(find.byTooltip('添加订阅'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, '订阅地址'),
        'https://feeds.example.com/html',
      );
      await tester.tap(find.text('预览'));
      await settleFetch(tester);

      expect(find.text('解析失败：该地址的内容不是可解析的 RSS/Atom'), findsOneWidget);
      // 失败时没有「确认添加」，因此用户无法把失败状态写进库。
      expect(find.text('确认添加'), findsNothing);
      expect((await catalog.listFeeds()).unwrap(), isEmpty);
    });

    testWidgets('地址不合法：字段级原因，且不发请求', (WidgetTester tester) async {
      await pumpPage(tester);

      await tester.tap(find.byTooltip('添加订阅'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, '订阅地址'),
        'not-a-url',
      );
      await tester.tap(find.text('预览'));
      await settleFetch(tester);

      expect(find.text('地址不合法：请输入完整的 http/https 订阅地址'), findsOneWidget);
      expect((await catalog.listFeeds()).unwrap(), isEmpty);
    });

    testWidgets('重复地址：预览说明已订阅，按钮变为关闭（不提供「确认添加」）', (WidgetTester tester) async {
      await seedFeed(name: '已有源', slug: 'existing');
      await pumpPage(tester);

      await tester.tap(find.byTooltip('添加订阅'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, '订阅地址'),
        'https://feeds.example.com/existing.xml',
      );
      await tester.tap(find.text('预览'));
      await settleFetch(tester);

      expect(find.text('该地址已订阅'), findsOneWidget);
      expect(find.textContaining('原有的分组、加精与刷新设置都保留'), findsOneWidget);
      expect(find.text('确认添加'), findsNothing);
      expect(find.text('关闭'), findsOneWidget);

      // 库里仍然只有一条。
      expect((await catalog.listFeeds()).unwrap(), hasLength(1));
    });
  });

  group('分组折叠（SET-025）', () {
    testWidgets('折叠后隐藏订阅行并显示数量，状态落到本机存储', (WidgetTester tester) async {
      await seedFeed(name: '源一');
      await seedFeed(name: '源二');
      await pumpPage(tester);

      expect(find.text('源一'), findsOneWidget);
      expect(find.text('源二'), findsOneWidget);

      // 折叠未分类组（第一个展开箭头按钮）。
      await tester.tap(find.byIcon(Icons.expand_more).first);
      await tester.pumpAndSettle();

      expect(find.text('源一'), findsNothing);
      expect(find.text('源二'), findsNothing);
      expect(find.text('2 个订阅（已折叠）'), findsOneWidget);

      // 状态真的落库（本机键），重启后仍然折叠。
      final GroupRecord reserved = await uncategorized();
      final Result<Map<String, bool>> stored = await collapse.readAll();
      expect(stored.unwrap()['${reserved.id}'], isTrue);
    });

    testWidgets('已折叠的分组在前一帧就按折叠渲染（本机记忆生效）', (WidgetTester tester) async {
      await seedFeed(name: '源一');
      final GroupRecord reserved = await uncategorized();
      await collapse.write(groupId: reserved.id, collapsed: true);

      await pumpPage(tester);

      expect(find.text('源一'), findsNothing);
      expect(find.text('1 个订阅（已折叠）'), findsOneWidget);
    });
  });

  group('未分类保护', () {
    testWidgets('保留组没有「删除分组」，只有说明性锁标记', (WidgetTester tester) async {
      await seedFeed(name: '源一');
      await pumpPage(tester);

      // 保留组的菜单里不含删除项。
      await tester.tap(find.byTooltip('分组操作').first);
      await tester.pumpAndSettle();

      expect(find.text('删除分组'), findsNothing);
      expect(find.text('重命名'), findsNothing);
      // 置顶是允许的（架构只限制删除与改名）。
      expect(find.text('置顶分组'), findsOneWidget);
      // 保留组说明。
      expect(find.byTooltip('保留分组：不能删除或改名，其中订阅可移动'), findsOneWidget);
    });

    testWidgets('普通分组有删除与重命名入口', (WidgetTester tester) async {
      // sortOrder 显式设为 1：保留组「未分类」是 0，若不指定则两者同权重，
      // 列表会退到按名称排序（'技术' 的码点小于 '未分类'），于是「技术」跑到最前，
      // 菜单索引的断言就会指错对象。这里把顺序钉死，让测试断言的是行为而不是巧合。
      final GroupRecord tech = (await catalog.createGroup(
        syncId: 'group.tech',
        name: '技术',
        sortOrder: 1,
      )).unwrap();
      await seedFeed(name: '源一', groupId: tech.id);
      await pumpPage(tester);

      // 「技术」组的菜单（最后一个分组操作，因为保留组在前）。
      final Finder menus = find.byTooltip('分组操作');
      await tester.tap(menus.last);
      await tester.pumpAndSettle();

      expect(find.text('删除分组'), findsOneWidget);
      expect(find.text('重命名'), findsOneWidget);
    });
  });

  group('加精与停用徽章', () {
    testWidgets('加精订阅显示徽标，未加精不显示', (WidgetTester tester) async {
      await seedFeed(name: '加精源', favorite: true);
      await seedFeed(name: '普通源');
      await pumpPage(tester);

      expect(find.bySemanticsLabel('加精'), findsOneWidget);
    });

    testWidgets('停用订阅显示「已停用」标签与说明', (WidgetTester tester) async {
      await seedFeed(name: '停用源', enabled: false);
      await pumpPage(tester);

      expect(find.text('已停用'), findsOneWidget);
      expect(find.byTooltip('已停用：自动刷新会跳过该源'), findsOneWidget);
    });

    testWidgets('未读数显示真实统计（later 不算未读）', (WidgetTester tester) async {
      final int feedId = await seedFeed(name: '有未读的源');
      await DriftFeedArticleStore(db).upsertArticles(<ArticleImport>[
        ArticleImport(
          feedId: feedId,
          title: '未读一',
          identityBasis: IdentityBasis.guid,
          guid: 'u1',
          guidPresent: true,
        ),
        ArticleImport(
          feedId: feedId,
          title: '稍后读',
          identityBasis: IdentityBasis.guid,
          guid: 'u2',
          guidPresent: true,
        ),
      ]);
      await (db.update(
        db.articles,
      )..where((Articles t) => t.guid.equals('u2'))).write(
        const ArticlesCompanion(readingState: Value(ReadingState.later)),
      );

      await pumpPage(tester);

      expect(find.text('1 未读'), findsOneWidget);
    });
  });

  group('订阅操作菜单', () {
    testWidgets('加精开关：菜单操作后徽标出现且落库', (WidgetTester tester) async {
      final int feedId = await seedFeed(name: '源一');
      await pumpPage(tester);

      expect(find.bySemanticsLabel('加精'), findsNothing);

      await tester.tap(find.byTooltip('订阅操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('加精'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('加精'), findsOneWidget);
      final List<FeedRecord> feeds = (await catalog.listFeeds()).unwrap();
      expect(feeds.single.id, feedId);
      expect(feeds.single.favorite, isTrue);
    });

    testWidgets('停用开关：菜单操作后显示已停用且落库', (WidgetTester tester) async {
      await seedFeed(name: '源一');
      await pumpPage(tester);

      await tester.tap(find.byTooltip('订阅操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('停用自动刷新'));
      await tester.pumpAndSettle();

      expect(find.text('已停用'), findsOneWidget);
      expect((await catalog.listFeeds()).unwrap().single.enabled, isFalse);
    });

    testWidgets('上移/下移：真实改变组内顺序（键盘可达的等价操作）', (WidgetTester tester) async {
      final GroupRecord reserved = await uncategorized();
      await seedFeed(name: 'A源', groupId: reserved.id);
      await seedFeed(name: 'B源', groupId: reserved.id);
      await pumpPage(tester);

      // 初始顺序按名称（同为 sortOrder 0）。
      expect(
        tester.getTopLeft(find.text('A源')).dy <
            tester.getTopLeft(find.text('B源')).dy,
        isTrue,
      );

      // 把 B 上移。
      await tester.tap(find.byTooltip('订阅操作').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('上移'));
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.text('B源')).dy <
            tester.getTopLeft(find.text('A源')).dy,
        isTrue,
        reason: '上移必须真实改变顺序',
      );
    });

    testWidgets('拖动把手存在（架构第 7 节：桌面排序可达）', (WidgetTester tester) async {
      await seedFeed(name: '源一');
      await pumpPage(tester);

      expect(find.byIcon(Icons.drag_indicator), findsOneWidget);
      expect(find.byTooltip('拖动或按上下方向键调整顺序'), findsOneWidget);
    });
  });

  group('分组管理界面', () {
    testWidgets('新建分组：对话框校验空名，成功后出现在列表', (WidgetTester tester) async {
      await pumpPage(tester);

      await tester.tap(find.byTooltip('新建分组'));
      await tester.pumpAndSettle();

      // 空名被拦下（字段级提示）。
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('分组名称不能为空'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, '分组名称'), '技术');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('技术'), findsOneWidget);
      expect(
        (await catalog.listGroups()).unwrap().length,
        2,
        reason: '未分类 + 新技术',
      );
    });

    testWidgets('删除分组（移动到未分类）：确认后订阅搬到未分类且分组消失', (WidgetTester tester) async {
      // sortOrder 显式设为 1：保留组「未分类」是 0，若不指定则两者同权重，
      // 列表会退到按名称排序（'技术' 的码点小于 '未分类'），于是「技术」跑到最前，
      // 菜单索引的断言就会指错对象。这里把顺序钉死，让测试断言的是行为而不是巧合。
      final GroupRecord tech = (await catalog.createGroup(
        syncId: 'group.tech',
        name: '技术',
        sortOrder: 1,
      )).unwrap();
      await seedFeed(name: '技术源', groupId: tech.id);
      await pumpPage(tester);

      await tester.tap(find.byTooltip('分组操作').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除分组'));
      await tester.pumpAndSettle();

      // 两个分支都列出，且删除订阅分支明确标注本期不生效。
      expect(find.text('移动到未分类'), findsOneWidget);
      expect(find.text('删除其中的订阅'), findsOneWidget);
      expect(find.textContaining('确认后才会真正删除'), findsOneWidget);

      await tester.tap(find.text('移动到未分类'));
      await tester.pumpAndSettle();

      expect(find.text('技术'), findsNothing, reason: '分组已删除');
      // 订阅仍在，且归属变成未分类。
      final List<FeedRecord> feeds = (await catalog.listFeeds()).unwrap();
      expect(feeds, hasLength(1));
      expect(feeds.single.name, '技术源');
      expect(feeds.single.groupId, (await uncategorized()).id);
    });

    testWidgets('删除分组（删除订阅分支）：真的删除，并在回执里给出清理与保留的篇数', (
      WidgetTester tester,
    ) async {
      // sortOrder 显式设为 1：保留组「未分类」是 0，若不指定则两者同权重，
      // 列表会退到按名称排序（'技术' 的码点小于 '未分类'），于是「技术」跑到最前，
      // 菜单索引的断言就会指错对象。这里把顺序钉死，让测试断言的是行为而不是巧合。
      final GroupRecord tech = (await catalog.createGroup(
        syncId: 'group.tech',
        name: '技术',
        sortOrder: 1,
      )).unwrap();
      await seedFeed(name: '技术源', groupId: tech.id);
      await pumpPage(tester);

      await tester.tap(find.byTooltip('分组操作').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除分组'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除其中的订阅'));
      await tester.pumpAndSettle();

      // T018 起这个分支**真的**删除（不再只是记录）。回执必须给出具体数字，
      // 而不是一句「已删除」——用户需要知道清掉了几篇、留下了几篇。
      expect(find.textContaining('已删除分组「技术」'), findsOneWidget);
      expect(find.textContaining('清理'), findsOneWidget);

      expect(
        (await catalog.listGroups()).unwrap(),
        hasLength(1),
        reason: '只剩保留组',
      );
      expect(
        (await catalog.listFeeds()).unwrap(),
        isEmpty,
        reason: '组内订阅被真正删除',
      );
    });
  });

  group('英文界面', () {
    testWidgets('英文下文案与中文对应（l10n 覆盖完整）', (WidgetTester tester) async {
      await seedFeed(name: 'A feed');
      await bootstrap.seedLanguage('en');
      await setSurfaceSize(tester, const Size(1000, 900));
      await tester.pumpWidget(
        wrapFluxApp(
          child: const SubscriptionManagerPage(),
          overrides: overrides(),
          localeOverride: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Subscriptions'), findsWidgets);
      expect(find.text('Refresh policy'), findsOneWidget);
      expect(find.text('Global automatic refresh'), findsOneWidget);
      expect(find.text('Uncategorized'), findsWidgets);
    });
  });

  group('OPML 入口（T015）', () {
    testWidgets('顶栏有导入/导出入口，点击进入 OPML 页', (WidgetTester tester) async {
      await seedFeed(name: 'A feed');
      await pumpPage(tester);

      // 入口必须真的可达：能力做完了却没有入口，用户看到的仍是「没有这个功能」。
      final Finder entry = find.byTooltip('导入 / 导出 OPML');
      expect(entry, findsOneWidget);

      await tester.tap(entry);
      await tester.pumpAndSettle();

      expect(find.byType(OpmlPage), findsOneWidget);
    });
  });
}
