// 卡片形态、分批加载与返回锚点（T019+ 补齐 T019 的验收缺口）。
//
// 三组断言各自对应一条**架构写明但容易做漏**的要求：
//
//   卡片形态（架构第 7 节）：紧凑无图标题 2 行摘要 1 行；正常右图 96×72 标题 2 摘要 2；
//     宽松上图 16:9 标题 3 摘要 3；**缺图不占位**；大字号允许增高不截断操作控件。
//   分批加载（架构 4.1「列表分页/虚拟化」）：一万条数据下**构建数量受控**——这条
//     断言的是一万条里只构建了十几张卡片，而不是任何性能数字（不在这里宣称帧率）。
//   返回锚点（架构 4.1「重返时恢复位置」/ SET-009）：从详情返回保持滚动位置；列表
//     被销毁重建后能跳回原处；换筛选/来源时按 SET-009 的语义**回到顶部**。
library;

import 'package:drift/drift.dart' show Batch, Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/articles/application/article_card_view.dart';
import 'package:flux/features/articles/application/article_list_state.dart';
import 'package:flux/features/articles/presentation/article_card.dart';
import 'package:flux/features/articles/presentation/article_list_scroll.dart';
import 'package:flux/features/articles/presentation/reading_page.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/feed_catalog_store.dart';

import '../../app/test_harness.dart';

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
        syncId: 'feed.a',
        normalizedUrl: 'https://a.example.com/feed.xml',
        name: '示例源',
      ),
    )).unwrap().id;
  });

  tearDown(() async {
    await bootstrap.dispose();
  });

  /// 批量落库 [count] 篇文章（用于虚拟化断言，逐条 insert 在测试时间上不可接受）。
  ///
  /// [laterEvery] 非 0 时，每第 N 篇落成「稍后再读」：筛选相关的用例需要「另一个筛选
  /// 也有内容」，否则换筛选之后列表是空的，滚动位置这件事就无从观察。
  Future<void> seedMany(int count, {int laterEvery = 0}) async {
    await db.batch((Batch batch) {
      batch.insertAll(db.articles, <ArticlesCompanion>[
        for (int i = 0; i < count; i++)
          ArticlesCompanion.insert(
            feedId: Value<int?>(feedId),
            title: '批量文章 $i',
            identityBasis: IdentityBasis.guid,
            guid: Value<String?>('guid-many-$i'),
            guidPresent: const Value<bool>(true),
            summary: const Value<String?>('摘要'),
            readingState: Value<ReadingState>(
              laterEvery != 0 && i % laterEvery == 0
                  ? ReadingState.later
                  : ReadingState.unread,
            ),
            publishedAt: Value<DateTime?>(
              DateTime.utc(2026, 9, 20, 12).subtract(Duration(minutes: i)),
            ),
          ),
      ]);
    });
  }

  /// 点开列表里**当前可见**的第一张卡片。
  ///
  /// 为什么不用 tester.tap(find.byType(ArticleCardBody).first)：滚动之后列表里
  /// **第一张被构建的卡片可能有一半在视口之上**（还有列表顶部与实际视口之间的
  /// 间隙），tap 会取它的几何中心，那个点落在卡片外面（滚出视口的部分），点击会被
  /// 工具栏吃掉。这里改为在视口内挑一张完整的卡片，点它标题所在的左侧位置。
  Future<void> tapVisibleCard(WidgetTester tester) async {
    final Size viewport =
        tester.view.physicalSize / tester.view.devicePixelRatio;
    for (final Element element in find.byType(ArticleCardBody).evaluate()) {
      final RenderBox box = element.renderObject! as RenderBox;
      final Rect rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect.top >= 0 && rect.bottom <= viewport.height) {
        // 左侧是标题区（行尾才是三态/收藏控件）。
        await tester.tapAt(Offset(rect.left + 40, rect.center.dy));
        return;
      }
    }
    fail('列表里没有一张完整可见的卡片可点');
  }

  /// 渲染单张卡片内容（形态断言不需要整个页面）。
  ///
  /// 卡片放在可滚动容器里：宽松模式的 16:9 大图加上 3 行标题/摘要在测试视口里可能
  /// 高于窗口，而卡片本来就允许随字号与内容增高（架构第 7 节）。用固定高度会把
  /// 「允许增高」这条要求反过来变成一次 overflow 失败。
  Future<void> pumpCard(
    WidgetTester tester, {
    required ArticleCardViewMode mode,
    required ArticleListEntry entry,
  }) async {
    await setSurfaceSize(tester, const Size(700, 700));
    await tester.pumpWidget(
      wrapFluxApp(
        overrides: bootstrap.overrides(),
        child: Scaffold(
          body: SingleChildScrollView(
            child: ArticleCardBody(
              entry: entry,
              mode: mode,
              metaLine: '示例源 · 2026-09-20 12:00',
              trailing: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ArticleListEntry entryOf({
    required String title,
    String? summary,
    String? imageUrl,
  }) => ArticleListEntry(
    id: 1,
    feedId: feedId,
    feedName: '示例源',
    title: title,
    readingState: ReadingState.unread,
    favorite: false,
    publishedAt: DateTime.utc(2026, 9, 20, 12),
    fetchedAt: DateTime.utc(2026, 9, 20, 12),
    summary: summary,
    imageUrl: imageUrl,
  );

  /// 页面级渲染（分批加载与锚点断言用）。
  Future<void> pumpPage(
    WidgetTester tester, {
    required List<Override> overrides,
    Key? listKey,
  }) async {
    await setSurfaceSize(tester, const Size(900, 700));
    await tester.pumpWidget(
      wrapFluxApp(
        overrides: overrides,
        child: Scaffold(
          body: KeyedSubtree(
            key: listKey ?? const ValueKey<String>('list'),
            child: const ReadingPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('卡片形态（架构第 7 节）', () {
    testWidgets('紧凑：无图位，标题 2 行、摘要 1 行', (WidgetTester tester) async {
      await pumpCard(
        tester,
        mode: ArticleCardViewMode.compact,
        // 即使这篇**有**图地址，紧凑模式也不给它图位（不是「有图位但空着」）。
        entry: entryOf(
          title: '紧凑标题',
          summary: '紧凑摘要',
          imageUrl: 'https://cdn.example.com/a.png',
        ),
      );

      final Text title = tester.widget<Text>(find.text('紧凑标题'));
      expect(title.maxLines, 2);
      final Text summary = tester.widget<Text>(find.text('紧凑摘要'));
      expect(summary.maxLines, 1);
      expect(find.byType(Image), findsNothing, reason: '紧凑模式没有图位');
    });

    testWidgets('正常：右图 96×72，标题 2 行、摘要 2 行', (WidgetTester tester) async {
      await pumpCard(
        tester,
        mode: ArticleCardViewMode.normal,
        entry: entryOf(
          title: '正常标题',
          summary: '正常摘要',
          imageUrl: 'https://cdn.example.com/normal.png',
        ),
      );

      expect(tester.widget<Text>(find.text('正常标题')).maxLines, 2);
      expect(tester.widget<Text>(find.text('正常摘要')).maxLines, 2);
      final Image image = tester.widget<Image>(find.byType(Image));
      expect(image.width, kCardThumbWidth, reason: '架构第 7 节：右图 96 宽');
      expect(image.height, kCardThumbHeight, reason: '架构第 7 节：右图 72 高');
      // 右图：图片在标题文字的右侧。
      expect(
        tester.getTopLeft(find.byType(Image)).dx,
        greaterThan(tester.getTopLeft(find.text('正常标题')).dx),
      );
    });

    testWidgets('宽松：上图 16:9，标题 3 行、摘要 3 行', (WidgetTester tester) async {
      await pumpCard(
        tester,
        mode: ArticleCardViewMode.relaxed,
        entry: entryOf(
          title: '宽松标题',
          summary: '宽松摘要',
          imageUrl: 'https://cdn.example.com/wide.png',
        ),
      );

      expect(tester.widget<Text>(find.text('宽松标题')).maxLines, 3);
      expect(tester.widget<Text>(find.text('宽松摘要')).maxLines, 3);
      final AspectRatio cover = tester.widget<AspectRatio>(
        find.byType(AspectRatio),
      );
      expect(cover.aspectRatio, closeTo(16 / 9, 0.0001));
      // 上图：图片在标题文字的上方。
      expect(
        tester.getTopLeft(find.byType(Image)).dy,
        lessThan(tester.getTopLeft(find.text('宽松标题')).dy),
      );
    });

    testWidgets('缺图不占位：正常/宽松模式下没有图就不画图片位', (WidgetTester tester) async {
      for (final ArticleCardViewMode mode in <ArticleCardViewMode>[
        ArticleCardViewMode.normal,
        ArticleCardViewMode.relaxed,
      ]) {
        await pumpCard(
          tester,
          mode: mode,
          entry: entryOf(title: '无图', summary: '摘要'),
        );
        expect(find.byType(Image), findsNothing, reason: '$mode：缺图不占位');
        // 文字仍然完整（不因为缺图就少画内容）。
        expect(find.text('无图'), findsOneWidget);
      }
    });

    test('三种形态的行数与尺寸口径（纯 Dart，可逐项断言）', () {
      expect(ArticleCardViewMode.compact.titleLines, 2);
      expect(ArticleCardViewMode.compact.summaryLines, 1);
      expect(ArticleCardViewMode.compact.showsImage, isFalse);

      expect(ArticleCardViewMode.normal.titleLines, 2);
      expect(ArticleCardViewMode.normal.summaryLines, 2);
      expect(ArticleCardViewMode.normal.showsImage, isTrue);
      expect(ArticleCardViewMode.normal.imageOnTop, isFalse);

      expect(ArticleCardViewMode.relaxed.titleLines, 3);
      expect(ArticleCardViewMode.relaxed.summaryLines, 3);
      expect(ArticleCardViewMode.relaxed.imageOnTop, isTrue);

      // SET-008 的稳定取值名。
      expect(
        ArticleCardViewMode.values.map((m) => m.storageName).toList(),
        <String>['compact', 'normal', 'relaxed'],
      );
      // 未知/损坏的设置值回退到注册表默认形态（normal），而不是让整页读不出来。
      expect(
        ArticleCardViewMode.fromStorage('nope'),
        ArticleCardViewMode.normal,
      );
      expect(ArticleCardViewMode.fromStorage(null), ArticleCardViewMode.normal);
      expect(
        ArticleCardViewMode.fromStorage('relaxed'),
        ArticleCardViewMode.relaxed,
      );
    });

    testWidgets('大字号允许增高，不截断操作控件（架构第 7 节）', (WidgetTester tester) async {
      // 用 2 倍字号渲染：标题与摘要按形态行数放大，而**行尾控件仍完整可见**。
      await setSurfaceSize(tester, const Size(700, 600));
      await tester.pumpWidget(
        wrapFluxApp(
          overrides: bootstrap.overrides(),
          child: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              // 同样放可滚动容器：放大字号后卡片本来就该变高（架构第 7 节允许增高），
              // 因此这里要断言的是「控件还在卡片的边界内」，而不是「卡片塞得进窗口」。
              body: SingleChildScrollView(
                child: ArticleCardBody(
                  entry: entryOf(
                    title: '大字号标题',
                    summary: '大字号摘要',
                    imageUrl: 'https://cdn.example.com/big.png',
                  ),
                  mode: ArticleCardViewMode.normal,
                  metaLine: '示例源 · 2026-09-20 12:00',
                  trailing: const Icon(Icons.star_border, key: Key('trailing')),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('trailing')), findsOneWidget);
      final Rect card = tester.getRect(find.byType(ArticleCardBody));
      final Rect control = tester.getRect(find.byKey(const Key('trailing')));
      expect(
        card.contains(control.topLeft) && card.contains(control.bottomRight),
        isTrue,
        reason: '放大字号后操作控件必须仍在卡片内（不得被 overflow 裁掉）',
      );
    });
  });

  group('分批加载与虚拟化（架构 4.1）', () {
    testWidgets('一万条数据：只构建可见区域的卡片，构建数量受控', (WidgetTester tester) async {
      await seedMany(10000);
      await pumpPage(tester, overrides: bootstrap.overrides());

      // 内容确实读到了（总数来自库，不是本页长度）。
      expect(find.textContaining('已加载 100 / 10000 篇'), findsWidgets);

      // 虚拟化：一万条里被真正构建的卡片是**十几张**这个量级。这里给一个宽松但有效
      // 的上界（120）：它证明「只构建可见区域附近」而不是「把一万条全建出来」，
      // 同时不去宣称任何帧率或耗时数字（那不是本测试能证明的）。
      final int built = tester.widgetList(find.byType(ArticleCardBody)).length;
      expect(
        built,
        lessThan(120),
        reason: 'ListView.builder 只应构建可见区域附近的条目，实测构建 $built 张',
      );
      expect(built, greaterThan(0));
    });

    testWidgets('加载下一批：已加载条数按批增加，批大小 100', (WidgetTester tester) async {
      await seedMany(250);
      await pumpPage(tester, overrides: bootstrap.overrides());

      expect(ArticleListState.defaultBatchSize, 100);
      expect(find.textContaining('已加载 100 / 250 篇'), findsWidgets);

      // 点「加载更多」（滚动到底的等价动作，键盘用户也走这条路径）。
      await tester.tap(find.widgetWithText(TextButton, '加载更多').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('已加载 200 / 250 篇'), findsWidgets);

      await tester.tap(find.widgetWithText(TextButton, '加载更多').first);
      await tester.pumpAndSettle();
      // 最后一批只到 250：不再显示「加载更多」。
      expect(find.textContaining('已加载 250 / 250 篇'), findsWidgets);
      expect(find.text('加载更多'), findsNothing);
    });

    testWidgets('滚动到底部自动加载下一批', (WidgetTester tester) async {
      await seedMany(300);
      await pumpPage(tester, overrides: bootstrap.overrides());
      expect(find.textContaining('已加载 100 / 300 篇'), findsWidgets);

      // 滚到底（drag 不足以一次到底，直接驱动控制器）。
      final ScrollController controller = ProviderScope.containerOf(
        tester.element(find.byType(ReadingPage)),
      ).read(articleListScrollControllerProvider);
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();

      expect(find.textContaining('已加载 200 / 300 篇'), findsWidgets);
    });
  });

  group('返回锚点（架构 4.1 / SET-009）', () {
    testWidgets('从详情返回列表：滚动位置保持', (WidgetTester tester) async {
      await seedMany(60);
      await pumpPage(tester, overrides: bootstrap.overrides());

      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(ReadingPage)),
      );
      final ScrollController controller = container.read(
        articleListScrollControllerProvider,
      );
      controller.jumpTo(600);
      await tester.pumpAndSettle();
      expect(controller.offset, 600);

      // 打开一篇可见的文章，再返回。点标题文字而不是卡片中心：卡片中心可能落在
      // 行尾控件的热区之外（列表里的卡片内容高度不一），点标题是用户的实际动作。
      await tapVisibleCard(tester);
      await tester.pumpAndSettle();
      expect(find.byTooltip('返回列表'), findsOneWidget, reason: '详情页已打开');

      await tester.tap(find.byTooltip('返回列表'));
      await tester.pumpAndSettle();

      expect(
        container.read(articleListScrollControllerProvider).offset,
        600,
        reason: '返回列表时不得回到顶部（架构 4.1「重返时恢复位置」）',
      );
    });

    testWidgets('列表被销毁重建（换去向/断点变化）：跳回上次位置', (WidgetTester tester) async {
      await seedMany(60);
      await pumpPage(tester, overrides: bootstrap.overrides());

      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(ReadingPage)),
      );
      container.read(articleListScrollControllerProvider).jumpTo(700);
      await tester.pumpAndSettle();
      // 滚动回调把偏移记进锚点。
      expect(container.read(articleListScrollAnchorProvider).offset, 700);

      // 换掉 KeyedSubtree 的 key：列表整棵子树被销毁重建（等同离开这一页再回来）。
      await pumpPage(
        tester,
        overrides: bootstrap.overrides(),
        listKey: const ValueKey<String>('list-rebuilt'),
      );

      expect(
        container.read(articleListScrollControllerProvider).offset,
        700,
        reason: '重建后必须跳回锚点，而不是从头开始',
      );
    });

    testWidgets('换筛选/来源：按 SET-009 语义回到顶部', (WidgetTester tester) async {
      // 每第 3 篇是「稍后再读」，因此换到那个筛选仍然有内容——否则列表变成空态，
      // 滚动位置这件事就没有可观察的对象（控制器也会随列表一起卸载）。
      await seedMany(60, laterEvery: 3);
      await pumpPage(tester, overrides: bootstrap.overrides());

      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(ReadingPage)),
      );
      container.read(articleListScrollControllerProvider).jumpTo(700);
      await tester.pumpAndSettle();

      await tester.tap(find.text('稍后再读'));
      await tester.pumpAndSettle();

      // 换筛选后列表仍有内容，因此控制器仍挂在列表上。
      expect(find.byType(ArticleCardBody), findsWidgets);
      expect(
        container.read(articleListScrollControllerProvider).offset,
        0,
        reason: '内容换了，停在原来的像素高度会落到与用户选中无关的文章上',
      );
      expect(container.read(articleListScrollAnchorProvider).offset, 0);
    });
  });
}
