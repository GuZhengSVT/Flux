// 刷新流水线测试（T013；架构 4.1、手册 6.3「身份」）。
//
// 覆盖手册点名的必测用例：
//   - 同 Feed 同 GUID 重复导入不新增；
//   - **两个 Feed 有相同 GUID 不合并**（GUID 只在源内识别）；
//   - 无 GUID 按规范化链接；带参数 URL 不损坏；
//   - 正文修订：正文变了要更新正文，但**保留阅读状态与收藏**；
//   - 无日期用抓取时间且不伪造发布时间；
//   - 304 不更新任何文章；
//   - 解析失败/网络失败保留旧内容；
//   - 每个 fixture 都走本地，不联网。
library;

import 'dart:convert';

// drift 与 matcher 都导出 isNull/isNotNull；本文件只用 drift 的 Value与 companion，
// 断言用 matcher 版本，因此把两个同名符号从 drift 隐藏。
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/feeds/application/refresh_feed.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/feed_store_adapter.dart';
import 'package:flux/infrastructure/local/tables/article_tables.dart';
import 'package:flux/infrastructure/network/feed_fetcher.dart';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 记录调用的诊断 sink（验证「失败要留痕」）。
final class _RecordingSink implements DiagnosticSink {
  final List<String> messages = <String>[];

  @override
  void record(DiagnosticSeverity severity, String message, {String? tag}) =>
      messages.add('${severity.name}:$tag:$message');

  @override
  void error(String message, {String? tag}) =>
      record(DiagnosticSeverity.error, message, tag: tag);

  @override
  void warning(String message, {String? tag}) =>
      record(DiagnosticSeverity.warning, message, tag: tag);

  @override
  void info(String message, {String? tag}) =>
      record(DiagnosticSeverity.info, message, tag: tag);
}

/// 一个按 URL 返回响应的 fetcher（避免依赖真实网络）。
FeedFetcher _fetcherFor(
  Map<String, http.Response> routes, {
  FeedFetchConfig config = const FeedFetchConfig(),
}) {
  return HttpFeedFetcher(
    client: MockClient((http.Request request) async {
      final http.Response? response = routes[request.url.toString()];
      if (response == null) {
        return http.Response('not found', 404);
      }
      return response;
    }),
    config: config,
  );
}

http.Response _xml(String body, {int status = 200}) => http.Response.bytes(
  utf8.encode(body),
  status,
  headers: <String, String>{'content-type': 'application/xml; charset=utf-8'},
);

/// 固定时钟（让抓取时间可预测）。
final class _FixedClock implements Clock {
  const _FixedClock(this._now);

  final DateTime _now;

  @override
  DateTime now() => _now;

  @override
  Duration monotonic() => Duration.zero;
}

const String _rssOne = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel>
  <title>测试源</title>
  <link>https://feeds.example.com/</link>
  <item>
    <title>第一篇文章</title>
    <link>https://feeds.example.com/posts/1?utm_source=rss&amp;id=1</link>
    <guid isPermaLink="false">post-1</guid>
    <pubDate>Sun, 20 Sep 2026 22:15:00 GMT</pubDate>
    <description>摘要一</description>
    <content:encoded xmlns:content="http://purl.org/rss/1.0/modules/content/">
      <![CDATA[<p>正文一</p>]]>
    </content:encoded>
  </item>
  <item>
    <title>第二篇文章</title>
    <link>https://feeds.example.com/posts/2</link>
    <guid isPermaLink="false">post-2</guid>
    <pubDate>Sun, 20 Sep 2026 23:15:00 GMT</pubDate>
    <description>摘要二</description>
    <content:encoded xmlns:content="http://purl.org/rss/1.0/modules/content/">
      <![CDATA[<p>正文二</p>]]>
    </content:encoded>
  </item>
</channel></rss>''';

void main() {
  late AppDatabase db;
  late FeedArticleStore store;
  late int feedA;
  late int feedB;

  /// 建库并创建两个源（用于「同 GUID 异 feed 不合并」）。
  Future<void> setUpDatabase() async {
    db = AppDatabase.memory();
    await db.customSelect('SELECT 1').get();
    store = DriftFeedArticleStore(db);
    feedA = await db
        .into(db.feeds)
        .insert(
          FeedsCompanion.insert(
            syncId: 'feed-a',
            normalizedUrl: 'https://feeds.example.com/a.xml',
            name: '源 A',
          ),
        );
    feedB = await db
        .into(db.feeds)
        .insert(
          FeedsCompanion.insert(
            syncId: 'feed-b',
            normalizedUrl: 'https://feeds.example.com/b.xml',
            name: '源 B',
          ),
        );
  }

  setUp(setUpDatabase);
  tearDown(() async => db.close());

  Future<List<Article>> allArticles() => db.select(db.articles).get();

  /// 构造用例。
  RefreshFeedUseCase buildUseCase({
    required Map<String, http.Response> routes,
    DiagnosticSink? diagnostics,
    DateTime? now,
    FeedFetchConfig config = const FeedFetchConfig(),
  }) => RefreshFeedUseCase(
    fetcher: _fetcherFor(routes, config: config),
    store: store,
    diagnostics: diagnostics ?? const NoopDiagnosticSink(),
    clock: _FixedClock(now ?? DateTime.utc(2026, 9, 21, 12)),
  );

  group('成功路径', () {
    test('首次抓取：条目入库、正文清洗、字段正确', () async {
      final RefreshFeedUseCase useCase = buildUseCase(
        routes: <String, http.Response>{
          'https://feeds.example.com/a.xml': _xml(_rssOne),
        },
      );

      final FeedRefreshResult result = await useCase(
        FeedRefreshRequest(
          feedId: feedA,
          url: Uri.parse('https://feeds.example.com/a.xml'),
        ),
      );

      expect(result.outcome, FeedRefreshOutcome.updated);
      expect(result.inserted, 2);
      expect(result.error, isNull);

      final List<Article> articles = await allArticles();
      expect(articles, hasLength(2));

      final Article first = articles.firstWhere(
        (Article a) => a.guid == 'post-1',
      );
      expect(first.title, '第一篇文章');
      expect(first.body, '正文一', reason: '正文是清洗后的受控文档纯文本（HTML 标签被解析掉）');
      expect(first.bodyCompleteness, BodyCompleteness.sourceBody);
      expect(first.summary, '摘要一');
      expect(first.publishedAt, DateTime.utc(2026, 9, 20, 22, 15));
      expect(first.readingState, ReadingState.unread);
      expect(first.favorite, isFalse);
      expect(
        first.sourceUrl,
        'https://feeds.example.com/posts/1?utm_source=rss&id=1',
        reason: '原始链接必须保留跟踪参数（外开时要用原地址）',
      );
      expect(
        first.normalizedLink,
        'https://feeds.example.com/posts/1?id=1',
        reason: '规范化链接剥离跟踪参数，仅用于匹配',
      );
      expect(first.bodyHash, isNotNull);
    });

    test('全部条目已存在且无变化时结果为 unchanged（不产生多余写入）', () async {
      final RefreshFeedUseCase useCase = buildUseCase(
        routes: <String, http.Response>{
          'https://feeds.example.com/a.xml': _xml(_rssOne),
        },
      );
      final FeedRefreshRequest request = FeedRefreshRequest(
        feedId: feedA,
        url: Uri.parse('https://feeds.example.com/a.xml'),
      );

      await useCase(request);
      final DateTime afterFirst = (await allArticles()).first.updatedAt;

      final FeedRefreshResult second = await useCase(request);
      expect(second.outcome, FeedRefreshOutcome.unchanged);
      expect(second.inserted, 0);
      expect(second.imported!.unchanged, 2);
      expect(await allArticles(), hasLength(2), reason: '不新增行');
      expect(
        (await allArticles()).first.updatedAt,
        afterFirst,
        reason: '无变化时连 updatedAt 都不应推进',
      );
    });

    test('条件请求缓存被写回（下次可发 If-None-Match）', () async {
      final RefreshFeedUseCase useCase = buildUseCase(
        routes: <String, http.Response>{
          'https://feeds.example.com/a.xml': http.Response.bytes(
            utf8.encode(_rssOne),
            200,
            headers: <String, String>{
              'etag': '"rev-1"',
              'last-modified': 'Sun, 20 Sep 2026 23:20:00 GMT',
            },
          ),
        },
      );

      await useCase(
        FeedRefreshRequest(
          feedId: feedA,
          url: Uri.parse('https://feeds.example.com/a.xml'),
        ),
      );

      final Feed feed = (await db.select(db.feeds).get()).firstWhere(
        (Feed f) => f.id == feedA,
      );
      expect(feed.httpEtag, '"rev-1"');
      expect(feed.httpLastModified, 'Sun, 20 Sep 2026 23:20:00 GMT');
      expect(feed.lastCheckedAt, DateTime.utc(2026, 9, 21, 12));
      expect(feed.lastRefreshResult, 'updated');
      expect(feed.lastRefreshErrorKind, isNull);
    });

    test('响应未带 ETag 时不覆盖已有缓存值（否则退化成每次全量下载）', () async {
      // 第一次带 ETag。
      await buildUseCase(
        routes: <String, http.Response>{
          'https://feeds.example.com/a.xml': http.Response.bytes(
            utf8.encode(_rssOne),
            200,
            headers: <String, String>{'etag': '"keep-me"'},
          ),
        },
      )(
        FeedRefreshRequest(
          feedId: feedA,
          url: Uri.parse('https://feeds.example.com/a.xml'),
        ),
      );

      // 第二次响应没有 ETag。
      final RefreshFeedUseCase second = buildUseCase(
        routes: <String, http.Response>{
          'https://feeds.example.com/a.xml': _xml(_rssOne),
        },
      );
      await second(
        FeedRefreshRequest(
          feedId: feedA,
          url: Uri.parse('https://feeds.example.com/a.xml'),
        ),
      );

      final Feed feed = (await db.select(db.feeds).get()).firstWhere(
        (Feed f) => f.id == feedA,
      );
      expect(feed.httpEtag, '"keep-me"', reason: '缺失的头不得清掉已有缓存');
    });
  });

  group('304 与失败：保留旧内容', () {
    test('304：不更新任何文章、记录检查时间与 notModified', () async {
      // 先成功抓一次。
      await buildUseCase(
        routes: <String, http.Response>{
          'https://feeds.example.com/a.xml': _xml(_rssOne),
        },
        now: DateTime.utc(2026, 9, 21, 10),
      )(
        FeedRefreshRequest(
          feedId: feedA,
          url: Uri.parse('https://feeds.example.com/a.xml'),
        ),
      );
      final List<Article> before = await allArticles();

      // 第二次 304（并把缓存值传进去，模拟真实调用）。
      final RefreshFeedUseCase useCase = buildUseCase(
        routes: <String, http.Response>{
          'https://feeds.example.com/a.xml': http.Response('', 304),
        },
        now: DateTime.utc(2026, 9, 21, 12),
      );
      final FeedRefreshResult result = await useCase(
        FeedRefreshRequest(
          feedId: feedA,
          url: Uri.parse('https://feeds.example.com/a.xml'),
          etag: '"rev-1"',
        ),
      );

      expect(result.outcome, FeedRefreshOutcome.notModified);
      expect(result.didWrite, isFalse, reason: '304 不得写任何文章');

      final List<Article> after = await allArticles();
      expect(after, hasLength(before.length));
      expect(
        after.first.updatedAt,
        before.first.updatedAt,
        reason: '304 时文章行必须完全不动',
      );

      final Feed feed = (await db.select(db.feeds).get()).firstWhere(
        (Feed f) => f.id == feedA,
      );
      expect(
        feed.lastCheckedAt,
        DateTime.utc(2026, 9, 21, 12),
        reason: '304 也要推进「上次检查时间」',
      );
      expect(feed.lastRefreshResult, 'notModified');
    });

    test('网络失败：旧内容保留、记录检查时间与错误类别', () async {
      await buildUseCase(
        routes: <String, http.Response>{
          'https://feeds.example.com/a.xml': _xml(_rssOne),
        },
      )(
        FeedRefreshRequest(
          feedId: feedA,
          url: Uri.parse('https://feeds.example.com/a.xml'),
        ),
      );
      final List<Article> before = await allArticles();

      final _RecordingSink sink = _RecordingSink();
      final RefreshFeedUseCase failing = buildUseCase(
        routes: <String, http.Response>{
          'https://feeds.example.com/a.xml': http.Response('boom', 503),
        },
        diagnostics: sink,
        now: DateTime.utc(2026, 9, 21, 13),
      );
      final FeedRefreshResult result = await failing(
        FeedRefreshRequest(
          feedId: feedA,
          url: Uri.parse('https://feeds.example.com/a.xml'),
        ),
      );

      expect(result.outcome, FeedRefreshOutcome.networkFailed);
      expect(result.error, isA<NetworkError>());
      expect(await allArticles(), hasLength(before.length), reason: '保留旧内容');
      expect(sink.messages, isNotEmpty, reason: '失败必须留痕');

      final Feed feed = (await db.select(db.feeds).get()).firstWhere(
        (Feed f) => f.id == feedA,
      );
      expect(feed.lastRefreshResult, 'networkFailed');
      expect(feed.lastRefreshErrorKind, 'network');
      expect(feed.lastCheckedAt, DateTime.utc(2026, 9, 21, 13));
    });

    test('解析失败：旧内容保留、记为 parseFailed、保留条件缓存', () async {
      await buildUseCase(
        routes: <String, http.Response>{
          'https://feeds.example.com/a.xml': http.Response.bytes(
            utf8.encode(_rssOne),
            200,
            headers: <String, String>{'etag': '"good-etag"'},
          ),
        },
      )(
        FeedRefreshRequest(
          feedId: feedA,
          url: Uri.parse('https://feeds.example.com/a.xml'),
        ),
      );
      final List<Article> before = await allArticles();

      final _RecordingSink sink = _RecordingSink();
      final RefreshFeedUseCase broken = buildUseCase(
        routes: <String, http.Response>{
          'https://feeds.example.com/a.xml': _xml(
            '<rss version="2.0"><channel><item><title>坏了',
          ),
        },
        diagnostics: sink,
      );
      final FeedRefreshResult result = await broken(
        FeedRefreshRequest(
          feedId: feedA,
          url: Uri.parse('https://feeds.example.com/a.xml'),
        ),
      );

      expect(result.outcome, FeedRefreshOutcome.parseFailed);
      expect(result.error, isA<ParseError>());
      expect(await allArticles(), hasLength(before.length));
      expect(sink.messages.any((String m) => m.contains('feed.parse')), isTrue);

      final Feed feed = (await db.select(db.feeds).get()).firstWhere(
        (Feed f) => f.id == feedA,
      );
      expect(feed.lastRefreshResult, 'parseFailed');
      expect(feed.lastRefreshErrorKind, 'parse');
      expect(
        feed.httpEtag,
        '"good-etag"',
        reason: '源内容坏了不代表缓存失效，保留条件请求才能在恢复后立刻命中 304',
      );
    });

    test('含 DTD 的响应被拒绝，且不写入任何文章', () async {
      final _RecordingSink sink = _RecordingSink();
      final RefreshFeedUseCase useCase = buildUseCase(
        routes: <String, http.Response>{
          'https://feeds.example.com/a.xml': _xml(
            '<?xml version="1.0"?>'
            '<!DOCTYPE rss [<!ENTITY xxe SYSTEM "file:///etc/passwd">]>'
            '<rss version="2.0"><channel><item><title>&xxe;</title></item>'
            '</channel></rss>',
          ),
        },
        diagnostics: sink,
      );
      final FeedRefreshResult result = await useCase(
        FeedRefreshRequest(
          feedId: feedA,
          url: Uri.parse('https://feeds.example.com/a.xml'),
        ),
      );

      expect(result.outcome, FeedRefreshOutcome.parseFailed);
      expect(await allArticles(), isEmpty);
      expect(
        sink.messages.any((String m) => m.contains('/etc/passwd')),
        isFalse,
        reason: '诊断不得回显被拒绝文档里的敏感路径',
      );
    });
  });

  group('去重与身份（手册 6.3「身份」）', () {
    test('同一源同 GUID 重复导入不新增', () async {
      final RefreshFeedUseCase useCase = buildUseCase(
        routes: <String, http.Response>{
          'https://feeds.example.com/a.xml': _xml(_rssOne),
        },
      );
      final FeedRefreshRequest request = FeedRefreshRequest(
        feedId: feedA,
        url: Uri.parse('https://feeds.example.com/a.xml'),
      );
      await useCase(request);
      await useCase(request);
      expect(await allArticles(), hasLength(2));
    });

    test('**两个源有相同 GUID 不合并**（GUID 只在源内识别）', () async {
      // 两个源用同一份内容（相同的 guid），但属于不同 feed。
      final RefreshFeedUseCase useCase = buildUseCase(
        routes: <String, http.Response>{
          'https://feeds.example.com/a.xml': _xml(_rssOne),
          'https://feeds.example.com/b.xml': _xml(_rssOne),
        },
      );

      await useCase(
        FeedRefreshRequest(
          feedId: feedA,
          url: Uri.parse('https://feeds.example.com/a.xml'),
        ),
      );
      await useCase(
        FeedRefreshRequest(
          feedId: feedB,
          url: Uri.parse('https://feeds.example.com/b.xml'),
        ),
      );

      final List<Article> articles = await allArticles();
      expect(articles, hasLength(4), reason: '两个源各自持有同 GUID 的两篇');
      expect(
        articles.where((Article a) => a.guid == 'post-1'),
        hasLength(2),
        reason: '同 GUID 在不同源里是两篇文章',
      );
      expect(articles.map((Article a) => a.feedId).toSet(), <int>{
        feedA,
        feedB,
      });
    });

    test('无 GUID 时按规范化链接去重（跟踪参数不同视为同一篇）', () async {
      const String noGuid = '''<?xml version="1.0"?>
<rss version="2.0"><channel>
  <item>
    <title>无 GUID 文章</title>
    <link>https://feeds.example.com/posts/x?utm_source=rss&amp;utm_campaign=weekly&amp;id=9</link>
    <description>摘要</description>
  </item>
</channel></rss>''';
      // 第二次把跟踪参数换个顺序/换名字，语义相同。
      const String noGuidVariant = '''<?xml version="1.0"?>
<rss version="2.0"><channel>
  <item>
    <title>无 GUID 文章</title>
    <link>https://feeds.example.com/posts/x?id=9&amp;utm_medium=email</link>
    <description>摘要</description>
  </item>
</channel></rss>''';

      await buildUseCase(
        routes: <String, http.Response>{
          'https://feeds.example.com/a.xml': _xml(noGuid),
        },
      )(
        FeedRefreshRequest(
          feedId: feedA,
          url: Uri.parse('https://feeds.example.com/a.xml'),
        ),
      );

      final FeedRefreshResult second =
          await buildUseCase(
            routes: <String, http.Response>{
              'https://feeds.example.com/a.xml': _xml(noGuidVariant),
            },
          )(
            FeedRefreshRequest(
              feedId: feedA,
              url: Uri.parse('https://feeds.example.com/a.xml'),
            ),
          );

      expect(second.inserted, 0, reason: '规范化后是同一个地址，不得新增');
      expect(await allArticles(), hasLength(1));
      expect(
        (await allArticles()).single.normalizedLink,
        'https://feeds.example.com/posts/x?id=9',
      );
    });

    test('同源不同跟踪参数视为同一篇（不重复入库）', () async {
      const String first = '''<rss version="2.0"><channel>
  <item><title>甲</title>
  <link>https://feeds.example.com/p/1?utm_source=a</link></item>
</channel></rss>''';
      const String second = '''<rss version="2.0"><channel>
  <item><title>甲</title>
  <link>https://feeds.example.com/p/1?utm_source=b</link></item>
</channel></rss>''';

      await buildUseCase(
        routes: <String, http.Response>{
          'https://feeds.example.com/a.xml': _xml(first),
        },
      )(
        FeedRefreshRequest(
          feedId: feedA,
          url: Uri.parse('https://feeds.example.com/a.xml'),
        ),
      );

      final FeedRefreshResult result =
          await buildUseCase(
            routes: <String, http.Response>{
              'https://feeds.example.com/a.xml': _xml(second),
            },
          )(
            FeedRefreshRequest(
              feedId: feedA,
              url: Uri.parse('https://feeds.example.com/a.xml'),
            ),
          );
      expect(result.inserted, 0);
      expect(await allArticles(), hasLength(1));
    });

    test('无 GUID 且无链接时用指纹兜底（来源+标题+时间）', () async {
      const String noIdentity = '''<rss version="2.0"><channel>
  <item><title>只有标题</title>
  <pubDate>Sun, 20 Sep 2026 10:00:00 GMT</pubDate>
  <description>摘要</description></item>
</channel></rss>''';

      final RefreshFeedUseCase useCase = buildUseCase(
        routes: <String, http.Response>{
          'https://feeds.example.com/a.xml': _xml(noIdentity),
        },
      );
      final FeedRefreshRequest request = FeedRefreshRequest(
        feedId: feedA,
        url: Uri.parse('https://feeds.example.com/a.xml'),
      );
      await useCase(request);
      await useCase(request);

      expect(await allArticles(), hasLength(1), reason: '指纹相同应视为同一篇');
      final Article stored = (await allArticles()).single;
      expect(stored.identityBasis, IdentityBasis.fingerprint);
      expect(stored.fallbackFingerprint, isNotNull);
      expect(
        stored.fingerprintReliability,
        FingerprintReliability.reliable,
        reason: '有发布时间时指纹可靠',
      );
    });

    test('无链接且无发布时间的指纹标记为 unreliable', () async {
      const String noDate = '''<rss version="2.0"><channel>
  <item><title>没有日期</title><description>摘要</description></item>
</channel></rss>''';
      await buildUseCase(
        routes: <String, http.Response>{
          'https://feeds.example.com/a.xml': _xml(noDate),
        },
      )(
        FeedRefreshRequest(
          feedId: feedA,
          url: Uri.parse('https://feeds.example.com/a.xml'),
        ),
      );
      final Article stored = (await allArticles()).single;
      expect(stored.fingerprintReliability, FingerprintReliability.unreliable);
      expect(stored.publishedAt, isNull, reason: '源没给日期时必须保持 null，不能伪造一个发布时间');
      expect(
        stored.fetchedAt,
        DateTime.utc(2026, 9, 21, 12),
        reason: '抓取时间由时钟提供，界面据此排序并注明「时间未知」',
      );
    });

    test('不同源的相同标题/时间不会合并（指纹含源标识）', () async {
      const String sameContent = '''<rss version="2.0"><channel>
  <item><title>同标题</title>
  <pubDate>Sun, 20 Sep 2026 10:00:00 GMT</pubDate></item>
</channel></rss>''';
      final RefreshFeedUseCase useCase = buildUseCase(
        routes: <String, http.Response>{
          'https://feeds.example.com/a.xml': _xml(sameContent),
          'https://feeds.example.com/b.xml': _xml(sameContent),
        },
      );
      await useCase(
        FeedRefreshRequest(
          feedId: feedA,
          url: Uri.parse('https://feeds.example.com/a.xml'),
        ),
      );
      await useCase(
        FeedRefreshRequest(
          feedId: feedB,
          url: Uri.parse('https://feeds.example.com/b.xml'),
        ),
      );
      expect(await allArticles(), hasLength(2), reason: '指纹含源标识，不得跨源合并');
      final Set<String?> fingerprints = (await allArticles())
          .map((Article a) => a.fallbackFingerprint)
          .toSet();
      expect(fingerprints, hasLength(2), reason: '两个源的指纹必须不同');
    });
  });

  group('正文修订（保留状态与收藏）', () {
    test('正文变化 → 更新正文；标题/摘要变化 → 更新字段', () async {
      const String original = '''<rss version="2.0"><channel>
  <item><title>修订前</title><guid>rev-1</guid>
  <description>旧摘要</description>
  <content:encoded xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <![CDATA[<p>旧正文</p>]]></content:encoded></item>
</channel></rss>''';
      const String revised = '''<rss version="2.0"><channel>
  <item><title>修订后</title><guid>rev-1</guid>
  <description>新摘要</description>
  <content:encoded xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <![CDATA[<p>新正文</p>]]></content:encoded></item>
</channel></rss>''';

      await buildUseCase(
        routes: <String, http.Response>{
          'https://feeds.example.com/a.xml': _xml(original),
        },
      )(
        FeedRefreshRequest(
          feedId: feedA,
          url: Uri.parse('https://feeds.example.com/a.xml'),
        ),
      );

      // 用户把它标为 later 并收藏。
      final Article before = (await allArticles()).single;
      await (db.update(
        db.articles,
      )..where((Articles t) => t.id.equals(before.id))).write(
        const ArticlesCompanion(
          readingState: Value<ReadingState>(ReadingState.later),
          favorite: Value<bool>(true),
        ),
      );

      final FeedRefreshResult result =
          await buildUseCase(
            routes: <String, http.Response>{
              'https://feeds.example.com/a.xml': _xml(revised),
            },
          )(
            FeedRefreshRequest(
              feedId: feedA,
              url: Uri.parse('https://feeds.example.com/a.xml'),
            ),
          );

      expect(result.bodyUpdated, 1);
      expect(result.inserted, 0);

      final Article after = (await allArticles()).single;
      expect(after.body, '新正文');
      expect(after.title, '修订后');
      expect(after.summary, '新摘要');
      expect(after.bodyHash, isNot(before.bodyHash));
      // 关键：正文更新不得丢用户状态（手册 6.3「正文更新不丢状态」）。
      expect(after.readingState, ReadingState.later);
      expect(after.favorite, isTrue);
    });

    test('正文未变时不做任何写入（哈希相同即同一修订）', () async {
      final RefreshFeedUseCase useCase = buildUseCase(
        routes: <String, http.Response>{
          'https://feeds.example.com/a.xml': _xml(_rssOne),
        },
      );
      await useCase(
        FeedRefreshRequest(
          feedId: feedA,
          url: Uri.parse('https://feeds.example.com/a.xml'),
        ),
      );
      final Article before = (await allArticles()).first;
      await (db.update(
        db.articles,
      )..where((Articles t) => t.id.equals(before.id))).write(
        const ArticlesCompanion(
          readingState: Value<ReadingState>(ReadingState.read),
        ),
      );

      // 再抓同一份内容。
      await useCase(
        FeedRefreshRequest(
          feedId: feedA,
          url: Uri.parse('https://feeds.example.com/a.xml'),
        ),
      );
      final Article after = (await allArticles()).first;
      expect(after.bodyHash, before.bodyHash);
      expect(after.body, before.body);
      expect(after.readingState, ReadingState.read, reason: '状态保持用户选择');
    });

    test('HTML 表面变化但纯文本相同 → 不算修订（避免假修订）', () async {
      const String v1 = '''<rss version="2.0"><channel>
  <item><title>同一篇</title><guid>h-1</guid>
  <content:encoded xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <![CDATA[<p>一样的文字</p>]]></content:encoded></item>
</channel></rss>''';
      const String v2 = '''<rss version="2.0"><channel>
  <item><title>同一篇</title><guid>h-1</guid>
  <content:encoded xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <![CDATA[<p class="x" style="margin:0">一样的文字</p>]]></content:encoded>
  </item>
</channel></rss>''';

      await buildUseCase(
        routes: <String, http.Response>{
          'https://feeds.example.com/a.xml': _xml(v1),
        },
      )(
        FeedRefreshRequest(
          feedId: feedA,
          url: Uri.parse('https://feeds.example.com/a.xml'),
        ),
      );
      final FeedRefreshResult result =
          await buildUseCase(
            routes: <String, http.Response>{
              'https://feeds.example.com/a.xml': _xml(v2),
            },
          )(
            FeedRefreshRequest(
              feedId: feedA,
              url: Uri.parse('https://feeds.example.com/a.xml'),
            ),
          );
      expect(result.bodyUpdated, 0, reason: '正文哈希基于清洗后的文本，属性变化不应触发正文重写');
    });
  });

  group('完整性判定与摘要', () {
    test('只有摘要没有正文时标为 summaryOnly 且 body 为 null', () async {
      const String summaryOnly = '''<rss version="2.0"><channel>
  <item><title>只有摘要</title><guid>s-1</guid>
  <description>这是摘要</description></item>
</channel></rss>''';
      await buildUseCase(
        routes: <String, http.Response>{
          'https://feeds.example.com/a.xml': _xml(summaryOnly),
        },
      )(
        FeedRefreshRequest(
          feedId: feedA,
          url: Uri.parse('https://feeds.example.com/a.xml'),
        ),
      );
      final Article stored = (await allArticles()).single;
      expect(stored.bodyCompleteness, BodyCompleteness.summaryOnly);
      expect(stored.body, isNull);
      expect(stored.bodyHash, isNull);
      expect(stored.summary, '这是摘要');
    });

    test('源内摘要是 HTML 时被清洗成纯文本（列表里不出现标签）', () async {
      const String htmlSummary = '''<rss version="2.0"><channel>
  <item><title>带 HTML 摘要</title><guid>h-2</guid>
  <description>&lt;p&gt;摘要&lt;strong&gt;加粗&lt;/strong&gt;&lt;/p&gt;</description>
  </item>
</channel></rss>''';
      await buildUseCase(
        routes: <String, http.Response>{
          'https://feeds.example.com/a.xml': _xml(htmlSummary),
        },
      )(
        FeedRefreshRequest(
          feedId: feedA,
          url: Uri.parse('https://feeds.example.com/a.xml'),
        ),
      );
      final Article stored = (await allArticles()).single;
      expect(stored.summary, '摘要加粗');
      expect(stored.summary, isNot(contains('<')));
    });

    test('部分条目无效时结果为 partial，有效条目照常入库', () async {
      const String mixed = '''<rss version="2.0"><channel>
  <item><title>有效</title><guid>ok-1</guid>
  <content:encoded xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <![CDATA[<p>正文</p>]]></content:encoded></item>
  <item><description>既没标题也没链接</description></item>
  <item><description>同样无效</description></item>
</channel></rss>''';
      final FeedRefreshResult result =
          await buildUseCase(
            routes: <String, http.Response>{
              'https://feeds.example.com/a.xml': _xml(mixed),
            },
          )(
            FeedRefreshRequest(
              feedId: feedA,
              url: Uri.parse('https://feeds.example.com/a.xml'),
            ),
          );

      expect(result.outcome, FeedRefreshOutcome.partial);
      expect(result.rejectedEntries, 2);
      expect(result.inserted, 1);
      expect(await allArticles(), hasLength(1));
    });

    test('空 channel 不算失败，结果为 unchanged 且无文章', () async {
      final FeedRefreshResult result =
          await buildUseCase(
            routes: <String, http.Response>{
              'https://feeds.example.com/a.xml': _xml(
                '<rss version="2.0"><channel><title>空源</title></channel></rss>',
              ),
            },
          )(
            FeedRefreshRequest(
              feedId: feedA,
              url: Uri.parse('https://feeds.example.com/a.xml'),
            ),
          );
      expect(result.outcome, FeedRefreshOutcome.unchanged);
      expect(result.inserted, 0);
      expect(await allArticles(), isEmpty);
    });
  });

  group('Atom 端到端', () {
    test('Atom 条目也能正确入库（含 xhtml 正文与 feed 级作者）', () async {
      const String atom = '''<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Atom 源</title>
  <link href="https://example.com/atom" rel="alternate"/>
  <author><name>Feed 作者</name></author>
  <entry>
    <title>Atom 文章一</title>
    <link href="https://example.com/atom/one" rel="alternate"/>
    <id>urn:uuid:entry-1</id>
    <published>2026-09-20T21:00:00Z</published>
    <summary>条目摘要</summary>
    <content type="xhtml">
      <div xmlns="http://www.w3.org/1999/xhtml">
        <p>XHTML <strong>正文</strong></p>
      </div>
    </content>
  </entry>
</feed>''';

      final FeedRefreshResult result =
          await buildUseCase(
            routes: <String, http.Response>{
              'https://feeds.example.com/a.xml': _xml(atom),
            },
          )(
            FeedRefreshRequest(
              feedId: feedA,
              url: Uri.parse('https://feeds.example.com/a.xml'),
            ),
          );

      expect(result.inserted, 1);
      final Article stored = (await allArticles()).single;
      expect(stored.guid, 'urn:uuid:entry-1');
      expect(stored.title, 'Atom 文章一');
      expect(stored.author, 'Feed 作者', reason: 'Atom 允许条目继承 feed 级作者');
      expect(stored.body, 'XHTML 正文');
      expect(stored.publishedAt, DateTime.utc(2026, 9, 20, 21));
      expect(stored.bodyCompleteness, BodyCompleteness.sourceBody);
    });
  });
}
