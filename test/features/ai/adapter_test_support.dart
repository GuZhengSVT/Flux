// T026 适配器测试的共用工具（不含任何协议断言）。
//
// 只放「把夹具喂给适配器」这类与协议无关的搬运：真正的期望分别写在
// chat_completions_adapter_test.dart 与 responses_adapter_test.dart，两个文件
// **不共用任何期望**（架构 4.3 要求两个协议独立验证）。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 读取一个 AI 夹具文件（原始字节，保留 CRLF）。
String readAiFixture(String name) =>
    File('test/fixtures/ai/$name').readAsStringSync();

/// 把一段 SSE 文本按**任意**位置切块发出。
///
/// 为什么不用「一整块」：真实的 SSE 会在 TCP 分段处被切开，切点通常落在 JSON 中间。
/// 只有按小块发送，才能验证「跨 chunk 的半个行」被正确拼回。
Stream<List<int>> chunkedBytes(
  String body, {
  int chunkSize = 7,
  Duration? gap,
}) async* {
  final List<int> bytes = utf8.encode(body);
  for (int start = 0; start < bytes.length; start += chunkSize) {
    final int end = start + chunkSize > bytes.length
        ? bytes.length
        : start + chunkSize;
    yield bytes.sublist(start, end);
    if (gap != null) {
      await Future<void>.delayed(gap);
    }
  }
}

/// 构造一个返回 SSE 流的 MockClient。
MockClient sseClient(
  String body, {
  int statusCode = 200,
  Map<String, String> headers = const <String, String>{},
  int chunkSize = 7,
  Duration? gap,
  void Function(http.BaseRequest request)? onRequest,
}) => MockClient.streaming((
  http.BaseRequest request,
  http.ByteStream requestBody,
) async {
  onRequest?.call(request);
  return http.StreamedResponse(
    chunkedBytes(body, chunkSize: chunkSize, gap: gap),
    statusCode,
    headers: <String, String>{'content-type': 'text/event-stream', ...headers},
  );
});

/// 构造一个返回固定 JSON/文本体的 MockClient（错误响应）。
MockClient bodyClient(
  String body, {
  int statusCode = 200,
  Map<String, String> headers = const <String, String>{},
  void Function(http.BaseRequest request)? onRequest,
}) => MockClient((http.Request request) async {
  onRequest?.call(request);
  return http.Response(body, statusCode, headers: headers);
});

/// 构造一个**卡住**的流：先发 [body] 然后永不结束（用于停滞超时用例）。
MockClient stalledClient(
  String body, {
  required Duration hold,
  int statusCode = 200,
}) => MockClient.streaming((
  http.BaseRequest request,
  http.ByteStream requestBody,
) async {
  Stream<List<int>> stalled() async* {
    yield utf8.encode(body);
    await Future<void>.delayed(hold);
  }

  return http.StreamedResponse(
    stalled(),
    statusCode,
    headers: <String, String>{'content-type': 'text/event-stream'},
  );
});

/// 收集事件流；失败时抛出（由调用方 expectLater 捕获）。
Future<List<Object?>> collectEvents(Stream<Object?> events) => events.toList();
