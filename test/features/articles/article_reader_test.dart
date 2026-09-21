// 正文阅读器组件测试（T019）。
//
// 覆盖手册 6.3 的「渲染」与架构 4.2/第 7 节：
//   - 受控文档渲染（标题/段落/引用/列表/链接/图片占位/表格/行内代码/围栏代码/公式）；
//   - 代码块复制与折叠、未知语言按纯文本；
//   - 不支持的命令显示原式与提示（不空白）；
//   - 目录（h1–h3）、上下篇边界（首/尾）、页内查找计数；
//   - 完整性四态显示；
//   - MarkReadOnOpen 集成（打开 unread→read、later 不变）。
//
// 断言的层次与 T017 一致：这里验证「界面确实画对了」，解析规则由
// markdown_to_document_test 用纯 Dart 验证。
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/articles/application/reader_outline.dart';
import 'package:flux/features/articles/domain/markdown_to_document.dart';
import 'package:flux/features/articles/presentation/article_detail_page.dart';
import 'package:flux/features/articles/presentation/reader/doc_blocks.dart';
import 'package:flux/features/articles/presentation/reader/doc_renderer.dart';
import 'package:flux/features/articles/presentation/reader/doc_theme.dart';
import 'package:flux/features/articles/presentation/reader/reader_chrome.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/feed_catalog_store.dart';
import 'package:flux/infrastructure/local/tables/article_tables.dart';

import '../../app/test_harness.dart';

/// 测试用排版（浅色 token 表）。
const DocTypography kTestTypography = DocTypography(
  baseSize: 18,
  theme: DocTheme(
    background: Color(0xFFF6F7F9),
    surface: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF20242B),
    textSecondary: Color(0xFF596273),
    border: Color(0xFFD9DEE7),
    accent: Color(0xFF315E52),
    selectedSurface: Color(0xFFE8F0EC),
    danger: Color(0xFFB42318),
    warningSurface: Color(0xFFFFF4E5),
    codeBackground: Color(0xFFF2F4F7),
    readingPaper: Color(0xFFF4EEDC),
    brightness: Brightness.light,
  ),
);

/// 厨房水槽（受控文档渲染的覆盖面）。
// 用拼接而不是三引号：fixture 里本身含有三引号围栏，直接内嵌会让字面量提前结束。
const String kKitchenSink =
    '# 标题\n'
    '\n'
    '段落文字。\n'
    '\n'
    '> 引用内容\n'
    '\n'
    '- 项目一\n'
    '- 项目二\n'
    '\n'
    '1. 有序一\n'
    '2. 有序二\n'
    '\n'
    '```dart\n'
    'void main() {}\n'
    '```\n'
    '\n'
    '| 列一 | 列二 |\n'
    '| --- | --- |\n'
    '| 1 | 2 |\n'
    '\n'
    '---\n';

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

  Future<int> seedArticle(
    String title, {
    String? body,
    String? author,
    ReadingState state = ReadingState.unread,
    BodyCompleteness completeness = BodyCompleteness.sourceBody,
  }) => db
      .into(db.articles)
      .insert(
        ArticlesCompanion.insert(
          feedId: Value<int?>(feedId),
          title: title,
          identityBasis: IdentityBasis.guid,
          guid: Value<String?>('guid-$title'),
          guidPresent: const Value<bool>(true),
          body: Value<String?>(body),
          author: Value<String?>(author),
          bodyCompleteness: Value<BodyCompleteness>(completeness),
          readingState: Value<ReadingState>(state),
        ),
      );

  /// 只渲染受控文档（不经过数据库与页面），用于渲染层的细粒度断言。
  Future<void> pumpDoc(WidgetTester tester, String markdown) async {
    await tester.pumpWidget(
      wrapFluxApp(
        // 包一层滚动：fixture 比测试视口高，直接挂 Column 会溢出（溢出会掩盖真正的
        // 断言失败，而不是让测试更容易通过）。
        child: SingleChildScrollView(
          child: DocDocumentView(
            document: parseMarkdownToDocument(markdown),
            typography: kTestTypography,
          ),
        ),
        overrides: bootstrap.overrides(),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('受控文档渲染', () {
    testWidgets('每种块级构造都画出来了', (WidgetTester tester) async {
      await pumpDoc(tester, kKitchenSink);
      expect(find.text('标题'), findsOneWidget);
      expect(find.text('段落文字。'), findsOneWidget);
      expect(find.textContaining('引用内容'), findsOneWidget);
      expect(find.textContaining('项目一'), findsOneWidget);
      expect(find.textContaining('有序一'), findsOneWidget);
      expect(find.byType(CodeBlockView), findsOneWidget);
      expect(find.byType(TableView), findsOneWidget);
      expect(find.text('列一'), findsOneWidget);
    });

    testWidgets('图片位保留版位与替代文字，并且可点击（T020 打开查看器）', (WidgetTester tester) async {
      await pumpDoc(tester, '![图说](https://example.com/i.png)');
      expect(find.textContaining('图说'), findsOneWidget);
      // 图片块现在会真的尝试加载（T020；缓存与限额属 T021），因此这里不再断言占位图标，
      // 而是断言「替代文字仍在」与「可点」——这两条才是产品要求。
      expect(find.byType(InkWell), findsWidgets, reason: '图片位可点击以打开查看器');
      expect(find.textContaining('https://example.com/i.png'), findsOneWidget);
    });

    testWidgets('危险链接可见但不可点（不静默丢弃）', (WidgetTester tester) async {
      await pumpDoc(tester, '[点我](javascript:alert(1))');
      expect(find.textContaining('点我'), findsOneWidget);
      expect(find.textContaining('已拦截'), findsOneWidget);
    });

    testWidgets('围栏代码块：语言标签与复制按钮', (WidgetTester tester) async {
      await pumpDoc(tester, kDartFence);
      expect(find.text('dart'), findsOneWidget);
      expect(find.text('复制代码'), findsOneWidget);
      expect(find.textContaining('void main()'), findsOneWidget);
    });

    testWidgets('未知语言按纯文本显示（不冒充认出语言）', (WidgetTester tester) async {
      await pumpDoc(tester, kUnknownFence);
      expect(find.text('纯文本'), findsOneWidget);
      expect(find.text('notalanguage'), findsNothing);
    });

    testWidgets('长代码块默认折叠，可展开', (WidgetTester tester) async {
      await pumpDoc(tester, kLongFence);
      expect(find.textContaining('展开'), findsOneWidget);
      await tester.tap(find.textContaining('展开'));
      await tester.pumpAndSettle();
      expect(find.text('折叠'), findsOneWidget);
    });

    testWidgets('不支持的 LaTeX 命令显示原式与原因，不留空白', (WidgetTester tester) async {
      await pumpDoc(tester, kBadMath);
      expect(find.textContaining('公式无法渲染'), findsOneWidget);
      // 原式在提示里出现两次（未渲染的公式本体与原因里的表达式），因此这里断言
      // 「可见」而不是「恰好一个」——关键是它没有被吞掉。
      expect(find.textContaining('thiscommanddoesnotexist'), findsWidgets);
      expect(find.textContaining('原因：'), findsOneWidget);
    });

    testWidgets('常用公式真的被排版（不是回退提示）', (WidgetTester tester) async {
      await pumpDoc(tester, kGoodMath);
      expect(find.textContaining('公式无法渲染'), findsNothing);
    });
  });

  group('目录与上下篇', () {
    test('目录只取 h1–h3，按文档顺序，带块下标', () {
      final DocDocument doc = parseMarkdownToDocument(kOutlineDoc);
      final List<ReaderOutlineEntry> outline = extractOutline(doc);
      expect(outline.map((ReaderOutlineEntry e) => e.label).toList(), <String>[
        '一级',
        '二级',
      ]);
      expect(outline.first.level, 1);
      expect(outline.first.blockIndex, 0);
      // h4 不进目录，因此目录最后一项是下标 1 的那个 h2。
      expect(outline.last.blockIndex, 1);
    });

    test('空标题不进目录（否则会成为一个点不动的条目）', () {
      final DocDocument doc = parseMarkdownToDocument(kEmptyHeadingDoc);
      expect(extractOutline(doc), isEmpty);
    });

    test('上下篇边界：首篇无上一篇、末篇无下一篇、单篇两者都无', () {
      const ReaderSnapshot first = ReaderSnapshot(
        orderedIds: <int>[1, 2, 3],
        index: 0,
        filter: ArticleFilter.all,
        feedId: null,
      );
      expect(first.hasPrevious, isFalse);
      expect(first.previousId, isNull);
      expect(first.nextId, 2);

      const ReaderSnapshot last = ReaderSnapshot(
        orderedIds: <int>[1, 2, 3],
        index: 2,
        filter: ArticleFilter.all,
        feedId: null,
      );
      expect(last.hasNext, isFalse);
      expect(last.nextId, isNull);
      expect(last.previousId, 2);

      const ReaderSnapshot single = ReaderSnapshot(
        orderedIds: <int>[7],
        index: 0,
        filter: ArticleFilter.all,
        feedId: null,
      );
      expect(single.hasPrevious, isFalse);
      expect(single.hasNext, isFalse);
    });

    test('当前文章不在快照里时不谎报相邻（index = -1）', () {
      const ReaderSnapshot missing = ReaderSnapshot(
        orderedIds: <int>[1, 2],
        index: -1,
        filter: ArticleFilter.all,
        feedId: null,
      );
      expect(missing.hasPrevious, isFalse);
      expect(missing.hasNext, isFalse);
    });

    testWidgets('底栏在无快照时不显示可用的上下篇，而是说明依据', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapFluxApp(
          child: NeighborBar(
            snapshot: null,
            currentId: 1,
            onNavigate: (int _) {},
          ),
          overrides: bootstrap.overrides(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('快照'), findsOneWidget);
    });
  });

  group('页内查找', () {
    test('计数按纯文本统计（跨节点也算法）', () {
      final DocDocument doc = parseMarkdownToDocument(
        '矩阵 与 **矩阵** 都出现，还有一个 矩阵。',
      );
      expect(DocDocumentView.countMatches(doc, '矩阵'), 3);
      expect(DocDocumentView.countMatches(doc, 'x'), 0);
      expect(DocDocumentView.countMatches(doc, ''), 0, reason: '空查询不算匹配');
    });

    test('大小写不敏感', () {
      final DocDocument doc = parseMarkdownToDocument('Flutter 与 flutter');
      expect(DocDocumentView.countMatches(doc, 'FLUTTER'), 2);
    });
  });

  group('详情页与 SET-010 集成', () {
    testWidgets('完整性四态各自显示', (WidgetTester tester) async {
      for (final (BodyCompleteness value, String label) entry
          in <(BodyCompleteness, String)>[
            (BodyCompleteness.sourceBody, '来源全文'),
            (BodyCompleteness.summaryOnly, '仅摘要'),
            (BodyCompleteness.extracted, '本机提取'),
            (BodyCompleteness.unknown, '完整性未知'),
          ]) {
        await tester.pumpWidget(
          wrapFluxApp(
            child: CompletenessBadge(
              completeness: entry.$1,
              color: const Color(0xFF596273),
              border: const Color(0xFFD9DEE7),
            ),
            overrides: bootstrap.overrides(),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(entry.$2), findsOneWidget);
      }
    });

    testWidgets('打开 unread 文章：自动标已读，正文渲染出来', (WidgetTester tester) async {
      final int id = await seedArticle('未读文章', body: kArticleBody);
      await tester.pumpWidget(
        wrapFluxApp(
          child: ArticleDetailPage(articleId: id, initialTitle: '未读文章'),
          overrides: bootstrap.overrides(),
        ),
      );
      await tester.pumpAndSettle();

      final Article row = await (db.select(
        db.articles,
      )..where((Articles t) => t.id.equals(id))).getSingle();
      expect(
        row.readingState,
        ReadingState.read,
        reason: 'SET-010：unread → read',
      );
      expect(find.text('小节'), findsOneWidget, reason: '受控文档渲染出标题');
      expect(find.textContaining('正文内容。'), findsOneWidget);
    });

    testWidgets('打开 later 文章：状态不变（later 不自动标已读）', (WidgetTester tester) async {
      final int id = await seedArticle(
        '稍后读文章',
        body: '正文',
        state: ReadingState.later,
      );
      await tester.pumpWidget(
        wrapFluxApp(
          child: ArticleDetailPage(articleId: id),
          overrides: bootstrap.overrides(),
        ),
      );
      await tester.pumpAndSettle();

      final Article row = await (db.select(
        db.articles,
      )..where((Articles t) => t.id.equals(id))).getSingle();
      expect(row.readingState, ReadingState.later);
    });

    testWidgets('没有正文：说明「源只提供了摘要」而不是渲染失败', (WidgetTester tester) async {
      final int id = await seedArticle(
        '只有摘要',
        completeness: BodyCompleteness.summaryOnly,
      );
      await tester.pumpWidget(
        wrapFluxApp(
          child: ArticleDetailPage(articleId: id),
          overrides: bootstrap.overrides(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('仅摘要'), findsOneWidget);
      // 「只提供了摘要」出现在两处：无正文说明与「仅摘要不是全文」的横幅。
      expect(find.textContaining('只提供了摘要'), findsWidgets, reason: '显式说明不是全文');
    });

    testWidgets('详情页显示作者与来源', (WidgetTester tester) async {
      final int id = await seedArticle('有作者', body: '正文', author: '张三');
      await tester.pumpWidget(
        wrapFluxApp(
          child: ArticleDetailPage(articleId: id),
          overrides: bootstrap.overrides(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('张三'), findsOneWidget);
      expect(find.textContaining('示例源'), findsOneWidget);
    });
  });
}

/// 有语言的围栏代码块。
const String kDartFence =
    '```dart\n'
    'void main() {}\n'
    '```';

/// 未知语言的围栏代码块（应按纯文本显示）。
const String kUnknownFence =
    '```notalanguage\n'
    'some text\n'
    '```';

/// 超过折叠阈值的长代码块。
const String kLongFence =
    '```dart\n'
    'line-0\nline-1\nline-2\nline-3\nline-4\n'
    'line-5\nline-6\nline-7\nline-8\nline-9\n'
    'line-10\nline-11\nline-12\nline-13\nline-14\n'
    'line-15\nline-16\nline-17\nline-18\nline-19\n'
    'line-20\nline-21\nline-22\nline-23\nline-24\n'
    'line-25\nline-26\nline-27\nline-28\nline-29\n'
    'line-30\nline-31\nline-32\nline-33\nline-34\n'
    'line-35\nline-36\nline-37\nline-38\nline-39\n'
    '```';

/// 不支持的 LaTeX 命令：必须显示原式与原因。
const String kBadMath = r'公式 $\thiscommanddoesnotexist{abc}$ 结束';

/// 常用 LaTeX：必须被真正排版。
const String kGoodMath = r'结果是 $E = mc^2$ 的关系';

/// 目录 fixture（h1/h2 进目录，h4 不进）。
const String kOutlineDoc = '''# 一级

## 二级

#### 四级不进目录
''';

/// 空标题 fixture。
const String kEmptyHeadingDoc = '''##

正文
''';

/// 详情页正文 fixture。
const String kArticleBody = '''# 小节

正文内容。
''';
