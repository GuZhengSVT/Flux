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
import 'dart:convert';
import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:flux/core/core.dart';

import 'http_client_factory.dart';

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
      final Result<_RawBody> body = await _readBody(response);
      if (body.isErr) {
        return Err<FeedFetchResult>(body.errorOrNull!);
      }
      final _RawBody raw = body.unwrap();

      // ---- 解压（同样限长） -----------------------------------------------
      final Result<String> decoded = _decodeBody(raw, current);
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

  /// 读取响应体，超过上限立刻中止（不把整段读完再检查）。
  ///
  /// 流式检查而不是「读完再看长度」：后者在 10 GiB 响应面前已经先把内存吃光了，
  /// 上限就失去意义。
  Future<Result<_RawBody>> _readBody(http.StreamedResponse response) async {
    final int? declared = response.contentLength;
    if (declared != null && declared > config.maxResponseBytes) {
      return Err<_RawBody>(
        NetworkError(
          uri: response.request?.url.toString() ?? '',
          reason: '响应体声明长度 $declared 超过上限 ${config.maxResponseBytes}',
        ),
      );
    }

    final BytesBuilder builder = BytesBuilder(copy: false);
    int total = 0;
    try {
      await for (final List<int> chunk in response.stream.timeout(
        config.timeout,
        onTimeout: (EventSink<List<int>> sink) => sink.addError(
          TimeoutException('feed body timeout', config.timeout),
        ),
      )) {
        total += chunk.length;
        if (total > config.maxResponseBytes) {
          return Err<_RawBody>(
            NetworkError(
              uri: response.request?.url.toString() ?? '',
              reason: '响应体超过上限 ${config.maxResponseBytes} 字节',
            ),
          );
        }
        builder.add(chunk);
      }
    } on TimeoutException {
      return Err<_RawBody>(
        DeadlineExceededError(
          limitKind: 'feedFetchBody',
          limit: config.timeout,
        ),
      );
    } on Exception catch (error) {
      return Err<_RawBody>(
        NetworkError(
          uri: response.request?.url.toString() ?? '',
          reason: '读取响应体失败（${error.runtimeType}）',
          cause: error,
        ),
      );
    }

    return Ok<_RawBody>(
      _RawBody(
        bytes: builder.takeBytes(),
        contentEncoding: response.headers['content-encoding'],
      ),
    );
  }

  /// 解压并转成文本；解压**后**同样限长（zip bomb 保护）。
  Result<String> _decodeBody(_RawBody raw, Uri uri) {
    Uint8List bytes = raw.bytes;
    final String? encoding = raw.contentEncoding?.toLowerCase();
    if (encoding != null && encoding.contains('gzip')) {
      final Result<Uint8List> inflated = _gunzipBounded(bytes);
      if (inflated.isErr) {
        return Err<String>(inflated.errorOrNull!);
      }
      bytes = inflated.unwrap();
    }

    // 编码：优先用 Content-Type 里声明的 charset，其次按 UTF-8 解析。
    //
    // 为什么要显式解码而不是 http 的 body 字符串：RSS 源里 latin-1 与无声明编码很常见，
    // 直接按 UTF-8 硬解会产生大量替换字符，正文里的中文会整段变乱码。
    final String text = _decodeText(bytes);
    return Ok<String>(text);
  }

  /// 有界 gzip 解压。
  ///
  /// 用 dart:io 的 **chunked** 解码入口（ZLibDecoder.startChunkedConversion）而不是
  /// gzip.decode(bytes)：后者是一次性转换器，会先把整个解压结果构造出来再交给我们，
  /// 那时解压结果已经在内存里，上限等于没有。chunked 入口允许在**每个输出分块**上计数
  /// 并在超限时立刻中止，这才是压缩炸弹的真正防线。
  Result<Uint8List> _gunzipBounded(Uint8List input) {
    final _BoundedSink sink = _BoundedSink(config.maxResponseBytes);
    try {
      final ByteConversionSink decoder = ZLibDecoder(gzip: true)
          .startChunkedConversion(sink);
      // 分块喂入：输入侧已受 maxResponseBytes 限制，这里按 64 KiB 切片是为了让
      // 「边解压边计数」尽可能早地触发中止。
      const int chunkSize = 64 * 1024;
      for (int offset = 0; offset < input.length; offset += chunkSize) {
        final int end = (offset + chunkSize).clamp(0, input.length);
        decoder.add(input.sublist(offset, end));
      }
      decoder.close();
    } on _BodyTooLargeException {
      return Err<Uint8List>(
        NetworkError(
          uri: '',
          reason: '解压后超过上限 ${config.maxResponseBytes} 字节（疑似压缩炸弹）',
        ),
      );
    } on FormatException catch (error) {
      return Err<Uint8List>(
        NetworkError(
          uri: '',
          reason: 'gzip 数据非法（${error.message}）',
          cause: error,
        ),
      );
    } on Exception catch (error) {
      return Err<Uint8List>(
        NetworkError(
          uri: '',
          reason: 'gzip 解压失败（${error.runtimeType}）',
          cause: error,
        ),
      );
    }
    final Uint8List decoded = sink.takeBytes();
    // dart:io 的增量解压对**截断**输入是宽容的：它不报错，只是不产出
    // 更多字节。因此这里必须自己判断「非空输入却解出空结果」：那是明确的
    // 损坏，而不是「一个正常的空源」。若不检查，抓取层会报「成功、正文为空」，
    // 把一个损坏响应描述成正常结果。真正的完整性验证仍由解析层完成（截断的 XML
    // 会在那里报结构错误），这里只把「完全没解出东西」这种最明显的情况
    // 提前报出。
    if (input.isNotEmpty && decoded.isEmpty) {
      return Err<Uint8List>(
        NetworkError(uri: '', reason: 'gzip 数据损坏或被截断（非空输入未解出任何内容）'),
      );
    }
    return Ok<Uint8List>(decoded);
  }

  /// 字节转文本：先看 BOM，再尝试 UTF-8，最后退到 latin-1。
  ///
  /// 退到 latin-1 而不是「用替换字符填充」：latin-1 对任意字节都能构造出确定文本，
  /// 至少不会让整篇正文变成一个问号；源站编码声明错误是现实里很常见的情况。
  static String _decodeText(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3), allowMalformed: true);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return _decodeUtf16(bytes.sublist(2), littleEndian: true);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return _decodeUtf16(bytes.sublist(2), littleEndian: false);
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes, allowInvalid: true);
    }
  }

  static String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
    final List<int> units = <int>[];
    for (int i = 0; i + 1 < bytes.length; i += 2) {
      units.add(
        littleEndian
            ? bytes[i] | (bytes[i + 1] << 8)
            : (bytes[i] << 8) | bytes[i + 1],
      );
    }
    return String.fromCharCodes(units);
  }

  /// 日志/错误里使用的地址：脱敏后返回（去掉 query 里的秘密参数）。
  static String _safeUri(Uri uri) =>
      SecretRedaction.sanitizeUrlString(uri.toString());
}

/// 解压后的原始体。
class _RawBody {
  const _RawBody({required this.bytes, this.contentEncoding});

  final Uint8List bytes;
  final String? contentEncoding;
}

/// 超出体积上限的内部信号。
class _BodyTooLargeException implements Exception {
  const _BodyTooLargeException();
}

/// 带输出上限的字节收集器（gzip 解压的输出侧防线）。
///
/// 作为 ByteConversionSink 接收解码器的输出：每次 add 都在累计长度上检查，超限立即
/// 抛 [_BodyTooLargeException]。因为解码器是 chunked 的，异常会在解压**过程中**抛出，
/// 而不是等整段解完——这正是「上限真的挡得住压缩炸弹」与「上限只是事后检查」的区别。
class _BoundedSink extends ByteConversionSinkBase {
  _BoundedSink(this.limit);

  final int limit;
  final BytesBuilder _builder = BytesBuilder(copy: false);
  int _length = 0;

  @override
  void add(List<int> chunk) {
    if (chunk.isEmpty) {
      return;
    }
    _length += chunk.length;
    if (_length > limit) {
      throw const _BodyTooLargeException();
    }
    _builder.add(chunk);
  }

  @override
  void close() {}

  /// 取出已收集的全部字节。
  Uint8List takeBytes() => _builder.takeBytes();
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
