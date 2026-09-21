// 订阅抓取端口（T013；架构 2.2「依赖接口只设置在需要替换/测试的边界：FeedFetcher…」）。
//
// 为什么这些类型放在 core 而不是 infrastructure/network：
//   取字节的**接口**与其入参/出参是纯数据，不依赖 http 或任何平台能力；而消费方是
//   features/feeds 的刷新流程，它不得 import infrastructure。若把端口留在
//   infrastructure，要么刷新流程违反分层，要么就得把同样的形状在两侧各写一份。
//   放在 core 之后，infrastructure 实现它、features 消费它，双方都只依赖 core。
//
// 本文件不含任何 I/O 实现，也**不**依赖 Flutter：HttpFeedFetcher 等实现住在
// lib/infrastructure/network。
library;

import '../result.dart';

/// 抓取配置（默认值即 SET-028 的文档口径：并发 4 / 单源超时 30 秒）。
class FeedFetchConfig {
  /// 构造配置。
  const FeedFetchConfig({
    this.timeout = const Duration(seconds: 30),
    this.maxConcurrency = 4,
    this.maxResponseBytes = 10 * 1024 * 1024,
    this.maxRedirects = 5,
    this.userAgent = defaultUserAgent,
  }) : assert(maxConcurrency >= 1, '并发上限至少为 1'),
       assert(maxRedirects >= 0, '重定向上限不能为负');

  /// 默认 User-Agent（项目标识 + 主页，不含凭据）。
  static const String defaultUserAgent =
      'Flux/0.2 (+https://github.com/GuZhengSVT/Flux)';

  /// 单源超时（SET-028：默认 30 秒，范围 10–120）。
  final Duration timeout;

  /// 并发上限（SET-028：默认 4，范围 1–8）。
  final int maxConcurrency;

  /// 响应体字节上限（未压缩与解压后各自适用）。
  final int maxResponseBytes;

  /// 重定向次数上限。
  final int maxRedirects;

  /// User-Agent。
  final String userAgent;
}

/// 条件请求缓存（来自 feeds 表的 ETag / Last-Modified 列）。
class FeedCacheValidator {
  /// 构造条件请求头来源。
  const FeedCacheValidator({this.etag, this.lastModified});

  /// ETag（原样回送，含引号）。
  final String? etag;

  /// Last-Modified（原样回送）。
  final String? lastModified;

  /// 是否没有任何可用的条件（此时不发送条件请求头）。
  bool get isEmpty =>
      (etag == null || etag!.isEmpty) &&
      (lastModified == null || lastModified!.isEmpty);
}

/// 抓取结果类别。
enum FeedFetchStatus {
  /// 取到内容。
  ok,

  /// 条件请求命中 304：源未修改，**不更新任何文章**。
  notModified,
}

/// 一次抓取的产物。
class FeedFetchResult {
  /// 构造结果。
  const FeedFetchResult({
    required this.status,
    required this.requestedUri,
    required this.finalUri,
    this.body,
    this.etag,
    this.lastModified,
    this.contentType,
    this.redirectCount = 0,
    this.encodedBytes = 0,
    this.decodedBytes = 0,
  });

  /// 结果类别。
  final FeedFetchStatus status;

  /// 最初请求的地址（已脱敏）。
  final String requestedUri;

  /// 最终地址（跟随重定向之后；已脱敏）。
  final String finalUri;

  /// 响应体文本；304 时为 null。
  final String? body;

  /// 新的 ETag；未提供时为 null（此时**不覆盖**已有值）。
  final String? etag;

  /// 新的 Last-Modified；未提供时为 null。
  final String? lastModified;

  /// Content-Type（原样保留）。
  final String? contentType;

  /// 实际发生的重定向次数。
  final int redirectCount;

  /// 解压前字节数（诊断用）。
  final int encodedBytes;

  /// 解压后字节数（诊断用）。
  final int decodedBytes;

  /// 是否命中 304。
  bool get isNotModified => status == FeedFetchStatus.notModified;
}

/// 订阅抓取端口。
///
/// 实现约定（由实现方与测试共同保证）：
///   - 遵守 [FeedFetchConfig] 的超时、并发、体积与重定向上限；
///   - 命中 304 时返回 [FeedFetchStatus.notModified]，而不是错误，也不是空内容；
///   - 失败返回类型化错误（[NetworkError] / [DeadlineExceededError]），**不返回部分内容**；
///   - 失败时不清空调用方已有的缓存校验值。
abstract interface class FeedFetcher {
  /// 抓取一个源。
  Future<Result<FeedFetchResult>> fetch(
    Uri uri, {
    FeedCacheValidator? validator,
  });
}
