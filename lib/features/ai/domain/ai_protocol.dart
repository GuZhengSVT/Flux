// AI 协议标识（T025；架构 4.3「三种独立适配器，不能只改 URL」）。
//
// 为什么协议是一个显式枚举而不是「从 baseUrl 猜」：
//   OpenAI 的 Chat Completions 与 Responses 在**同一个域名**下并存（/chat/completions
//   与 /responses），请求体、事件流、错误体结构与 usage 字段名都不同。若协议由地址推断，
//   一个自建或代理端点（例如 https://api.deepseek.com）就永远无法确定该用哪套模型，
//   适配器只能在运行时才发现「拿到的 JSON 不是我以为的形状」。
//
// 协议名是**稳定字符串**（落库、诊断、fixture 名都用它），不依赖枚举序号。
library;

/// 一个 AI 协议（请求形状 + 事件流形状 + 错误体形状的唯一标识）。
enum AiProtocol {
  /// OpenAI Chat Completions（`POST {base}/chat/completions`）及其兼容实现。
  openAiChatCompletions(
    id: 'openai.chat_completions',
    path: 'chat/completions',
    label: 'OpenAI Chat Completions',
  ),

  /// OpenAI Responses（`POST {base}/responses`）。
  openAiResponses(
    id: 'openai.responses',
    path: 'responses',
    label: 'OpenAI Responses',
  ),

  /// Anthropic Messages（`POST {base}/messages`）。
  ///
  /// T025 只登记协议本身（能力声明、模型记录、UI 选择项），**适配器属 T027**。
  /// 把「协议已登记」与「适配器已实现」分开，是为了让「列出了这个选项」不等于
  /// 「这个选项真的能用」——见 [hasAdapter]。
  anthropicMessages(
    id: 'anthropic.messages',
    path: 'messages',
    label: 'Anthropic Messages',
  );

  const AiProtocol({required this.id, required this.path, required this.label});

  /// 稳定协议标识（落库与诊断用；不改写）。
  final String id;

  /// 相对 Base URL 的请求路径（不含前导斜杠）。
  final String path;

  /// 界面展示名（不是本地化文案：协议名是产品专有名词，中英一致）。
  final String label;

  /// 本协议当前是否已有适配器实现。
  ///
  /// 只有 [openAiChatCompletions] 与 [openAiResponses] 在 T026 落地；
  /// [anthropicMessages] 的实现属 T027。UI 必须据此把未实现的协议明确标成
  /// 「待实现」，而不是让用户选完、配置完、点测试才发现没有实现。
  bool get hasAdapter => this != AiProtocol.anthropicMessages;

  /// 找不到适配器时给出的原因（写进错误信息，不让用户猜）。
  String get missingAdapterReason => '协议 $label 的适配器尚未实现（T027）';

  /// 由稳定标识还原协议；未知标识返回 null（调用方据此报校验错误）。
  static AiProtocol? fromId(String? id) {
    for (final AiProtocol protocol in AiProtocol.values) {
      if (protocol.id == id) {
        return protocol;
      }
    }
    return null;
  }
}
