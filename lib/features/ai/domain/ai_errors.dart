// AI 错误的**共用映射**（T025）。
//
// 类型本身住在 core/error/app_error.dart：core 的 AppError 是 sealed 类型，子类必须
// 与它同库，否则 sealed 的穷尽匹配能力就失去意义（编译器再也无法保证 switch 覆盖全部
// 错误类别）。本文件只放「协议无关」的判断与翻译函数，因此可以住在 features 层。
//
// 为什么把映射放在这里而不是各适配器里写一遍：两个 OpenAI 协议的**状态码语义**是同一套
// （429 限流、401/403 认证、400 内容拒绝），各写一份必然有一份先被改。适配器只负责把
// 各自响应体里的字段**取出来**（Chat Completions 的 error.type/error.code 与 Responses
// 的 error.code），映射规则共用。
//
// 安全约束：映射只使用结构性字段与状态码，不使用响应体文案做判断或拼进错误消息——
// 响应体可能回显请求内容（架构第 8 节）。
library;

import 'package:flux/core/core.dart';

/// HTTP 状态码到类型化错误的**统一映射**（两个适配器共用，避免各写一套而漂移）。
///
/// 映射口径（架构 4.5）：
///   429                 → [RateLimitError]（可重试，服从 Retry-After）
///   401 / 402 / 403     → [AuthError]（不可重试，配置问题）
///   400 + 内容拒绝信号   → [ContentFilteredError]（不可重试且不得跨服务商规避）
///   其余 4xx/5xx        → [NetworkError]（保留状态码；5xx 可重试）
///
/// [errorType] / [errorCode] 是服务商错误体里的**结构性字段**（不是文案匹配）：
/// 用「消息里含 filter 字样」这类模糊匹配会把无关的 400 误判成内容拒绝，从而
/// **阻止用户重试一次本来能成功的请求**。
AppError mapAiHttpError({
  required String provider,
  required Uri endpoint,
  required int statusCode,
  String? errorType,
  String? errorCode,
  Duration? retryAfter,
  Object? cause,
  StackTrace? stackTrace,
}) {
  final String? detail = describeErrorMarkers(errorType, errorCode);
  if (statusCode == 429) {
    return RateLimitError(
      provider: provider,
      retryAfter: retryAfter,
      detail: detail,
      cause: cause,
      stackTrace: stackTrace,
    );
  }
  if (statusCode == 401 || statusCode == 402 || statusCode == 403) {
    return AuthError(
      provider: provider,
      statusCode: statusCode,
      detail: detail,
      cause: cause,
      stackTrace: stackTrace,
    );
  }
  if (isContentFilterSignal(errorType: errorType, errorCode: errorCode)) {
    return ContentFilteredError(
      provider: provider,
      statusCode: statusCode,
      detail: detail,
      cause: cause,
      stackTrace: stackTrace,
    );
  }
  return NetworkError(
    uri: endpoint.toString(),
    statusCode: statusCode,
    reason: detail,
    cause: cause,
    stackTrace: stackTrace,
  );
}

/// 判断服务商的错误类型/错误码是否表示**内容拒绝**。
///
/// 只认结构化标记（`content_filter`、`content_policy_violation` 等），不做自由
/// 文本匹配。两个协议的字段路径不同，但这套语义标记是同一套，因此判断共用。
bool isContentFilterSignal({String? errorType, String? errorCode}) {
  const Set<String> markers = <String>{
    'content_filter',
    'content_filtered',
    'content_policy_violation',
    'content_policy',
    'safety',
  };
  for (final String? candidate in <String?>[errorType, errorCode]) {
    if (candidate == null) {
      continue;
    }
    if (markers.contains(candidate.trim().toLowerCase())) {
      return true;
    }
  }
  return false;
}

/// 解析 `Retry-After` 头（秒数形式；HTTP 日期形式不猜测，返回 null）。
Duration? parseRetryAfterHeader(String? raw) {
  if (raw == null) {
    return null;
  }
  final int? seconds = int.tryParse(raw.trim());
  if (seconds == null || seconds < 0) {
    return null;
  }
  return Duration(seconds: seconds);
}

/// 把错误的结构性标记拼成一段**可安全写入日志**的说明。
///
/// 只允许 errorType / errorCode 这类协议字段：响应体原文可能回显请求内容
/// （架构第 8 节），因此这里不接受任意文本。
/// 公开（而非私有）是因为 Anthropic 的映射住在 infrastructure/network/ai_http.dart，
/// 两处必须使用同一份格式，否则日志里同一件事会有两种写法。
String? describeErrorMarkers(String? errorType, String? errorCode) {
  final List<String> parts = <String>[
    if (errorType != null && errorType.isNotEmpty) 'type=$errorType',
    if (errorCode != null && errorCode.isNotEmpty) 'code=$errorCode',
  ];
  return parts.isEmpty ? null : parts.join(', ');
}
