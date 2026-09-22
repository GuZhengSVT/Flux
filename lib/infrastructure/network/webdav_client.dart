// WebDAV 客户端（T042；架构 5.2 的条件发布协议、SET-070/071）。
//
// 只做**协议动作**：PROPFIND 列目录/读元数据、GET 读资源、PUT 写资源（可带 If-Match）、
// DELETE、MKCOL。业务决策（三方合并、冲突呈现）不住在这里。
//
// 六条安全与协议约束（逐条都有对应断言）：
//   1) **密码只进认证头**，不进 URL、不进日志、不进错误消息（SET-071；架构第 8 节）。
//      密码由调用方从 Keychain 读出后传入，本层不读 Keychain、不缓存密码。
//   2) **XML 解析禁 DTD/ENTITY**：与 T013/T015 同一条防线（外部实体能读本机文件、发起
//      内网请求），在一个 207 Multi-Status 响应上完全一样成立。
//   3) **响应体有界**：PROPFIND 的 207 体可能是任意大的（恶意或配置错的服务器），
//      声明长度与流式计数两道限制。
//   4) **地址守卫**：WebDAV 端点是**用户显式配置**的（SET-070），因此用
//      [UrlGuardPolicy.configuredSource]——用户把同步目录放在自己内网是正当需求。
//   5) **不强求 TLS**：本项目不全局忽略证书校验（架构第 8 节），https 由配置决定。
//   6) **412 是正常结果**，不是异常：它是条件写的冲突信号，调用方据此重读重试。因此
//      本层把它翻译成 [WebDavStatus.conflict] 而不是抛错。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

import 'package:flux/core/core.dart';

import 'http_client_factory.dart';

/// WebDAV 请求的配置。
final class WebDavConfig {
  /// 构造配置。
  const WebDavConfig({
    this.timeout = const Duration(seconds: 30),
    this.maxResponseBytes = 4 * 1024 * 1024,
    this.maxResourceBytes = 64 * 1024 * 1024,
    this.userAgent = 'Flux/0.2 (+https://github.com/GuZhengSVT/Flux)',
  });

  /// 单次请求超时。
  final Duration timeout;

  /// 元数据类响应（PROPFIND）上限。
  final int maxResponseBytes;

  /// 资源类响应（GET 快照/manifest）上限。
  final int maxResourceBytes;

  /// User-Agent（不含凭据）。
  final String userAgent;
}

/// 一次 WebDAV 响应的结论类别。
enum WebDavStatus {
  /// 成功（GET/PUT/PROPFIND/MKCOL）。
  ok,

  /// 资源不存在（404）。
  notFound,

  /// 条件写失败（412）：调用方应重读重试。
  conflict,

  /// 认证失败（401/403）。
  unauthorized,

  /// 远端拒绝写（405/409/423 等），例如目录只读或被锁。
  writeRejected,

  /// 其它非成功状态。
  failed,
}

/// 一个远端资源条目（PROPFIND 的解析结果）。
final class WebDavResource {
  /// 构造条目。
  const WebDavResource({
    required this.path,
    required this.isCollection,
    this.etag,
    this.lastModified,
    this.contentLength,
  });

  /// 资源路径（自响应 href 解码后的规范形式，用于与本地构造的路径比较）。
  final String path;

  /// 是否为目录。
  final bool isCollection;

  /// ETag（服务器给的原样值，含引号与可能的 W/ 前缀）。
  final String? etag;

  /// Last-Modified 原文。
  final String? lastModified;

  /// 内容长度（服务器给出时）。
  final int? contentLength;

  /// 服务器是否提供了 ETag。
  bool get hasEtag => etag != null && etag!.isNotEmpty;

  /// ETag 是否为**弱** ETag（W/ 前缀）。
  ///
  /// 弱 ETag 不能用于 If-Match 的强比较语义：两台设备可能算出不同内容的同一个弱 ETag，
  /// 于是条件写退化成无条件覆盖。因此探测阶段必须把它判成不支持。
  bool get isWeakEtag => etag != null && etag!.trimLeft().startsWith('W/');
}

/// 一次带状态的 WebDAV 响应。
final class WebDavResponse {
  /// 构造响应。
  const WebDavResponse({
    required this.status,
    required this.httpStatus,
    this.bodyBytes,
    this.etag,
    this.resources = const <WebDavResource>[],
    this.reason,
  });

  /// 结论类别。
  final WebDavStatus status;

  /// HTTP 状态码；连接层失败时为 null。
  final int? httpStatus;

  /// 响应体（GET 时为资源字节）。
  final Uint8List? bodyBytes;

  /// 响应头里的 ETag。
  final String? etag;

  /// PROPFIND 解析出的条目。
  final List<WebDavResource> resources;

  /// 失败原因的结构性标识（不含地址与凭据）。
  final String? reason;

  /// 是否成功。
  bool get isOk => status == WebDavStatus.ok;

  /// 响应体文本（UTF-8）；无体时为 null。
  String? get bodyText {
    final Uint8List? bytes = bodyBytes;
    return bytes == null ? null : utf8.decode(bytes, allowMalformed: true);
  }
}

/// 基于 package:http 的 WebDAV 客户端。
final class WebDavClient {
  /// 构造客户端。
  ///
  /// [client] 与 [config] 可注入（测试用内存服务器替换），生产不传 [client]。
  WebDavClient({http.Client? httpClient, this.config = const WebDavConfig()})
    : _client = httpClient;

  /// 注入的客户端（测试用）。
  final http.Client? _client;

  /// 配置。
  final WebDavConfig config;

  /// PROPFIND：列目录（Depth: 1）或读单个资源的元数据（Depth: 0）。
  Future<WebDavResponse> propfind(
    Uri url, {
    required String username,
    required String password,
    int depth = 1,
  }) async {
    final Result<http.StreamedResponse> sent = await _send(
      'PROPFIND',
      url,
      username: username,
      password: password,
      headers: <String, String>{
        'Depth': '$depth',
        'Content-Type': 'application/xml; charset=utf-8',
      },
      body: _propfindBody,
    );
    if (sent.isErr) {
      return _failure(sent.errorOrNull!);
    }
    final http.StreamedResponse response = sent.unwrap();
    final WebDavStatus status = _classify(response.statusCode);
    if (status != WebDavStatus.ok) {
      // 即使失败也要把流读干净，否则连接无法复用（长跑应用里会积累连接）。
      await _drain(response);
      return WebDavResponse(
        status: status,
        httpStatus: response.statusCode,
        reason: _reasonFor(status),
      );
    }
    final Result<String> body = await _readText(
      response,
      maxBytes: config.maxResponseBytes,
      limitKind: 'webdavPropfind',
    );
    if (body.isErr) {
      return _failure(body.errorOrNull!);
    }
    final Result<List<WebDavResource>> parsed = parseMultiStatus(body.unwrap());
    if (parsed.isErr) {
      return WebDavResponse(
        status: WebDavStatus.failed,
        httpStatus: response.statusCode,
        reason: 'multiStatusParseFailed',
      );
    }
    return WebDavResponse(
      status: WebDavStatus.ok,
      httpStatus: response.statusCode,
      resources: parsed.unwrap(),
    );
  }

  /// GET：读资源字节。
  Future<WebDavResponse> get(
    Uri url, {
    required String username,
    required String password,
  }) async {
    final Result<http.StreamedResponse> sent = await _send(
      'GET',
      url,
      username: username,
      password: password,
    );
    if (sent.isErr) {
      return _failure(sent.errorOrNull!);
    }
    final http.StreamedResponse response = sent.unwrap();
    final WebDavStatus status = _classify(response.statusCode);
    if (status != WebDavStatus.ok) {
      await _drain(response);
      return WebDavResponse(
        status: status,
        httpStatus: response.statusCode,
        etag: response.headers['etag'],
        reason: _reasonFor(status),
      );
    }
    final Result<Uint8List> bytes = await _readBytes(
      response,
      maxBytes: config.maxResourceBytes,
      limitKind: 'webdavGet',
    );
    if (bytes.isErr) {
      return _failure(bytes.errorOrNull!);
    }
    return WebDavResponse(
      status: WebDavStatus.ok,
      httpStatus: response.statusCode,
      bodyBytes: bytes.unwrap(),
      etag: response.headers['etag'],
    );
  }

  /// PUT：写资源；[ifMatch] 非 null 时带上 If-Match（条件写）。
  ///
  /// [ifMatch] 传 '*' 表示「只在资源**不存在**时创建」：首次发布 manifest 用它表达
  /// 「远端还没有当前版本」。这依赖服务器对 * 的实现，因此探测阶段已经验证过条件写能力。
  Future<WebDavResponse> put(
    Uri url, {
    required String username,
    required String password,
    required List<int> bytes,
    String? ifMatch,
  }) async {
    final Result<http.StreamedResponse> sent = await _send(
      'PUT',
      url,
      username: username,
      password: password,
      headers: _withIfMatch(<String, String>{
        'Content-Type': 'application/json; charset=utf-8',
      }, ifMatch),
      bodyBytes: bytes,
    );
    if (sent.isErr) {
      return _failure(sent.errorOrNull!);
    }
    final http.StreamedResponse response = sent.unwrap();
    await _drain(response);
    final WebDavStatus status = _classify(response.statusCode);
    return WebDavResponse(
      status: status,
      httpStatus: response.statusCode,
      // PUT 的响应常带新 ETag；不带时由调用方 GET 回读（探测阶段正是这么判定的）。
      etag: response.headers['etag'],
      reason: status == WebDavStatus.ok ? null : _reasonFor(status),
    );
  }

  /// DELETE：删除资源。
  Future<WebDavResponse> delete(
    Uri url, {
    required String username,
    required String password,
    String? ifMatch,
  }) async {
    final Result<http.StreamedResponse> sent = await _send(
      'DELETE',
      url,
      username: username,
      password: password,
      headers: _withIfMatch(<String, String>{}, ifMatch),
    );
    if (sent.isErr) {
      return _failure(sent.errorOrNull!);
    }
    final http.StreamedResponse response = sent.unwrap();
    await _drain(response);
    final WebDavStatus status = _classify(response.statusCode);
    return WebDavResponse(
      status: status,
      httpStatus: response.statusCode,
      reason: status == WebDavStatus.ok ? null : _reasonFor(status),
    );
  }

  /// MKCOL：建目录。已存在（405）视为成功（幂等：目录该在的地方就在）。
  Future<WebDavResponse> mkcol(
    Uri url, {
    required String username,
    required String password,
  }) async {
    final Result<http.StreamedResponse> sent = await _send(
      'MKCOL',
      url,
      username: username,
      password: password,
    );
    if (sent.isErr) {
      return _failure(sent.errorOrNull!);
    }
    final http.StreamedResponse response = sent.unwrap();
    await _drain(response);
    // 201 创建成功；405 表示已存在——对「保证目录存在」这个意图来说是成功。
    final bool alreadyExists = response.statusCode == 405;
    final WebDavStatus status = alreadyExists
        ? WebDavStatus.ok
        : _classify(response.statusCode);
    return WebDavResponse(
      status: status,
      httpStatus: response.statusCode,
      reason: status == WebDavStatus.ok ? null : _reasonFor(status),
    );
  }

  // -------------------------------------------------------------------------
  // 内部：请求发送与响应读取
  // -------------------------------------------------------------------------

  Future<Result<http.StreamedResponse>> _send(
    String method,
    Uri url, {
    required String username,
    required String password,
    Map<String, String>? headers,
    List<int>? bodyBytes,
    String? body,
  }) async {
    // 守卫只做字面量判断（协议、主机名）。WebDAV 端点是用户显式配置的（SET-070），
    // 指向自己的内网是正当需求——与订阅源同一档策略（configuredSource）。
    final UrlGuardResult guarded = checkUrlGuarded(
      url,
      UrlGuardPolicy.configuredSource,
    );
    if (!guarded.allowed) {
      return Err<http.StreamedResponse>(urlGuardError(url));
    }

    final http.Client? owned = _client == null ? createRawHttpClient() : null;
    final http.Client effective = owned ?? _client!;
    try {
      final http.Request request = http.Request(method, url)
        ..followRedirects = false
        ..headers['User-Agent'] = config.userAgent
        // 密码只在这里出现一次：Basic 认证头。它不进 URL、不进日志、不进错误。
        ..headers['Authorization'] = _basicAuth(username, password);
      if (headers != null) {
        request.headers.addAll(headers);
      }
      if (bodyBytes != null) {
        request.bodyBytes = bodyBytes;
      } else if (body != null) {
        request.body = body;
      }
      final http.StreamedResponse response = await effective
          .send(request)
          .timeout(
            config.timeout,
            onTimeout: () =>
                throw TimeoutException('webdavTimeout', config.timeout),
          );
      return Ok<http.StreamedResponse>(response);
    } on TimeoutException {
      owned?.close();
      return Err<http.StreamedResponse>(
        DeadlineExceededError(limitKind: 'webdav', limit: config.timeout),
      );
    } on Exception catch (error) {
      owned?.close();
      return Err<http.StreamedResponse>(
        NetworkError(
          uri: url.toString(),
          reason: 'WebDAV 请求失败（${error.runtimeType}）',
          cause: error,
        ),
      );
    }
  }

  /// 读干一个响应流（失败路径上也要做，避免连接无法复用）。
  Future<void> _drain(http.StreamedResponse response) async {
    try {
      await response.stream.drain<void>();
    } on Exception {
      // 忽略：这里只是为了释放连接，读失败不影响已经拿到的状态码。
    }
  }

  Future<Result<String>> _readText(
    http.StreamedResponse response, {
    required int maxBytes,
    required String limitKind,
  }) async {
    final Result<Uint8List> bytes = await _readBytes(
      response,
      maxBytes: maxBytes,
      limitKind: limitKind,
    );
    if (bytes.isErr) {
      return Err<String>(bytes.errorOrNull!);
    }
    return Ok<String>(utf8.decode(bytes.unwrap(), allowMalformed: true));
  }

  Future<Result<Uint8List>> _readBytes(
    http.StreamedResponse response, {
    required int maxBytes,
    required String limitKind,
  }) async {
    // 声明长度先拒一次：一个声明了 2 GiB 的 207 体不该被读进内存后再判断。
    final int? declared = response.contentLength;
    if (declared != null && declared > maxBytes) {
      await _drain(response);
      return Err<Uint8List>(
        NetworkError(
          uri: response.request?.url.toString() ?? '',
          reason: '响应体声明长度 $declared 超过上限 $maxBytes',
        ),
      );
    }
    final BytesBuilder builder = BytesBuilder(copy: false);
    int total = 0;
    try {
      await for (final List<int> chunk in response.stream.timeout(
        config.timeout,
        onTimeout: (EventSink<List<int>> sink) =>
            sink.addError(TimeoutException(limitKind, config.timeout)),
      )) {
        total += chunk.length;
        if (total > maxBytes) {
          return Err<Uint8List>(
            NetworkError(
              uri: response.request?.url.toString() ?? '',
              reason: '响应体超过上限 $maxBytes 字节',
            ),
          );
        }
        builder.add(chunk);
      }
    } on TimeoutException {
      return Err<Uint8List>(
        DeadlineExceededError(limitKind: limitKind, limit: config.timeout),
      );
    } on Exception catch (error) {
      return Err<Uint8List>(
        NetworkError(
          uri: response.request?.url.toString() ?? '',
          reason: '读取响应体失败（${error.runtimeType}）',
          cause: error,
        ),
      );
    }
    return Ok<Uint8List>(builder.takeBytes());
  }

  static WebDavResponse _failure(AppError error) => WebDavResponse(
    status: error is AuthError
        ? WebDavStatus.unauthorized
        : WebDavStatus.failed,
    httpStatus: null,
    reason: error.kind,
  );

  /// 构造带可选 If-Match 的头集合。
  ///
  /// 单独一个函数而不是在调用点写条件元素：条件元素换成显式分支之后，「ifMatch 为 null
  /// 时**不带**这个头」与「带了空串」在代码上不再可能混淆——空串的 If-Match 在多数服务器
  /// 上等价于「一定失败」，而少一个头才是「不要求前提条件」。
  static Map<String, String> _withIfMatch(
    Map<String, String> headers,
    String? ifMatch,
  ) {
    if (ifMatch != null) {
      headers['If-Match'] = ifMatch;
    }
    return headers;
  }

  static WebDavStatus _classify(int status) {
    if (status >= 200 && status < 300) {
      return WebDavStatus.ok;
    }
    return switch (status) {
      404 => WebDavStatus.notFound,
      401 || 403 => WebDavStatus.unauthorized,
      412 => WebDavStatus.conflict,
      405 || 409 || 423 || 507 => WebDavStatus.writeRejected,
      _ => WebDavStatus.failed,
    };
  }

  static String? _reasonFor(WebDavStatus status) => switch (status) {
    WebDavStatus.ok => null,
    WebDavStatus.notFound => 'notFound',
    WebDavStatus.conflict => 'preconditionFailed',
    WebDavStatus.unauthorized => 'unauthorized',
    WebDavStatus.writeRejected => 'writeRejected',
    WebDavStatus.failed => 'httpFailure',
  };

  /// Basic 认证头。只产出 base64（值本身不回显、不记日志）。
  static String _basicAuth(String username, String password) =>
      'Basic ${base64Encode(utf8.encode('$username:$password'))}';
}

/// PROPFIND 请求体（请求全部属性；allprop 比逐项列举更宽容，服务器实现差异更小）。
const String _propfindBody =
    '<?xml version="1.0" encoding="utf-8"?>'
    '<d:propfind xmlns:d="DAV:"><d:allprop/></d:propfind>';

/// 解析 207 Multi-Status 响应。
///
/// 两道防线，顺序与 T013/T015 一致（先拒 DTD/ENTITY，再限深度与节点数）：
///   1) **DTD 与实体声明一律拒绝**。外部实体能读本机文件、发起内网请求（XXE），
///      而一个 WebDAV 目录列表没有任何正当理由需要它们；
///   2) 建树之前先用事件流扫一遍结构上限（深度/节点数），避免畸形文档把解析器拖垮。
///
/// 只取需要的属性（resourcetype / getetag / getcontentlength / getlastmodified）与 href：
/// 多取属性会让「这个服务器还返回了什么」成为一条未定义的数据通道，而本层对它们的语义
/// 无任何保证。
Result<List<WebDavResource>> parseMultiStatus(String document) {
  final Result<void> guard = rejectWebDavDoctypeAndEntities(document);
  if (guard.isErr) {
    return Err<List<WebDavResource>>(guard.errorOrNull!);
  }
  final Result<void> structure = scanWebDavEvents(document);
  if (structure.isErr) {
    return Err<List<WebDavResource>>(structure.errorOrNull!);
  }

  final XmlDocument xml;
  try {
    xml = XmlDocument.parse(document);
  } on XmlException catch (error) {
    return Err<List<WebDavResource>>(
      ParseError(
        source: 'webdav.multiStatus',
        detail: 'XML 结构非法（${error.runtimeType}）',
        cause: error,
      ),
    );
  }

  final List<WebDavResource> resources = <WebDavResource>[];
  for (final XmlElement response in findWebDavElements(xml, 'response')) {
    String? href;
    bool isCollection = false;
    String? etag;
    String? lastModified;
    int? contentLength;
    for (final XmlElement element in response.descendantElements) {
      final String name = element.name.local.toLowerCase();
      switch (name) {
        case 'href':
          href ??= element.innerText.trim();
        case 'collection':
          // <d:resourcetype><d:collection/></d:resourcetype>
          isCollection = true;
        case 'getetag':
          final String text = element.innerText.trim();
          etag = text.isEmpty ? null : text;
        case 'getlastmodified':
          final String text = element.innerText.trim();
          lastModified = text.isEmpty ? null : text;
        case 'getcontentlength':
          contentLength = int.tryParse(element.innerText.trim());
        default:
          break;
      }
    }
    if (href == null || href.isEmpty) {
      // 没有 href 的 response 元素无法定位到任何资源，跳过而不是猜一个路径：
      // 猜出来的路径会让「远端有哪一版快照」的列表里出现不存在的名字。
      continue;
    }
    resources.add(
      WebDavResource(
        path: normalizeHrefPath(href),
        isCollection: isCollection,
        etag: etag,
        lastModified: lastModified,
        contentLength: contentLength,
      ),
    );
  }
  return Ok<List<WebDavResource>>(resources);
}

/// 把 href 归一化成可用于比较的路径。
///
/// 服务器给出的是**完整 URL 或绝对路径**（两种情况都常见，且编码方式未必与请求 URL
/// 一致），因此先解码 percent-encoding 再去掉末尾斜杠：比较的是「路径是不是同一个资源」，
/// 编码差异不该让同一个文件看起来像两个。
String normalizeHrefPath(String href) {
  final String trimmed = href.trim();
  String path = trimmed;
  final Uri? uri = Uri.tryParse(trimmed);
  if (uri != null && uri.hasScheme) {
    path = uri.path;
  }
  try {
    path = Uri.decodeComponent(path);
  } on ArgumentError {
    // 非法编码：保留原样（比较会失败，但不会崩）。
  }
  if (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return path;
}

/// 拒绝 DTD 与实体声明（与 feed_parser / opml 同一条防线，独立实现以便各自演进）。
Result<void> rejectWebDavDoctypeAndEntities(String document) {
  final RegExp doctype = RegExp(r'<\s*!\s*DOCTYPE', caseSensitive: false);
  final RegExp entity = RegExp(r'<\s*!\s*ENTITY', caseSensitive: false);
  final RegExpMatch? doctypeMatch = doctype.firstMatch(document);
  final RegExpMatch? entityMatch = entity.firstMatch(document);
  if (doctypeMatch == null && entityMatch == null) {
    return const Ok<void>(null);
  }
  final List<String> parts = <String>[
    if (entityMatch != null) '实体声明（<!ENTITY），可能是实体扩展攻击',
    if (doctypeMatch != null) 'DTD 声明（<!DOCTYPE），外部实体可能读取本机文件',
  ];
  final int offset = <int>[
    if (doctypeMatch != null) doctypeMatch.start,
    if (entityMatch != null) entityMatch.start,
  ].reduce((int a, int b) => a < b ? a : b);
  return Err<void>(
    ParseError(
      source: 'webdav.multiStatus',
      offset: offset,
      detail: '拒绝解析：文档含 ${parts.join('与')}',
    ),
  );
}

/// Multi-Status 的结构上限（深度/节点数）。
///
/// 用常量而不是配置项：一份**目录列表**远超这些值说明对端不是我们以为的那种服务器，
/// 此时放宽上限只会让一次同步把内存吃光。
const int webDavMaxDepth = 64;
const int webDavMaxNodes = 20000;

/// 事件流扫描：深度、节点数、doctype 二次确认。
Result<void> scanWebDavEvents(String document) {
  int depth = 0;
  int nodes = 0;
  try {
    for (final XmlEvent event in parseEvents(document)) {
      if (event is XmlDoctypeEvent) {
        return Err<void>(
          ParseError(
            source: 'webdav.multiStatus',
            detail: '拒绝解析：事件流中出现 doctype',
          ),
        );
      }
      if (event is XmlStartElementEvent) {
        depth++;
        nodes++;
        if (depth > webDavMaxDepth) {
          return Err<void>(
            ParseError(
              source: 'webdav.multiStatus',
              detail: '嵌套深度超过上限 $webDavMaxDepth',
            ),
          );
        }
        if (nodes > webDavMaxNodes) {
          return Err<void>(
            ParseError(
              source: 'webdav.multiStatus',
              detail: '元素数超过上限 $webDavMaxNodes',
            ),
          );
        }
      } else if (event is XmlEndElementEvent) {
        if (depth > 0) {
          depth--;
        }
      }
    }
  } on XmlException {
    // 结构上限类错误由 DOM 阶段给出一致结论；这里只关心 doctype 与上限，
    // 因此解析异常在这里不升级为失败（否则两种入口会对同一份文档给出不同结论）。
    return const Ok<void>(null);
  }
  return const Ok<void>(null);
}

/// 按 local name 找**所有**后代元素（忽略命名空间前缀差异：D:/d:/ns0: 都常见）。
Iterable<XmlElement> findWebDavElements(XmlNode node, String localName) {
  final String lowered = localName.toLowerCase();
  return node.descendantElements.where(
    (XmlElement e) => e.name.local.toLowerCase() == lowered,
  );
}
