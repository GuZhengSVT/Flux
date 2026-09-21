// T024：静态网页抓取与「仅用户显式触发」的用例。
//
// 覆盖验收条件里的四条边界：
//   * URL/DNS/重定向信任边界（与订阅/图片抓取同一条判据链）；
//   * 失败保留原文（用例失败路径上没有任何写操作）；
//   * **无自动触发**（打开文章、读列表都不抓；只有显式调用才发请求）；
//   * 外链安全（危险协议在渲染层已拒；这里验证地址非法时不发请求）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/articles/application/fetch_original_article.dart';
import 'package:flux/infrastructure/network/static_page_fetcher.dart';

/// 记录请求的替身抓取端口。
final class _RecordingFetcher implements StaticPageFetcherPort {
  _RecordingFetcher({this.html, this.error});

  final String? html;
  final AppError? error;

  /// 收到的请求地址（每次调用追加）。
  final List<Uri> requests = <Uri>[];

  @override
  Future<Result<StaticPageDocument>> fetch(Uri uri) async {
    requests.add(uri);
    if (error != null) {
      return Err<StaticPageDocument>(error!);
    }
    return Ok<StaticPageDocument>(
      StaticPageDocument(
        html: html ?? '',
        finalUri: uri.toString(),
        contentType: 'text/html',
      ),
    );
  }
}

/// 记录写入的替身提取存储。
final class _RecordingExtractions implements ArticleExtractionStore {
  _RecordingExtractions();

  /// 已保存的提取结果（按文章 id）。
  final Map<int, ExtractedArticleBody> saved = <int, ExtractedArticleBody>{};

  /// 保存调用次数（用于断言「失败不写」）。
  int saveCalls = 0;

  @override
  Future<Result<ExtractedArticleBody?>> readExtraction(int articleId) async =>
      Ok<ExtractedArticleBody?>(saved[articleId]);

  @override
  Future<Result<void>> saveExtraction({
    required int articleId,
    required ExtractedArticleBody extraction,
  }) async {
    saveCalls++;
    saved[articleId] = extraction;
    return const Ok<void>(null);
  }

  @override
  Future<Result<void>> clearExtraction(int articleId) async {
    saved.remove(articleId);
    return const Ok<void>(null);
  }
}

String _fixture(String name) => File('test/fixtures/$name').readAsStringSync();

/// 写入必然失败的替身存储（验证存储失败不被伪装成成功）。
final class _FailingExtractionStore implements ArticleExtractionStore {
  @override
  Future<Result<ExtractedArticleBody?>> readExtraction(int articleId) async =>
      const Ok<ExtractedArticleBody?>(null);

  @override
  Future<Result<void>> saveExtraction({
    required int articleId,
    required ExtractedArticleBody extraction,
  }) async =>
      Err<void>(StorageError(operation: 'saveExtraction', detail: '测试替身：故意失败'));

  @override
  Future<Result<void>> clearExtraction(int articleId) async =>
      const Ok<void>(null);
}

void main() {
  group('用例：仅有用户显式调用才抓取', () {
    test('调用一次 → 恰好一个请求（不存在自动/批量路径）', () async {
      final _RecordingFetcher fetcher = _RecordingFetcher(
        html: _fixture('static_page_normal.html'),
      );
      final _RecordingExtractions store = _RecordingExtractions();
      final FetchOriginalArticleUseCase useCase = FetchOriginalArticleUseCase(
        fetcher: fetcher,
        extractions: store,
      );
      final Result<FetchOriginalResult> result = await useCase(
        articleId: 1,
        sourceUrl: 'https://example.com/post',
      );
      expect(result.unwrap().outcome, FetchOriginalOutcome.ok);
      expect(fetcher.requests, hasLength(1), reason: '一次调用只发一个请求');
      expect(store.saveCalls, 1);
    });

    test('没有调用 → 没有任何请求（用例对象自身不会在构造时抓取）', () {
      final _RecordingFetcher fetcher = _RecordingFetcher(
        html: _fixture('static_page_normal.html'),
      );
      // 只是构造用例，什么都不做。
      FetchOriginalArticleUseCase(
        fetcher: fetcher,
        extractions: _RecordingExtractions(),
      );
      expect(fetcher.requests, isEmpty);
    });

    test('地址缺失或非法 → 不抓取、不写入，返回失败', () async {
      final _RecordingFetcher fetcher = _RecordingFetcher(
        html: _fixture('static_page_normal.html'),
      );
      final _RecordingExtractions store = _RecordingExtractions();
      final FetchOriginalArticleUseCase useCase = FetchOriginalArticleUseCase(
        fetcher: fetcher,
        extractions: store,
      );
      for (final String? bad in <String?>[
        null,
        '',
        '   ',
        'not a url',
        '/relative',
      ]) {
        final Result<FetchOriginalResult> result = await useCase(
          articleId: 1,
          sourceUrl: bad,
        );
        expect(result.unwrap().outcome, FetchOriginalOutcome.failed);
      }
      expect(fetcher.requests, isEmpty, reason: '地址不可用时一个请求都不该发出去');
      expect(store.saveCalls, 0);
    });
  });

  group('用例：成功路径', () {
    test('成功 → 保存提取正文、返回 ok 且带哈希', () async {
      final _RecordingExtractions store = _RecordingExtractions();
      final FetchOriginalArticleUseCase useCase = FetchOriginalArticleUseCase(
        fetcher: _RecordingFetcher(html: _fixture('static_page_normal.html')),
        extractions: store,
      );
      final FetchOriginalResult result = (await useCase(
        articleId: 7,
        sourceUrl: 'https://example.com/post',
      )).unwrap();
      expect(result.outcome, FetchOriginalOutcome.ok);
      expect(result.saved, isTrue);
      expect(result.paywallHint, isFalse);
      final ExtractedArticleBody stored = store.saved[7]!;
      expect(stored.body, contains('本地优先的阅读器'));
      expect(stored.bodyHash, isNotEmpty);
      expect(stored.imageUrls, isNotEmpty);
      expect(stored.title, '离线阅读的实现细节');
    });

    test('付费墙页面：仍然保存，但带提示', () async {
      final _RecordingExtractions store = _RecordingExtractions();
      final FetchOriginalArticleUseCase useCase = FetchOriginalArticleUseCase(
        fetcher: _RecordingFetcher(html: _fixture('static_page_paywall.html')),
        extractions: store,
      );
      final FetchOriginalResult result = (await useCase(
        articleId: 9,
        sourceUrl: 'https://example.com/paid',
      )).unwrap();
      // 试读部分是可用的，因此保存下来；同时提示付费墙。
      expect(result.outcome, FetchOriginalOutcome.ok);
      expect(result.paywallHint, isTrue);
      expect(store.saved.containsKey(9), isTrue);
    });

    test('纯 JS 页面：不保存、返回 noContent（不假装成功）', () async {
      final _RecordingExtractions store = _RecordingExtractions();
      final FetchOriginalArticleUseCase useCase = FetchOriginalArticleUseCase(
        fetcher: _RecordingFetcher(html: _fixture('static_page_js_only.html')),
        extractions: store,
      );
      final FetchOriginalResult result = (await useCase(
        articleId: 11,
        sourceUrl: 'https://example.com/js',
      )).unwrap();
      expect(result.outcome, FetchOriginalOutcome.noContent);
      expect(store.saveCalls, 0, reason: '没有可用正文时不该写库');
    });
  });

  group('用例：失败保留原文', () {
    test('网络失败 → 不写入任何东西，失败原因可显示', () async {
      final _RecordingExtractions store = _RecordingExtractions();
      final FetchOriginalArticleUseCase useCase = FetchOriginalArticleUseCase(
        fetcher: _RecordingFetcher(
          error: NetworkError(uri: 'https://example.com/x', reason: '连接失败'),
        ),
        extractions: store,
      );
      final FetchOriginalResult result = (await useCase(
        articleId: 3,
        sourceUrl: 'https://example.com/x',
      )).unwrap();
      expect(result.outcome, FetchOriginalOutcome.failed);
      expect(result.error, isNotNull);
      expect(store.saveCalls, 0, reason: '失败不得改动已存正文（架构 4.2）');
      expect(store.saved, isEmpty);
    });

    test('存储失败 → 如实返回失败（不假装已保存）', () async {
      final _FailingExtractionStore store = _FailingExtractionStore();
      final FetchOriginalArticleUseCase useCase = FetchOriginalArticleUseCase(
        fetcher: _RecordingFetcher(html: _fixture('static_page_normal.html')),
        extractions: store,
      );
      final FetchOriginalResult result = (await useCase(
        articleId: 5,
        sourceUrl: 'https://example.com/post',
      )).unwrap();
      expect(result.outcome, FetchOriginalOutcome.failed);
      expect(result.error, isA<StorageError>());
    });
  });

  group('抓取层：地址与重定向信任边界', () {
    test('拒绝非 http(s) 协议（不发请求）', () async {
      final List<Uri> seen = <Uri>[];
      final HttpStaticPageFetcher fetcher = HttpStaticPageFetcher(
        client: MockClient((http.Request request) async {
          seen.add(request.url);
          return http.Response('ok', 200);
        }),
      );
      final Result<StaticPageFetchResult> result = await fetcher.fetch(
        Uri.parse('file:///etc/passwd'),
      );
      expect(result.isErr, isTrue);
      expect(seen, isEmpty);
    });

    test('拒绝字面量私网地址（不发请求）', () async {
      final List<Uri> seen = <Uri>[];
      final HttpStaticPageFetcher fetcher = HttpStaticPageFetcher(
        client: MockClient((http.Request request) async {
          seen.add(request.url);
          return http.Response('ok', 200);
        }),
      );
      for (final String host in <String>[
        'http://127.0.0.1/x',
        'http://10.0.0.5/x',
        'http://169.254.169.254/latest/meta-data/',
        'http://localhost:8080/x',
        'http://[::1]/x',
      ]) {
        final Result<StaticPageFetchResult> result = await fetcher.fetch(
          Uri.parse(host),
        );
        expect(result.isErr, isTrue, reason: '$host 应当被拒绝');
      }
      expect(seen, isEmpty);
    });

    test('公网域名解析到私网地址 → 拒绝（DNS 复检，防 rebinding）', () async {
      final List<Uri> seen = <Uri>[];
      final HttpStaticPageFetcher fetcher = HttpStaticPageFetcher(
        client: MockClient((http.Request request) async {
          seen.add(request.url);
          return http.Response('ok', 200);
        }),
        resolveHost: (String host) async => <InternetAddress>[
          InternetAddress('127.0.0.1'),
        ],
      );
      final Result<StaticPageFetchResult> result = await fetcher.fetch(
        Uri.parse('https://evil.example.com/x'),
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<NetworkError>());
      expect(seen, isEmpty);
    });

    test('重定向到内网地址被拒（每跳都复检）', () async {
      final List<Uri> seen = <Uri>[];
      final HttpStaticPageFetcher fetcher = HttpStaticPageFetcher(
        client: MockClient((http.Request request) async {
          seen.add(request.url);
          if (request.url.host == 'public.example.com') {
            return http.Response(
              '',
              302,
              headers: <String, String>{'location': 'http://127.0.0.1/secret'},
            );
          }
          return http.Response('should not reach here', 200);
        }),
        resolveHost: (String host) async => <InternetAddress>[
          InternetAddress('93.184.216.34'),
        ],
      );
      final Result<StaticPageFetchResult> result = await fetcher.fetch(
        Uri.parse('https://public.example.com/post'),
      );
      expect(result.isErr, isTrue);
      expect(seen.map((Uri u) => u.host).toList(), <String>[
        'public.example.com',
      ], reason: '第二跳（内网）不得被请求');
    });

    test('正常抓取：返回 HTML，跟随一次重定向', () async {
      final HttpStaticPageFetcher fetcher = HttpStaticPageFetcher(
        client: MockClient((http.Request request) async {
          if (request.url.host == 'example.com') {
            return http.Response(
              '',
              301,
              headers: <String, String>{
                'location': 'https://www.example.com/final',
              },
            );
          }
          return http.Response(
            _fixture('static_page_normal.html'),
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }),
        resolveHost: (String host) async => <InternetAddress>[
          InternetAddress('93.184.216.34'),
        ],
      );
      final StaticPageFetchResult page = (await fetcher.fetch(
        Uri.parse('https://example.com/post'),
      )).unwrap();
      expect(page.html, contains('离线阅读的实现细节'));
      expect(page.redirectCount, 1);
      // 地址已脱敏（不携带查询里的秘密）。
      expect(page.finalUri, contains('www.example.com'));
    });

    test('响应体超过上限被拒绝（声明长度）', () async {
      final HttpStaticPageFetcher fetcher = HttpStaticPageFetcher(
        client: MockClient((http.Request request) async {
          return http.Response.bytes(
            // 实际字节数超过上限：MockClient 会用 body 长度覆盖 content-length，
            // 因此这里必须真的发一个超限的体，而不是只声明一个大的头。
            utf8.encode('x' * 5000),
            200,
            headers: <String, String>{'content-type': 'text/html'},
          );
        }),
        resolveHost: (String host) async => <InternetAddress>[
          InternetAddress('93.184.216.34'),
        ],
        config: const StaticPageFetchConfig(maxBytes: 1000),
      );
      final Result<StaticPageFetchResult> result = await fetcher.fetch(
        Uri.parse('https://example.com/huge'),
      );
      expect(result.isErr, isTrue);
    });

    test('访问受限（401/402/403）明确说明不绕过访问限制', () async {
      final HttpStaticPageFetcher fetcher = HttpStaticPageFetcher(
        client: MockClient((http.Request request) async {
          return http.Response('forbidden', 403);
        }),
        resolveHost: (String host) async => <InternetAddress>[
          InternetAddress('93.184.216.34'),
        ],
      );
      final Result<StaticPageFetchResult> result = await fetcher.fetch(
        Uri.parse('https://example.com/paid'),
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull!.message, contains('不绕过访问限制'));
      // 访问限制不是可重试的失败（重试不会改变结果）。
      expect(result.errorOrNull!.isRetryable, isFalse);
    });
  });
}
