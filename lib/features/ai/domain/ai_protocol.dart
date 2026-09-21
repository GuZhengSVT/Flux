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
  /// 适配器在 T027 落地（[AnthropicMessagesAdapter]）。T025 期间这个协议只被登记，
  /// UI 会明确标成「适配器待实现」；把「协议已登记」与「适配器已实现」分开，是为了让
  /// 「列出了这个选项」不等于「这个选项真的能用」——见 [hasAdapter]。
  anthropicMessages(
    id: 'anthropic.messages',
    path: 'messages',
    label: 'Anthropic Messages',
    // 显式写出：T027 落地了这个协议的适配器，因此它不再是「已登记但待实现」。
    adapterImplemented: true,
  );

  const AiProtocol({
    required this.id,
    required this.path,
    required this.label,
    this.adapterImplemented = true,
  });

  /// 稳定协议标识（落库与诊断用；不改写）。
  final String id;

  /// 相对 Base URL 的请求路径（不含前导斜杠）。
  final String path;

  /// 界面展示名（不是本地化文案：协议名是产品专有名词，中英一致）。
  final String label;

  /// 该协议的适配器是否已实现。
  ///
  /// 用**数据**表达，而不是在 [hasAdapter] 里写死一个协议名的判断：将来新增一个
  /// 「先登记协议、适配器留给后续任务」的条目时，只需在枚举里写
  /// adapterImplemented: false，UI 与 ModelManager 就会自动把它标成「待实现」并
  /// 拒绝调用，不需要改动判断逻辑本身。
  final bool adapterImplemented;

  /// 本协议当前是否已有适配器实现。
  ///
  /// T026/T027 之后三个协议的适配器都已落地，因此当前恒为 true；保留这个属性
  /// （而不是删掉）是为了让「列出了这个选项」与「这个选项真的能用」在类型上继续
  /// 分开——判据见 [adapterImplemented]。
  bool get hasAdapter => adapterImplemented;

  /// 找不到适配器时给出的原因（写进错误信息，不让用户猜）。
  String get missingAdapterReason => '协议 $label 的适配器尚未实现';

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
