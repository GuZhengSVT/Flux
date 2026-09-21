// SearXNG 适配器（T031；协议事实来源：主代理提供，检索于 2026-09-22）。
//
// 请求（GET {instance}/search?format=json&q=...）：
//   参数 q, language, pageno, time_range, categories
//   自建实例：用户填 BaseURL；**可能**需要 Authorization 头（实例自配，默认无认证）。
//
// 响应：{results:[{title, url, content, publishedDate?}], number_of_results}
//
// 与另两家**本质不同**的地方：
//   1) **没有默认端点**：实例地址只有用户自己知道。替用户猜一个公网实例等于把她的
//      查询发给一个她从没选过的第三方——这是隐私问题，不是配置便利问题；
//   2) 认证是**可选**的（反向代理层可能自己做）；因此「没有凭据」不构成拒绝理由，
//      真正需要认证的实例会返回 401/403，届时错误分类会明确指向「去补凭据」；
//   3) 分页参数叫 pageno（页码）而不是 offset（条数偏移）。本适配器只做第 1 页：
//      收到 offset 时**明确报错**，不做「offset / count 换算成 pageno」的猜测换算
//      ——页码→偏移的映射取决于实例的每页大小配置，换算出来的页可能是错的，
//      而错的页比没有页更糟（调用方会以为拿到了连续的第二页）。
//
// 安全边界（SET-041、架构第 8 节）：
//   - 未显式批准时，**私网/环回地址在发出请求之前就被拒绝**。自建实例常在局域网，
//     因此这条拒绝的文案必须指向「去打开 SET-041 的显式批准」，而不是一句「地址非法」；
//   - 批准只对**这一个端点**生效（存在记录里），不是一个全局开关；
//   - Authorization 头只在有凭据时发送，且从不拼进 URL 或日志。
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

/// SearXNG 适配器。
final class SearxngSearchAdapter implements SearchProvider {
  /// 构造适配器。
  SearxngSearchAdapter({
    required this.baseUrl,
    this.apiKey = '',
    this.allowPrivateEndpoint = false,
    this.maxResults = 10,
    this.timeout = const Duration(seconds: 20),
    this.client,
  });

  /// 实例 Base URL（必填；没有默认值）。
  final String baseUrl;

  /// 实例认证 Token；空串表示不发送 Authorization 头。
  final String apiKey;

  /// 用户是否已显式批准该端点指向内网/明文 HTTP（SET-041）。
  final bool allowPrivateEndpoint;

  /// 默认结果数（SET-040）。
  final int maxResults;

  /// 单次检索超时（SET-040）。
  final Duration timeout;

  /// 可注入的 HTTP 客户端（测试用 MockClient）；为空时每次请求自建。
  final http.Client? client;

  /// 端点（{instance}/search）。
  Uri get endpoint => SearchProtocol.searxng.endpointFor(baseUrl);

  @override
  String get providerId => SearchProtocol.searxng.id;

  @override
  Future<Result<SearchResponse>> search(SearchRequest query) async {
    final Result<void> valid = validateSearchQueryText(query.text);
    if (valid.isErr) {
      return Err<SearchResponse>(valid.errorOrNull!);
    }
    if (query.offset != null) {
      return Err<SearchResponse>(
        ValidationError(
          field: 'offset',
          reason: 'SearXNG 使用页码而不是条数偏移，本适配器只支持第 1 页',
          value: '${query.offset}',
        ),
      );
    }
    // 地址守卫在**发出请求之前**运行（SET-041 的显式批准是唯一的放行条件）。
    final Result<void> guarded = _guardEndpoint();
    if (guarded.isErr) {
      return Err<SearchResponse>(guarded.errorOrNull!);
    }

    final http.Client? owned = client == null ? http.Client() : null;
    final http.Client effective = owned ?? client!;
    try {
      final Map<String, String> params = <String, String>{
        'format': 'json',
        'q': query.text.trim(),
        if (query.language != null && query.language!.isNotEmpty)
          'language': query.language!,
      };
      final http.Request request = http.Request(
        'GET',
        endpoint.replace(queryParameters: params),
      )..headers['Accept'] = 'application/json';
      // 只在有凭据时发送认证头：无条件发一个空 Bearer 会让某些反向代理直接 401。
      if (apiKey.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $apiKey';
      }

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

  /// 端点守卫：协议 + 私网判定（SET-041）。
  ///
  /// 用 configuredSource 还是 embeddedContent？**都不是**，因此这里显式写出两段判断
  /// 而不是复用其中一个策略：
  ///   - configuredSource **允许**私网（订阅源常用局域网），搜索服务不行——查询词是
  ///     用户内容，发到内网某个端口等于把内容交给一个未经审查的服务；
  ///   - embeddedContent 的拒绝面是对的，但它的错误信息面向「内容里的地址」，
  ///     而这里需要告诉用户「去开启 SET-041 的显式批准」。
  /// 因此判据复用（checkUrlGuarded），文案单独构造——判据只有一份，提示面向当下场景。
  Result<void> _guardEndpoint() {
    final Uri uri = endpoint;
    final UrlGuardResult literal = checkUrlGuarded(
      uri,
      UrlGuardPolicy.embeddedContent,
    );
    if (literal.allowed) {
      return const Ok<void>(null);
    }
    if (!allowPrivateEndpoint) {
      return Err<void>(
        ValidationError(
          field: 'SET-041',
          reason: '该端点指向本机或私有网络，需要在设置里显式批准（SET-041）后才能使用',
          value: uri.host,
        ),
      );
    }
    // 已显式批准：只有**私网**这一类失败被批准放行；协议非法（file:// 等）仍然拒绝，
    // 因为那不是「用户想连自己的服务」，而是一个不可能的请求。
    if (literal.failure == UrlGuardFailure.privateAddress) {
      return const Ok<void>(null);
    }
    return Err<void>(urlGuardError(uri));
  }

  /// 把协议响应映射到统一结构。
  SearchResponse _mapResponse(Map<String, Object?> body, String query) {
    final List<SearchResult> results = <SearchResult>[];
    int rank = 0;
    for (final Map<String, Object?> entry in searchObjectList(
      body['results'],
    )) {
      final String? url = searchString(entry['url']);
      if (url == null || !isUsableSearchResultUrl(url)) {
        rank++;
        continue;
      }
      final DateTime? published = searchAbsoluteTime(entry['publishedDate']);
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
          rank: rank,
        ),
      );
      rank++;
    }
    return SearchResponse(
      provider: providerId,
      query: query,
      results: List<SearchResult>.unmodifiable(results),
      totalResults: searchInt(body['number_of_results']),
    );
  }
}
