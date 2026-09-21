// T031：Brave Search 适配器（**独立**夹具与期望，不与 Tavily/SearXNG 共用）。
//
// 覆盖协议事实（主代理提供，检索于 2026-09-22）里的每一条：
//   - 请求形状：GET + 查询参数（q/count/offset/search_lang）；
//   - 认证走 **X-Subscription-Token**（不是 Bearer，也不是 query 参数）；
//   - 结果在 web.results 两层嵌套里；
//   - **description 里的 b 高亮标签必须被剥离**（这是本协议特有的要求）；
//   - age（"3 days ago"）**不换算**成绝对时刻；
//   - 无 answer / 无 score / 无结果总数（一律为 null，不编造）；
//   - 结果里的回环地址被丢弃；
//   - 错误映射与「无凭据绝不发请求」。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/domain/search_provider.dart';
import 'package:flux/features/ai/domain/search_result.dart';
import 'package:flux/infrastructure/network/brave_search_adapter.dart';

import 'search_adapter_support.dart';

void main() {
  const String token = 'bsa-fixture-not-a-real-token-000000';

  BraveSearchAdapter adapter({http.Client? client}) => BraveSearchAdapter(
    baseUrl: 'https://api.example.com',
    apiKey: token,
    client: client,
  );

  SearchRequest request({int count = 10, int? offset, String? language}) =>
      SearchRequest(
        text: 'flux reader',
        count: count,
        offset: offset,
        language: language,
      );

  group('请求形状', () {
    test('GET + 查询参数，认证走 X-Subscription-Token 头', () async {
      http.BaseRequest? seen;
      final BraveSearchAdapter sut = adapter(
        client: searchClient(
          readSearchFixture('brave_search_response.json'),
          onRequest: (http.BaseRequest request) => seen = request,
        ),
      );
      await sut.search(request());

      expect(seen!.method, 'GET');
      expect(
        seen!.url.toString(),
        startsWith('https://api.example.com/res/v1/web/search'),
      );
      // **不是** Bearer：Brave 用错的认证头一律 401。
      expect(seen!.headers['X-Subscription-Token'], token);
      expect(seen!.headers.containsKey('Authorization'), isFalse);
      expect(seen!.url.query, isNot(contains(token)), reason: '凭据绝不进 query');

      expect(seen!.url.queryParameters['q'], 'flux reader');
      expect(seen!.url.queryParameters['count'], '10');
      expect(seen!.url.queryParameters['result_filter'], 'web');
      expect(seen!.url.queryParameters.containsKey('offset'), isFalse);
    });

    test('offset 与 search_lang 在给定时才发送', () async {
      http.BaseRequest? seen;
      final BraveSearchAdapter sut = adapter(
        client: searchClient(
          readSearchFixture('brave_search_response.json'),
          onRequest: (http.BaseRequest request) => seen = request,
        ),
      );
      await sut.search(request(offset: 20, language: 'zh-hans'));
      expect(seen!.url.queryParameters['offset'], '20');
      expect(seen!.url.queryParameters['search_lang'], 'zh-hans');
    });

    test('负 offset 被拒绝（不发请求）', () async {
      final BraveSearchAdapter sut = adapter(
        client: searchClient(readSearchFixture('brave_search_response.json')),
      );
      final Result<SearchResponse> result = await sut.search(
        request(offset: -1),
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<ValidationError>());
    });
  });

  group('响应映射', () {
    test('web.results 被取出；标题与片段的 b 高亮标签都被剥离；回环地址被丢弃', () async {
      final BraveSearchAdapter sut = adapter(
        client: searchClient(readSearchFixture('brave_search_response.json')),
      );
      final SearchResponse response = (await sut.search(request())).unwrap();

      // 夹具第三条指向 127.0.0.1，必须被丢弃 → 只剩两条。
      expect(response.results, hasLength(2), reason: '回环地址必须被丢弃');
      for (final SearchResult result in response.results) {
        expect(result.provider, 'brave');
        expect(result.url, isNot(contains('127.0.0.1')));
      }

      final SearchResult first = response.results.first;
      // **高亮标签被剥离，文字保留**：这是 Brave 特有的形状要求。
      expect(first.title, 'Flux reader');
      expect(first.title, isNot(contains('<b>')));
      expect(first.snippet, 'A local-first reader for news & RSS.');
      expect(first.snippet, isNot(contains('<b>')));
      expect(first.snippet, isNot(contains('&amp;')), reason: '实体被解码');

      // age 是相对时间：不换算成绝对时刻，因此发布时间为 null。
      expect(first.publishedAt, isNull, reason: '相对时间不猜成绝对时刻');
      expect(first.score, isNull, reason: 'Brave 不提供分数');
      expect(first.accessCategory, SearchAccessCategory.general);

      // 第二条命中技术表（docs.dart.dev 不在表内，但 dart 文档站不在表中）
      expect(response.results[1].title, 'Dart language docs');

      expect(response.answer, isNull);
      expect(response.totalResults, isNull);
      expect(response.responseTime, isNull);
    });

    test('web 缺失或结构不符时容错为「没有结果」', () async {
      final BraveSearchAdapter sut = adapter(
        client: searchClient(jsonEncode(<String, Object?>{'web': 'nope'})),
      );
      final SearchResponse response = (await sut.search(request())).unwrap();
      expect(response.results, isEmpty);
    });
  });

  group('错误映射与安全边界', () {
    test('401 → AuthError（Brave 用错认证头的典型响应）', () async {
      final BraveSearchAdapter sut = adapter(
        client: searchClient('{}', statusCode: 401),
      );
      final Result<SearchResponse> result = await sut.search(request());
      expect(result.errorOrNull, isA<AuthError>());
    });

    test('429 → RateLimitError', () async {
      final BraveSearchAdapter sut = adapter(
        client: searchClient('{}', statusCode: 429),
      );
      final Result<SearchResponse> result = await sut.search(request());
      expect(result.errorOrNull, isA<RateLimitError>());
    });

    test('403 → AuthError（档位不允许）', () async {
      final BraveSearchAdapter sut = adapter(
        client: searchClient('{}', statusCode: 403),
      );
      final Result<SearchResponse> result = await sut.search(request());
      expect(result.errorOrNull, isA<AuthError>());
    });

    test('无凭据 → AuthError，且一次请求都不发', () async {
      int calls = 0;
      final BraveSearchAdapter sut = BraveSearchAdapter(
        baseUrl: 'https://api.example.com',
        apiKey: '',
        client: countingSearchClient(<String>[
          readSearchFixture('brave_search_response.json'),
        ], onRequest: (http.BaseRequest request) => calls++),
      );
      final Result<SearchResponse> result = await sut.search(request());
      expect(result.errorOrNull, isA<AuthError>());
      expect(calls, 0);
    });

    test('凭据不出现在错误消息里', () async {
      final BraveSearchAdapter sut = adapter(
        client: searchClient('{}', statusCode: 401),
      );
      final Result<SearchResponse> result = await sut.search(request());
      expect(result.errorOrNull!.message, isNot(contains(token)));
    });
  });
}
