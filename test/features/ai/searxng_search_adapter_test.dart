// T031：SearXNG 适配器（**独立**夹具与期望，不与 Tavily/Brave 共用）。
//
// 覆盖协议事实（主代理提供，检索于 2026-09-22）与 SET-041 的边界：
//   - 请求形状：GET {instance}/search?format=json&q=...（language 可带）；
//   - 认证**可选**：有凭据才发 Authorization 头；SearXNG 没有默认端点；
//   - 响应映射：results[].title/url/content/publishedDate + number_of_results；
//   - **私网/回环端点未显式批准时在发请求之前被拒绝**（SET-041）；
//   - offset 不被支持（协议用 pageno），明确报错；
//   - 结果里的私网地址被丢弃；非法日期不解析成时间；
//   - 超时 → DeadlineExceededError。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/domain/search_provider.dart';
import 'package:flux/features/ai/domain/search_result.dart';
import 'package:flux/infrastructure/network/searxng_search_adapter.dart';

import 'search_adapter_support.dart';

void main() {
  SearxngSearchAdapter adapter({
    String baseUrl = 'https://search.example.com',
    String apiKey = '',
    bool allowPrivate = false,
    http.Client? client,
    Duration timeout = const Duration(seconds: 20),
  }) => SearxngSearchAdapter(
    baseUrl: baseUrl,
    apiKey: apiKey,
    allowPrivateEndpoint: allowPrivate,
    timeout: timeout,
    client: client,
  );

  SearchRequest request({int count = 10}) =>
      SearchRequest(text: 'flux reader', count: count);

  group('请求形状', () {
    test('GET {instance}/search?format=json&q=...，无凭据时不发认证头', () async {
      http.BaseRequest? seen;
      final SearxngSearchAdapter sut = adapter(
        client: searchClient(
          readSearchFixture('searxng_search_response.json'),
          onRequest: (http.BaseRequest request) => seen = request,
        ),
      );
      await sut.search(request());

      expect(seen!.method, 'GET');
      expect(seen!.url.path, '/search');
      expect(seen!.url.queryParameters['format'], 'json');
      expect(seen!.url.queryParameters['q'], 'flux reader');
      // 可选认证：没有凭据就**不发送** Authorization（空 Bearer 会让某些反向代理
      // 直接 401）。
      expect(seen!.headers.containsKey('Authorization'), isFalse);
    });

    test('有凭据时发送 Authorization: Bearer（但不进 URL）', () async {
      http.BaseRequest? seen;
      final SearxngSearchAdapter sut = adapter(
        apiKey: 'instance-token-fixture',
        client: searchClient(
          readSearchFixture('searxng_search_response.json'),
          onRequest: (http.BaseRequest request) => seen = request,
        ),
      );
      await sut.search(request());
      expect(seen!.headers['Authorization'], 'Bearer instance-token-fixture');
      expect(seen!.url.toString(), isNot(contains('instance-token-fixture')));
    });

    test('Base URL 里已有的路径段被保留（实例常挂在子路径下）', () async {
      http.BaseRequest? seen;
      final SearxngSearchAdapter sut = adapter(
        baseUrl: 'https://host.example.com/searxng',
        client: searchClient(
          readSearchFixture('searxng_search_response.json'),
          onRequest: (http.BaseRequest request) => seen = request,
        ),
      );
      await sut.search(request());
      expect(seen!.url.path, '/searxng/search');
    });

    test('offset 不被支持：明确报错而不是静默忽略（协议用 pageno）', () async {
      final SearxngSearchAdapter sut = adapter(
        client: searchClient(readSearchFixture('searxng_search_response.json')),
      );
      final Result<SearchResponse> result = await sut.search(
        const SearchRequest(text: 'flux', offset: 10),
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<ValidationError>());
    });
  });

  group('SET-041：私网端点必须显式批准', () {
    test('未批准时私网端点被拒绝，且**一次请求都不发**', () async {
      int calls = 0;
      final SearxngSearchAdapter sut = adapter(
        baseUrl: 'http://192.168.1.10:8080',
        client: countingSearchClient(<String>[
          readSearchFixture('searxng_search_response.json'),
        ], onRequest: (http.BaseRequest request) => calls++),
      );
      final Result<SearchResponse> result = await sut.search(request());
      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<ValidationError>());
      expect(
        (result.errorOrNull! as ValidationError).field,
        'SET-041',
        reason: '拒绝原因必须指向 SET-041 的显式批准入口，而不是一句「地址非法」',
      );
      expect(calls, 0, reason: '未批准时不得把查询发到内网');
    });

    test('loopback 与链路本地地址同样需要批准', () async {
      for (final String baseUrl in <String>[
        'http://127.0.0.1:8888',
        'http://localhost:8888',
        'http://169.254.169.254',
      ]) {
        final SearxngSearchAdapter sut = adapter(baseUrl: baseUrl);
        final Result<SearchResponse> result = await sut.search(request());
        expect(result.isErr, isTrue, reason: '$baseUrl 未批准时必须被拒绝');
      }
    });

    test('已显式批准后私网端点可以发出请求', () async {
      int calls = 0;
      final SearxngSearchAdapter sut = adapter(
        baseUrl: 'http://192.168.1.10:8080',
        allowPrivate: true,
        client: countingSearchClient(<String>[
          readSearchFixture('searxng_search_response.json'),
        ], onRequest: (http.BaseRequest request) => calls++),
      );
      final Result<SearchResponse> result = await sut.search(request());
      expect(result.isOk, isTrue);
      expect(calls, 1);
    });

    test('批准只放行私网这一类：file:// 这类非法协议仍然被拒绝', () async {
      final SearxngSearchAdapter sut = adapter(
        baseUrl: 'file:///etc/passwd',
        allowPrivate: true,
        client: searchClient(readSearchFixture('searxng_search_response.json')),
      );
      final Result<SearchResponse> result = await sut.search(request());
      expect(result.isErr, isTrue, reason: '批准「内网端点」不等于批准任意协议');
    });
  });

  group('响应映射', () {
    test('results 映射到统一结构；私网结果被丢弃；非法日期不解析；总数保留', () async {
      final SearxngSearchAdapter sut = adapter(
        client: searchClient(readSearchFixture('searxng_search_response.json')),
      );
      final SearchResponse response = (await sut.search(request())).unwrap();

      expect(response.results, hasLength(2));
      expect(response.provider, 'searxng');
      expect(response.totalResults, 142);

      final SearchResult first = response.results.first;
      expect(first.title, 'Flux documentation');
      // ISO-8601 绝对时刻被解析并归一到 UTC（+08:00 → Z）。
      expect(first.publishedAt, DateTime.utc(2026, 9, 19, 2));
      expect(first.publishedAt!.isUtc, isTrue);
      expect(first.accessCategory, SearchAccessCategory.news);

      final SearchResult second = response.results[1];
      expect(second.publishedAt, isNull);
      expect(second.snippet, isEmpty);
      expect(second.accessCategory, SearchAccessCategory.general);
    });

    test('结果里的私网地址被丢弃；非法日期字段不产生时间', () async {
      final SearxngSearchAdapter sut = adapter(
        client: searchClient(
          readSearchFixture('searxng_private_response.json'),
        ),
      );
      final SearchResponse response = (await sut.search(request())).unwrap();
      expect(response.results, isEmpty, reason: '私网地址的结果必须被丢弃');
      expect(response.totalResults, 1, reason: '总数原样保留（它不是「可用条数」）');
    });

    test('响应体不是 JSON → ParseError', () async {
      final SearxngSearchAdapter sut = adapter(
        client: searchClient(jsonEncode(<String, Object?>{})),
      );
      // 空对象是合法的 JSON 对象，只是没有 results → 空结果而不是错误。
      final SearchResponse response = (await sut.search(request())).unwrap();
      expect(response.results, isEmpty);

      final SearxngSearchAdapter bad = adapter(
        client: searchClient('not-json'),
      );
      final Result<SearchResponse> failed = await bad.search(request());
      expect(failed.errorOrNull, isA<ParseError>());
    });
  });

  group('错误映射', () {
    test('401 → AuthError（实例需要认证时会如此）', () async {
      final SearxngSearchAdapter sut = adapter(
        client: searchClient('{}', statusCode: 401),
      );
      final Result<SearchResponse> result = await sut.search(request());
      expect(result.errorOrNull, isA<AuthError>());
    });

    test('429 → RateLimitError', () async {
      final SearxngSearchAdapter sut = adapter(
        client: searchClient('{}', statusCode: 429),
      );
      final Result<SearchResponse> result = await sut.search(request());
      expect(result.errorOrNull, isA<RateLimitError>());
    });

    test('超时 → DeadlineExceededError（限制类别为 search）', () async {
      final SearxngSearchAdapter sut = adapter(
        timeout: const Duration(milliseconds: 30),
        client: hangingSearchClient(),
      );
      final Result<SearchResponse> result = await sut.search(request());
      expect(result.errorOrNull, isA<DeadlineExceededError>());
      expect(
        (result.errorOrNull! as DeadlineExceededError).limitKind,
        'search',
      );
    });
  });
}
