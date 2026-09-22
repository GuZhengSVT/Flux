// 同步传输端口与凭据端口（T043；架构 2.2 的依赖方向、架构 5.2 的条件发布协议）。
//
// 为什么需要这一层而不是让用例直接调用 T042 的 `WebDavClient`：
//   * `WebDavClient` 住在 `lib/infrastructure/network`，而**合并与发布编排住在用例层**
//     （`lib/features/sync`），features 不得 import infrastructure（分层守卫测试会拦）；
//   * 更重要的是：编排里最容易出错的不是 HTTP 细节，而是**何时读、何时写、写失败之后
//     怎么办**（412 重读重合并、读到一半的失败要留孤儿快照、降级服务器一个字节都不写）。
//     把这些决策放在用例层，HTTP 层就只剩「协议动作 + 状态翻译」；
//   * 端口的中性类型让「服务器不支持条件写」这类**行为**能在内存服务器上逐条断言，
//     不需要任何真实凭据。
//
// 这里**没有**任何接收或返回秘密的方法之外的通道：密码只作为一次调用的实参传入，
// 不存在「把凭据存进引擎」的字段（架构第 8 节：凭据不落库、不进日志、不进错误消息）。
library;

import '../result.dart';

import 'webdav.dart';

/// 一次同步传输请求的结论类别（与 `WebDavStatus` 同口径，但不依赖 infrastructure）。
enum SyncTransportStatus {
  /// 成功。
  ok,

  /// 资源不存在（404）。
  notFound,

  /// 条件写失败（412）：调用方必须重读、重合并、重试。
  conflict,

  /// 认证失败（401/403）。
  unauthorized,

  /// 远端拒绝写（405/409/423 等）。
  writeRejected,

  /// 其它失败（网络/超时/解析）。
  failed,
}

/// 远端目录里的一个条目。
final class SyncRemoteEntry {
  /// 构造条目。
  const SyncRemoteEntry({
    required this.name,
    required this.isCollection,
    this.etag,
  });

  /// 文件名（不含目录）。
  final String name;

  /// 是否为目录。
  final bool isCollection;

  /// ETag（服务器给出时）。
  final String? etag;
}

/// 一次传输响应。
final class SyncTransportResponse {
  /// 构造响应。
  const SyncTransportResponse({
    required this.status,
    this.bytes,
    this.etag,
    this.entries = const <SyncRemoteEntry>[],
    this.reason,
  });

  /// 结论类别。
  final SyncTransportStatus status;

  /// 响应体（GET 时）。
  final List<int>? bytes;

  /// 响应头里的 ETag。
  final String? etag;

  /// 目录条目（PROPFIND 时）。
  final List<SyncRemoteEntry> entries;

  /// 失败原因的结构性标识（**不含**地址与凭据）。
  final String? reason;

  /// 是否成功。
  bool get isOk => status == SyncTransportStatus.ok;

  /// 快照文件（名字以快照前缀开头、且不是目录）。
  List<String> get snapshotNames => entries
      .where(
        (SyncRemoteEntry entry) =>
            !entry.isCollection && entry.name.startsWith(syncSnapshotPrefix),
      )
      .map((SyncRemoteEntry entry) => entry.name)
      .toList(growable: false);
}

/// 同步传输端口（实现住 infrastructure/network，包住 T042 的 WebDavClient）。
abstract interface class SyncTransport {
  /// 列出一个远端目录（Depth: 1）。
  Future<Result<SyncTransportResponse>> listDirectory(Uri directory);

  /// 读一个资源。
  Future<Result<SyncTransportResponse>> read(Uri url);

  /// 写一个资源；[ifMatch] 非 null 时是**条件写**（412 表示冲突）。
  Future<Result<SyncTransportResponse>> write(
    Uri url, {
    required List<int> bytes,
    String? ifMatch,
  });

  /// 保证目录存在（已存在视为成功；幂等）。
  Future<Result<SyncTransportResponse>> ensureDirectory(Uri url);
}

/// WebDAV 凭据（SET-070 的用户名 + SET-071 的密码）。
///
/// 密码只在这里出现一次：调用方（用例层）在本轮同步期间持有它，传输端口每次调用都要
/// 显式传参，因此「引擎缓存密码」这件事在结构上不存在。
/// **[toString] 刻意不输出密码**（诊断日志会打印对象，不覆盖它等于把秘密写进日志）。
final class SyncCredentials {
  /// 构造凭据。
  const SyncCredentials({required this.username, required this.password});

  /// 用户名（非秘密，可落库）。
  final String username;

  /// 密码/Token（只住 Keychain）。
  final String password;

  @override
  String toString() =>
      'SyncCredentials(username=$username, password=<redacted>)';
}
