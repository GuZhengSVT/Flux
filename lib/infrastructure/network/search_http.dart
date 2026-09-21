// 搜索适配器的共用件（T031）。
//
// 与 ai_http.dart 同一个理由，放在 infrastructure/network：它们全部是**传输层细节**
// （有界读体、JSON 取值、错误体解析），features 不得 import HTTP 细节（架构 2.2 的
// 依赖方向守卫会拦），而三个搜索适配器共用它们，因此必须比适配器更下层。
//
// 本文件**不含**任何协议判断（哪个字段对应哪条结果）——那是各自适配器的职责。
// 这里只有「三家都一样」的部分：有界读体、JSON 对象取值、字段容错。
//
// 安全约束：本文件不接收也不记录 API Key（Key 只在适配器里进各自的认证头）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:flux/core/core.dart';

/// 搜索响应体上限。
///
/// 搜索结果体是**不可信输入**：一个配置错的端点可能返回几百 MB 的 HTML 错误页或
/// 一整个镜像首页。搜索的响应体（含片段）正常不会超过 2 MiB（10 条 × 2000 字符
/// 片段远小于此），因此 4 MiB 已是宽松上限。
const int defaultSearchMaxResponseBytes = 4 * 1024 * 1024;

/// 读取一个响应体并解析为 JSON 对象。
///
/// 所有失败都返回 [Result] 而不是抛异常：调用点总要分支处理（报 ParseError 让用户
/// 看到「这个端点返回的不是搜索 JSON」，比一个未捕获异常更有用）。
///
/// [provider] 只用于错误来源标识，不含地址与凭据。
Future<Result<Map<String, Object?>>> readSearchJsonBody(
  http.StreamedResponse response, {
  required String provider,
  required Duration timeout,
  int maxBytes = defaultSearchMaxResponseBytes,
}) async {
  // 已经拿到的响应头里就声明了超限：直接拒绝，不进读体循环。
  final int? declared = response.contentLength;
  if (declared != null && declared > maxBytes) {
    return Err<Map<String, Object?>>(
      ParseError(
        source: 'search:$provider',
        detail: '响应体声明长度 $declared 超过上限 $maxBytes',
      ),
    );
  }

  final List<int> bytes;
  try {
    final BytesBuilder builder = BytesBuilder(copy: false);
    int total = 0;
    await for (final List<int> chunk in response.stream.timeout(
      timeout,
      onTimeout: (EventSink<List<int>> sink) =>
          sink.addError(TimeoutException('searchBody', timeout)),
    )) {
      total += chunk.length;
      if (total > maxBytes) {
        return Err<Map<String, Object?>>(
          ParseError(
            source: 'search:$provider',
            detail: '响应体超过上限 $maxBytes 字节',
          ),
        );
      }
      builder.add(chunk);
    }
    bytes = builder.takeBytes();
  } on TimeoutException {
    return Err<Map<String, Object?>>(
      DeadlineExceededError(limitKind: 'searchBody', limit: timeout),
    );
  } on Exception catch (error) {
    return Err<Map<String, Object?>>(
      NetworkError(
        uri: provider,
        reason: '读取搜索响应体失败（${error.runtimeType}）',
        cause: error,
      ),
    );
  }

  if (bytes.isEmpty) {
    return Err<Map<String, Object?>>(
      ParseError(source: 'search:$provider', detail: '响应体为空'),
    );
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(decodeSearchText(bytes));
  } on FormatException {
    return Err<Map<String, Object?>>(
      ParseError(source: 'search:$provider', detail: '响应体不是合法 JSON'),
    );
  }
  if (decoded is! Map<String, Object?>) {
    return Err<Map<String, Object?>>(
      ParseError(source: 'search:$provider', detail: '响应体不是 JSON 对象'),
    );
  }
  return Ok<Map<String, Object?>>(decoded);
}

/// 把响应字节解码为文本（UTF-8，带替换字符容忍）。
///
/// 搜索响应**没有** gzip 自动解压问题（我们这一层不解压：dart:io 的默认客户端会
/// 自动解压并保留 content-encoding 头，而这里不做第二次解压，因此不需要 T013 那套
/// 有界解压管线），因此只需处理编码。
String decodeSearchText(List<int> bytes) =>
    utf8.decode(bytes, allowMalformed: true);

/// 读取一个字符串字段；类型不符或为空串时返回 null（字段容错）。
String? searchString(Object? value) {
  if (value is String) {
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  return null;
}

/// 读取一个数值字段（协议有时用 double 表示整数）。
double? searchNumber(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return null;
}

/// 读取一个整数字段。
int? searchInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return null;
}

/// 读取一个对象数组字段；不是数组时返回空列表（字段容错）。
List<Map<String, Object?>> searchObjectList(Object? value) {
  if (value is! List<Object?>) {
    return const <Map<String, Object?>>[];
  }
  return value.whereType<Map<String, Object?>>().toList(growable: false);
}

/// 解析一个绝对时间字段。
///
/// 只接受可解析为绝对时刻的写法（ISO-8601 与 RFC-1123 两种协议里实际出现的形态）。
/// **相对时间**（Brave 的 "3 days ago"）不在这里换算：换算需要抓取时刻作为基准，
/// 而基准不是协议事实，猜出来的日期会被下游当作真实发布时间。
DateTime? searchAbsoluteTime(Object? value) {
  final String? raw = searchString(value);
  if (raw == null) {
    return null;
  }
  final DateTime? parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    return null;
  }
  return parsed.toUtc();
}

/// 解析 Retry-After 头（秒数形式；HTTP 日期形式不猜测，返回 null）。
Duration? searchRetryAfter(String? raw) {
  if (raw == null) {
    return null;
  }
  final int? seconds = int.tryParse(raw.trim());
  if (seconds == null || seconds < 0) {
    return null;
  }
  return Duration(seconds: seconds);
}
