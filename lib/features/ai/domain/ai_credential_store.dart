// AI 凭据存取端口（T025；SET-031「遮盖，可替换/删除/显示；不写日志」）。
//
// 为什么需要这一层端口而不是让 features 直接用 T010 的 CredentialStore：
//   features 不得 import infrastructure（架构 2.2，测试会拦截）。Keychain 的实现
//   属于 infrastructure/platform，因此这里只声明「按别名读写一份 Key」的能力，
//   由组合根把真实 Keychain 适配上来（见 lib/app/app_providers.dart）。
//
// 安全契约（架构第 8 节，实现与调用方都必须守）：
//   1) 读出的 Key 只用于发起请求，**不进入**日志、异常消息、诊断包、UI 明文的持久化；
//   2) 没有安全存储时**不落盘**：返回失败，让上层提示「本次会话可用但不保存」，
//      绝不改写普通表或文件；
//   3) 删除是幂等的：条目不存在也算成功。
library;

import 'package:flux/core/core.dart';

/// AI 凭据存取端口（以提供商别名为标识）。
abstract interface class AiCredentialStore {
  /// 读取某个别名的 Key；未配置时返回 `Err(StorageError(isMissing: true))`。
  Future<Result<String>> read(String alias);

  /// 写入（或替换）某个别名的 Key。
  Future<Result<void>> write(String alias, String apiKey);

  /// 删除某个别名的 Key（幂等）。
  Future<Result<void>> delete(String alias);

  /// 某个别名是否已配置 Key。
  Future<Result<bool>> exists(String alias);

  /// 该平台是否提供安全存储；false 时上层必须提示「会话使用或失败」。
  Future<bool> isAvailable();
}
