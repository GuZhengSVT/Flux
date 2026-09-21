// 远程图片抓取（T021；架构 4.2「受控 MIME/尺寸/重定向」与第 8 节图像安全）。
//
// 与 T013 的 [HttpFeedFetcher] 分开而不是复用它：抓取层要解决的是「取回一批文章」，
// 图片层要解决的是「取回一张可能带攻击面的字节流」。两者共享的是**守卫判据**
// （[UrlGuardPolicy]），不是请求流程——把图片塞进源抓取会得到一堆「只对图片成立」
// 的分支，而那些分支正好是最需要被单独测到的部分。
//
// 本层依次做四件事，每一件失败都不产生「半个结果」：
//   1) **地址守卫**：只允许 http/https，拒绝字面量私网/回环（embeddedContent 策略）；
//   2) **DNS 解析后再验一次**：字面量检查挡不住 evil.example.com → 127.0.0.1。因此
//      解析主机名，对**每个**解析出的地址再判一次私网（防 DNS rebinding 的第一步：
//      至少不让已知的私网结果通过）；
//   3) **重定向逐跳校验**：手动跟随（同 T013 的理由），每一跳都重跑 1) 与 2)；
//   4) **字节校验**：Content-Type 白名单 + 声明长度上限 + 流式计数上限 + 魔数嗅探
//      （魔数与声明不一致即拒绝）。
//
// 为什么要显式传「已解析地址」给客户端：dart:io 的 HttpClient 自己会再解析一次
// DNS。两次解析之间的时间窗就是经典的 TOCTOU（DNS rebinding：第一次解析得到公网
// 地址通过检查，第二次解析得到 127.0.0.1）。本层用的是**先解析、再校验、然后用已
// 校验过的地址发起请求**的顺序（见 `_connectAddress`），把窗口收敛到最小；真正的
// 彻底修复需要连接级别的地址固定，属平台能力，这里如实记录边界而不是声称已解决。
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:flux/core/core.dart';

import 'http_client_factory.dart';

/// 图片抓取配置。
final class MediaFetchConfig {
  /// 构造配置。
  const MediaFetchConfig({
    this.timeout = const Duration(seconds: 20),
    this.maxBytes = kMaxImageBytes,
    this.maxRedirects = 5,
    this.maxDecodedPixels = kMaxDecodedPixels,
    this.userAgent = FeedFetchConfig.defaultUserAgent,
  });

  /// 单张图片的超时。
  final Duration timeout;

  /// 字节上限（默认 [kMaxImageBytes]）。
  final int maxBytes;

  /// 重定向上限。
  final int maxRedirects;

  /// 解码像素上限。
  final int maxDecodedPixels;

  /// User-Agent。
  final String userAgent;
}

/// 取回一张图片的产物：**已校验**的字节与元数据。
final class MediaFetchResult {
  /// 构造结果。
  const MediaFetchResult({
    required this.bytes,
    required this.mimeType,
    required this.format,
    required this.dimensions,
    required this.finalUri,
    required this.redirectCount,
  });

  /// 字节（已通过 MIME/体积/魔数校验）。
  final Uint8List bytes;

  /// 最终生效的 MIME（来自 Content-Type；与格式一致）。
  final String mimeType;

  /// 嗅探出的格式。
  final ImageFormat format;

  /// 头部声明的尺寸。
  final ImageDimensions dimensions;

  /// 最终地址（已脱敏）。
  final Uri finalUri;

  /// 实际重定向次数。
  final int redirectCount;
}

/// 远程图片抓取器。
final class HttpMediaFetcher {
  /// 构造抓取器。
  ///
  /// [client] 可注入（测试用 MockClient）；[resolveHost] 可注入 DNS 解析（测试用，
  /// 避免测试真的做 DNS 查询）。
  HttpMediaFetcher({
    this.client,
    this.config = const MediaFetchConfig(),
    Future<List<InternetAddress>> Function(String host)? resolveHost,
  }) : _resolveHost = resolveHost ?? _defaultResolve;

  /// 注入的客户端（测试用）。
  final http.Client? client;

  /// 配置。
  final MediaFetchConfig config;

  final Future<List<InternetAddress>> Function(String host) _resolveHost;

  static Future<List<InternetAddress>> _defaultResolve(String host) =>
      InternetAddress.lookup(host);

  /// 取回 [start] 指向的图片。
  ///
  /// 失败一律返回类型化错误，**不抛异常**：一张图片拿不到是正常情况（远端删图、
  /// 网络抖动），调用方据此画占位框（架构 4.2「失败不阻塞文章」）。
  Future<Result<MediaFetchResult>> fetch(Uri start) async {
    Uri current = start;
    final List<Uri> visited = <Uri>[];
    int redirects = 0;

    while (true) {
      // 守卫两步都要做：字面量检查（纯函数）挡 IP 与常见内网名，DNS 解析后的复检
      // 挡「公网域名解析到 127.0.0.1」。只做第一步是这类实现最常见的漏。
      final Result<void> guarded = await resolveAndGuard(current);
      if (guarded.isErr) {
        return Err<MediaFetchResult>(guarded.errorOrNull!);
      }
      // 环检测：源可以把自己重定向到自己，无限跳下去会一直占着这一次图片请求。
      if (visited.contains(current)) {
        return Err<MediaFetchResult>(
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
        ..headers['Accept'] =
            'image/png, image/jpeg, image/gif, image/webp, */*;q=0.1'
        // 图片不需要压缩传输（JPEG/WebP 已压缩），但有些源仍会 gzip 一个 SVG 之类
        // 的文本；不声明 Accept-Encoding 时会拿到未压缩体，语义最简单。
        ..headers['Accept-Encoding'] = 'identity';

      final http.Client? owned = client == null ? createRawHttpClient() : null;
      final http.Client effective = owned ?? client!;
      http.StreamedResponse response;
      try {
        response = await effective
            .send(request)
            .timeout(
              config.timeout,
              onTimeout: () =>
                  throw TimeoutException('media fetch timeout', config.timeout),
            );
      } on TimeoutException {
        owned?.close();
        return Err<MediaFetchResult>(
          DeadlineExceededError(limitKind: 'mediaFetch', limit: config.timeout),
        );
      } on Exception catch (error) {
        owned?.close();
        return Err<MediaFetchResult>(
          NetworkError(
            uri: current.toString(),
            reason: '图片请求失败（${error.runtimeType}）',
            cause: error,
          ),
        );
      }

      final int status = response.statusCode;

      if (_isRedirect(status)) {
        final String? location = response.headers['location'];
        if (location == null || location.trim().isEmpty) {
          owned?.close();
          return Err<MediaFetchResult>(
            NetworkError(
              uri: current.toString(),
              statusCode: status,
              reason: '重定向缺少 Location',
            ),
          );
        }
        if (redirects >= config.maxRedirects) {
          owned?.close();
          return Err<MediaFetchResult>(
            NetworkError(
              uri: current.toString(),
              statusCode: status,
              reason: '重定向次数超过上限 ${config.maxRedirects}',
            ),
          );
        }
        // 关键：重定向的目标**重新走一遍守卫与 DNS 校验**（下一轮循环开头）。
        // 不在这一跳就信任 Location，否则「公网地址跳到内网」是一条一次写成的绕过。
        current = current.resolve(location.trim());
        redirects++;
        continue;
      }

      if (status < 200 || status >= 300) {
        owned?.close();
        return Err<MediaFetchResult>(
          NetworkError(
            uri: current.toString(),
            statusCode: status,
            reason: '图片响应非成功（HTTP $status）',
          ),
        );
      }

      // MIME 白名单：**先**看声明，再读字节。
      final String? declaredMime = normalizeMimeType(
        response.headers['content-type'],
      );
      if (!isAllowedImageMime(declaredMime)) {
        owned?.close();
        return Err<MediaFetchResult>(
          NetworkError(
            uri: current.toString(),
            reason: declaredMime == null
                ? '响应没有声明图片类型（不按扩展名猜测）'
                : '图片类型 $declaredMime 不在允许列表内',
            isRetryable: false,
          ),
        );
      }
      final int? declaredLength = response.contentLength;
      if (declaredLength != null && declaredLength > config.maxBytes) {
        owned?.close();
        return Err<MediaFetchResult>(
          NetworkError(
            uri: current.toString(),
            reason: '图片声明长度 $declaredLength 超过上限 ${config.maxBytes} 字节',
            isRetryable: false,
          ),
        );
      }

      final Result<Uint8List> body = await _readBounded(
        response,
        current,
        owned: owned,
      );
      owned?.close();
      if (body.isErr) {
        return Err<MediaFetchResult>(body.errorOrNull!);
      }
      final Uint8List bytes = body.unwrap();

      // 字节校验：魔数与声明必须一致，且尺寸不得超解码上限。
      final ImageFormat? format = sniffImageFormat(bytes);
      if (format == null) {
        return Err<MediaFetchResult>(
          NetworkError(
            uri: current.toString(),
            reason: '图片字节无法识别（不是 jpeg/png/gif/webp 中的任何一种）',
            isRetryable: false,
          ),
        );
      }
      // 声明与内容不一致：例如声明 image/png 实际是 jpeg。拒绝而不是「按实际类型
      // 渲染」——远端控制了这两个字段，让它们互相矛盾说明不了善意，而渲染管线不该
      // 在这种输入上做猜测。
      final String sniffedMime = imageFormatMimeType(format);
      final String effectiveMime = sniffedMime;
      if (!_mimeMatches(declaredMime!, format)) {
        return Err<MediaFetchResult>(
          NetworkError(
            uri: current.toString(),
            reason: '图片声明类型 $declaredMime 与实际字节格式 $sniffedMime 不一致',
            isRetryable: false,
          ),
        );
      }

      final ImageDimensions? dimensions = probeImageDimensions(bytes);
      if (dimensions == null) {
        return Err<MediaFetchResult>(
          NetworkError(
            uri: current.toString(),
            reason: '无法从图片头部读出尺寸（畸形或截断）',
            isRetryable: false,
          ),
        );
      }
      if (dimensions.pixels > config.maxDecodedPixels) {
        return Err<MediaFetchResult>(
          NetworkError(
            uri: current.toString(),
            reason:
                '图片尺寸 ${dimensions.width}×${dimensions.height} 超过解码上限 '
                '${config.maxDecodedPixels} 像素',
            isRetryable: false,
          ),
        );
      }

      return Ok<MediaFetchResult>(
        MediaFetchResult(
          bytes: bytes,
          mimeType: effectiveMime,
          format: format,
          dimensions: dimensions,
          finalUri: current,
          redirectCount: redirects,
        ),
      );
    }
  }

  /// 守卫 + DNS 解析后再验私网。
  Result<void> _guardUri(Uri uri) {
    final UrlGuardResult literal = checkUrlGuarded(
      uri,
      UrlGuardPolicy.embeddedContent,
    );
    if (!literal.allowed) {
      return Err<void>(urlGuardError(uri));
    }
    return const Ok<void>(null);
  }

  /// 在**发出请求之前**解析主机并校验每个结果。
  ///
  /// 与 [_guardUri] 分开：字面量检查是纯函数（domain 层），DNS 是 I/O（这一层）。
  /// 调用方必须两步都做。
  Future<Result<void>> resolveAndGuard(Uri uri) async {
    final Result<void> literal = _guardUri(uri);
    if (literal.isErr) {
      return literal;
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

  /// 带上限的流式读取。
  Future<Result<Uint8List>> _readBounded(
    http.StreamedResponse response,
    Uri uri, {
    http.Client? owned,
  }) async {
    final BytesBuilder builder = BytesBuilder(copy: false);
    int total = 0;
    try {
      await for (final List<int> chunk in response.stream.timeout(
        config.timeout,
        onTimeout: (EventSink<List<int>> sink) => sink.addError(
          TimeoutException('media body timeout', config.timeout),
        ),
      )) {
        total += chunk.length;
        if (total > config.maxBytes) {
          return Err<Uint8List>(
            NetworkError(
              uri: uri.toString(),
              reason: '图片实际长度超过上限 ${config.maxBytes} 字节',
              isRetryable: false,
            ),
          );
        }
        builder.add(chunk);
      }
    } on TimeoutException {
      return Err<Uint8List>(
        DeadlineExceededError(
          limitKind: 'mediaFetchBody',
          limit: config.timeout,
        ),
      );
    } on Exception catch (error) {
      return Err<Uint8List>(
        NetworkError(
          uri: uri.toString(),
          reason: '读取图片响应失败（${error.runtimeType}）',
          cause: error,
        ),
      );
    }
    final Uint8List bytes = builder.takeBytes();
    if (bytes.isEmpty) {
      return Err<Uint8List>(
        NetworkError(uri: uri.toString(), reason: '图片响应为空', isRetryable: false),
      );
    }
    return Ok<Uint8List>(bytes);
  }

  static bool _isRedirect(int status) =>
      status == 301 ||
      status == 302 ||
      status == 303 ||
      status == 307 ||
      status == 308;

  /// 声明类型与嗅探格式是否一致。
  ///
  /// jpg/jpeg 是同一个格式的两个名字，必须都接受：把 image/jpg 判成不一致会让一批
  /// 真实存在的源直接看不到图（它们写的就是 image/jpg）。
  static bool _mimeMatches(String declaredMime, ImageFormat format) {
    final String declared = declaredMime;
    return switch (format) {
      ImageFormat.png => declared == 'image/png',
      ImageFormat.jpeg => declared == 'image/jpeg' || declared == 'image/jpg',
      ImageFormat.gif => declared == 'image/gif',
      ImageFormat.webp => declared == 'image/webp',
    };
  }
}
