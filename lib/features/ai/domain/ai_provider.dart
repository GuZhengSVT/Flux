// 统一 AIProvider 契约（T025；架构 4.3「三种独立适配器，不能只改 URL」）。
//
// 契约只回答一件事：**给一个请求，产出一串统一事件**。
// 具体到某家协议怎么拼 body、怎么解 SSE、怎么映射错误，全部由适配器承担
// （T026 的 Chat Completions / Responses，T027 的 Anthropic Messages）。
//
// 为什么返回 `Stream<AiEvent>` 而不是 Future<String>：
//   - 流式是首发协议能力（架构 4.3 与 SET-033 的 streaming 能力声明），用一个
//     非流式签名会**结构性地**丢掉增量能力，之后每个调用点都要自己重新拼一遍；
//   - 用量（usage）与结束原因不是「返回值的附属品」，在流式协议里它们是**独立的
//     事件**（见 [AiUsage] 的说明），用事件表达才不会丢。
//
// 错误语义：流在**首次订阅后**才可能发出错误；失败以 [AppError] 的类型化子类抛出
// （RateLimitError/AuthError/ContentFilteredError/NetworkError/CancelledError 等）。
// 之所以允许抛出而不是包一层 `Result<Stream<...>>`：流已经建立之后再发生的失败
// 无法用「建立前的返回值」表达——那正是适配器最容易漏掉的一类失败。
library;

import 'package:flux/core/core.dart';

import 'ai_message.dart';

/// 一个可调用的 AI 提供者（某个协议下的某个模型）。
abstract interface class AiProvider {
  /// 发起一次生成调用，产出增量文本、用量与完成事件。
  ///
  /// 实现必须遵守：
  ///   1) **取消**：request.cancellation 触发后停止读取并结束流（不得继续解析、
  ///      不得继续把已经收到的内容再发出去）；
  ///   2) **不吞错误**：协议错误体必须翻译成类型化错误抛出，不得退化成空流——
  ///      空流在 UI 上表现为「模型没说话」，与真实失败无法区分；
  ///   3) **Stream 单次消费**：调用方不得多次 listen（由调用点保证）。
  Stream<AiEvent> generate(AiRequest request);
}

/// 由模型记录构造适配器的工厂（组合根注入，T026 提供真实实现）。
///
/// 为什么是一个显式工厂而不是「在 ModelManager 里 switch 协议」：
/// 适配器需要 http.Client、超时配置、取消与错误映射，这些都是 infrastructure 的
/// 关注点；把它们放进 features 的用例层会让 features 依赖 HTTP 细节（架构 2.2 的
/// 依赖方向守卫会拦）。工厂让「哪个协议由哪个实现承担」只有一个装配点。
abstract interface class AiProviderFactory {
  /// 为一个模型创建适配器。
  ///
  /// [apiKey] 由调用方从安全存储取出后传入，**不会**被工厂或适配器写进日志或 URL；
  /// [baseUrl] 与 [modelId] 来自模型记录。
  ///
  /// 返回 Result 而不是抛异常：`协议尚未实现`（例如 T025 期间的 Anthropic）与
  /// `Base URL 非法` 都是可预期的配置问题，调用方需要把它们变成界面提示，
  /// 而不是让一次点击崩掉整页。
  Result<AiProvider> create({
    required String alias,
    required String protocolId,
    required String baseUrl,
    required String modelId,
    required String apiKey,
  });
}
