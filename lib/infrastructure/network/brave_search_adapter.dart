// Brave Search 适配器（T031；协议事实来源：主代理提供，检索于 2026-09-22）。
//
// 请求（GET {base}/res/v1/web/search）：
//   查询参数 q, count(1-20), offset, country, search_lang, freshness(pd/pw/pm/py 或范围)
// 认证：**X-Subscription-Token** 头（不是 Bearer）。
//   「也支持 Bearer」是常见误记，而 Brave 用错的认证头一律 401；因此认证方式是
//   SearchProtocol 的属性，适配器只读它，界面展示也来自同一份数据。
//
// 响应：{web:{results:[{title, url, description, age?}]}}
//   description 含 <b> 高亮标签，**必须剥离**（否则片段在界面上显示成源码）。
//   age 是相对时间（"3 days ago"），**不换算成绝对时刻**：换算需要抓取时刻作基准，
//   而基准不是协议事实。
//
// 与另两家**本质不同**的地方：
//   1) 唯一支持 offset 分页的协议（Tavily 没有 offset，SearXNG 用 pageno）；
//   2) 结果在 web.results 两层嵌套里，不是顶层 results；
//   3) 片段字段叫 description 且带高亮标签；
//   4) 没有 answer、没有 score、没有结果总数。
//
// 安全边界：订阅 Token 只出现在 X-Subscription-Token 头里，**从不**拼进 URL 或日志
// （URL 会进代理与浏览器历史，凭据进 URL 是最典型的一次泄漏）。
library;

import 'dart:async';

import 'package:http/http.dart' as http;

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/domain/search_errors.dart';
import 'package:flux/features/ai/domain/search_protocol.dart';
import 'package:flux/features/ai/domain/search_provider.dart';
import 'package:flux/features/ai/domain/search_result.dart';
import 'package:flux/features/ai/domain/search_service.dart';

import 'search_http.dart';

/// Brave Search 适配器。
final class BraveSearchAdapter implements SearchProvider {
  /// 构造适配器。
  BraveSearchAdapter({
    required this.baseUrl,
    required this.apiKey,
    this.maxResults = 10,
    this.timeout = const Duration(seconds: 20),
    this.client,
  });

  /// Base URL（不含协议路径）。
  final String baseUrl;

  /// 订阅 Token（只用于 X-Subscription-Token 头）。
  final String apiKey;

  /// 默认结果数（SET-040）。
  final int maxResults;

  /// 单次检索超时（SET-040）。
  final Duration timeout;

  /// 可注入的 HTTP 客户端（测试用 MockClient）；为空时每次请求自建。
  final http.Client? client;

  /// 端点（{base}/res/v1/web/search）。
  Uri get endpoint => SearchProtocol.brave.endpointFor(baseUrl);

  @override
  String get providerId => SearchProtocol.brave.id;

  @override
  Future<Result<SearchResponse>> search(SearchRequest query) async {
    // 没有 Token 时**在发出任何字节之前**拒绝（见文件头说明）。
    if (apiKey.isEmpty) {
      return Err<SearchResponse>(
        AuthError(provider: providerId, detail: 'credentialMissing'),
      );
    }
    final Result<void> valid = validateSearchQueryText(query.text);
    if (valid.isErr) {
      return Err<SearchResponse>(valid.errorOrNull!);
    }
    if (query.offset != null && query.offset! < 0) {
      return Err<SearchResponse>(
        ValidationError(
          field: 'offset',
          reason: 'offset 不能为负',
          value: '${query.offset}',
        ),
      );
    }

    final http.Client? owned = client == null ? http.Client() : null;
    final http.Client effective = owned ?? client!;
    try {
      final Map<String, String> params = <String, String>{
        'q': query.text.trim(),
        'count': '${_clampResults(query.count)}',
        // 默认只取网页结果：另几种结果版块（news/videos）在 web.results 之外，
        // 不声明 result_filter 会让响应结构随账号档位变化。
        'result_filter': 'web',
        if (query.offset != null) 'offset': '${query.offset}',
        if (query.language != null && query.language!.isNotEmpty)
          'search_lang': query.language!,
      };
      final http.Request request =
          http.Request('GET', endpoint.replace(queryParameters: params))
            ..headers['X-Subscription-Token'] = apiKey
            ..headers['Accept'] = 'application/json';

      final http.StreamedResponse response;
      try {
        response = await effective
            .send(request)
            .timeout(
              timeout,
              onTimeout: () => throw DeadlineExceededError(
                limitKind: 'search',
                limit: timeout,
              ),
            );
      } on DeadlineExceededError {
        rethrow;
      } on http.ClientException catch (error) {
        throw NetworkError(
          uri: endpoint.toString(),
          reason: '连接失败',
          cause: error,
        );
      } on Exception catch (error) {
        throw NetworkError(
          uri: endpoint.toString(),
          reason: '请求失败（${error.runtimeType}）',
          cause: error,
        );
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        try {
          await response.stream.drain<void>();
        } on Exception {
          // 排空失败不影响本次分类：状态码已经拿到。
        }
        return Err<SearchResponse>(
          mapSearchHttpError(
            provider: providerId,
            endpoint: endpoint,
            statusCode: response.statusCode,
            retryAfter: searchRetryAfter(response.headers['retry-after']),
          ),
        );
      }

      final Result<Map<String, Object?>> body = await readSearchJsonBody(
        response,
        provider: providerId,
        timeout: timeout,
      );
      if (body.isErr) {
        return Err<SearchResponse>(body.errorOrNull!);
      }
      return Ok<SearchResponse>(_mapResponse(body.unwrap(), query.text.trim()));
    } on AppError catch (error) {
      return Err<SearchResponse>(error);
    } finally {
      owned?.close();
    }
  }

  /// 把协议响应映射到统一结构（结果在 web.results 里）。
  SearchResponse _mapResponse(Map<String, Object?> body, String query) {
    final Object? web = body['web'];
    final Object? rawResults = web is Map<String, Object?>
        ? web['results']
        : null;
    final List<SearchResult> results = <SearchResult>[];
    int rank = 0;
    for (final Map<String, Object?> entry in searchObjectList(rawResults)) {
      final String? url = searchString(entry['url']);
      if (url == null || !isUsableSearchResultUrl(url)) {
        rank++;
        continue;
      }
      // **必须剥离高亮标签**：description 里的 b 标签是协议约定，不是脏数据。
      // 标题同样处理——Brave 会把命中的查询词在标题里也高亮（实测的响应形状），
      // 只清 description 会让界面上出现「Flux <b>reader</b>」这种源码样标题。
      // age（"3 days ago"）刻意不解析成绝对时间（见文件头说明）。
      results.add(
        SearchResult(
          sourceId: searchResultSourceId(provider: providerId, rank: rank),
          title: clampSearchText(
            stripSearchHighlight(searchString(entry['title']) ?? ''),
            kSearchTitleMaxLength,
          ),
          url: url,
          snippet: clampSearchText(
            stripSearchHighlight(searchString(entry['description']) ?? ''),
            kSearchSnippetMaxLength,
          ),
          provider: providerId,
          // Brave 不提供发布时间，因此类别只能由主机判定（不猜时间）。
          accessCategory: classifySearchAccessCategory(url: url),
          rank: rank,
        ),
      );
      rank++;
    }
    // Brave 没有 answer / 结果总数 / response_time：这三项一律为 null，不编造。
    return SearchResponse(
      provider: providerId,
      query: query,
      results: List<SearchResult>.unmodifiable(results),
    );
  }

  /// 把结果数夹到 SET-040 的允许区间（协议本身也是 1–20）。
  int _clampResults(int requested) =>
      requested.clamp(kSearchMinResults, kSearchMaxResults);
}
