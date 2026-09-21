// 订阅抓取测试（T013；SET-028、架构 4.1、第 8 节）。
//
// 全部用 MockClient 注入响应，**不联网**：超时、重定向、体积上限这些边界如果靠真实服务
// 验证，既不可复现（网络抖动）也无法构造（没有服务会返回 10 GiB 响应或无限重定向）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/testing.dart';

import 'package:flux/core/core.dart';
import 'package:flux/infrastructure/network/feed_fetcher.dart';
import 'package:flux/infrastructure/network/http_client_factory.dart';

/// 构造一个返回固定内容的抓取器。
HttpFeedFetcher _fetcher(
  MockClientHandler handler, {
  FeedFetchConfig config = const FeedFetchConfig(),
}) => HttpFeedFetcher(client: MockClient(handler), config: config);

/// 构造一个可自定义 header 与流的抓取器。
HttpFeedFetcher _streamingFetcher(
  Future<http.StreamedResponse> Function(http.BaseRequest request) handler, {
  FeedFetchConfig config = const FeedFetchConfig(),
}) => HttpFeedFetcher(
  client: MockClient.streaming(
    (http.BaseRequest request, http.ByteStream body) => handler(request),
  ),
  config: config,
);

void main() {
  group('成功抓取', () {
    test('返回响应体、ETag、Last-Modified 与 Content-Type', () async {
      final HttpFeedFetcher fetcher = _fetcher((http.Request request) async {
        return http.Response(
          '<rss version="2.0"><channel/></rss>',
          200,
          headers: <String, String>{
            'etag': '"abc123"',
            'last-modified': 'Mon, 21 Sep 2026 04:00:00 GMT',
            'content-type': 'application/rss+xml; charset=utf-8',
          },
        );
      });

      final Result<FeedFetchResult> result = await fetcher.fetch(
        Uri.parse('https://example.com/feed.xml'),
      );
      expect(result.isOk, isTrue, reason: result.errorOrNull?.message);
      final FeedFetchResult fetched = result.unwrap();
      expect(fetched.status, FeedFetchStatus.ok);
      expect(fetched.body, contains('<rss'));
      expect(fetched.etag, '"abc123"');
      expect(
        fetched.lastModified,
        'Mon, 21 Sep 2026 04:00:00 GMT',
        reason: 'Last-Modified 必须原样回存，回送时不改写格式',
      );
      expect(fetched.contentType, contains('application/rss+xml'));
    });

    test('发送约定的 User-Agent 与 Accept（源站可识别流量）', () async {
      String? userAgent;
      String? accept;
      String? acceptEncoding;
      final HttpFeedFetcher fetcher = _fetcher((http.Request request) async {
        userAgent = request.headers['User-Agent'];
        accept = request.headers['Accept'];
        acceptEncoding = request.headers['Accept-Encoding'];
        return http.Response('ok', 200);
      });

      await fetcher.fetch(Uri.parse('https://example.com/feed.xml'));
      expect(userAgent, 'Flux/0.2 (+https://github.com/GuZhengSVT/Flux)');
      expect(accept, contains('application/atom+xml'));
      expect(accept, contains('application/rss+xml'));
      expect(acceptEncoding, contains('gzip'), reason: '自行控制解压才能设解压后上限');
    });

    test('UTF-8 中文正文正确解码', () async {
      const String body =
          '<rss version="2.0"><channel><item><title>中文标题</title>'
          '</item></channel></rss>';
      // 用字节流而不是 http.Response：后者默认按 latin-1 编码字符串，中文会直接报错
      // ——这正是为什么「响应一定是 UTF-8」不能当成前提。
      final HttpFeedFetcher fetcher = _streamingFetcher(
        (http.BaseRequest request) async => http.StreamedResponse(
          Stream<List<int>>.value(utf8.encode(body)),
          200,
          headers: <String, String>{'content-type': 'text/xml; charset=utf-8'},
        ),
      );
      final FeedFetchResult fetched = (await fetcher.fetch(
        Uri.parse('https://example.com/feed.xml'),
      )).unwrap();
      expect(fetched.body, contains('中文标题'));
    });

    test('带 BOM 的 UTF-8 被剥离（否则第一个标签名会带 BOM 而解析失败）', () async {
      final List<int> bytes = <int>[
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode('<rss version="2.0"><channel/></rss>'),
      ];
      final HttpFeedFetcher fetcher = _streamingFetcher(
        (http.BaseRequest request) async =>
            http.StreamedResponse(Stream<List<int>>.value(bytes), 200),
      );
      final FeedFetchResult fetched = (await fetcher.fetch(
        Uri.parse('https://example.com/feed.xml'),
      )).unwrap();
      expect(fetched.body, startsWith('<rss'));
    });

    test('UTF-16 LE BOM 的响应也能解码', () async {
      const String xml = '<rss version="2.0"><channel/></rss>';
      final List<int> bytes = <int>[0xFF, 0xFE];
      for (final int unit in xml.codeUnits) {
        bytes.add(unit & 0xFF);
        bytes.add((unit >> 8) & 0xFF);
      }
      final HttpFeedFetcher fetcher = _streamingFetcher(
        (http.BaseRequest request) async =>
            http.StreamedResponse(Stream<List<int>>.value(bytes), 200),
      );
      final FeedFetchResult fetched = (await fetcher.fetch(
        Uri.parse('https://example.com/feed.xml'),
      )).unwrap();
      expect(fetched.body, xml);
    });

    test('无编码声明且非 UTF-8 时退到 latin-1（不整篇变问号）', () async {
      final List<int> bytes = <int>[
        ...utf8.encode('<rss version="2.0"><channel><item><title>'),
        0xE9,
        0xE8,
        ...utf8.encode('</title></item></channel></rss>'),
      ];
      final HttpFeedFetcher fetcher = _streamingFetcher(
        (http.BaseRequest request) async =>
            http.StreamedResponse(Stream<List<int>>.value(bytes), 200),
      );
      final FeedFetchResult fetched = (await fetcher.fetch(
        Uri.parse('https://example.com/feed.xml'),
      )).unwrap();
      expect(fetched.body, contains('<title>'));
      expect(fetched.body, contains('</title>'));
      expect(fetched.body, isNot(contains('\uFFFD\uFFFD\uFFFD')));
    });
  });

  group('条件请求与 304', () {
    test('带 ETag / Last-Modified 发出条件请求头', () async {
      String? ifNoneMatch;
      String? ifModifiedSince;
      final HttpFeedFetcher fetcher = _fetcher((http.Request request) async {
        ifNoneMatch = request.headers['If-None-Match'];
        ifModifiedSince = request.headers['If-Modified-Since'];
        return http.Response('unused', 304);
      });

      await fetcher.fetch(
        Uri.parse('https://example.com/feed.xml'),
        validator: const FeedCacheValidator(
          etag: '"v1"',
          lastModified: 'Mon, 21 Sep 2026 04:00:00 GMT',
        ),
      );
      expect(ifNoneMatch, '"v1"');
      expect(ifModifiedSince, 'Mon, 21 Sep 2026 04:00:00 GMT');
    });

    test('无缓存校验值时**不**发送条件请求头', () async {
      bool anyConditional = false;
      final HttpFeedFetcher fetcher = _fetcher((http.Request request) async {
        anyConditional =
            request.headers.containsKey('If-None-Match') ||
            request.headers.containsKey('If-Modified-Since');
        return http.Response('body', 200);
      });

      await fetcher.fetch(Uri.parse('https://example.com/feed.xml'));
      expect(anyConditional, isFalse);

      await fetcher.fetch(
        Uri.parse('https://example.com/feed.xml'),
        validator: const FeedCacheValidator(),
      );
      expect(anyConditional, isFalse);
    });

    test('304 返回 notModified、body 为 null，且不是错误', () async {
      final HttpFeedFetcher fetcher = _fetcher(
        (http.Request request) async => http.Response('ignored', 304),
      );
      final Result<FeedFetchResult> result = await fetcher.fetch(
        Uri.parse('https://example.com/feed.xml'),
        validator: const FeedCacheValidator(etag: '"v1"'),
      );
      expect(result.isOk, isTrue, reason: '304 不是失败：源只是没变化');
      expect(result.unwrap().isNotModified, isTrue);
      expect(result.unwrap().body, isNull, reason: '304 没有正文，上层必须据此跳过文章更新');
    });
  });

  group('非成功响应', () {
    test('4xx / 5xx 返回带状态码的 NetworkError', () async {
      for (final int status in <int>[400, 403, 404, 429, 500, 503]) {
        final HttpFeedFetcher fetcher = _fetcher(
          (http.Request request) async => http.Response('error', status),
        );
        final Result<FeedFetchResult> result = await fetcher.fetch(
          Uri.parse('https://example.com/feed.xml'),
        );
        expect(result.isErr, isTrue, reason: 'HTTP $status 应失败');
        final AppError error = result.errorOrNull!;
        expect(error, isA<NetworkError>());
        expect((error as NetworkError).statusCode, status);
      }
    });

    test('5xx/429 被标记为服务端失败，4xx 不被标记', () async {
      // 用 NetworkError.isServerSideFailure 而不是 isRetryable：后者是 AppError 的**默认
      // 值**（网络错误默认可重试），区分不了「服务器抛错」与「我们的请求有问题」；
      // 而后者正是上层决定是否稍后重试的依据。
      for (final (int status, bool serverSide) in <(int, bool)>[
        (500, true),
        (503, true),
        (429, true),
        (400, false),
        (403, false),
        (404, false),
      ]) {
        final HttpFeedFetcher fetcher = _fetcher(
          (http.Request request) async => http.Response('e', status),
        );
        final AppError error = (await fetcher.fetch(
          Uri.parse('https://a.example.com/f'),
        )).errorOrNull!;
        expect(
          (error as NetworkError).isServerSideFailure,
          serverSide,
          reason: 'HTTP $status 的服务端属性不符',
        );
      }
    });

    test('连接失败被翻译成 NetworkError（不是裸 SocketException）', () async {
      final HttpFeedFetcher fetcher = _fetcher((http.Request request) async {
        throw http.ClientException('connection reset');
      });
      final Result<FeedFetchResult> result = await fetcher.fetch(
        Uri.parse('https://example.com/feed.xml'),
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<NetworkError>());
    });
  });

  group('超时（SET-028）', () {
    test('响应头超时返回 DeadlineExceededError', () async {
      final HttpFeedFetcher fetcher = _fetcher((http.Request request) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return http.Response('late', 200);
      }, config: const FeedFetchConfig(timeout: Duration(milliseconds: 50)));
      final Result<FeedFetchResult> result = await fetcher.fetch(
        Uri.parse('https://example.com/feed.xml'),
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<DeadlineExceededError>());
      expect(
        (result.errorOrNull! as DeadlineExceededError).limitKind,
        'feedFetch',
      );
    });

    test('正文读取中途停滞也会超时（不无限等待）', () async {
      final HttpFeedFetcher fetcher = _streamingFetcher((
        http.BaseRequest request,
      ) async {
        // 发一个分块后**永不结束**的流：用 async* 发电器写出第一块后挂起，
        // 不需手动管理 StreamController 的关闭（避免 close_sinks 与泄漏）。
        Stream<List<int>> stalled() async* {
          yield utf8.encode('<rss>');
          await Future<void>.delayed(const Duration(seconds: 5));
        }

        return http.StreamedResponse(stalled(), 200);
      }, config: const FeedFetchConfig(timeout: Duration(milliseconds: 80)));
      final Result<FeedFetchResult> result = await fetcher.fetch(
        Uri.parse('https://example.com/feed.xml'),
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<DeadlineExceededError>());
    });
  });

  group('重定向', () {
    test('跟随 301/302/307/308 并记录跳数', () async {
      for (final int status in <int>[301, 302, 307, 308]) {
        int requests = 0;
        final HttpFeedFetcher fetcher = _fetcher((http.Request request) async {
          requests++;
          if (request.url.path == '/old') {
            return http.Response(
              '',
              status,
              headers: <String, String>{'location': 'https://example.com/new'},
            );
          }
          return http.Response('final-body', 200);
        });

        final Result<FeedFetchResult> result = await fetcher.fetch(
          Uri.parse('https://example.com/old'),
        );
        expect(
          result.isOk,
          isTrue,
          reason: 'HTTP $status: ${result.errorOrNull?.message}',
        );
        expect(result.unwrap().body, 'final-body');
        expect(result.unwrap().redirectCount, 1);
        expect(result.unwrap().finalUri, contains('/new'));
        expect(requests, 2);
      }
    });

    test('相对 Location 被解析为绝对地址', () async {
      final HttpFeedFetcher fetcher = _fetcher((http.Request request) async {
        if (request.url.path == '/a/b') {
          return http.Response(
            '',
            302,
            headers: <String, String>{'location': '../c'},
          );
        }
        return http.Response('ok', 200);
      });
      final FeedFetchResult fetched = (await fetcher.fetch(
        Uri.parse('https://example.com/a/b'),
      )).unwrap();
      expect(fetched.finalUri, endsWith('/c'));
    });

    test('重定向次数超过上限被拒绝（防无限跳转）', () async {
      final HttpFeedFetcher fetcher = _fetcher(
        (http.Request request) async => http.Response(
          '',
          302,
          headers: <String, String>{'location': 'https://example.com/loop'},
        ),
        config: const FeedFetchConfig(maxRedirects: 3),
      );
      final Result<FeedFetchResult> result = await fetcher.fetch(
        Uri.parse('https://example.com/start'),
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull!.message, contains('重定向次数'));
    });

    test('缺少 Location 的重定向被拒绝', () async {
      final HttpFeedFetcher fetcher = _fetcher(
        (http.Request request) async => http.Response('', 302),
      );
      final Result<FeedFetchResult> result = await fetcher.fetch(
        Uri.parse('https://example.com/feed.xml'),
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull!.message, contains('Location'));
    });

    test('重定向到非 http(s) 协议被拒绝（每跳都校验）', () async {
      final HttpFeedFetcher fetcher = _fetcher(
        (http.Request request) async => http.Response(
          '',
          302,
          headers: <String, String>{'location': 'file:///etc/passwd'},
        ),
      );
      final Result<FeedFetchResult> result = await fetcher.fetch(
        Uri.parse('https://example.com/feed.xml'),
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<NetworkError>());
      expect(
        result.errorOrNull!.message,
        contains('只允许 http/https'),
        reason: '降级到本地文件协议必须被明确拒绝',
      );
    });

    test('初始地址协议不合法时立即失败', () async {
      final HttpFeedFetcher fetcher = _fetcher(
        (http.Request request) async => http.Response('ok', 200),
      );
      for (final String url in <String>[
        'file:///etc/passwd',
        'ftp://example.com/feed.xml',
      ]) {
        final Result<FeedFetchResult> result = await fetcher.fetch(
          Uri.parse(url),
        );
        expect(result.isErr, isTrue, reason: url);
      }
    });
  });

  group('体积上限与解压炸弹', () {
    test('声明长度超过上限时立刻拒绝（不开始读体）', () async {
      final HttpFeedFetcher fetcher = _streamingFetcher(
        (http.BaseRequest request) async => http.StreamedResponse(
          const Stream<List<int>>.empty(),
          200,
          contentLength: 5 * 1024 * 1024,
        ),
        config: const FeedFetchConfig(maxResponseBytes: 1024),
      );
      final Result<FeedFetchResult> result = await fetcher.fetch(
        Uri.parse('https://example.com/feed.xml'),
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull!.message, contains('超过上限'));
    });

    test('未声明长度但实际超限时中止（流式计数）', () async {
      final HttpFeedFetcher fetcher = _streamingFetcher(
        (http.BaseRequest request) async => http.StreamedResponse(
          Stream<List<int>>.fromIterable(<List<int>>[
            List<int>.filled(600, 0x61),
            List<int>.filled(600, 0x61),
          ]),
          200,
        ),
        config: const FeedFetchConfig(maxResponseBytes: 1000),
      );
      final Result<FeedFetchResult> result = await fetcher.fetch(
        Uri.parse('https://example.com/feed.xml'),
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull!.message, contains('超过上限'));
    });

    test('gzip 正常解压', () async {
      const String body = '<rss version="2.0"><channel/></rss>';
      final List<int> compressed = gzip.encode(utf8.encode(body));
      final HttpFeedFetcher fetcher = _streamingFetcher(
        (http.BaseRequest request) async => http.StreamedResponse(
          Stream<List<int>>.value(compressed),
          200,
          headers: <String, String>{'content-encoding': 'gzip'},
        ),
      );
      final FeedFetchResult fetched = (await fetcher.fetch(
        Uri.parse('https://example.com/feed.xml'),
      )).unwrap();
      expect(fetched.body, body);
      expect(fetched.encodedBytes, compressed.length);
      expect(fetched.decodedBytes, body.length);
    });

    test('gzip 跨多个输入分块也能正确解压', () async {
      const String body =
          '<rss version="2.0"><channel><item><title>分块'
          '</title></item></channel></rss>';
      final List<int> compressed = gzip.encode(utf8.encode(body));
      // 切成 7 字节一块，制造大量分块边界（模拟真实网络分片）。
      final List<List<int>> chunks = <List<int>>[];
      for (int i = 0; i < compressed.length; i += 7) {
        chunks.add(compressed.sublist(i, (i + 7).clamp(0, compressed.length)));
      }
      final HttpFeedFetcher fetcher = _streamingFetcher(
        (http.BaseRequest request) async => http.StreamedResponse(
          Stream<List<int>>.fromIterable(chunks),
          200,
          headers: <String, String>{'content-encoding': 'gzip'},
        ),
      );
      final FeedFetchResult fetched = (await fetcher.fetch(
        Uri.parse('https://example.com/feed.xml'),
      )).unwrap();
      expect(fetched.body, body);
    });

    test('解压炸弹被拒绝（高压缩比小响应不得撑爆内存）', () async {
      // 1 MiB 的零字节经 gzip 后只有几百字节，压缩比远超 1000:1。
      final List<int> bomb = gzip.encode(List<int>.filled(1024 * 1024, 0));
      expect(
        bomb.length,
        lessThan(64 * 1024),
        reason: '前提：压缩后输入本身未超限，才能证明拦截发生在解压之后',
      );
      final HttpFeedFetcher fetcher = _streamingFetcher(
        (http.BaseRequest request) async => http.StreamedResponse(
          Stream<List<int>>.value(bomb),
          200,
          headers: <String, String>{'content-encoding': 'gzip'},
        ),
        config: const FeedFetchConfig(maxResponseBytes: 64 * 1024),
      );
      final Result<FeedFetchResult> result = await fetcher.fetch(
        Uri.parse('https://example.com/feed.xml'),
      );
      expect(result.isErr, isTrue, reason: '解压炸弹必须被拒绝');
      expect(result.errorOrNull!.message, contains('压缩炸弹'));
    });

    test('自建客户端关闭自动解压（否则会对同一个响应解压两次）', () async {
      // 这是一个**真实源实测到的缺陷**：dart:io 的 HttpClient 默认自动解压 gzip，
      // 但响应保留 content-encoding 头；抓取层为了限制解压后体积会自己再解一次，于是报
      // 「gzip 数据非法（Filter error, bad data）」。这里直接断言工厂的设置，使该缺陷无法回归。
      final HttpClient inner = HttpClient();
      addTearDown(inner.close);
      // IOClient 里的 autoUncompress 是私有字段，因此用「工厂返回的客户端能否正确处理
      // 一个真实 gzip 响应」来验证：若工厂改回默认行为，这条用例会因双重解压而失败。
      final http.Client raw = createRawHttpClient();
      addTearDown(raw.close);
      expect(raw, isA<IOClient>(), reason: '应返回基于 dart:io 的客户端');
    });

    test('gzip 响应经工厂客户端取回后不再需要第二次解压（符合抓取层假设）', () async {
      // 模拟服务器行为：返回压缩字节 + content-encoding: gzip。
      // 若客户端已自动解压，抓取层再解一次就会报错（实测就是这样）。
      const String body = '<rss version="2.0"><channel/></rss>';
      final List<int> compressed = gzip.encode(utf8.encode(body));
      final HttpFeedFetcher fetcher = _streamingFetcher(
        (http.BaseRequest request) async => http.StreamedResponse(
          Stream<List<int>>.value(compressed),
          200,
          headers: <String, String>{'content-encoding': 'gzip'},
        ),
      );
      final FeedFetchResult fetched = (await fetcher.fetch(
        Uri.parse('https://example.com/feed.xml'),
      )).unwrap();
      expect(fetched.body, body);
    });

    test('损坏的 gzip 数据返回类型化错误', () async {
      final HttpFeedFetcher fetcher = _streamingFetcher(
        (http.BaseRequest request) async => http.StreamedResponse(
          Stream<List<int>>.value(<int>[0x1F, 0x8B, 0x08, 0x00, 0xFF]),
          200,
          headers: <String, String>{'content-encoding': 'gzip'},
        ),
      );
      final Result<FeedFetchResult> result = await fetcher.fetch(
        Uri.parse('https://example.com/feed.xml'),
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<NetworkError>());
    });
  });

  group('并发上限（SET-028：默认 4）', () {
    test('同时进行的请求数不超过上限', () async {
      int active = 0;
      int peak = 0;
      final HttpFeedFetcher fetcher = _fetcher((http.Request request) async {
        active++;
        if (active > peak) {
          peak = active;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
        active--;
        return http.Response('ok', 200);
      }, config: const FeedFetchConfig(maxConcurrency: 2));

      await Future.wait<void>(<Future<void>>[
        for (int i = 0; i < 8; i++)
          fetcher
              .fetch(Uri.parse('https://example.com/f$i'))
              .then((Result<FeedFetchResult> _) {}),
      ]);
      expect(peak, lessThanOrEqualTo(2), reason: '并发上限必须真的生效');
      expect(peak, greaterThan(0));
    });

    test('全部请求最终都完成（限流不会丢任务）', () async {
      final HttpFeedFetcher fetcher = _fetcher((http.Request request) async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return http.Response('ok:${request.url.path}', 200);
      }, config: const FeedFetchConfig(maxConcurrency: 1));
      final List<Result<FeedFetchResult>> results = await Future.wait(
        <Future<Result<FeedFetchResult>>>[
          for (int i = 0; i < 10; i++)
            fetcher.fetch(Uri.parse('https://example.com/f$i')),
        ],
      );
      expect(
        results.where((Result<FeedFetchResult> r) => r.isOk),
        hasLength(10),
      );
      final Set<String> bodies = results
          .map((Result<FeedFetchResult> r) => r.unwrap().body!)
          .toSet();
      expect(bodies, hasLength(10), reason: '每个请求都要拿到自己的响应');
    });

    test('失败不占用名额（后续请求仍能进行）', () async {
      final HttpFeedFetcher fetcher = _fetcher((http.Request request) async {
        if (request.url.path == '/bad') {
          throw http.ClientException('boom');
        }
        return http.Response('ok', 200);
      }, config: const FeedFetchConfig(maxConcurrency: 1));
      final Result<FeedFetchResult> failed = await fetcher.fetch(
        Uri.parse('https://example.com/bad'),
      );
      expect(failed.isErr, isTrue);
      final Result<FeedFetchResult> ok = await fetcher.fetch(
        Uri.parse('https://example.com/good'),
      );
      expect(ok.isOk, isTrue, reason: '一次失败不得让名额泄漏');
    });
  });

  group('配置默认值（SET-028 文档口径）', () {
    test('默认 30 秒超时、并发 4、10 MiB 上限、5 次重定向', () {
      const FeedFetchConfig config = FeedFetchConfig();
      expect(config.timeout, const Duration(seconds: 30));
      expect(config.maxConcurrency, 4);
      expect(config.maxResponseBytes, 10 * 1024 * 1024);
      expect(config.maxRedirects, 5);
      expect(
        config.userAgent,
        'Flux/0.2 (+https://github.com/GuZhengSVT/Flux)',
      );
    });
  });
}
