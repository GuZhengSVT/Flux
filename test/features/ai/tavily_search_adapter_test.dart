// T031：Tavily 适配器（**独立**夹具与期望，不与 Brave/SearXNG 共用）。
//
// 覆盖协议事实（主代理提供，检索于 2026-09-22）里的每一条：
//   - 请求形状：POST + JSON body（query/max_results/search_depth/include_answer）；
//   - 认证走 Authorization: Bearer（**不是** body 里的 api_key，也**不是** query）；
//   - 响应映射：results[].title/url/content/score/published_date → 统一结构；
//   - answer 与 response_time 两个不属于单条结果的字段；
//   - 字段缺失容忍（无 published_date、无 score）；
//   - 结果里的私网地址被丢弃；
//   - 错误映射：401 → AuthError、429 → RateLimitError（服从 Retry-After）；
//   - **无凭据绝不发请求**（用请求计数断言）。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/domain/search_provider.dart';
import 'package:flux/features/ai/domain/search_result.dart';
import 'package:flux/infrastructure/network/tavily_search_adapter.dart';

import 'search_adapter_support.dart';

void main() {
  const String apiKey = 'tvly-fixture-not-a-real-key-000000';

  TavilySearchAdapter adapter({http.Client? client}) => TavilySearchAdapter(
    baseUrl: 'https://api.example.com',
    apiKey: apiKey,
    client: client,
  );

  SearchRequest request({int count = 10, String text = 'flux reader'}) =>
      SearchRequest(text: text, count: count);

  group('请求形状', () {
    test('POST + JSON body，认证走 Authorization 头，凭据不进 URL', () async {
      http.BaseRequest? seen;
      final TavilySearchAdapter sut = adapter(
        client: searchClient(
          readSearchFixture('tavily_search_response.json'),
          onRequest: (http.BaseRequest request) => seen = request,
        ),
      );
      await sut.search(request());

      expect(seen!.method, 'POST');
      expect(seen!.url.toString(), 'https://api.example.com/search');
      // Key 只出现在 Authorization 头里；URL 与 query 里都不含它。
      expect(seen!.headers['Authorization'], 'Bearer $apiKey');
      expect(seen!.url.query, isEmpty, reason: '凭据绝不进 query（会进日志与代理记录）');
      expect(seen!.url.toString(), isNot(contains(apiKey)));

      final Map<String, Object?> body = requestJson(seen!);
      expect(body['query'], 'flux reader');
      expect(body['max_results'], 10);
      expect(body['search_depth'], 'basic');
      expect(body['include_answer'], isTrue);
      // body 里**不**放 api_key（两代认证并存，本工程只用头）。
      expect(body.containsKey('api_key'), isFalse);
    });

    test('结果数被夹到 SET-040 的 1–20', () async {
      http.BaseRequest? seen;
      final TavilySearchAdapter sut = adapter(
        client: searchClient(
          readSearchFixture('tavily_search_response.json'),
          onRequest: (http.BaseRequest request) => seen = request,
        ),
      );
      await sut.search(request(count: 999));
      expect(requestJson(seen!)['max_results'], 20);
    });

    test('offset 不被支持：明确报错而不是静默忽略', () async {
      final TavilySearchAdapter sut = adapter(
        client: searchClient(readSearchFixture('tavily_search_response.json')),
      );
      final Result<SearchResponse> result = await sut.search(
        const SearchRequest(text: 'flux', offset: 10),
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<ValidationError>());
    });

    test('空查询词被拒绝（不发请求）', () async {
      final TavilySearchAdapter sut = adapter(
        client: searchClient(readSearchFixture('tavily_search_response.json')),
      );
      final Result<SearchResponse> result = await sut.search(
        const SearchRequest(text: '   '),
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<ValidationError>());
    });
  });

  group('响应映射', () {
    test('三条结果映射到统一结构；私网地址被丢弃；answer/response_time 保留', () async {
      final TavilySearchAdapter sut = adapter(
        client: searchClient(readSearchFixture('tavily_search_response.json')),
      );
      final SearchResponse response = (await sut.search(request())).unwrap();

      // 夹具里第三条指向 169.254.169.254，必须被丢弃 → 只剩两条。
      expect(response.results, hasLength(2), reason: '链路本地地址必须被丢弃');
      for (final SearchResult result in response.results) {
        expect(result.url, isNot(contains('169.254.169.254')));
        expect(result.provider, 'tavily');
        expect(result.sourceId, isNotEmpty);
        expect(
          result.sourceId,
          isNot(contains('http')),
          reason: 'sourceId 是摘要而非地址',
        );
      }

      final SearchResult first = response.results.first;
      expect(first.title, 'Flux — local-first news reader');
      expect(first.url, 'https://example.com/flux');
      expect(first.snippet, 'A local-first reader for news and RSS.');
      expect(first.score, closeTo(0.97, 0.001));
      // 有发布时间 → 归类为新闻（时效性是最强信号）。
      expect(first.accessCategory, SearchAccessCategory.news);
      expect(first.publishedAt!.isUtc, isTrue);
      expect(first.publishedAt, DateTime.utc(2026, 9, 18, 8));

      // 第二条：无 published_date（时间缺失如实为 null），主机命中技术表 → technical。
      final SearchResult second = response.results[1];
      expect(second.publishedAt, isNull, reason: '字段缺失时如实为 null，不编造时间');
      expect(second.score, closeTo(0.81, 0.001), reason: 'score 存在时原样保留');
      expect(second.accessCategory, SearchAccessCategory.technical);

      expect(response.answer, 'Flux is a local-first news and RSS reader.');
      expect(response.responseTime, isNotNull);
      expect(response.responseTime!.inMilliseconds, 830);
    });

    test('score / published_date / answer 缺失时一律为 null（不编造）', () async {
      final TavilySearchAdapter sut = adapter(
        client: searchClient(
          jsonEncode(<String, Object?>{
            'results': <Object?>[
              <String, Object?>{
                'title': 'Only title and url',
                'url': 'https://example.com/minimal',
              },
            ],
          }),
        ),
      );
      final SearchResponse response = (await sut.search(request())).unwrap();
      final SearchResult only = response.results.single;
      expect(only.score, isNull);
      expect(only.publishedAt, isNull);
      expect(only.snippet, isEmpty, reason: 'content 缺失时片段为空，而不是伪造一段文字');
      expect(only.accessCategory, SearchAccessCategory.general);
      expect(response.answer, isNull);
      expect(response.responseTime, isNull);
    });

    test('sourceId 由协议与序号决定：同序号的摘要是稳定的', () {
      final String a = searchResultSourceId(provider: 'tavily', rank: 0);
      final String b = searchResultSourceId(provider: 'tavily', rank: 0);
      final String other = searchResultSourceId(provider: 'brave', rank: 0);
      expect(a, b, reason: '同一协议同一序号必须得到同一 id');
      expect(a, isNot(other), reason: '不同协议不得得到同一 id');
      expect(a, hasLength(16));
    });

    test('响应体不是 JSON 对象 → ParseError（不退化成一堆空结果）', () async {
      final TavilySearchAdapter sut = adapter(client: searchClient('[1,2,3]'));
      final Result<SearchResponse> result = await sut.search(request());
      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<ParseError>());
    });

    test('results 字段结构不符时容错为「没有结果」，不抛异常', () async {
      final TavilySearchAdapter sut = adapter(
        client: searchClient(jsonEncode(<String, Object?>{'results': 'nope'})),
      );
      final SearchResponse response = (await sut.search(request())).unwrap();
      expect(response.results, isEmpty);
      expect(response.answer, isNull);
    });
  });

  group('错误映射', () {
    test('401 → AuthError（不可重试，指向配置问题）', () async {
      final TavilySearchAdapter sut = adapter(
        client: searchClient('{}', statusCode: 401),
      );
      final Result<SearchResponse> result = await sut.search(request());
      expect(result.errorOrNull, isA<AuthError>());
      expect(result.errorOrNull!.isRetryable, isFalse);
    });

    test('429 → RateLimitError（可重试，并解析 Retry-After）', () async {
      final TavilySearchAdapter sut = adapter(
        client: searchClient(
          '{}',
          statusCode: 429,
          headers: <String, String>{'retry-after': '7'},
        ),
      );
      final Result<SearchResponse> result = await sut.search(request());
      final AppError error = result.errorOrNull!;
      expect(error, isA<RateLimitError>());
      expect((error as RateLimitError).retryAfter, const Duration(seconds: 7));
      expect(error.isRetryable, isTrue);
    });

    test('500 → NetworkError（保留状态码，可重试）', () async {
      final TavilySearchAdapter sut = adapter(
        client: searchClient('{}', statusCode: 500),
      );
      final Result<SearchResponse> result = await sut.search(request());
      expect(result.errorOrNull, isA<NetworkError>());
      expect((result.errorOrNull! as NetworkError).statusCode, 500);
    });
  });

  group('安全边界', () {
    test('无凭据 → AuthError，且**一次请求都不发**', () async {
      int calls = 0;
      final TavilySearchAdapter sut = TavilySearchAdapter(
        baseUrl: 'https://api.example.com',
        apiKey: '',
        client: countingSearchClient(<String>[
          readSearchFixture('tavily_search_response.json'),
        ], onRequest: (http.BaseRequest request) => calls++),
      );
      final Result<SearchResponse> result = await sut.search(request());
      expect(result.errorOrNull, isA<AuthError>());
      expect(calls, 0, reason: '没有凭据时不得发出任何请求（不浪费配额、不留下失败记录）');
    });

    test('凭据不出现在错误消息里', () async {
      final TavilySearchAdapter sut = adapter(
        client: searchClient('{}', statusCode: 401),
      );
      final Result<SearchResponse> result = await sut.search(request());
      expect(result.errorOrNull!.message, isNot(contains(apiKey)));
    });
  });
}
