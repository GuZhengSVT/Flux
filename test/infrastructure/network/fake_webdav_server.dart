// 内存 WebDAV 服务器（测试替身，T042）。
//
// 为什么必须自己写一个而不是用 MockClient 逐条脚本化响应：
//   * 条件写（If-Match / ETag 变化 / 412）是**状态机**行为。用固定响应脚本模拟时，
//     「412 之后重读、第二轮成功」这条重试链路只能靠人肉拼出响应顺序，一旦实现改了调用
//     顺序，脚本就跟不上，而失败信息会指向一个与真实原因无关的地方；
//   * 「孤儿快照」与「manifest 未更新」的语义需要在**同一份状态**上判断：快照已存在、
//     指针仍指向旧版本。分离的响应脚本表达不了这个关系。
//
// 因此这里实现一个最小但**真的**状态化服务器：文件表 + ETag + If-Match 判定，行为对齐
// 架构 5.2 要求的能力（强 ETag、条件写、412）。它**不联网**，因此本任务的测试完全离线。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:flux/core/core.dart';

/// 一个内存 WebDAV 服务器。
///
/// 类可以被测试继承（例如「每次 manifest 写入都 412」「读回内容被换掉」这类服务器行为），
/// 因此不用 final：这些行为是**服务器**的属性，让测试去改服务器的行为比让测试去改客户端
/// 的输入更贴近真实。
class FakeWebDavServer {
  /// 构造服务器。
  ///
  /// [supportsIfMatch] 为 false 时模拟「忽略 If-Match 的服务器」（用它验证能力探测能
  /// 识破一台会让多端静默互相覆盖的服务器）。
  FakeWebDavServer({
    this.supportsIfMatch = true,
    this.supportsEtag = true,
    this.username = 'flux',
    this.password = 'secret',
  });

  /// 是否真的执行 If-Match 判定。
  bool supportsIfMatch;

  /// 是否在响应里给出 ETag。
  bool supportsEtag;

  /// 期望的用户名。
  final String username;

  /// 期望的密码。
  final String password;

  /// 路径 → 内容。
  final Map<String, Uint8List> files = <String, Uint8List>{};

  /// 路径 → ETag（随每次成功写变化）。
  final Map<String, String> etags = <String, String>{};

  /// 已创建的目录路径。
  final Set<String> collections = <String>{'/flux-v1'};

  /// 收到的请求记录（方法 + 路径），用于断言「一个字节都没发」这类规则。
  final List<String> requestLog = <String>[];

  /// 故意的网络失败开关（模拟断网）。
  bool offline = false;

  int _etagCounter = 0;
  int _putCount = 0;

  /// 写入一个文件（测试夹具用，不经过 HTTP，因此不改 requestLog）。
  void seedFile(String path, List<int> bytes) {
    files[path] = Uint8List.fromList(bytes);
    etags[path] = _nextEtag();
  }

  /// 当前 manifest（若存在且可解析）。
  SyncManifest? currentManifest({String root = '/flux-v1'}) {
    final Uint8List? bytes = files['$root/manifest.json'];
    if (bytes == null) {
      return null;
    }
    return SyncManifest.decode(utf8.decode(bytes));
  }

  /// 把服务器包成 package:http 的客户端，交给 WebDavClient。
  http.Client asClient() => _FakeWebDavClient(this);

  /// 快照文件名列表（不含 manifest 与目录）。
  List<String> snapshotNames({String root = '/flux-v1'}) => files.keys
      .where((String path) => path.startsWith('$root/snapshot-'))
      .map((String path) => path.split('/').last)
      .toList(growable: false);

  /// 处理一个请求。
  Future<http.StreamedResponse> handle(http.BaseRequest request) async {
    final String path = request.url.path;
    requestLog.add('${request.method} $path');

    if (offline) {
      // 断网：连接层失败（不返回任何 HTTP 状态）。
      throw http.ClientException('offline', request.url);
    }

    if (!_authorized(request)) {
      return _empty(401);
    }

    switch (request.method) {
      case 'PROPFIND':
        return _propfind(path);
      case 'GET':
        return _get(path);
      case 'PUT':
        return _put(path, request);
      case 'DELETE':
        return _delete(path, request);
      case 'MKCOL':
        return _mkcol(path);
      default:
        return _empty(405);
    }
  }

  bool _authorized(http.BaseRequest request) {
    final String? header =
        request.headers['Authorization'] ?? request.headers['authorization'];
    if (header == null || !header.startsWith('Basic ')) {
      return false;
    }
    final String decoded;
    try {
      decoded = utf8.decode(base64Decode(header.substring(6)));
    } on FormatException {
      return false;
    }
    return decoded == '$username:$password';
  }

  Future<http.StreamedResponse> _propfind(String path) async {
    final String normalized = _trimTrailingSlash(path);
    final bool exists =
        files.containsKey(normalized) ||
        collections.contains(normalized) ||
        files.keys.any((String p) => p.startsWith('$normalized/'));
    if (!exists) {
      return _empty(404);
    }
    final List<Map<String, Object?>> entries = <Map<String, Object?>>[];
    if (collections.contains(normalized) ||
        files.keys.any((String p) => p.startsWith('$normalized/'))) {
      entries.add(<String, Object?>{'path': normalized, 'collection': true});
      for (final MapEntry<String, Uint8List> entry in files.entries) {
        if (entry.key.startsWith('$normalized/') &&
            !entry.key.substring(normalized.length + 1).contains('/')) {
          entries.add(<String, Object?>{
            'path': entry.key,
            'collection': false,
            'etag': etags[entry.key],
            'length': entry.value.length,
          });
        }
      }
    } else {
      entries.add(<String, Object?>{
        'path': normalized,
        'collection': false,
        'etag': etags[normalized],
        'length': files[normalized]!.length,
      });
    }
    return _xml(207, entries);
  }

  Future<http.StreamedResponse> _get(String path) async {
    final Uint8List? bytes = files[_trimTrailingSlash(path)];
    if (bytes == null) {
      return _empty(404);
    }
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      200,
      headers: <String, String>{
        'content-type': 'application/json',
        'content-length': '${bytes.length}',
        if (supportsEtag) 'etag': etags[_trimTrailingSlash(path)]!,
      },
    );
  }

  Future<http.StreamedResponse> _put(
    String path,
    http.BaseRequest request,
  ) async {
    _putCount++;
    final String normalized = _trimTrailingSlash(path);
    final String? ifMatch =
        request.headers['If-Match'] ?? request.headers['if-match'];

    if (ifMatch != null && supportsIfMatch) {
      final String? currentEtag = etags[normalized];
      if (ifMatch == '*') {
        // If-Match: * → 只有资源**不存在**时才允许写。
        if (files.containsKey(normalized)) {
          return _empty(412);
        }
      } else if (currentEtag == null || currentEtag != ifMatch) {
        return _empty(412);
      }
    }
    // 不支持 If-Match 的服务器：照写不误（这正是探测要识破的行为）。

    final Uint8List body = await _readRequestBody(request);
    files[normalized] = body;
    etags[normalized] = _nextEtag();
    return http.StreamedResponse(
      const Stream<List<int>>.empty(),
      201,
      headers: <String, String>{if (supportsEtag) 'etag': etags[normalized]!},
    );
  }

  Future<http.StreamedResponse> _delete(
    String path,
    http.BaseRequest request,
  ) async {
    final String normalized = _trimTrailingSlash(path);
    final String? ifMatch =
        request.headers['If-Match'] ?? request.headers['if-match'];
    if (ifMatch != null && supportsIfMatch) {
      final String? currentEtag = etags[normalized];
      if (currentEtag == null || currentEtag != ifMatch) {
        return _empty(412);
      }
    }
    if (files.remove(normalized) == null) {
      return _empty(404);
    }
    etags.remove(normalized);
    return _empty(204);
  }

  Future<http.StreamedResponse> _mkcol(String path) async {
    final String normalized = _trimTrailingSlash(path);
    if (collections.contains(normalized)) {
      return _empty(405);
    }
    collections.add(normalized);
    return _empty(201);
  }

  static Future<Uint8List> _readRequestBody(http.BaseRequest request) async {
    if (request is http.Request) {
      return request.bodyBytes;
    }
    throw StateError('FakeWebDavServer 只支持 http.Request 形式的请求体');
  }

  String _nextEtag() {
    _etagCounter++;
    // 形如 '"e-3"'：带引号（HTTP 规范要求原样回送），且随每次写变化。
    return '"e-$_etagCounter"';
  }

  static String _trimTrailingSlash(String path) =>
      path.length > 1 && path.endsWith('/')
      ? path.substring(0, path.length - 1)
      : path;

  static http.StreamedResponse _empty(int status) => http.StreamedResponse(
    const Stream<List<int>>.empty(),
    status,
    headers: <String, String>{'content-length': '0'},
  );

  static http.StreamedResponse _xml(
    int status,
    List<Map<String, Object?>> entries,
  ) {
    final StringBuffer buffer = StringBuffer();
    buffer.write('<?xml version="1.0" encoding="utf-8"?>');
    buffer.write('<D:multistatus xmlns:D="DAV:">');
    for (final Map<String, Object?> entry in entries) {
      buffer.write('<D:response><D:href>');
      buffer.write(entry['path']);
      buffer.write('</D:href><D:propstat><D:prop>');
      buffer.write('<D:resourcetype>');
      if (entry['collection'] == true) {
        buffer.write('<D:collection/>');
      }
      buffer.write('</D:resourcetype>');
      final Object? etag = entry['etag'];
      if (etag != null) {
        buffer.write('<D:getetag>$etag</D:getetag>');
      }
      final Object? length = entry['length'];
      if (length != null) {
        buffer.write('<D:getcontentlength>$length</D:getcontentlength>');
      }
      buffer
        ..write(
          '<D:getlastmodified>Mon, 22 Sep 2026 04:00:00 GMT</D:getlastmodified>',
        )
        ..write('</D:prop><D:status>HTTP/1.1 200 OK</D:status>')
        ..write('</D:propstat></D:response>');
    }
    buffer.write('</D:multistatus>');
    final List<int> bytes = utf8.encode(buffer.toString());
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      status,
      headers: <String, String>{
        'content-type': 'application/xml; charset=utf-8',
        'content-length': '${bytes.length}',
      },
    );
  }

  /// 已发生的 PUT 次数（判定「降级时一个字节都没写」）。
  int get putCount => _putCount;
}

/// 把 [FakeWebDavServer] 接到 package:http 的客户端接口上。
final class _FakeWebDavClient extends http.BaseClient {
  _FakeWebDavClient(this._server);

  final FakeWebDavServer _server;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _server.handle(request);
}
