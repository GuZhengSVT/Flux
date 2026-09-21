// T031 搜索适配器测试的共用工具（不含任何协议断言）。
//
// 与 adapter_test_support.dart 同一分工：这里只放「把夹具喂给适配器」这类与协议无关的
// 搬运，真正的期望分别写在三个 *_search_adapter_test.dart 里，三个文件**不共用任何期望**
// （架构 4.3 要求三个协议独立验证）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 读取一个搜索夹具文件。
String readSearchFixture(String name) =>
    File('test/fixtures/ai/$name').readAsStringSync();

/// 构造一个返回固定 JSON 体的 MockClient，并记录请求。
///
/// [onRequest] 用于断言请求形状（方法、URL、认证头、查询参数）。
MockClient searchClient(
  String body, {
  int statusCode = 200,
  Map<String, String> headers = const <String, String>{},
  void Function(http.BaseRequest request) onRequest = _noop,
  String? bodyText,
}) => MockClient((http.Request request) async {
  onRequest(request);
  return http.Response(
    bodyText ?? body,
    statusCode,
    headers: <String, String>{'content-type': 'application/json', ...headers},
  );
});

/// 构造一个**记录请求次数**的复合客户端：第 N 次返回第 N 个体。
///
/// 需要一个计数器而不只是「返回固定体」的场景：验证「无凭据绝不发请求」。
MockClient countingSearchClient(
  List<String> bodies, {
  List<int> statusCodes = const <int>[200],
  void Function(http.BaseRequest request) onRequest = _noop,
}) {
  int calls = 0;
  return MockClient((http.Request request) async {
    onRequest(request);
    final int index = calls < bodies.length ? calls : bodies.length - 1;
    final int status = calls < statusCodes.length
        ? statusCodes[calls]
        : statusCodes.last;
    calls++;
    return http.Response(
      bodies[index],
      status,
      headers: <String, String>{'content-type': 'application/json'},
    );
  });
}

/// 一个永不返回的客户端（用于超时用例）。
MockClient hangingSearchClient({Duration hold = const Duration(seconds: 5)}) =>
    MockClient((http.Request request) async {
      await Future<void>.delayed(hold);
      return http.Response('{}', 200);
    });

void _noop(http.BaseRequest request) {}

/// 解析一个请求体为 JSON 对象（POST 协议用）。
Map<String, Object?> requestJson(http.BaseRequest request) =>
    jsonDecode((request as http.Request).body) as Map<String, Object?>;
