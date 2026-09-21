// 统一 SearchProvider 契约（T031；架构 4.3「SearchProvider 统一结果结构」、
// 架构 2.2 的依赖接口「SearchProvider」）。
//
// 契约只回答一件事：**给一个查询，产出一批统一结果**。具体到某家协议怎么拼请求、
// 怎么解响应、怎么映射错误，全部由适配器承担（Tavily / Brave / SearXNG 各一个）。
//
// 为什么返回 [SearchResponse] 而不是裸的 List<SearchResult>：协议里有**三个不属于
// 单条结果的字段**——Tavily 的 answer（服务商直接给出的答案摘要）、response_time
// 与结果总数。若签名只给列表，这三个字段只能被丢弃，而 answer 恰恰是 Tavily 的
// 主要卖点之一；丢弃之后「用 Tavily 检索再让模型总结」会变成一个比协议本身更弱的
// 流程。列表仍然可以通过 response.results 取到。
//
// 错误语义：与 AiProvider 一致——失败以 [AppError] 的类型化子类抛出或包在 Result 里
// 返回（适配器统一返回 [Result]，因为一次检索的失败在调用点总要被分支处理：
// 没配 Key 要提示去配置、限流要提示稍后、超时要提示重试）。
library;

import 'package:flux/core/core.dart';

import 'search_protocol.dart';
import 'search_result.dart';

/// 一次检索的参数。
///
/// 名字用 Request 而不是 Query：core 里已有一个 [SearchQuery]（本地全库检索的参数），
/// 而两者语义完全不同（一个发往第三方搜索服务，一个发给本地 SQLite）。同名会让每个
/// 同时用到两者的文件都必须加前缀，也容易在重构时改错那一个。
final class SearchRequest {
  /// 构造参数。
  const SearchRequest({
    required this.text,
    this.count = 10,
    this.offset,
    this.language,
  });

  /// 查询词。
  final String text;

  /// 期望结果数（SET-040：默认 10，范围 1–20）。
  final int count;

  /// 偏移（仅 Brave 支持；其余协议收到非空 offset 时**必须**报错而不是忽略）。
  final int? offset;

  /// 语言提示（Brave 的 search_lang / SearXNG 的 language）；null 表示不发该参数。
  final String? language;
}

/// 一个可调用的搜索提供者（某个协议下的某个端点）。
abstract interface class SearchProvider {
  /// 本提供者使用的协议标识。
  String get providerId;

  /// 发起一次检索。
  ///
  /// 实现必须遵守：
  ///   1) **不发没有凭据的请求**：协议要求凭据而拿不到时，在发出任何字节之前返回
  ///      类型化错误（[AuthError]），不得先发一次再看 401——那既浪费配额，也会在
  ///      服务商侧留下一次失败记录；
  ///   2) **不把不合格地址写进结果**：结果 URL 必须通过地址守卫；被拒绝的条目
  ///      直接丢弃并计入诊断，而不是带着一个危险地址进入下游；
  ///   3) **不吞错误**：非 2xx 与畸形响应体必须翻译成类型化错误，不得退化成空列表
  ///      ——空列表在界面上表现为「没搜到」，与真实失败无法区分。
  Future<Result<SearchResponse>> search(SearchRequest query);
}

/// 由搜索服务记录构造适配器的工厂（组合根注入）。
///
/// 与 [AiProviderFactory] 同一个理由：适配器需要 http.Client、超时与错误映射，
/// 这些是 infrastructure 的关注点；工厂让「哪个协议由哪个实现承担」只有一个装配点。
abstract interface class SearchProviderFactory {
  /// 为一个搜索服务创建适配器。
  ///
  /// [apiKey] 由调用方从安全存储取出后传入，**不会**被写进日志或 URL（Brave 的
  /// 认证走头，Tavily 走 Authorization 头，SearXNG 走 Authorization 头）；
  /// 空串表示没有凭据，工厂应据此拒绝要求凭据的协议。
  Result<SearchProvider> create({
    required SearchProtocol protocol,
    required String baseUrl,
    required String apiKey,
    Duration timeout = const Duration(seconds: 20),
    int maxResults = 10,
    bool allowPrivateEndpoint = false,
  });
}
