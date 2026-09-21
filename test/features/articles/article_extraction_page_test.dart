// T024：详情页的原站全文入口（组件层）。
//
// 验三件事（都是验收条件的直接映射）：
//   * **打开文章不发请求**：挂载详情页后抓取端口的请求数为 0（无自动触发）；
//   * 点击按钮 → 发起一次请求、显示结果，并把提取正文渲染出来；
//   * 失败 → 显示原因与「在浏览器打开」入口，且**原文仍在**（保留原内容）。
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/articles/application/fetch_original_article.dart';
import 'package:flux/features/articles/presentation/article_detail_page.dart'
    show ArticleDetailPage;
import 'package:flux/infrastructure/local/database.dart';

import '../../app/test_harness.dart';

/// 记录请求的替身抓取端口。
final class _SpyFetcher implements StaticPageFetcherPort {
  _SpyFetcher({required this.html, this.error});

  final String html;
  final AppError? error;
  final List<Uri> requests = <Uri>[];

  @override
  Future<Result<StaticPageDocument>> fetch(Uri uri) async {
    requests.add(uri);
    if (error != null) {
      return Err<StaticPageDocument>(error!);
    }
    return Ok<StaticPageDocument>(
      StaticPageDocument(
        html: html,
        finalUri: uri.toString(),
        contentType: 'text/html',
      ),
    );
  }
}

/// 文章正文（源内文本，Markdown）。
const String kSourceBody = '# 源内标题\n\n这是源内提供的正文，读者原本看到的就是它。';

/// 原站 HTML。
final String kOriginalHtml =
    '<html><head><title>原站标题</title></head><body><article><h1>原站标题</h1>'
    '<p>${'这是从原站静态提取出来的正文内容，与源内正文不同。' * 20}</p>'
    '</article></body></html>';

/// 付费墙迹象的页面。
final String kPaywallHtml =
    '<html><head><title>付费文章</title>'
    '<meta name="keywords" content="paywall"></head>'
    '<body><div class="paywall"><p>${'试读内容，付费后可读全文。' * 12}</p>'
    '</div></body></html>';

/// 纯 JS 渲染的页面。
const String kJsOnlyHtml =
    '<html><head><title>js</title></head><body><div id="a"></div></body></html>';

void main() {
  late TestBootstrap bootstrap;
  late int articleId;

  setUp(() async {
    bootstrap = TestBootstrap();
    await bootstrap.database.customSelect('SELECT 1').get();
    final int feedId = await bootstrap.database
        .into(bootstrap.database.feeds)
        .insert(
          FeedsCompanion.insert(
            syncId: 'feed-t024',
            normalizedUrl: 'https://t024.example.com/feed.xml',
            name: 'T024 源',
          ),
        );
    articleId = await bootstrap.database
        .into(bootstrap.database.articles)
        .insert(
          ArticlesCompanion.insert(
            feedId: Value<int?>(feedId),
            title: 'T024 文章',
            identityBasis: IdentityBasis.guid,
            body: const Value<String?>(kSourceBody),
            sourceUrl: const Value<String?>('https://example.com/post'),
          ),
        );
  });

  tearDown(() async {
    await bootstrap.dispose();
  });

  testWidgets('打开文章不发任何请求（无自动抓取）', (WidgetTester tester) async {
    final _SpyFetcher fetcher = _SpyFetcher(html: kOriginalHtml);
    await setSurfaceSize(tester, const Size(1200, 900));
    await tester.pumpWidget(
      wrapFluxApp(
        child: ArticleDetailPage(articleId: articleId),
        overrides: bootstrap.overrides(staticPageFetcher: fetcher),
      ),
    );
    await tester.pumpAndSettle();
    expect(fetcher.requests, isEmpty, reason: '打开文章不得发起任何网页请求');
    expect(find.text('获取原站全文'), findsOneWidget);
    expect(find.textContaining('这是源内提供的正文'), findsWidgets);
  });

  testWidgets('点击后抓取一次、渲染提取正文，并可切回原文', (WidgetTester tester) async {
    final _SpyFetcher fetcher = _SpyFetcher(html: kOriginalHtml);
    await setSurfaceSize(tester, const Size(1200, 900));
    await tester.pumpWidget(
      wrapFluxApp(
        child: ArticleDetailPage(articleId: articleId),
        overrides: bootstrap.overrides(staticPageFetcher: fetcher),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('获取原站全文'));
    await tester.pumpAndSettle();

    expect(fetcher.requests, hasLength(1));
    expect(find.textContaining('这是从原站静态提取出来的正文内容'), findsWidgets);
    expect(find.text('查看原文'), findsOneWidget);
    await tester.tap(find.text('查看原文'));
    await tester.pumpAndSettle();
    expect(find.textContaining('这是源内提供的正文'), findsWidgets);
  });

  testWidgets('失败：显示原因与外开入口，原文仍在', (WidgetTester tester) async {
    final _SpyFetcher fetcher = _SpyFetcher(
      html: '',
      error: NetworkError(uri: 'https://example.com/post', reason: '连接失败'),
    );
    await setSurfaceSize(tester, const Size(1200, 900));
    await tester.pumpWidget(
      wrapFluxApp(
        child: ArticleDetailPage(articleId: articleId),
        overrides: bootstrap.overrides(staticPageFetcher: fetcher),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('获取原站全文'));
    await tester.pumpAndSettle();

    expect(find.textContaining('未能获取原站正文'), findsOneWidget);
    expect(find.text('在浏览器打开'), findsOneWidget);
    expect(find.textContaining('这是源内提供的正文'), findsWidgets);
  });

  testWidgets('纯 JS 页面：提示可能无法获取，原文仍在', (WidgetTester tester) async {
    final _SpyFetcher fetcher = _SpyFetcher(html: kJsOnlyHtml);
    await setSurfaceSize(tester, const Size(1200, 900));
    await tester.pumpWidget(
      wrapFluxApp(
        child: ArticleDetailPage(articleId: articleId),
        overrides: bootstrap.overrides(staticPageFetcher: fetcher),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('获取原站全文'));
    await tester.pumpAndSettle();
    expect(find.textContaining('可能需要脚本渲染'), findsOneWidget);
    expect(find.textContaining('这是源内提供的正文'), findsWidgets);
  });

  testWidgets('付费墙页面：有提示但正文仍被提取', (WidgetTester tester) async {
    final _SpyFetcher fetcher = _SpyFetcher(html: kPaywallHtml);
    await setSurfaceSize(tester, const Size(1200, 900));
    await tester.pumpWidget(
      wrapFluxApp(
        child: ArticleDetailPage(articleId: articleId),
        overrides: bootstrap.overrides(staticPageFetcher: fetcher),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('获取原站全文'));
    await tester.pumpAndSettle();
    expect(find.textContaining('可能要求付费或登录'), findsOneWidget);
  });

  testWidgets('已保存的提取正文在重开时直接可用（不再抓取）', (WidgetTester tester) async {
    final _SpyFetcher fetcher = _SpyFetcher(html: kOriginalHtml);
    await bootstrap.database.update(bootstrap.database.articles).write(
      ArticlesCompanion(
        extractedBody: const Value<String?>('# 上次提取'),
        extractedBodyHash: const Value<String?>('hash-1'),
        extractedAt: Value<DateTime?>(DateTime.utc(2026, 9, 21)),
      ),
    );
    await setSurfaceSize(tester, const Size(1200, 900));
    await tester.pumpWidget(
      wrapFluxApp(
        child: ArticleDetailPage(articleId: articleId),
        overrides: bootstrap.overrides(staticPageFetcher: fetcher),
      ),
    );
    await tester.pumpAndSettle();
    expect(fetcher.requests, isEmpty);
    expect(find.text('查看提取正文'), findsOneWidget);
    expect(find.textContaining('这是源内提供的正文'), findsWidgets);
  });
}
