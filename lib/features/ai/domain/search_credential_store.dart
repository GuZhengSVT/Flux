// 搜索服务凭据存取端口（T031；SET-039「与 AI 凭据分开管理」、架构第 8 节）。
//
// 与 [AiCredentialStore] 是**两个**接口而不是一个泛化的「凭据端口」：SET-039 明确
// 要求搜索凭据与 AI 凭据分开管理，而分开的落点就是 Keychain 的**类别前缀**——
// 两处同名（用户可能给一个模型和一个搜索服务都起名 openai）时，共用前缀会让
// 「按名字取凭据」取到另一类的 Key，然后把搜索 Key 当 API Key 发给模型端点。
//
// 两个接口形状相同但类型不同，因此「把模型凭据传给搜索适配器」在编译期就写不出来。
//
// 安全契约（与 AiCredentialStore 逐条一致）：
//   1) 读出的 Key 只用于发起请求，**不进入**日志、异常消息、诊断包、UI 明文持久化；
//   2) 没有安全存储时**不落盘**：返回失败，让上层提示「本次会话可用但不保存」；
//   3) 删除是幂等的：条目不存在也算成功。
library;

import 'package:flux/core/core.dart';

/// 搜索服务凭据存取端口（以服务名为标识）。
abstract interface class SearchCredentialStore {
  /// 读取某个服务名的 Key；未配置时返回 isMissing 为 true 的存储错误。
  Future<Result<String>> read(String identifier);

  /// 写入（或替换）某个服务名的 Key。
  Future<Result<void>> write(String identifier, String apiKey);

  /// 删除某个服务名的 Key（幂等）。
  Future<Result<void>> delete(String identifier);

  /// 某个服务名是否已配置 Key。
  Future<Result<bool>> exists(String identifier);

  /// 该平台是否提供安全存储；false 时上层必须提示「会话使用或失败」。
  Future<bool> isAvailable();
}
