// T044：能力探测与只读连接探测（架构 5.2「多写入服务须验证强 ETag/If-Match」）。
//
// 两条边界，各有一组用例：
//   1) **能力探测**真的做那四个实验，并且把结论交给 T042 的纯函数判定。最要紧的一条是
//      「忽略 If-Match 的服务器必须被判成降级只读」——那类服务器能通过前三步，
//      只在多端并发时静默互相覆盖；
//   2) **只读连接探测**一个写请求都不发（这是对用户的承诺：在还不确定能不能用的地址上
//      不该被迫接受一次写入）。
//
// 全部走内存服务器（T042 的状态化替身），因此没有网络、没有凭据。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:flux/core/core.dart';
import 'package:flux/features/sync/application/sync_settings.dart';
import 'package:flux/infrastructure/network/webdav_capability_probe.dart';
import 'package:flux/infrastructure/network/webdav_client.dart';
import 'package:flux/infrastructure/network/webdav_connection_prober.dart';

import 'fake_webdav_server.dart';

/// 模拟「忽略 If-Match」的服务器：照写不误（这正是探测要识破的那一类）。
class _IfMatchIgnoringServer extends FakeWebDavServer {
  /// 构造。
  _IfMatchIgnoringServer() : super(supportsIfMatch: false);
}

/// 记录请求方法的服务器。
class _RecordingServer extends FakeWebDavServer {
  /// 收到的方法（按顺序）。
  final List<String> methods = <String>[];

  @override
  Future<http.StreamedResponse> handle(http.BaseRequest request) {
    methods.add(request.method);
    return super.handle(request);
  }
}

/// 一个可用的同步设置（地址指向内存服务器）。
SyncSettings _settings({
  String url = 'http://dav.example.com',
  String directory = 'flux-v1',
}) => SyncSettings.fromEffective(<String, Object?>{
  SettingId.set070.code: <String, Object?>{
    'url': url,
    'username': 'flux',
    'remoteDirectory': directory,
    'deviceName': 'Mac-A',
  },
  SettingId.set072.code: <String, Object?>{'enabled': true},
});

void main() {
  group('能力探测（四步实验 + T042 的纯函数判定）', () {
    test('支持条件写的服务器：判成 conditionalWrite', () async {
      final FakeWebDavServer server = FakeWebDavServer();
      final Result<WebDavWriteCapability> result = await probeWebDavCapability(
        client: WebDavClient(httpClient: server.asClient()),
        settings: _settings(),
        password: 'secret',
      );
      expect(result.unwrap(), WebDavWriteCapability.conditionalWrite);
    });

    test('忽略 If-Match 的服务器：判成 readOnlyPull（前三步会通过）', () async {
      final _IfMatchIgnoringServer server = _IfMatchIgnoringServer();
      final Result<WebDavWriteCapability> result = await probeWebDavCapability(
        client: WebDavClient(httpClient: server.asClient()),
        settings: _settings(),
        password: 'secret',
      );
      // 这就是「过期 ETag 必须被拒」这一步的价值：少了它会判成支持条件写。
      expect(result.unwrap(), WebDavWriteCapability.readOnlyPull);
    });

    test('不提供 ETag 的服务器：判成 readOnlyPull（没有可用的前提条件）', () async {
      final FakeWebDavServer server = FakeWebDavServer(supportsEtag: false);
      final Result<WebDavWriteCapability> result = await probeWebDavCapability(
        client: WebDavClient(httpClient: server.asClient()),
        settings: _settings(),
        password: 'secret',
      );
      expect(result.unwrap(), WebDavWriteCapability.readOnlyPull);
    });

    test('地址非法：直接失败，一个请求都不发', () async {
      final _RecordingServer server = _RecordingServer();
      final Result<WebDavWriteCapability> result = await probeWebDavCapability(
        client: WebDavClient(httpClient: server.asClient()),
        settings: _settings(url: 'ftp://dav.example.com'),
        password: 'secret',
      );
      expect(result.isErr, isTrue);
      expect(server.requestLog, isEmpty);
    });

    test('探测只动自己的探测文件（不碰 manifest 与快照）', () async {
      final FakeWebDavServer server = FakeWebDavServer();
      await probeWebDavCapability(
        client: WebDavClient(httpClient: server.asClient()),
        settings: _settings(),
        password: 'secret',
      );
      // 探测结束后自己的文件被清掉；manifest 从未被创建，目录里也不留垃圾。
      expect(server.currentManifest(), isNull);
      expect(
        server.files.keys.where((String p) => p.contains('capability-probe')),
        isEmpty,
      );
    });
  });

  group('只读连接探测（一个写请求都不发）', () {
    test('目录存在且已有内容：给出「可达 + 目录存在 + 有内容」', () async {
      final _RecordingServer recording = _RecordingServer();
      // 预置一份 manifest，模拟「远端已经同步过」。
      recording.seedFile(
        '/flux-v1/manifest.json',
        utf8.encode(
          SyncManifest.forSnapshot(
            snapshotHash: 'a' * 64,
            deviceName: 'Mac-B',
            revision: 1,
            publishedAt: DateTime.utc(2026, 9, 22),
          ).encode(),
        ),
      );

      final Result<SyncConnectionProbe> result =
          await WebDavConnectionProber(
            client: WebDavClient(httpClient: recording.asClient()),
          ).probe(
            url: 'http://dav.example.com',
            username: 'flux',
            password: 'secret',
            remoteDirectory: 'flux-v1',
          );
      expect(result.unwrap().reachable, isTrue);
      expect(result.unwrap().directoryExists, isTrue);
      expect(
        result.unwrap().hasRemoteContent,
        isTrue,
        reason: '远端已有 manifest → 界面可以提示「这台设备会与已有内容合并」',
      );
      // 探测本身仍然是只读的。
      expect(recording.putCount, 0);
    });

    test('内存服务器上：探测可达、目录存在、无下游写请求', () async {
      final _RecordingServer server = _RecordingServer();
      final Result<SyncConnectionProbe> result =
          await WebDavConnectionProber(
            client: WebDavClient(httpClient: server.asClient()),
          ).probe(
            url: 'http://dav.example.com',
            username: 'flux',
            password: 'secret',
            remoteDirectory: 'flux-v1',
          );

      expect(result.unwrap().reachable, isTrue);
      expect(result.unwrap().directoryExists, isTrue);
      // **没有任何写动作**：只有 PROPFIND 与 GET。
      expect(server.methods.toSet(), <String>{
        'PROPFIND',
        'GET',
      }, reason: '测试连接不得写入远端');
      expect(server.putCount, 0);
    });

    test('目录不存在：可达但目录缺失（不是失败）', () async {
      final _RecordingServer server = _RecordingServer();
      // 内存服务器默认只有 /flux-v1；换一个不存在的目录名。
      final Result<SyncConnectionProbe> result =
          await WebDavConnectionProber(
            client: WebDavClient(httpClient: server.asClient()),
          ).probe(
            url: 'http://dav.example.com',
            username: 'flux',
            password: 'secret',
            remoteDirectory: '还没有创建',
          );

      expect(result.unwrap().reachable, isTrue);
      expect(result.unwrap().directoryExists, isFalse);
      expect(result.unwrap().reason, 'directoryMissing');
    });

    test('认证失败：明确给出 unauthorized，且不写入', () async {
      final _RecordingServer server = _RecordingServer();
      final Result<SyncConnectionProbe> result =
          await WebDavConnectionProber(
            client: WebDavClient(httpClient: server.asClient()),
          ).probe(
            url: 'http://dav.example.com',
            username: 'flux',
            password: 'wrong-password',
            remoteDirectory: 'flux-v1',
          );

      expect(result.unwrap().reachable, isFalse);
      expect(result.unwrap().reason, 'unauthorized');
      expect(server.putCount, 0);
    });

    test('地址非法：失败，一个请求都不发', () async {
      final _RecordingServer server = _RecordingServer();
      final Result<SyncConnectionProbe> result =
          await WebDavConnectionProber(
            client: WebDavClient(httpClient: server.asClient()),
          ).probe(
            url: 'not a url',
            username: 'flux',
            password: 'secret',
            remoteDirectory: 'flux-v1',
          );

      expect(result.isErr, isTrue);
      expect(server.requestLog, isEmpty);
    });
  });
}
