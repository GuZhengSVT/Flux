// 「测试连接」的只读探测（T044；SET-070、架构 5.2）。
//
// 这个动作只有三条规则，但每一条都是为了「不让一次配置变成一次写入」：
//
//   1) **只读**：连 MKCOL 都不做（即使目录不存在也不建），PROPFIND 问一下当前有什么，
//      再 GET 一次 manifest——404 也是有效结论（说明这个地址能用，但远端还没有内容）。
//      用户在一个还不确定能不能用的地址上不该被迫接受一次写入。
//   2) **结论可区分**：连不上 / 认证失败 / 地址非法 / 目录不存在，四种原因给四种说明，
//      因为它们对应的用户动作不同（改地址 / 改密码 / 修协议 / 建目录）。
//   3) **密码只进认证头**：密码是一次调用的实参，用完即弃；结论里没有任何字段能携带它。
library;

import 'package:flux/core/core.dart';
import 'package:flux/features/sync/application/sync_settings.dart';

import 'webdav_client.dart';
import 'webdav_transport.dart';

/// 只读探测端口的生产实现（端口在 features/sync/application/sync_settings.dart）。
final class WebDavConnectionProber implements SyncConnectionProber {
  /// 构造实现。
  ///
  /// [client] 为空时按需构造真实客户端（每次探测一个，探测完即弃——探测是低频动作，
  /// 为此长期持有一个 HTTP 客户端只会让它带着可能已经失效的连接活着）。
  const WebDavConnectionProber({this.client});

  /// 注入的客户端（测试传内存服务器上的客户端，因此探测路径与生产同一条）。
  final WebDavClient? client;

  @override
  Future<Result<SyncConnectionProbe>> probe({
    required String url,
    required String username,
    required String password,
    required String remoteDirectory,
  }) async {
    final Uri? endpoint = parseSyncEndpoint(url);
    if (endpoint == null) {
      return Err<SyncConnectionProbe>(
        ValidationError(field: 'SET-070.url', reason: '地址非法或未填写'),
      );
    }
    final String directory = remoteDirectory.trim().isEmpty
        ? defaultWebDavRemoteRoot
        : remoteDirectory.trim();
    final Uri directoryUrl = endpoint.replace(
      pathSegments: <String>[
        ...endpoint.pathSegments.where((String segment) => segment.isNotEmpty),
        directory,
      ],
    );
    final WebDavSyncTransport transport = WebDavSyncTransport(
      client: client ?? WebDavClient(),
      credentials: SyncCredentials(username: username, password: password),
    );

    final Result<SyncTransportResponse> listing = await transport.listDirectory(
      directoryUrl,
    );
    if (listing.isErr) {
      return Err<SyncConnectionProbe>(listing.errorOrNull!);
    }
    final SyncTransportResponse listed = listing.unwrap();
    if (listed.status == SyncTransportStatus.unauthorized) {
      return const Ok<SyncConnectionProbe>(
        SyncConnectionProbe(
          reachable: false,
          directoryExists: false,
          hasRemoteContent: false,
          reason: 'unauthorized',
        ),
      );
    }
    if (listed.status == SyncTransportStatus.notFound) {
      // 地址可用但目录还不存在（远端也可能不支持对单个集合的探测）。
      return const Ok<SyncConnectionProbe>(
        SyncConnectionProbe(
          reachable: true,
          directoryExists: false,
          hasRemoteContent: false,
          reason: 'directoryMissing',
        ),
      );
    }
    if (!listed.isOk) {
      return Ok<SyncConnectionProbe>(
        SyncConnectionProbe(
          reachable: false,
          directoryExists: false,
          hasRemoteContent: false,
          reason: listed.reason ?? listed.status.name,
        ),
      );
    }

    // GET manifest：404 说明「能连上但远端还没有内容」，这也是一个有效且有用的结论。
    final Result<SyncTransportResponse> manifest = await transport.read(
      directoryUrl.replace(
        pathSegments: <String>[
          ...directoryUrl.pathSegments,
          syncManifestFileName,
        ],
      ),
    );
    final bool hasContent =
        manifest.isOk && manifest.unwrap().status == SyncTransportStatus.ok;
    return Ok<SyncConnectionProbe>(
      SyncConnectionProbe(
        reachable: true,
        directoryExists: true,
        hasRemoteContent: hasContent,
      ),
    );
  }
}
