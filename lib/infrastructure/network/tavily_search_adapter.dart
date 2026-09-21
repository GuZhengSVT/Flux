// Tavily Search 适配器（T031；协议事实来源：主代理提供，检索于 2026-09-22）。
//
// 请求（POST {base}/search，Content-Type: application/json）：
//   {query, max_results(1-20), search_depth:"basic"|"advanced",
//    include_answer?, include_domains?, exclude_domains?}
// 认证：body 里 api_key 或 Authorization: Bearer 头（两代并存）。本工程**用 Bearer 头**：
//   body 里的 api_key 会跟着请求体进入任何中间层的日志/抓包，而头部同样是标准位置且
//   不会被「顺手 log 一下 body」这类调试代码带走。
//
// 响应：
//   {results:[{title, url, content(片段), score, published_date?}], answer?, response_time}
//
// 三条与另两家**本质不同**的地方（因此不能只改 URL）：
//   1) 唯一一个用 POST + JSON body 的协议（另两家是 GET 查询串）；
//   2) 有 answer（服务商直接给出的答案摘要）与 response_time 两个不属于单条结果的字段；
//   3) 请求体里有 search_depth 与 include/exclude_domains 这类**请求侧过滤**参数。
//
// 安全边界：API Key 只出现在 Authorization 头里，**从不**拼进 URL、日志或异常消息；
// 响应体只被解析成结构化字段，不整段写入错误消息（响应体会回显查询词）。
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/domain/search_errors.dart';
import 'package:flux/features/ai/domain/search_protocol.dart';
import 'package:flux/features/ai/domain/search_provider.dart';
import 'package:flux/features/ai/domain/search_result.dart';
import 'package:flux/features/ai/domain/search_service.dart';

import 'search_http.dart';

/// Tavily 适配器。
final class TavilySearchAdapter implements SearchProvider {
  /// 构造适配器。
  TavilySearchAdapter({
    required this.baseUrl,
    required this.apiKey,
    this.maxResults = 10,
    this.timeout = const Duration(seconds: 20),
    this.client,
  });

  /// Base URL（不含协议路径）。
  final String baseUrl;

  /// API Key（只用于 Authorization 头）。
  final String apiKey;

  /// 默认结果数（SET-040；调用参数未指定时使用）。
  final int maxResults;

  /// 单次检索超时（SET-040）。
  final Duration timeout;

  /// 可注入的 HTTP 客户端（测试用 MockClient）；为空时每次请求自建。
  final http.Client? client;

  /// 端点（{base}/search）。
  Uri get endpoint => SearchProtocol.tavily.endpointFor(baseUrl);

  @override
  String get providerId => SearchProtocol.tavily.id;

  @override
  Future<Result<SearchResponse>> search(SearchRequest query) async {
    // 没有 Key 时**在发出任何字节之前**拒绝：Tavily 没有匿名额度，发出去必然 401，
    // 而这一次失败会在服务商侧留下记录（有些套餐把失败请求也计入速率统计）。
    if (apiKey.isEmpty) {
      return Err<SearchResponse>(
        AuthError(provider: providerId, detail: 'credentialMissing'),
      );
    }
    final Result<void> valid = validateSearchQueryText(query.text);
    if (valid.isErr) {
      return Err<SearchResponse>(valid.errorOrNull!);
    }
    // Tavily 的请求体没有 offset 字段。静默忽略会让调用方以为拿到了第二页。
    if (query.offset != null) {
      return Err<SearchResponse>(
        ValidationError(
          field: 'offset',
          reason: 'Tavily 协议不支持 offset 分页',
          value: '${query.offset}',
        ),
      );
    }

    final http.Client? owned = client == null ? http.Client() : null;
    final http.Client effective = owned ?? client!;
    try {
      final http.Request request = http.Request('POST', endpoint)
        ..headers['Authorization'] = 'Bearer $apiKey'
        ..headers['Content-Type'] = 'application/json'
        ..headers['Accept'] = 'application/json'
        ..body = jsonEncode(<String, Object?>{
          'query': query.text.trim(),
          'max_results': _clampResults(query.count),
          'search_depth': 'basic',
          'include_answer': true,
        });

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
        // 错误体只用于判断（不读它的文案）；这里必须读完并关闭，否则连接不会释放。
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

  /// 把协议响应映射到统一结构。
  SearchResponse _mapResponse(Map<String, Object?> body, String query) {
    final List<SearchResult> results = <SearchResult>[];
    int rank = 0;
    for (final Map<String, Object?> entry in searchObjectList(
      body['results'],
    )) {
      final String? url = searchString(entry['url']);
      // 地址不合格的条目**丢弃而不是保留**：结果来自第三方，一个指向内网的地址
      // 留着等下游再判一次，就是「某条路径忘记过滤」的典型来源。
      if (url == null || !isUsableSearchResultUrl(url)) {
        rank++;
        continue;
      }
      final DateTime? published = searchAbsoluteTime(entry['published_date']);
      results.add(
        SearchResult(
          sourceId: searchResultSourceId(provider: providerId, rank: rank),
          title: clampSearchText(
            searchString(entry['title']) ?? '',
            kSearchTitleMaxLength,
          ),
          url: url,
          snippet: clampSearchText(
            searchString(entry['content']) ?? '',
            kSearchSnippetMaxLength,
          ),
          provider: providerId,
          accessCategory: classifySearchAccessCategory(
            url: url,
            publishedAt: published,
          ),
          publishedAt: published,
          score: searchNumber(entry['score']),
          rank: rank,
        ),
      );
      rank++;
    }
    return SearchResponse(
      provider: providerId,
      query: query,
      results: List<SearchResult>.unmodifiable(results),
      answer: searchString(body['answer']),
      responseTime: _responseTime(body['response_time']),
    );
  }

  /// response_time 是**秒**（可能是小数）；换算成 Duration。
  static Duration? _responseTime(Object? value) {
    final double? seconds = searchNumber(value);
    if (seconds == null || seconds < 0) {
      return null;
    }
    return Duration(microseconds: (seconds * 1000000).round());
  }

  /// 把结果数夹到 SET-040 的允许区间（协议本身也是 1–20）。
  int _clampResults(int requested) =>
      requested.clamp(kSearchMinResults, kSearchMaxResults);
}
