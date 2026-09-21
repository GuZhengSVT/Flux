// 凭据存储接口（T010，架构第 8 节）。
//
// 为什么先定义接口而不是直接调平台通道：
//   - 上层（AI provider、WebDAV、私密订阅）只依赖 [CredentialStore]，测试可用内存
//     实现替换，不必在单元测试里驱动 Keychain；
//   - 平台实现（macOS Keychain / Android Keystore）差异被隔离在
//     lib/infrastructure/platform 内部，不泄漏到业务层；
//   - “没有安全存储时不得明文回退”这条规则需要有一个明确失败的默认实现，
//     而不是让调用方自己记得检查平台。
//
// 安全约束（架构第 8 节，必须在实现里保持）：
//   - Keychain/Keystore 不等于整库加密，也不保护已被攻陷的设备；
//   - 凭据不得写进日志、截图、分享、同步包或明文备份；
//   - **没有可用安全存储时提示会话使用或失败，绝不明文回退到普通存储或文件**；
//   - 写入的是敏感值本身，因此异常文案里不得包含值。
library;

import 'package:flux/core/core.dart';

/// 一个凭据的定位键（对应 Keychain 的 account）。
///
/// 用「类别 + 标识」而不是直接把凭据名当字符串：不同类别的同名凭据（例如两个
/// 提供商的 `token`）必须落在不同条目上，否则会互相覆盖。
final class CredentialKey {
  /// 以类别与标识构造。
  const CredentialKey({required this.category, required this.identifier});

  /// 凭据类别，例如 `ai-provider`、`search-provider`、`feed-auth`、`webdav`。
  final String category;

  /// 类别内的稳定标识，例如提供商别名、订阅 syncId。
  final String identifier;

  /// Keychain account 字符串（类别与标识用分隔符拼接）。
  ///
  /// 用 `:` 分隔并对标识做最小转义：标识里若含 `:` 会让「类别:标识」在解析时
  /// 产生歧义；这里直接把 `:` 替换为 `%3A` 让拼接可逆。
  String get account => '$category:${identifier.replaceAll(':', '%3A')}';

  @override
  bool operator ==(Object other) =>
      other is CredentialKey &&
      other.category == category &&
      other.identifier == identifier;

  @override
  int get hashCode => Object.hash(category, identifier);

  @override
  String toString() => account;
}

/// 凭据存取接口。
///
/// 所有方法返回 [Result]：凭据失败是可预期失败（未登录、权限被拒、条目不存在），
/// 上层需要据此区分「没配过」与「读取失败」并给出不同提示。
abstract interface class CredentialStore {
  /// 读取凭据；不存在时返回 `Err(StorageError(isMissing: true))`。
  Future<Result<String>> read(CredentialKey key);

  /// 写入（或覆盖）凭据。
  Future<Result<void>> write(CredentialKey key, String value);

  /// 删除凭据；条目不存在也视为成功（幂等）。
  Future<Result<void>> delete(CredentialKey key);

  /// 凭据是否存在。
  Future<Result<bool>> exists(CredentialKey key);

  /// 该平台是否提供安全存储能力。
  ///
  /// 返回 false 时上层必须提示「会话使用或失败」，不得改写普通存储。
  Future<bool> isAvailable();
}

/// 会话内存实现：不落盘、进程结束即丢失。
///
/// 用途有二：单元测试的替身；以及在**没有安全存储**的平台上作为明确的降级结果
/// ——它让“本次会话可用但不会持久化”成为显式选择，而不是悄悄写成明文文件。
final class InMemoryCredentialStore implements CredentialStore {
  /// 创建空的内存凭据存储。
  InMemoryCredentialStore();

  final Map<String, String> _entries = <String, String>{};

  @override
  Future<Result<String>> read(CredentialKey key) async {
    final String? value = _entries[key.account];
    if (value == null) {
      return Err<String>(
        StorageError(
          operation: 'credentialStore.read',
          detail: 'no entry for ${key.account}',
          isMissing: true,
        ),
      );
    }
    return Ok<String>(value);
  }

  @override
  Future<Result<void>> write(CredentialKey key, String value) async {
    _entries[key.account] = value;
    return okUnit();
  }

  @override
  Future<Result<void>> delete(CredentialKey key) async {
    _entries.remove(key.account);
    return okUnit();
  }

  @override
  Future<Result<bool>> exists(CredentialKey key) async {
    return Ok<bool>(_entries.containsKey(key.account));
  }

  @override
  Future<bool> isAvailable() async => true;
}

/// Keychain 条目不存在时的错误种类标记。
///
/// 单独区分「条目不存在」与「读取失败」：前者是正常状态（用户还没配过），
/// 后者可能是权限/系统问题，UI 文案与重试策略都不同。
const String credentialMissingOperation = 'credentialStore.read';

/// 判断一个错误是否为「凭据不存在」。
bool isCredentialMissing(AppError error) =>
    error is StorageError &&
    error.isMissing &&
    error.operation == credentialMissingOperation;
