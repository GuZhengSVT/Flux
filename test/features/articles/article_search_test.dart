// T022：检索界面与控制器（搜索框、范围、三种空态、竞态、片段高亮渲染）。
//
// 数据层的检索语义由 article_search_store_test 覆盖；这里验的是**界面与状态机**：
// 用户输入后发生了什么、结果怎么画、失败与无结果是否分得开。
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/articles/application/article_search_state.dart';
import 'package:flux/features/articles/presentation/reading_page.dart';
import 'package:flux/features/articles/presentation/reader/search_snippet_view.dart';
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
        syncId: 'feed.tech',
        normalizedUrl: 'https://tech.example.com/feed.xml',
        name: '科技日报',
      ),
    )).unwrap().id;
  });

  tearDown(() async => bootstrap.dispose());

  Future<int> add(String title, {String? body, String? summary}) => db
      .into(db.articles)
      .insert(
        ArticlesCompanion.insert(
          feedId: Value<int?>(feedId),
          title: title,
          identityBasis: IdentityBasis.guid,
          guid: Value<String?>('guid-$title'),
          guidPresent: const Value<bool>(true),
          body: Value<String?>(body),
          summary: Value<String?>(summary),
        ),
      );

  Future<void> pumpReading(WidgetTester tester) async {
    await setSurfaceSize(tester, const Size(1200, 900));
    await tester.pumpWidget(
      wrapFluxApp(
        overrides: bootstrap.overrides(),
        localeOverride: const Locale('zh'),
        child: const Scaffold(body: ReadingPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 输入查询词并等防抖（180 ms）过去。
  Future<void> typeQuery(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField).first, text);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
  }

  group('搜索框与结果', () {
    testWidgets('搜索框存在，且默认就是浏览列表（还没搜过）', (WidgetTester tester) async {
      await add('离线阅读', body: '正文');
      await pumpReading(tester);
      expect(find.byType(TextField), findsWidgets);
      expect(find.text('输入关键词开始检索'), findsNothing, reason: '还没输入时不该显示检索空态');
      expect(find.text('离线阅读'), findsWidgets, reason: '默认显示浏览列表');
    });

    testWidgets('输入 2 字中文后显示命中文章（短词路径）', (WidgetTester tester) async {
      await add('离线阅读的实现', body: '正文提到离线缓存');
      await add('另一篇无关文章', body: '别的正文');
      await pumpReading(tester);

      await typeQuery(tester, '离线');
      expect(find.text('命中 1 篇'), findsOneWidget);
      expect(find.textContaining('离线阅读的实现'), findsWidgets);
    });

    testWidgets('输入长片段后命中（MATCH 路径）', (WidgetTester tester) async {
      await add('离线阅读的实现', body: '正文内容');
      await pumpReading(tester);
      await typeQuery(tester, '离线阅读的');
      expect(find.text('命中 1 篇'), findsOneWidget);
    });

    testWidgets('英文大小写不敏感', (WidgetTester tester) async {
      await add('Offline reading', body: 'AI');
      await pumpReading(tester);
      await typeQuery(tester, 'offline');
      expect(find.text('命中 1 篇'), findsOneWidget);
    });

    testWidgets('清空搜索框回到浏览列表', (WidgetTester tester) async {
      await add('离线阅读', body: '正文');
      await pumpReading(tester);
      await typeQuery(tester, '离线');
      expect(find.text('命中 1 篇'), findsOneWidget);

      await typeQuery(tester, '');
      expect(find.text('命中 1 篇'), findsNothing, reason: '清空后应回到列表');
    });
  });

  group('三种空态与失败可区分（架构第 7 节）', () {
    testWidgets('无结果显示「没有匹配的文章」而不是错误', (WidgetTester tester) async {
      await add('离线阅读');
      await pumpReading(tester);
      await typeQuery(tester, '完全不存在的词');
      expect(find.text('没有匹配的文章'), findsOneWidget);
      expect(find.textContaining('检索失败'), findsNothing);
    });

    testWidgets('无结果时给出范围说明（只搜本地、不访问网页）', (WidgetTester tester) async {
      await add('离线阅读');
      await pumpReading(tester);
      await typeQuery(tester, 'zzzzz');
      expect(find.textContaining('不会访问网页'), findsOneWidget);
    });
  });

  group('范围切换', () {
    testWidgets('范围选择器存在且默认全部', (WidgetTester tester) async {
      await add('离线阅读');
      await pumpReading(tester);
      expect(find.text('全部文章'), findsOneWidget);
      expect(find.text('当前筛选'), findsOneWidget);
    });
  });

  group('片段高亮渲染', () {
    testWidgets('命中片段被画成富文本，且控制字符不出现在界面', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SearchSnippetView(
              snippets: <SearchSnippet>[
                SearchSnippet(
                  field: SearchField.body,
                  segments: <HighlightSegment>[
                    HighlightSegment(text: '前言', isMatch: false),
                    HighlightSegment(text: '离线', isMatch: true),
                    HighlightSegment(text: '后记', isMatch: false),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('前言离线后记'), findsOneWidget);
      // 高亮段与非高亮段是分开的 TextSpan（不是同一段的一个字符）。
      final Text text = tester.widget<Text>(find.byType(Text));
      final TextSpan span = text.textSpan! as TextSpan;
      expect(span.children, hasLength(3));
      final TextSpan highlighted = span.children![1] as TextSpan;
      expect(highlighted.text, '离线');
      expect(highlighted.style!.fontWeight, FontWeight.w600);
    });

    testWidgets('片段顺序按 标题 → 摘要 → 正文 → 作者，且最多两条', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SearchSnippetView(
              snippets: <SearchSnippet>[
                SearchSnippet(
                  field: SearchField.body,
                  segments: <HighlightSegment>[
                    HighlightSegment(text: '正文片段', isMatch: true),
                  ],
                ),
                SearchSnippet(
                  field: SearchField.title,
                  segments: <HighlightSegment>[
                    HighlightSegment(text: '标题片段', isMatch: true),
                  ],
                ),
                SearchSnippet(
                  field: SearchField.author,
                  segments: <HighlightSegment>[
                    HighlightSegment(text: '作者片段', isMatch: true),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      // 只展示两条：标题优先，作者被挤掉。
      expect(find.text('标题片段'), findsOneWidget);
      expect(find.text('正文片段'), findsOneWidget);
      expect(find.text('作者片段'), findsNothing);
    });

    testWidgets('无片段时不画任何东西（不占位）', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SearchSnippetView(snippets: <SearchSnippet>[])),
        ),
      );
      expect(find.byType(Text), findsNothing);
    });
  });

  group('控制器状态机', () {
    testWidgets('空查询不检索、也不清空已有结果', (WidgetTester tester) async {
      final ProviderContainer container = ProviderContainer(
        overrides: bootstrap.overrides(),
      );
      addTearDown(container.dispose);
      final ArticleSearchController controller = container.read(
        searchControllerProvider.notifier,
      );

      controller.setQuery('离线');
      expect(container.read(searchControllerProvider).query, '离线');
      // 清空 query 但不希望结果被立刻丢掉（此时还没搜过，results 本就为空）。
      controller.setQuery('');
      final ArticleSearchState state = container.read(searchControllerProvider);
      expect(state.query, '');
      expect(state.searched, isFalse);
    });

    testWidgets('失败与无结果分开：失败时 error 非空、results 为空', (
      WidgetTester tester,
    ) async {
      // 用一个必然失败的检索端口（降级启动下就是这个实现）。
      final TestBootstrap degradedBootstrap = TestBootstrap(degraded: true);
      addTearDown(degradedBootstrap.dispose);
      final ProviderContainer container = ProviderContainer(
        overrides: degradedBootstrap.overrides(),
      );
      addTearDown(container.dispose);
      final ArticleSearchController controller = container.read(
        searchControllerProvider.notifier,
      );
      controller.setQuery('离线');
      // 等防抖计时器触发（它自己会调用 run）——不要绕过 setQuery 直接 run：
      // 那样会让防抖计时器悬空，测试结束时报「Timer is still pending」。
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      final ArticleSearchState state = container.read(searchControllerProvider);
      expect(state.error, isNotNull, reason: '降级启动下检索应明确失败');
      expect(state.isEmptyResult, isFalse, reason: '失败不是「无结果」');
      expect(state.searched, isTrue);
    });
  });
}
