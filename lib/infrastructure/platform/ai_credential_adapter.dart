// 把 T010 的 [CredentialStore] 接到 features 侧的 AiCredentialStore 端口上
// （T025；架构 2.2 的依赖方向）。
//
// 为什么需要适配器而不是让 features 直接用 CredentialStore：
//   CredentialStore 住在 infrastructure/platform，features 不得 import 它（测试会拦）。
//   适配器住在 infrastructure，由组合根注入，features 只看到自己的窄接口。
//
// 这一层**不加工**任何值：读出来的 Key 原样返回（不做「顺手 trim」之类的处理——
// 静默改写凭据会让一个本来能用的 Key 变得不能用）。本文件也不产生任何日志，
// 因此 Key 不可能被这一层写出去。
library;

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/domain/ai_credential_store.dart';

import 'credential_store.dart';

/// AI 提供商凭据的类别（Keychain account 前缀）。
///
/// 与 features 侧模型记录的凭据标识口径一致：同别名共用一份凭据（界面上「一个提供商
/// 填一次 Key」）。这里显式写字符串而不是 import features 的常量：适配器的职责只是
/// 转发，让「改类别名」不必跨越一次分层改动。
const String aiProviderCredentialCategory = 'ai-provider';

/// 适配器。
final class AiCredentialStoreAdapter implements AiCredentialStore {
  /// 绑定一个底层凭据存储。
  const AiCredentialStoreAdapter(this._inner);

  final CredentialStore _inner;

  @override
  Future<Result<String>> read(String alias) => _inner.read(_key(alias));

  @override
  Future<Result<void>> write(String alias, String apiKey) =>
      _inner.write(_key(alias), apiKey);

  @override
  Future<Result<void>> delete(String alias) => _inner.delete(_key(alias));

  @override
  Future<Result<bool>> exists(String alias) => _inner.exists(_key(alias));

  @override
  Future<bool> isAvailable() => _inner.isAvailable();

  static CredentialKey _key(String alias) =>
      CredentialKey(category: aiProviderCredentialCategory, identifier: alias);
}
