// 静态网页抓取（T024；架构 4.2「主动提取只用 HTTP + 静态解析」与第 8 节的安全约束）。
//
// 与 T013 的订阅抓取、T021 的图片抓取**共用同一条判据链**，不另写一套：
//   1) 地址守卫（UrlGuardPolicy）：只允许 http/https，拒绝字面量私网/回环；
//   2) DNS 解析后再验一次：字面量检查挡不住 evil.example.com → 127.0.0.1；
//   3) 重定向逐跳校验（手动跟随，每跳重跑 1 与 2）；
//   4) 体积上限：声明长度 + 流式计数 + 解压后上限（复用 T013 抽出的 response_body）。
//
// 为什么用 [UrlGuardPolicy.embeddedContent] 而不是 configuredSource：**这个地址不是用户
// 配置的**，它来自订阅源里的文章链接，也就是第三方内容。第三方内容指向内网是典型的
// SSRF 形态——让阅读器替攻击者去访问用户所在网络里的服务。订阅源本身仍允许内网（用户
// 明确配置的），两者策略不同是刻意的。
//
// 本层**不解析 HTML**：抽取是 features/articles/domain 的纯函数。分开之后，「网页字节」
// 与「正文」之间的边界只有一处，而解析规则可以用 fixture 离线验证，不需要联网。
//
// 无隐藏浏览器：本层只有 HTTP GET，没有任何 WebView/无头浏览器/脚本执行路径。这不是
// 「本轮还没做」，而是产品边界（D-05 与第 8 节）。
library;

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:flux/core/core.dart';

import 'http_client_factory.dart';
import 'response_body.dart';

/// 网页抓取配置。
final class StaticPageFetchConfig {
  /// 构造配置。
  const StaticPageFetchConfig({
    this.timeout = const Duration(seconds: 30),
    this.maxBytes = 10 * 1024 * 1024,
    this.maxRedirects = 5,
    this.userAgent = FeedFetchConfig.defaultUserAgent,
  });

  /// 单次抓取超时。
  final Duration timeout;

  /// 响应体上限（未压缩与解压后各自适用）。
  final int maxBytes;

  /// 重定向上限。
  final int maxRedirects;

  /// User-Agent（项目标识 + 主页，不含凭据，不伪装成浏览器）。
  final String userAgent;
}

/// 一次静态网页抓取的产物。
final class StaticPageFetchResult {
  /// 构造结果。
  const StaticPageFetchResult({
    required this.requestedUri,
    required this.finalUri,
    required this.html,
    required this.contentType,
    required this.redirectCount,
    required this.decodedBytes,
  });

  /// 最初请求的地址（已脱敏）。
  final String requestedUri;

  /// 最终地址（跟随重定向之后；已脱敏）。
  final String finalUri;

  /// 响应体文本（HTML）。
  final String html;

  /// Content-Type（原样保留；抽取层据此判断是不是 HTML）。
  final String? contentType;

  /// 实际重定向次数。
  final int redirectCount;

  /// 解压后字节数（诊断用）。
  final int decodedBytes;
}

/// 基于 package:http 的静态网页抓取实现。
final class HttpStaticPageFetcher {
  /// 构造抓取器。
  ///
  /// [client] 与 [resolveHost] 可注入（测试用），生产不传。
  HttpStaticPageFetcher({
    this.client,
    this.config = const StaticPageFetchConfig(),
    Future<List<InternetAddress>> Function(String host)? resolveHost,
  }) : _resolveHost = resolveHost ?? _defaultResolve;

  /// 注入的客户端（测试用）。
  final http.Client? client;

  /// 配置。
  final StaticPageFetchConfig config;

  final Future<List<InternetAddress>> Function(String host) _resolveHost;

  static Future<List<InternetAddress>> _defaultResolve(String host) =>
      InternetAddress.lookup(host);

  /// 取回 [start] 指向的网页。
  Future<Result<StaticPageFetchResult>> fetch(Uri start) async {
    Uri current = start;
    final List<Uri> visited = <Uri>[];
    int redirects = 0;

    while (true) {
      // 每一跳都要重跑守卫与 DNS 复检（与媒体抓取同一条理由：不在这一跳信任 Location）。
      final Result<void> guarded = await resolveAndGuard(current);
      if (guarded.isErr) {
        return Err<StaticPageFetchResult>(guarded.errorOrNull!);
      }
      if (visited.contains(current)) {
        return Err<StaticPageFetchResult>(
          NetworkError(
            uri: current.toString(),
            reason: '重定向成环（回到已访问过的地址）',
            isRetryable: false,
          ),
        );
      }
      visited.add(current);

      final http.Request request = http.Request('GET', current)
        ..headers['User-Agent'] = config.userAgent
        ..headers['Accept'] = 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.5'
        ..headers['Accept-Encoding'] = 'gzip';

      final http.Client? owned = client == null ? createRawHttpClient() : null;
      final http.Client effective = owned ?? client!;
      http.StreamedResponse response;
      try {
        response = await effective
            .send(request)
            .timeout(
              config.timeout,
              onTimeout: () =>
                  throw TimeoutException('page fetch timeout', config.timeout),
            );
      } on TimeoutException {
        owned?.close();
        return Err<StaticPageFetchResult>(
          DeadlineExceededError(limitKind: 'pageFetch', limit: config.timeout),
        );
      } on Exception catch (error) {
        owned?.close();
        return Err<StaticPageFetchResult>(
          NetworkError(
            uri: current.toString(),
            reason: '网页请求失败（${error.runtimeType}）',
            cause: error,
          ),
        );
      }

      final int status = response.statusCode;

      if (_isRedirect(status)) {
        final String? location = response.headers['location'];
        owned?.close();
        if (location == null || location.trim().isEmpty) {
          return Err<StaticPageFetchResult>(
            NetworkError(
              uri: current.toString(),
              statusCode: status,
              reason: '重定向缺少 Location',
            ),
          );
        }
        if (redirects >= config.maxRedirects) {
          return Err<StaticPageFetchResult>(
            NetworkError(
              uri: current.toString(),
              statusCode: status,
              reason: '重定向次数超过上限 ${config.maxRedirects}',
            ),
          );
        }
        current = current.resolve(location.trim());
        redirects++;
        continue;
      }

      if (status < 200 || status >= 300) {
        owned?.close();
        return Err<StaticPageFetchResult>(
          NetworkError(
            uri: current.toString(),
            statusCode: status,
            reason: status == 402 || status == 403
                ? '网页拒绝访问（可能需要登录或订阅；本应用不绕过访问限制）'
                : '网页响应非成功（HTTP $status）',
            // 401/402/403 是访问限制，重试不会改变结果。
            isRetryable: status != 401 && status != 402 && status != 403,
          ),
        );
      }

      final Result<RawResponseBody> body = await readBoundedBody(
        response,
        maxBytes: config.maxBytes,
        timeout: config.timeout,
        limitKind: 'pageFetchBody',
      );
      owned?.close();
      if (body.isErr) {
        return Err<StaticPageFetchResult>(body.errorOrNull!);
      }
      final RawResponseBody raw = body.unwrap();
      final Result<String> decoded = decodeResponseBody(
        raw,
        maxBytes: config.maxBytes,
      );
      if (decoded.isErr) {
        return Err<StaticPageFetchResult>(decoded.errorOrNull!);
      }
      final String html = decoded.unwrap();

      return Ok<StaticPageFetchResult>(
        StaticPageFetchResult(
          requestedUri: SecretRedaction.sanitizeUrlString(start.toString()),
          finalUri: SecretRedaction.sanitizeUrlString(current.toString()),
          html: html,
          contentType: response.headers['content-type'],
          redirectCount: redirects,
          decodedBytes: html.length,
        ),
      );
    }
  }

  static bool _isRedirect(int status) =>
      status == 301 ||
      status == 302 ||
      status == 303 ||
      status == 307 ||
      status == 308;

  /// 守卫 + DNS 解析后复检（与 T021 的媒体抓取同一顺序与理由）。
  Future<Result<void>> resolveAndGuard(Uri uri) async {
    final UrlGuardResult literal = checkUrlGuarded(
      uri,
      UrlGuardPolicy.embeddedContent,
    );
    if (!literal.allowed) {
      return Err<void>(urlGuardError(uri));
    }
    if (InternetAddress.tryParse(uri.host) != null) {
      return const Ok<void>(null);
    }
    final List<InternetAddress> addresses;
    try {
      addresses = await _resolveHost(uri.host).timeout(config.timeout);
    } on Exception catch (error) {
      // 解析失败不是安全事件，是一次网络失败：交给调用方按可重试处理。
      return Err<void>(
        NetworkError(
          uri: uri.toString(),
          reason: '主机名解析失败（$error）',
          cause: error,
        ),
      );
    }
    if (addresses.isEmpty) {
      return Err<void>(
        NetworkError(uri: uri.toString(), reason: '主机名没有解析出任何地址'),
      );
    }
    for (final InternetAddress address in addresses) {
      if (isPrivateHostLiteral(address.address)) {
        return Err<void>(
          NetworkError(
            uri: uri.toString(),
            reason: '主机 ${uri.host} 解析到本机或私有网络地址 ${address.address}',
            isRetryable: false,
          ),
        );
      }
    }
    return const Ok<void>(null);
  }
}
