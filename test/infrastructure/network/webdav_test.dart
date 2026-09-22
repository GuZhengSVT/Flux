// T042：WebDAV 能力探测、不可变快照传输与条件写冲突（架构 5.2、手册 6.3「同步」节）。
//
// 全部用例用内存服务器（test/infrastructure/network/fake_webdav_server.dart），**不联网**：
// 412 冲突、断网、忽略 If-Match 的服务器、读回哈希不一致这些分支在真实服务上既难构造
// 也不可复现。按手册 7.3，真实 WebDAV 调用在本轮记为 NOT_RUN（无凭据）。
//
// 七组：能力探测、多状态解析与 XML 防护、请求往返、快照发布协议、条件写冲突与重试上限、
// 孤儿快照、manifest 编解码与协议版本。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:flux/core/core.dart';
import 'package:flux/infrastructure/network/webdav_client.dart';
import 'package:flux/infrastructure/network/webdav_snapshot_publisher.dart';

import 'fake_webdav_server.dart';

const String _root = '/flux-v1';
final DateTime _epoch = DateTime.utc(2026, 9, 22);
final Uri _manifestUrl = Uri.parse(
  'https://dav.example.com/flux-v1/manifest.json',
);

Uri _snapshotUrl(String name) =>
    Uri.parse('https://dav.example.com/flux-v1/$name');

/// 拼一份 207 Multi-Status（用相邻字符串而不是三引号，避免正文里出现容易被误读的缩进）。
String _multiStatus(List<String> responses) =>
    '<?xml version="1.0" encoding="utf-8"?>'
    '<D:multistatus xmlns:D="DAV:">'
    '${responses.join()}'
    '</D:multistatus>';

void main() {
  group('能力探测（架构 5.2「须验证强 ETag/If-Match」）', () {
    test('四项事实齐备才判定支持条件写', () {
      expect(
        evaluateConditionalWriteProbe(
          const WebDavProbeFacts(
            probePutOk: true,
            firstEtag: '"a"',
            conditionalPutOk: true,
            secondEtag: '"b"',
            staleIfMatchRejected: true,
          ),
        ).capability,
        WebDavWriteCapability.conditionalWrite,
      );
    });

    test('PUT 不成功 → 降级（先修配置）', () {
      final WebDavProbeResult result = evaluateConditionalWriteProbe(
        const WebDavProbeFacts(
          probePutOk: false,
          firstEtag: '"a"',
          conditionalPutOk: false,
          secondEtag: null,
          staleIfMatchRejected: false,
        ),
      );
      expect(result.capability, WebDavWriteCapability.readOnlyPull);
      expect(result.reason, 'probePutFailed');
      expect(result.allowsConditionalWrite, isFalse);
    });

    test('服务器不给 ETag → 降级（条件写在协议上无从表达）', () {
      final WebDavProbeResult result = evaluateConditionalWriteProbe(
        const WebDavProbeFacts(
          probePutOk: true,
          firstEtag: null,
          conditionalPutOk: true,
          secondEtag: null,
          staleIfMatchRejected: false,
        ),
      );
      expect(result.capability, WebDavWriteCapability.readOnlyPull);
      expect(result.reason, 'noEtag');
    });

    test('带 If-Match 的写入被拒 → 降级', () {
      final WebDavProbeResult result = evaluateConditionalWriteProbe(
        const WebDavProbeFacts(
          probePutOk: true,
          firstEtag: '"a"',
          conditionalPutOk: false,
          secondEtag: '"b"',
          staleIfMatchRejected: true,
        ),
      );
      expect(result.capability, WebDavWriteCapability.readOnlyPull);
      expect(result.reason, 'ifMatchRejected');
    });

    test('写入后 ETag 不变 → 降级（固定/弱 ETag 会让条件写变成无条件覆盖）', () {
      final WebDavProbeResult result = evaluateConditionalWriteProbe(
        const WebDavProbeFacts(
          probePutOk: true,
          firstEtag: '"a"',
          conditionalPutOk: true,
          secondEtag: '"a"',
          staleIfMatchRejected: true,
        ),
      );
      expect(result.capability, WebDavWriteCapability.readOnlyPull);
      expect(result.reason, 'etagNotContentBased');
    });

    test('**过期 ETag 未被拒绝** → 降级（唯一能证明服务器真的执行条件判定的实验）', () {
      final WebDavProbeResult result = evaluateConditionalWriteProbe(
        const WebDavProbeFacts(
          probePutOk: true,
          firstEtag: '"a"',
          conditionalPutOk: true,
          secondEtag: '"b"',
          staleIfMatchRejected: false,
        ),
      );
      expect(result.capability, WebDavWriteCapability.readOnlyPull);
      expect(result.reason, 'ifMatchNotEnforced');
    });

    test('弱 ETag 被识别出来（W/ 前缀不能用于强比较）', () {
      const WebDavResource weak = WebDavResource(
        path: '/a',
        isCollection: false,
        etag: 'W/"weak"',
      );
      const WebDavResource strong = WebDavResource(
        path: '/a',
        isCollection: false,
        etag: '"strong"',
      );
      expect(weak.isWeakEtag, isTrue);
      expect(strong.isWeakEtag, isFalse);
      expect(weak.hasEtag, isTrue);
    });
  });

  group('Multi-Status 解析与 XML 防护（与 T013/T015 同一条防线）', () {
    test('解析出目录与文件的 resourcetype/etag/长度/时间', () {
      final String body = _multiStatus(<String>[
        '<D:response><D:href>/flux-v1/</D:href><D:propstat><D:prop>'
            '<D:resourcetype><D:collection/></D:resourcetype>'
            '</D:prop></D:propstat></D:response>',
        '<D:response><D:href>/flux-v1/snapshot-abc.json</D:href>'
            '<D:propstat><D:prop><D:resourcetype/>'
            '<D:getetag>"e-7"</D:getetag>'
            '<D:getcontentlength>42</D:getcontentlength>'
            '<D:getlastmodified>Mon, 22 Sep 2026 04:00:00 GMT</D:getlastmodified>'
            '</D:prop></D:propstat></D:response>',
      ]);
      final List<WebDavResource> resources = parseMultiStatus(body).unwrap();
      expect(resources.length, 2);
      expect(resources.first.isCollection, isTrue);
      final WebDavResource file = resources.last;
      expect(file.path, '/flux-v1/snapshot-abc.json');
      expect(file.etag, '"e-7"');
      expect(file.contentLength, 42);
      expect(file.lastModified, 'Mon, 22 Sep 2026 04:00:00 GMT');
    });

    test('命名空间前缀不同也认得出来（d:/D:/ns0:）', () {
      const String body =
          '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:">'
          '<d:response><d:href>/x/a.json</d:href><d:propstat><d:prop>'
          '<d:getetag>"e"</d:getetag>'
          '</d:prop></d:propstat></d:response></d:multistatus>';
      expect(parseMultiStatus(body).unwrap().single.path, '/x/a.json');
    });

    test('**DTD 声明一律拒绝**（外部实体能读本机文件）', () {
      const String body =
          '<?xml version="1.0"?>'
          '<!DOCTYPE multistatus [<!ENTITY xxe SYSTEM "file:///etc/passwd">]>'
          '<D:multistatus xmlns:D="DAV:"/>';
      final Result<List<WebDavResource>> result = parseMultiStatus(body);
      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<ParseError>());
      expect(
        result.errorOrNull!.message,
        isNot(contains('/etc/passwd')),
        reason: '错误消息不得回显实体内容',
      );
    });

    test('实体声明（大小写与空白变形）都被拒绝', () {
      for (final String body in <String>[
        '<!doctype x [<!entity a "b">]><x/>',
        '<! DOCTYPE x><x/>',
        '<!\tENTITY a "b"><x/>',
      ]) {
        expect(parseMultiStatus(body).isErr, isTrue, reason: '必须拒绝：$body');
      }
    });

    test('结构畸形 → ParseError（不抛异常、不回显原文）', () {
      final Result<List<WebDavResource>> result = parseMultiStatus('<a><b>');
      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<ParseError>());
    });

    test('嵌套过深被事件流挡下（超过上限）', () {
      final String deep = '<a>${'<b>' * (webDavMaxDepth + 5)}</a>';
      expect(parseMultiStatus(deep).isErr, isTrue);
    });

    test('href 归一化：完整 URL、percent 编码与末尾斜杠都归到同一路径', () {
      expect(
        normalizeHrefPath('https://dav.example.com/flux-v1/a.json'),
        '/flux-v1/a.json',
      );
      expect(normalizeHrefPath('/flux-v1/a%20b.json'), '/flux-v1/a b.json');
      expect(normalizeHrefPath('/flux-v1/'), '/flux-v1');
    });

    test('没有 href 的 response 被跳过（不猜一个路径出来）', () {
      const String body =
          '<D:multistatus xmlns:D="DAV:"><D:response>'
          '<D:propstat><D:prop><D:getetag>"e"</D:getetag>'
          '</D:prop></D:propstat></D:response></D:multistatus>';
      expect(parseMultiStatus(body).unwrap(), isEmpty);
    });
  });

  group('PROPFIND / GET / PUT / DELETE / MKCOL 的真实往返（内存服务器）', () {
    late FakeWebDavServer server;
    late WebDavClient client;

    setUp(() {
      server = FakeWebDavServer();
      client = WebDavClient(httpClient: server.asClient());
    });

    test('MKCOL 建目录；重复建视为成功（幂等）', () async {
      final Uri url = Uri.parse('https://dav.example.com/flux-v1/sub');
      final WebDavResponse first = await client.mkcol(
        url,
        username: 'flux',
        password: 'secret',
      );
      expect(first.isOk, isTrue);
      expect(first.httpStatus, 201);

      final WebDavResponse second = await client.mkcol(
        url,
        username: 'flux',
        password: 'secret',
      );
      expect(second.isOk, isTrue, reason: '目录该在的地方就在');
      expect(second.httpStatus, 405);
    });

    test('PUT 后 GET 读回同样的字节与 ETag', () async {
      final List<int> payload = utf8.encode('{"hello":"世界"}');
      final Uri url = Uri.parse('https://dav.example.com/flux-v1/a.json');
      final WebDavResponse put = await client.put(
        url,
        username: 'flux',
        password: 'secret',
        bytes: payload,
      );
      expect(put.isOk, isTrue);
      expect(put.etag, isNotNull);

      final WebDavResponse got = await client.get(
        url,
        username: 'flux',
        password: 'secret',
      );
      expect(got.isOk, isTrue);
      expect(got.bodyBytes, payload);
      expect(got.bodyText, '{"hello":"世界"}');
      expect(got.etag, put.etag);
    });

    test('PROPFIND（Depth: 1）列出目录、快照与 manifest', () async {
      server.seedFile('$_root/snapshot-a.json', utf8.encode('a'));
      server.seedFile('$_root/manifest.json', utf8.encode('{}'));
      final WebDavResponse response = await client.propfind(
        Uri.parse('https://dav.example.com/flux-v1/'),
        username: 'flux',
        password: 'secret',
      );
      expect(response.isOk, isTrue);
      expect(response.httpStatus, 207);
      final List<String> paths = response.resources
          .map((WebDavResource r) => r.path)
          .toList();
      expect(paths, contains('$_root/snapshot-a.json'));
      expect(paths, contains('$_root/manifest.json'));
      expect(paths, contains(_root));
      final WebDavResource collection = response.resources.firstWhere(
        (WebDavResource r) => r.path == _root,
      );
      expect(collection.isCollection, isTrue);
    });

    test('PROPFIND 单个资源的元数据（Depth: 0）带 ETag', () async {
      server.seedFile('$_root/manifest.json', utf8.encode('{}'));
      final WebDavResponse response = await client.propfind(
        _manifestUrl,
        username: 'flux',
        password: 'secret',
        depth: 0,
      );
      expect(response.isOk, isTrue);
      expect(response.resources.single.path, '$_root/manifest.json');
      expect(response.resources.single.etag, isNotNull);
    });

    test('DELETE 删除资源；删不存在的返回 notFound', () async {
      server.seedFile('$_root/gone.json', utf8.encode('x'));
      final Uri url = Uri.parse('https://dav.example.com/flux-v1/gone.json');
      final WebDavResponse deleted = await client.delete(
        url,
        username: 'flux',
        password: 'secret',
      );
      expect(deleted.isOk, isTrue);
      expect(server.files.containsKey('$_root/gone.json'), isFalse);

      final WebDavResponse again = await client.delete(
        url,
        username: 'flux',
        password: 'secret',
      );
      expect(again.status, WebDavStatus.notFound);
    });

    test('认证失败（401）识别为 unauthorized，且响应里不含密码', () async {
      final WebDavResponse response = await client.get(
        _manifestUrl,
        username: 'flux',
        password: 'wrong',
      );
      expect(response.status, WebDavStatus.unauthorized);
      expect(response.httpStatus, 401);
      expect(response.reason, 'unauthorized');
      expect(response.reason, isNot(contains('wrong')));
    });

    test('密码只出现在认证头里（不进 URL、不进请求日志）', () async {
      await client.get(_manifestUrl, username: 'flux', password: 'secret');
      for (final String entry in server.requestLog) {
        expect(entry, isNot(contains('secret')));
        expect(entry, isNot(contains('flux:')));
      }
      expect(server.requestLog.single, 'GET $_root/manifest.json');
    });

    test('断网（连接层失败）变成类型化网络错误，不抛异常', () async {
      server.offline = true;
      final WebDavResponse response = await client.get(
        _manifestUrl,
        username: 'flux',
        password: 'secret',
      );
      expect(response.status, WebDavStatus.failed);
      expect(response.httpStatus, isNull);
      expect(response.reason, 'network');
    });

    test('非 http/https 地址被守卫拒绝（一次请求都不发）', () async {
      final WebDavResponse response = await client.get(
        Uri.parse('ftp://dav.example.com/flux-v1/a.json'),
        username: 'flux',
        password: 'secret',
      );
      expect(response.status, WebDavStatus.failed);
      expect(server.requestLog, isEmpty, reason: '被拒绝的地址不该产生任何请求');
    });

    test('响应体超过上限被拒（声明长度先挡一次）', () async {
      final WebDavClient tiny = WebDavClient(
        httpClient: server.asClient(),
        config: const WebDavConfig(maxResourceBytes: 8),
      );
      server.seedFile('$_root/big.json', List<int>.filled(64, 0x41));
      final WebDavResponse response = await tiny.get(
        Uri.parse('https://dav.example.com/flux-v1/big.json'),
        username: 'flux',
        password: 'secret',
      );
      expect(response.status, WebDavStatus.failed);
    });
  });

  group('不可变快照与共享 manifest（架构 5.2 的发布协议）', () {
    late FakeWebDavServer server;
    late SnapshotPublisher publisher;

    setUp(() {
      server = FakeWebDavServer();
      publisher = SnapshotPublisher(
        client: WebDavClient(httpClient: server.asClient()),
        username: 'flux',
        password: 'secret',
      );
    });

    test('快照文件名由内容哈希决定（同内容同名，不同内容不同名）', () {
      final String a = snapshotContentHash(utf8.encode('one'));
      final String b = snapshotContentHash(utf8.encode('two'));
      expect(snapshotFileName(a), 'snapshot-$a.json');
      expect(snapshotFileName(a), isNot(snapshotFileName(b)));
      expect(snapshotFileName(a), snapshotFileName(a));
    });

    test('首次发布：上传快照 + 读回校验 + 条件写 manifest（If-Match: *）', () async {
      final List<int> payload = utf8.encode('{"settings":{}}');
      final Result<SnapshotPublishOutcome> result = await publisher.publish(
        manifestUrl: _manifestUrl,
        snapshotUrlFor: _snapshotUrl,
        buildSnapshot: (SyncManifest? parent) => payload,
        deviceName: 'Mac-A',
        revision: 1,
        publishedAt: DateTime.utc(2026, 9, 22, 4),
        capability: WebDavWriteCapability.conditionalWrite,
      );
      expect(result.isOk, isTrue, reason: result.errorOrNull?.message);
      final SnapshotPublishOutcome outcome = result.unwrap();
      expect(outcome.status, SnapshotPublishStatus.published);
      expect(outcome.attempts, 1);
      expect(outcome.advancedRemoteVersion, isTrue);

      final SyncManifest manifest = server.currentManifest()!;
      expect(manifest.deviceName, 'Mac-A');
      expect(manifest.parentVersion, isNull, reason: '首次发布没有父版本');
      expect(
        manifest.snapshotHash,
        snapshotContentHash(payload),
        reason: 'manifest 必须指向这次上传的内容',
      );
      expect(
        server.files.containsKey('$_root/${manifest.snapshotName}'),
        isTrue,
      );
      expect(
        utf8.decode(server.files['$_root/${manifest.snapshotName}']!),
        utf8.decode(payload),
      );
    });

    test('第二次发布：父版本链正确，旧快照保留（作合并基线）', () async {
      await publisher.publish(
        manifestUrl: _manifestUrl,
        snapshotUrlFor: _snapshotUrl,
        buildSnapshot: (_) => utf8.encode('v1'),
        deviceName: 'Mac-A',
        revision: 1,
        publishedAt: DateTime.utc(2026, 9, 22, 4),
        capability: WebDavWriteCapability.conditionalWrite,
      );
      final SyncManifest first = server.currentManifest()!;

      await publisher.publish(
        manifestUrl: _manifestUrl,
        snapshotUrlFor: _snapshotUrl,
        buildSnapshot: (_) => utf8.encode('v2'),
        deviceName: 'Mac-B',
        revision: 2,
        publishedAt: DateTime.utc(2026, 9, 22, 5),
        capability: WebDavWriteCapability.conditionalWrite,
      );
      final SyncManifest second = server.currentManifest()!;
      expect(second.parentVersion, first.version);
      expect(second.deviceName, 'Mac-B');
      expect(second.version, isNot(first.version));
      expect(
        server.files.containsKey('$_root/${first.snapshotName}'),
        isTrue,
        reason: '快照不可变、不删除：别的设备仍需要它作合并基线',
      );
    });

    test('重复发布同一内容：快照不重复上传（内容寻址幂等）', () async {
      final List<int> payload = utf8.encode('same');
      await publisher.publish(
        manifestUrl: _manifestUrl,
        snapshotUrlFor: _snapshotUrl,
        buildSnapshot: (_) => payload,
        deviceName: 'Mac-A',
        revision: 1,
        publishedAt: DateTime.utc(2026, 9, 22, 4),
        capability: WebDavWriteCapability.conditionalWrite,
      );
      final int afterFirst = server.putCount;
      expect(afterFirst, 2, reason: '一次快照 PUT + 一次 manifest PUT');

      await publisher.publish(
        manifestUrl: _manifestUrl,
        snapshotUrlFor: _snapshotUrl,
        buildSnapshot: (_) => payload,
        deviceName: 'Mac-A',
        revision: 2,
        publishedAt: DateTime.utc(2026, 9, 22, 6),
        capability: WebDavWriteCapability.conditionalWrite,
      );
      expect(
        server.putCount - afterFirst,
        1,
        reason: '同名快照被 PROPFIND 判定为已存在而跳过',
      );
    });

    test('读回校验失败（远端内容与上传的不同）→ 失败，且**不**写 manifest', () async {
      final _TamperingServer tampered = _TamperingServer();
      final SnapshotPublisher strict = SnapshotPublisher(
        client: WebDavClient(httpClient: tampered.asClient()),
        username: 'flux',
        password: 'secret',
      );
      final Result<SnapshotPublishOutcome> result = await strict.publish(
        manifestUrl: _manifestUrl,
        snapshotUrlFor: _snapshotUrl,
        buildSnapshot: (_) => utf8.encode('real'),
        deviceName: 'Mac-A',
        revision: 1,
        publishedAt: DateTime.utc(2026, 9, 22, 4),
        capability: WebDavWriteCapability.conditionalWrite,
      );
      expect(result.isOk, isTrue);
      expect(result.unwrap().status, SnapshotPublishStatus.failed);
      expect(result.unwrap().reason, 'validation');
      expect(
        tampered.files.containsKey('$_root/manifest.json'),
        isFalse,
        reason: '内容没通过校验就绝不把 manifest 指过去',
      );
    });
  });

  group('条件写冲突（412）与重试上限（架构 5.2「最多 3 轮」）', () {
    test('第一次 412、第二次成功 → attempts = 2，且基于新读到的父版本', () async {
      final _ConflictOnceServer server = _ConflictOnceServer();
      final SnapshotPublisher publisher = SnapshotPublisher(
        client: WebDavClient(httpClient: server.asClient()),
        username: 'flux',
        password: 'secret',
      );
      // 先有一个当前版本（这是父版本）。
      await publisher.publish(
        manifestUrl: _manifestUrl,
        snapshotUrlFor: _snapshotUrl,
        buildSnapshot: (_) => utf8.encode('base'),
        deviceName: 'Mac-A',
        revision: 1,
        publishedAt: DateTime.utc(2026, 9, 22, 4),
        capability: WebDavWriteCapability.conditionalWrite,
      );
      final SyncManifest base = server.currentManifest()!;

      // 竞争设备在第一轮的 manifest 写之前插进来发布一版。
      final SnapshotPublisher competitor = SnapshotPublisher(
        client: WebDavClient(httpClient: server.asClient()),
        username: 'flux',
        password: 'secret',
      );
      int call = 0;
      final Result<SnapshotPublishOutcome> result = await publisher.publish(
        manifestUrl: _manifestUrl,
        snapshotUrlFor: _snapshotUrl,
        buildSnapshot: (SyncManifest? parent) {
          call++;
          if (call == 1) {
            // 第一次已经读到旧基线：在返回内容之前让竞争设备先写一版。
            server.beforeNextManifestPut = () async {
              await competitor.publish(
                manifestUrl: _manifestUrl,
                snapshotUrlFor: _snapshotUrl,
                buildSnapshot: (_) => utf8.encode('other-device'),
                deviceName: 'Mac-B',
                revision: 9,
                publishedAt: DateTime.utc(2026, 9, 22, 4, 30),
                capability: WebDavWriteCapability.conditionalWrite,
              );
              return const Ok<WebDavStatus>(WebDavStatus.ok);
            };
          }
          return utf8.encode('mine-$call');
        },
        deviceName: 'Mac-A',
        revision: 2,
        publishedAt: DateTime.utc(2026, 9, 22, 5),
        capability: WebDavWriteCapability.conditionalWrite,
      );
      expect(result.isOk, isTrue);
      final SnapshotPublishOutcome outcome = result.unwrap();
      expect(outcome.status, SnapshotPublishStatus.published);
      expect(outcome.attempts, 2, reason: '第一轮 412，第二轮成功');
      expect(outcome.manifest!.parentVersion, isNotNull);
      expect(
        outcome.manifest!.parentVersion,
        isNot(base.version),
        reason: '第二轮基于**新读到的**基线，而不是最初读到的那个',
      );
    });

    test('每次 manifest 写入都 412 → 用满 3 轮后放弃（不覆盖、manifest 未被写入）', () async {
      final _AlwaysConflictServer always = _AlwaysConflictServer();
      final SnapshotPublisher publisher = SnapshotPublisher(
        client: WebDavClient(httpClient: always.asClient()),
        username: 'flux',
        password: 'secret',
      );
      final Result<SnapshotPublishOutcome> result = await publisher.publish(
        manifestUrl: _manifestUrl,
        snapshotUrlFor: _snapshotUrl,
        buildSnapshot: (_) => utf8.encode('mine'),
        deviceName: 'Mac-A',
        revision: 1,
        publishedAt: DateTime.utc(2026, 9, 22, 5),
        capability: WebDavWriteCapability.conditionalWrite,
      );
      final SnapshotPublishOutcome outcome = result.unwrap();
      expect(outcome.status, SnapshotPublishStatus.conflictExhausted);
      expect(outcome.attempts, manifestConflictRetryLimit);
      expect(outcome.advancedRemoteVersion, isFalse, reason: '没有推进远端版本');
      expect(
        always.files.containsKey('$_root/manifest.json'),
        isFalse,
        reason: 'conflictExhausted 路径上 manifest 从未被写进去',
      );
    });

    test('If-Match 被服务器忽略 → 探测判成降级，publish 一个字节都不写', () async {
      final FakeWebDavServer lax = FakeWebDavServer(supportsIfMatch: false);
      final WebDavClient client = WebDavClient(httpClient: lax.asClient());
      final Uri probeUrl = Uri.parse(
        'https://dav.example.com/flux-v1/probe.json',
      );

      final WebDavResponse firstPut = await client.put(
        probeUrl,
        username: 'flux',
        password: 'secret',
        bytes: utf8.encode('probe-1'),
      );
      final String? firstEtag = firstPut.etag;
      final WebDavResponse conditionalPut = await client.put(
        probeUrl,
        username: 'flux',
        password: 'secret',
        bytes: utf8.encode('probe-2'),
        ifMatch: firstEtag,
      );
      // 用过期的 ETag 再写一次：忽略 If-Match 的服务器**照写**。
      final WebDavResponse stalePut = await client.put(
        probeUrl,
        username: 'flux',
        password: 'secret',
        bytes: utf8.encode('probe-3'),
        ifMatch: firstEtag,
      );
      final WebDavProbeResult probe = evaluateConditionalWriteProbe(
        WebDavProbeFacts(
          probePutOk: firstPut.isOk,
          firstEtag: firstEtag,
          conditionalPutOk: conditionalPut.isOk,
          secondEtag: conditionalPut.etag,
          staleIfMatchRejected: stalePut.status == WebDavStatus.conflict,
        ),
      );
      expect(probe.capability, WebDavWriteCapability.readOnlyPull);
      expect(probe.reason, 'ifMatchNotEnforced');

      final int putsBefore = lax.putCount;
      final SnapshotPublisher publisher = SnapshotPublisher(
        client: WebDavClient(httpClient: lax.asClient()),
        username: 'flux',
        password: 'secret',
      );
      final Result<SnapshotPublishOutcome> result = await publisher.publish(
        manifestUrl: _manifestUrl,
        snapshotUrlFor: _snapshotUrl,
        buildSnapshot: (_) => utf8.encode('never-sent'),
        deviceName: 'Mac-A',
        revision: 1,
        publishedAt: DateTime.utc(2026, 9, 22, 5),
        capability: probe.capability,
      );
      final SnapshotPublishOutcome outcome = result.unwrap();
      expect(outcome.status, SnapshotPublishStatus.degradedReadOnly);
      expect(outcome.attempts, 0);
      expect(
        lax.putCount,
        putsBefore,
        reason: '降级模式下**一个字节都不写**（架构 5.2 禁止不安全多端覆盖）',
      );
      expect(lax.files.containsKey('$_root/manifest.json'), isFalse);
    });

    test('能力未探测（unknown）同样不写（fail-closed）', () async {
      final FakeWebDavServer server = FakeWebDavServer();
      final SnapshotPublisher publisher = SnapshotPublisher(
        client: WebDavClient(httpClient: server.asClient()),
        username: 'flux',
        password: 'secret',
      );
      final Result<SnapshotPublishOutcome> result = await publisher.publish(
        manifestUrl: _manifestUrl,
        snapshotUrlFor: _snapshotUrl,
        buildSnapshot: (_) => utf8.encode('x'),
        deviceName: 'Mac-A',
        revision: 1,
        publishedAt: DateTime.utc(2026, 9, 22, 5),
        capability: WebDavWriteCapability.unknown,
      );
      expect(result.unwrap().status, SnapshotPublishStatus.degradedReadOnly);
      expect(server.putCount, 0);
    });
  });

  group('孤儿快照（架构 5.2「上传中断的孤儿快照不是当前版本」）', () {
    test('快照上传成功但 manifest 写入失败 → orphanSnapshot，且不是当前版本', () async {
      final _ManifestWriteFailingServer server = _ManifestWriteFailingServer();
      final SnapshotPublisher publisher = SnapshotPublisher(
        client: WebDavClient(httpClient: server.asClient()),
        username: 'flux',
        password: 'secret',
      );
      final Result<SnapshotPublishOutcome> result = await publisher.publish(
        manifestUrl: _manifestUrl,
        snapshotUrlFor: _snapshotUrl,
        buildSnapshot: (_) => utf8.encode('orphan-body'),
        deviceName: 'Mac-A',
        revision: 1,
        publishedAt: DateTime.utc(2026, 9, 22, 5),
        capability: WebDavWriteCapability.conditionalWrite,
      );
      final SnapshotPublishOutcome outcome = result.unwrap();
      expect(outcome.status, SnapshotPublishStatus.orphanSnapshot);
      expect(outcome.leftOrphanSnapshot, isTrue);
      expect(outcome.advancedRemoteVersion, isFalse);

      final String name = snapshotFileName(
        snapshotContentHash(utf8.encode('orphan-body')),
      );
      expect(server.files.containsKey('$_root/$name'), isTrue);
      expect(server.currentManifest(), isNull, reason: 'manifest 没更新');
      expect(
        isCurrentSnapshot(snapshotName: name, currentManifest: null),
        isFalse,
        reason: '孤儿快照不是当前版本',
      );
    });

    test('孤儿判定：只有被 manifest 引用的名字才算当前版本', () {
      final SyncManifest manifest = SyncManifest(
        version: 'v-1',
        snapshotName: 'snapshot-aa.json',
        snapshotHash: 'aa',
        parentVersion: null,
        revision: 1,
        deviceName: 'A',
        publishedAt: _epoch,
      );
      expect(
        isCurrentSnapshot(
          snapshotName: 'snapshot-aa.json',
          currentManifest: manifest,
        ),
        isTrue,
      );
      expect(
        isCurrentSnapshot(
          snapshotName: 'snapshot-bb.json',
          currentManifest: manifest,
        ),
        isFalse,
      );
      expect(
        isCurrentSnapshot(snapshotName: 'x', currentManifest: null),
        isFalse,
        reason: '远端没有当前版本时，任何快照都不是当前版本',
      );
    });

    test('孤儿列表只含未被引用的快照（上一版仍作为基线保留）', () {
      final SyncManifest manifest = SyncManifest(
        version: 'v-2',
        snapshotName: 'snapshot-bb.json',
        snapshotHash: 'bb',
        parentVersion: 'v-1',
        revision: 2,
        deviceName: 'A',
        publishedAt: _epoch,
      );
      final List<String> orphans = orphanSnapshots(
        remoteSnapshotNames: <String>[
          'snapshot-aa.json',
          'snapshot-bb.json',
          'snapshot-cc.json',
        ],
        currentManifest: manifest,
        referencedNames: <String>{'snapshot-aa.json'},
      );
      expect(orphans, <String>['snapshot-cc.json']);
    });

    test('上传中断（断网）→ failed；远端没有任何文件被留下', () async {
      final FakeWebDavServer server = FakeWebDavServer();
      final SnapshotPublisher publisher = SnapshotPublisher(
        client: WebDavClient(httpClient: server.asClient()),
        username: 'flux',
        password: 'secret',
      );
      server.offline = true;
      final Result<SnapshotPublishOutcome> result = await publisher.publish(
        manifestUrl: _manifestUrl,
        snapshotUrlFor: _snapshotUrl,
        buildSnapshot: (_) => utf8.encode('never-arrives'),
        deviceName: 'Mac-A',
        revision: 1,
        publishedAt: DateTime.utc(2026, 9, 22, 5),
        capability: WebDavWriteCapability.conditionalWrite,
      );
      expect(result.unwrap().status, SnapshotPublishStatus.failed);
      expect(server.currentManifest(), isNull);
      expect(server.files, isEmpty);
    });
  });

  group('manifest 编解码与协议版本', () {
    test('往返无损，字段齐全', () {
      final SyncManifest manifest = SyncManifest.forSnapshot(
        snapshotHash: 'abcdef0123456789abcdef0123456789',
        deviceName: 'Mac-A',
        revision: 7,
        publishedAt: DateTime.utc(2026, 9, 22, 4, 30),
        parentVersion: 'v-parent',
      );
      final SyncManifest? decoded = SyncManifest.decode(manifest.encode());
      expect(decoded, isNotNull);
      expect(decoded!.version, manifest.version);
      expect(decoded.snapshotName, manifest.snapshotName);
      expect(decoded.snapshotHash, manifest.snapshotHash);
      expect(decoded.parentVersion, 'v-parent');
      expect(decoded.revision, 7);
      expect(decoded.deviceName, 'Mac-A');
      expect(decoded.publishedAt, DateTime.utc(2026, 9, 22, 4, 30));
    });

    test('版本号由快照哈希决定（确定性：同内容同版本）', () {
      expect(versionForSnapshot('abc'), versionForSnapshot('abc'));
      expect(versionForSnapshot('abc'), isNot(versionForSnapshot('abd')));
      expect(snapshotFileName('ABC'), 'snapshot-abc.json', reason: '哈希统一小写');
    });

    test('**新协议版本阻写**：读不懂的 manifest 返回 null（不按自己的形状解读）', () {
      final String newer = jsonEncode(<String, Object?>{
        'version': 'v-x',
        'snapshotName': 'snapshot-x.json',
        'snapshotHash': 'x',
        'parentVersion': null,
        'revision': 1,
        'deviceName': 'future',
        'publishedAt': '2026-09-22T00:00:00.000Z',
        'protocol': 'flux-sync-9',
      });
      expect(SyncManifest.decode(newer), isNull);
    });

    test('损坏/缺字段的 manifest 返回 null（不用默认值凑一个）', () {
      expect(SyncManifest.decode('not json'), isNull);
      expect(SyncManifest.decode('[]'), isNull);
      expect(SyncManifest.decode('{}'), isNull);
      expect(
        SyncManifest.decode(
          jsonEncode(<String, Object?>{
            'version': 'v',
            'snapshotName': 'snapshot-x.json',
            'snapshotHash': 'x',
            'revision': 'one',
            'deviceName': 'A',
            'publishedAt': '2026-09-22T00:00:00.000Z',
          }),
        ),
        isNull,
      );
      expect(
        SyncManifest.decode(
          jsonEncode(<String, Object?>{
            'version': 'v',
            'snapshotName': 'snapshot-x.json',
            'snapshotHash': 'x',
            'revision': 1,
            'deviceName': 'A',
            'publishedAt': 'not-a-time',
          }),
        ),
        isNull,
      );
    });

    test('远端 manifest 读不懂 → readManifest 明确失败（不当成「没有当前版本」）', () async {
      final FakeWebDavServer server = FakeWebDavServer();
      server.seedFile('$_root/manifest.json', utf8.encode('{ broken'));
      final SnapshotPublisher publisher = SnapshotPublisher(
        client: WebDavClient(httpClient: server.asClient()),
        username: 'flux',
        password: 'secret',
      );
      final Result<({SyncManifest? manifest, String? etag})> result =
          await publisher.readManifest(_manifestUrl);
      expect(result.isErr, isTrue);
      expect(
        result.errorOrNull,
        isA<StorageError>(),
        reason: '当作「没有当前版本」会让本机覆盖掉一份看不懂的版本',
      );
    });

    test('远端还没有 manifest → (null, null)，这是首次发布的正常状态', () async {
      final FakeWebDavServer server = FakeWebDavServer();
      final SnapshotPublisher publisher = SnapshotPublisher(
        client: WebDavClient(httpClient: server.asClient()),
        username: 'flux',
        password: 'secret',
      );
      final Result<({SyncManifest? manifest, String? etag})> result =
          await publisher.readManifest(_manifestUrl);
      expect(result.isOk, isTrue);
      expect(result.unwrap().manifest, isNull);
      expect(result.unwrap().etag, isNull);
    });

    test('确认发布需要三件读回的事实同时成立', () {
      final SyncManifest manifest = SyncManifest.forSnapshot(
        snapshotHash: 'deadbeef',
        deviceName: 'A',
        revision: 1,
        publishedAt: _epoch,
      );
      expect(
        canConfirmPublish(
          localHash: 'deadbeef',
          readBackHash: 'deadbeef',
          readBackManifest: manifest,
        ),
        isTrue,
      );
      expect(
        canConfirmPublish(
          localHash: 'deadbeef',
          readBackHash: 'other',
          readBackManifest: manifest,
        ),
        isFalse,
      );
      expect(
        canConfirmPublish(
          localHash: 'deadbeef',
          readBackHash: 'deadbeef',
          readBackManifest: null,
        ),
        isFalse,
      );
    });
  });
}

/// 篡改读回内容的服务器（验证读回校验真的生效）。
final class _TamperingServer extends FakeWebDavServer {
  @override
  Future<http.StreamedResponse> handle(http.BaseRequest request) async {
    // 只篡改**快照**的读回：manifest 的读取必须仍然正常，否则失败原因会变成
    // 「manifest 读不懂」，测不到读回校验这一步。
    if (request.method == 'GET' && request.url.path.contains('snapshot-')) {
      final List<int> tampered = utf8.encode('tampered');
      return http.StreamedResponse(
        Stream<List<int>>.value(tampered),
        200,
        headers: <String, String>{
          'content-type': 'application/json',
          'content-length': '${tampered.length}',
        },
      );
    }
    return super.handle(request);
  }
}

/// 每次 manifest 写入都返回 412 的服务器（验证重试上限）。
final class _AlwaysConflictServer extends FakeWebDavServer {
  @override
  Future<http.StreamedResponse> handle(http.BaseRequest request) async {
    if (request.method == 'PUT' && request.url.path.endsWith('manifest.json')) {
      requestLog.add('${request.method} ${request.url.path}');
      return http.StreamedResponse(
        const Stream<List<int>>.empty(),
        412,
        headers: <String, String>{'content-length': '0'},
      );
    }
    return super.handle(request);
  }
}

/// manifest 写入被拒（例如目录只读）的服务器（验证孤儿快照语义）。
final class _ManifestWriteFailingServer extends FakeWebDavServer {
  @override
  Future<http.StreamedResponse> handle(http.BaseRequest request) async {
    if (request.method == 'PUT' && request.url.path.endsWith('manifest.json')) {
      requestLog.add('${request.method} ${request.url.path}');
      return http.StreamedResponse(
        const Stream<List<int>>.empty(),
        507,
        headers: <String, String>{'content-length': '0'},
      );
    }
    return super.handle(request);
  }
}

/// 在**第一次** manifest 写入之前插一次外部发布的服务器（验证 412 重读重试）。
final class _ConflictOnceServer extends FakeWebDavServer {
  /// 下一次 manifest 写入前要执行的钩子（只生效一次）。
  Future<Result<WebDavStatus>> Function()? beforeNextManifestPut;

  @override
  Future<http.StreamedResponse> handle(http.BaseRequest request) async {
    if (request.method == 'PUT' && request.url.path.endsWith('manifest.json')) {
      final Future<Result<WebDavStatus>> Function()? hook =
          beforeNextManifestPut;
      if (hook != null) {
        beforeNextManifestPut = null;
        await hook();
      }
    }
    return super.handle(request);
  }
}
