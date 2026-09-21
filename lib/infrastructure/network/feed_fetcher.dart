// 订阅抓取（T013；架构 4.1「刷新有条件请求、取消、限并发，区分 304、没有新文章、
// 部分解析失败和网络失败；保留旧内容。XML 禁外部实体/DTD，设响应、解压、图片尺寸和
// 解析深度上限。」、SET-028、第 8 节）。
//
// 本文件只做**取回字节**这一件事，且把每条边界都做成显式参数或显式错误：
//   - 条件请求：If-None-Match / If-Modified-Since，304 直接返回 NotModified；
//   - 单源超时：默认 30 秒（SET-028）；
//   - 并发上限：默认 4（SET-028），用信号量串行化超出部分；
//   - 响应体上限：10 MiB；**解压后同样限 10 MiB**（zip bomb 保护）；
//   - 重定向：手动跟随，每跳重新校验协议与目标，次数 ≤5；
//   - 非 2xx/304：类型化网络错误。
//
// 为什么不解析、不入库：把「取字节」「解析」「写库」分开之后，「网络失败要保留旧内容」
// 这条规则变成结构上的必然——网络层失败时根本没有可供写入的数据。
//
// 关于 User-Agent：带上项目标识与主页，便于源站识别流量并在必要时联系。这不是伪装成
// 浏览器，也不带任何凭据。
library;

import 'dart:async';

import 'package:http/http.dart' as http;

import 'package:flux/core/core.dart';

import 'http_client_factory.dart';
import 'response_body.dart';

/// 基于 package:http 的抓取实现。
class HttpFeedFetcher implements FeedFetcher {
  /// 构造抓取器。
  ///
  /// [client] 可注入（测试用 MockClient）；不注入时每次请求自建，避免长期持有连接
  /// 造成测试与生命周期问题。
  HttpFeedFetcher({
    this.client,
    this.config = const FeedFetchConfig(),
    this.clock = const SystemClock(),
  });

  /// 可注入的 HTTP 客户端（测试用 MockClient）；为空时每次请求自建。
  final http.Client? client;

  /// 配置。
  final FeedFetchConfig config;

  /// 时钟（用于统一「现在」，测试可注入）。
  final Clock clock;

  /// 并发信号量（同一个实例内共享，保证并发上限是**实例级**约束）。
  late final _Semaphore _semaphore = _Semaphore(config.maxConcurrency);

  @override
  Future<Result<FeedFetchResult>> fetch(
    Uri uri, {
    FeedCacheValidator? validator,
  }) => _semaphore.run(() => _fetchWithRedirects(uri, validator));

  /// 手动跟随重定向。
  ///
  /// 为什么不用 http 客户端的自动跟随：自动跟随不会在每一跳重新校验协议与目标，
  /// 也无法限制跳数（Request.maxRedirects 在 streamed 请求上语义不一致）。手动跟随让
  /// 「每一跳都按同样的规则检查」成为代码结构上的事实。
  Future<Result<FeedFetchResult>> _fetchWithRedirects(
    Uri start,
    FeedCacheValidator? validator,
  ) async {
    Uri current = start;
    int redirects = 0;
    bool conditionalSent = false;

    while (true) {
      final Result<void> schemeCheck = _checkScheme(current);
      if (schemeCheck.isErr) {
        return Err<FeedFetchResult>(schemeCheck.errorOrNull!);
      }

      final http.Request request = http.Request('GET', current);
      request.headers['User-Agent'] = config.userAgent;
      request.headers['Accept'] =
          'application/atom+xml, application/rss+xml, application/xml, '
          'text/xml;q=0.9, */*;q=0.5';
      // 只要被显式要求解压，就必须自己限长：交给客户端自动解压会先解压再交给我们，
      // 解压炸弹在那时已经发生。因此请求里禁用自动解压，由本文件控制。
      request.headers['Accept-Encoding'] = 'gzip';
      // 条件请求只在第一跳带上：重定向之后目标资源与原始 ETag 不一定对应。
      if (!conditionalSent && validator != null && !validator.isEmpty) {
        if (validator.etag != null && validator.etag!.isNotEmpty) {
          request.headers['If-None-Match'] = validator.etag!;
        }
        if (validator.lastModified != null &&
            validator.lastModified!.isNotEmpty) {
          request.headers['If-Modified-Since'] = validator.lastModified!;
        }
        conditionalSent = true;
      }

      // 注入的客户端由调用方负责生命周期（测试里通常复用同一个 MockClient）；
      // 自建的临时客户端必须在本方法返回前关闭，否则每次抓取都会泄漏一个连接池。
      // 必须用 createRawHttpClient()（autoUncompress=false）：默认客户端会**自动解压**而保留
      // content-encoding 头，导致本文件再解一次而报「gzip 数据非法」（真实源实测到）。
      final http.Client? owned = client == null ? createRawHttpClient() : null;
      final http.Client effective = owned ?? client!;
      http.StreamedResponse response;
      try {
        response = await effective
            .send(request)
            .timeout(
              config.timeout,
              onTimeout: () {
                throw TimeoutException('feed fetch timeout', config.timeout);
              },
            );
      } on TimeoutException {
        owned?.close();
        return Err<FeedFetchResult>(
          DeadlineExceededError(limitKind: 'feedFetch', limit: config.timeout),
        );
      } on http.ClientException catch (error) {
        owned?.close();
        return Err<FeedFetchResult>(
          NetworkError(uri: current.toString(), reason: '连接失败', cause: error),
        );
      } on Exception catch (error) {
        owned?.close();
        return Err<FeedFetchResult>(
          NetworkError(
            uri: current.toString(),
            reason: '请求失败（${error.runtimeType}）',
            cause: error,
          ),
        );
      }

      final int status = response.statusCode;

      // ---- 重定向 ---------------------------------------------------------
      if (_isRedirect(status)) {
        final String? location = response.headers['location'];
        if (location == null || location.trim().isEmpty) {
          return Err<FeedFetchResult>(
            NetworkError(
              uri: current.toString(),
              statusCode: status,
              reason: '重定向缺少 Location',
            ),
          );
        }
        if (redirects >= config.maxRedirects) {
          return Err<FeedFetchResult>(
            NetworkError(
              uri: current.toString(),
              statusCode: status,
              reason: '重定向次数超过上限 ${config.maxRedirects}',
            ),
          );
        }
        // resolve 对绝对/相对 Location 都成立；它不返回 null，因此这里只需校验协议
        // 与主机（在下一轮循环开头统一做）。
        // 下一跳的协议与主机在循环开头统一校验，因此这里不再重复。
        current = current.resolve(location.trim());
        redirects++;
        continue;
      }

      // ---- 304 ------------------------------------------------------------
      if (status == 304) {
        return Ok<FeedFetchResult>(
          FeedFetchResult(
            status: FeedFetchStatus.notModified,
            requestedUri: _safeUri(start),
            finalUri: _safeUri(current),
            redirectCount: redirects,
          ),
        );
      }

      // ---- 其余非 2xx -----------------------------------------------------
      if (status < 200 || status >= 300) {
        return Err<FeedFetchResult>(
          NetworkError(
            uri: current.toString(),
            statusCode: status,
            reason: '非成功响应',
          ),
        );
      }

      // ---- 读体（带上限） --------------------------------------------------
      final Result<RawResponseBody> body = await readBoundedBody(
        response,
        maxBytes: config.maxResponseBytes,
        timeout: config.timeout,
        limitKind: 'feedFetchBody',
      );
      if (body.isErr) {
        return Err<FeedFetchResult>(body.errorOrNull!);
      }
      final RawResponseBody raw = body.unwrap();

      // ---- 解压（同样限长） -----------------------------------------------
      final Result<String> decoded = decodeResponseBody(
        raw,
        maxBytes: config.maxResponseBytes,
      );
      if (decoded.isErr) {
        return Err<FeedFetchResult>(decoded.errorOrNull!);
      }

      return Ok<FeedFetchResult>(
        FeedFetchResult(
          status: FeedFetchStatus.ok,
          requestedUri: _safeUri(start),
          finalUri: _safeUri(current),
          body: decoded.unwrap(),
          etag: response.headers['etag'],
          lastModified: response.headers['last-modified'],
          contentType: response.headers['content-type'],
          redirectCount: redirects,
          encodedBytes: raw.bytes.length,
          decodedBytes: decoded.unwrap().length,
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

  /// 每跳都校验协议：只允许 http/https。
  ///
  /// 这一条挡的是「https 源跳到 file:// 或其它协议」——重定向到本地文件或自定义协议
  /// 是典型的攻击面，即使当前抓取层不会执行它，也不该把它当成一次成功的抓取。
  static Result<void> _checkScheme(Uri uri) {
    if (!uri.isScheme('http') && !uri.isScheme('https')) {
      return Err<void>(
        NetworkError(
          uri: uri.toString(),
          reason: '只允许 http/https（实际 ${uri.scheme}）',
        ),
      );
    }
    if (uri.host.isEmpty) {
      return Err<void>(NetworkError(uri: uri.toString(), reason: '缺少主机名'));
    }
    return const Ok<void>(null);
  }

  /// 日志/错误里使用的地址：脱敏后返回（去掉 query 里的秘密参数）。
  static String _safeUri(Uri uri) =>
      SecretRedaction.sanitizeUrlString(uri.toString());
}

/// 简单计数信号量。
///
/// 为什么自己写：只需要「限制同时进行的请求数」这一件事，引入并发库会为几行逻辑带来
/// 一整套抽象；而这个实现可以被直接测试（见 feed_fetcher_test 的并发上限用例）。
class _Semaphore {
  _Semaphore(this.maxConcurrency) : _available = maxConcurrency;

  final int maxConcurrency;
  int _available;
  final List<Completer<void>> _waiters = <Completer<void>>[];

  Future<T> run<T>(Future<T> Function() action) async {
    await _acquire();
    try {
      return await action();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() {
    if (_available > 0) {
      _available--;
      return Future<void>.value();
    }
    final Completer<void> waiter = Completer<void>();
    _waiters.add(waiter);
    return waiter.future;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      // 直接把名额交给下一个等待者，避免「释放后又被新来的抢走」造成饥饿。
      final Completer<void> next = _waiters.removeAt(0);
      if (!next.isCompleted) {
        next.complete();
      }
      return;
    }
    _available++;
  }
}
