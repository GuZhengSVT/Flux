// WebDAV 传输端口实现（T043；端口在 core/domain/sync_transport.dart）。
//
// 这一层的全部职责是**把协议状态翻译成中性结论**，不做任何合并、事务或重试决策：
//   * 412 翻译成 `SyncTransportStatus.conflict`（调用方据此重读重合并），不是异常；
//   * 404 翻译成 `notFound`（「远端还没有这一版」是正常状态，不是失败）；
//   * 认证失败翻译成 `unauthorized` 且错误消息里**没有** URL 与凭据；
//   * PROPFIND 的结果只保留文件名与 ETag（编排只需要「远端有哪些快照」）。
//
// 密码每次调用都从实参取：本类**不持有**凭据字段，因此不存在「引擎或传输层缓存了密码」
// 这种状态（架构第 8 节）。
library;

import 'package:flux/core/core.dart';

import 'webdav_client.dart';

/// 基于 T042 客户端的传输实现。
final class WebDavSyncTransport implements SyncTransport {
  /// 构造实现。
  const WebDavSyncTransport({required this.client, required this.credentials});

  /// T042 的协议客户端。
  final WebDavClient client;

  /// 本轮同步的凭据（由用例层在本次运行期间持有）。
  final SyncCredentials credentials;

  @override
  Future<Result<SyncTransportResponse>> listDirectory(Uri directory) async {
    final WebDavResponse response = await client.propfind(
      directory,
      username: credentials.username,
      password: credentials.password,
      depth: 1,
    );
    if (!response.isOk) {
      return Ok<SyncTransportResponse>(_failure(response));
    }
    final List<SyncRemoteEntry> entries = <SyncRemoteEntry>[];
    for (final WebDavResource resource in response.resources) {
      final String name = _fileName(resource.path);
      if (name.isEmpty) {
        // 目录自身（href 以 / 结尾）在归一化后是路径本身，没有文件名：跳过它，
        // 「远端有哪些快照」的列表里不该混进目录项。
        continue;
      }
      entries.add(
        SyncRemoteEntry(
          name: name,
          isCollection: resource.isCollection,
          etag: resource.etag,
        ),
      );
    }
    return Ok<SyncTransportResponse>(
      SyncTransportResponse(
        status: SyncTransportStatus.ok,
        etag: response.etag,
        entries: entries,
      ),
    );
  }

  @override
  Future<Result<SyncTransportResponse>> read(Uri url) async {
    final WebDavResponse response = await client.get(
      url,
      username: credentials.username,
      password: credentials.password,
    );
    if (!response.isOk) {
      return Ok<SyncTransportResponse>(_failure(response));
    }
    return Ok<SyncTransportResponse>(
      SyncTransportResponse(
        status: SyncTransportStatus.ok,
        bytes: response.bodyBytes,
        etag: response.etag,
      ),
    );
  }

  @override
  Future<Result<SyncTransportResponse>> write(
    Uri url, {
    required List<int> bytes,
    String? ifMatch,
  }) async {
    final WebDavResponse response = await client.put(
      url,
      username: credentials.username,
      password: credentials.password,
      bytes: bytes,
      ifMatch: ifMatch,
    );
    return Ok<SyncTransportResponse>(
      response.isOk
          ? SyncTransportResponse(
              status: SyncTransportStatus.ok,
              etag: response.etag,
            )
          : _failure(response),
    );
  }

  @override
  Future<Result<SyncTransportResponse>> ensureDirectory(Uri url) async {
    final WebDavResponse response = await client.mkcol(
      url,
      username: credentials.username,
      password: credentials.password,
    );
    return Ok<SyncTransportResponse>(
      response.isOk
          ? const SyncTransportResponse(status: SyncTransportStatus.ok)
          : _failure(response),
    );
  }

  /// 状态映射：只翻译「结论」，失败原因用结构性标识（不含 URL 与凭据）。
  static SyncTransportResponse _failure(WebDavResponse response) {
    final SyncTransportStatus status = switch (response.status) {
      WebDavStatus.ok => SyncTransportStatus.ok,
      WebDavStatus.notFound => SyncTransportStatus.notFound,
      WebDavStatus.conflict => SyncTransportStatus.conflict,
      WebDavStatus.unauthorized => SyncTransportStatus.unauthorized,
      WebDavStatus.writeRejected => SyncTransportStatus.writeRejected,
      WebDavStatus.failed => SyncTransportStatus.failed,
    };
    return SyncTransportResponse(
      status: status,
      etag: response.etag,
      reason: response.reason ?? response.status.name,
    );
  }

  static String _fileName(String path) {
    final int slash = path.lastIndexOf('/');
    return slash < 0 ? path : path.substring(slash + 1);
  }
}
