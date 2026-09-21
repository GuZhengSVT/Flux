// macOS Keychain 凭据存储（T010，架构第 8 节）。
//
// 实现策略：Dart 侧只做「类型化接口 → MethodChannel 调用 → 错误翻译」，真正的
// SecItem* 调用在 macos/Runner/KeychainPlugin.swift。
//
// 关键约束（逐条对应架构第 8 节）：
//   1. kSecClassGenericPassword + 固定 service，不同凭据用 account 区分；
//   2. accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly：
//      `ThisDeviceOnly` 是关键——它明确**不**同步到 iCloud 钥匙串；
//      `AfterFirstUnlock` 让应用在用户解锁过一次之后即可在后台读取（定时总结
//      需要在无人值守时取凭据），同时不要求设备此刻处于解锁前台；
//   3. 只读写 String；
//   4. 错误翻译为 Result Err(StorageError)，itemNotFound 单独一种（isMissing）；
//   5. **绝不明文回退**：通道不可用（例如纯 Dart 单测、缺实现）时返回失败并把
//      isAvailable 报为 false，让上层提示“会话使用或失败”，而不是写文件。
library;

import 'package:flutter/services.dart';

import 'package:flux/core/core.dart';

import 'credential_store.dart';

/// macOS Keychain 存储的 service 名（架构第 8 节的包标识）。
const String fluxKeychainService = 'io.github.guzhengsvt.flux';

/// Keychain 通道名（与 macos/Runner/KeychainPlugin.swift 约定一致）。
const String fluxKeychainChannelName = 'io.github.guzhengsvt.flux/keychain';

/// 通过 MethodChannel 访问 macOS Keychain 的 [CredentialStore]。
final class KeychainCredentialStore implements CredentialStore {
  /// 以可选通道构造；默认使用平台绑定上的同名声道（便于测试替换）。
  KeychainCredentialStore({MethodChannel? channel, String? service})
    : _channel = channel ?? const MethodChannel(fluxKeychainChannelName),
      _service = service ?? fluxKeychainService;

  final MethodChannel _channel;
  final String _service;

  /// 结果缓存：避免每次读写都往返一次平台通道；不确定时保守返回 false。
  bool? _available;

  @override
  Future<Result<String>> read(CredentialKey key) async {
    try {
      final String? value = await _channel.invokeMethod<String>(
        'read',
        <String, Object?>{'service': _service, 'account': key.account},
      );
      if (value == null) {
        return Err<String>(
          StorageError(
            operation: credentialMissingOperation,
            detail: 'no keychain item for ${key.account}',
            isMissing: true,
          ),
        );
      }
      return Ok<String>(value);
    } on PlatformException catch (error, stackTrace) {
      return Err<String>(_translate(error, key, stackTrace));
    } on MissingPluginException catch (error, stackTrace) {
      return Err<String>(_unavailable(error, key, stackTrace));
    }
  }

  @override
  Future<Result<void>> write(CredentialKey key, String value) async {
    try {
      await _channel.invokeMethod<void>('write', <String, Object?>{
        'service': _service,
        'account': key.account,
        'value': value,
      });
      return okUnit();
    } on PlatformException catch (error, stackTrace) {
      return Err<void>(_translate(error, key, stackTrace));
    } on MissingPluginException catch (error, stackTrace) {
      return Err<void>(_unavailable(error, key, stackTrace));
    }
  }

  @override
  Future<Result<void>> delete(CredentialKey key) async {
    try {
      await _channel.invokeMethod<void>('delete', <String, Object?>{
        'service': _service,
        'account': key.account,
      });
      // 条目不存在也返回成功：删除是幂等操作，调用方不需要区分。
      return okUnit();
    } on PlatformException catch (error, stackTrace) {
      return Err<void>(_translate(error, key, stackTrace));
    } on MissingPluginException catch (error, stackTrace) {
      return Err<void>(_unavailable(error, key, stackTrace));
    }
  }

  @override
  Future<Result<bool>> exists(CredentialKey key) async {
    try {
      final bool? present = await _channel.invokeMethod<bool>(
        'exists',
        <String, Object?>{'service': _service, 'account': key.account},
      );
      return Ok<bool>(present ?? false);
    } on PlatformException catch (error, stackTrace) {
      return Err<bool>(_translate(error, key, stackTrace));
    } on MissingPluginException catch (error, stackTrace) {
      return Err<bool>(_unavailable(error, key, stackTrace));
    }
  }

  @override
  Future<bool> isAvailable() async {
    final bool? cached = _available;
    if (cached != null) {
      return cached;
    }
    try {
      final bool? value = await _channel.invokeMethod<bool>('isAvailable');
      _available = value ?? false;
    } on PlatformException {
      _available = false;
    } on MissingPluginException {
      _available = false;
    }
    return _available!;
  }

  /// 把平台错误翻译成类型化错误。
  ///
  /// 只使用平台给出的**错误码**与固定文案，不把原始 message 直接透出：
  /// Keychain 的错误信息可能带回条目名等细节，日志里不需要这些。
  StorageError _translate(
    PlatformException error,
    CredentialKey key,
    StackTrace stackTrace,
  ) {
    final bool missing = error.code == 'itemNotFound';
    return StorageError(
      operation: missing
          ? credentialMissingOperation
          : 'keychain.${error.code}',
      detail: missing ? 'no keychain item for ${key.account}' : error.code,
      isMissing: missing,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  /// 平台通道不可用时的错误（例如纯 Dart 测试环境、未注册插件）。
  ///
  /// 这里**不**回退到内存或文件：静默降级会让用户以为凭据已安全保存。
  /// 上层应据 [isAvailable] == false 提示会话使用或失败。
  StorageError _unavailable(
    Object error,
    CredentialKey key,
    StackTrace stackTrace,
  ) {
    _available = false;
    return StorageError(
      operation: 'keychain.unavailable',
      detail: 'secure storage channel is not available on this platform',
      cause: error,
      stackTrace: stackTrace,
    );
  }
}
