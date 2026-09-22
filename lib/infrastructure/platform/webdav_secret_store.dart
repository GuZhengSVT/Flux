// WebDAV 密码的安全存储适配（T044；SET-071、架构第 8 节）。
//
// 为什么密码必须走 Keychain 而不是设置表：
//   * 设置表是**明文**的（会被明文备份与 T041 的同步投影带走）；
//   * SET-071 在注册表里是 S 类，写入普通存储会被 SettingsValidator 明确拒绝——
//     这条拒绝不是限制，而是「密码不可能被写到那儿」的保证。
//
// 这一层是纯转发：不加工值（不 trim、不 base64）、不产生日志。类别前缀固定为 webdav，
// 因此它不会与 feed-auth / ai-provider / search-service 的凭据互相覆盖（同名也各是各的）。
library;

import 'package:flux/core/core.dart';
import 'package:flux/features/sync/application/sync_settings.dart';

import 'credential_store.dart';

/// WebDAV 凭据的类别（Keychain account 前缀）。
const String webdavCredentialCategory = 'webdav';

/// 单份 WebDAV 密码的标识（一台设备只有一份同步凭据）。
const String webdavCredentialIdentifier = 'sync';

/// 基于 [CredentialStore] 的同步凭据端口。
final class WebDavSyncSecretStore implements SyncSecretStore {
  /// 绑定底层凭据存储。
  const WebDavSyncSecretStore(this._inner);

  final CredentialStore _inner;

  static const CredentialKey _key = CredentialKey(
    category: webdavCredentialCategory,
    identifier: webdavCredentialIdentifier,
  );

  @override
  Future<Result<String>> readPassword() => _inner.read(_key);

  @override
  Future<Result<void>> writePassword(String password) =>
      _inner.write(_key, password);

  @override
  Future<Result<void>> deletePassword() => _inner.delete(_key);

  @override
  Future<Result<bool>> hasPassword() => _inner.exists(_key);

  @override
  Future<bool> isAvailable() => _inner.isAvailable();
}
