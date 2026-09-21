// 提供商预设目录与验证状态（T028；SET-030「预设端点来自验证清单」）。
//
// 预设回答的是「这家服务商怎么接」，**不是**「这家服务商能用」：
//   - 协议 + Base URL + 认证方式 = 一个预设的全部内容；
//   - 状态标记记录**本轮真的做到了哪一步**（fixture 级 / 实测 / 待验证），
//     它是数据而不是文案：界面据此显示徽章，矩阵据此逐行填表。
//
// 为什么状态要与预设绑在一起而不是写在文档里：架构说明书第 174 行明确要求「未验证的
// 条目标明待验证/不可用」。若状态只存在于手册表格里，界面就会把一个从没调通过的端点
// 展示成「可用」，用户点下去才发现——而「列出来了」不等于「验证过了」正是这条要求
// 要防的。
//
// 安全边界（架构第 8 节）：预设里**没有**任何凭据字段。预设只是模板，Key 永远由用户
// 在模型表单里手填、只住 Keychain。
library;

import 'ai_protocol.dart';

/// 一个预设的验证状态（互斥的三档，不写「部分可用」这类含糊说法）。
enum PresetVerificationStatus {
  /// **实测**：本轮真的对真实端点发过调用并成功（有对应的轮次记录）。
  liveVerified,

  /// **fixture 通过**：该协议的适配器有完整夹具级证据，但没对真实端点发过调用。
  fixtureVerified,

  /// **待验证**：既没有实测，也没有针对该端点的夹具证据（通常是没有凭据）。
  unverified,
}

/// 一个预设的认证方式。
///
/// 用枚举而不是「头名 + 头值」的自由字符串：认证方式是**协议事实**的一部分
/// （Anthropic 用 x-api-key 加版本头，其余用 Authorization Bearer），把它写成自由
/// 文本会让界面可以显示一个与适配器实际行为不一致的说明。
enum PresetAuthScheme {
  /// Authorization: Bearer（OpenAI 及其兼容端点）。
  bearer,

  /// x-api-key 加 anthropic-version（Anthropic Messages）。
  anthropicApiKey,
}

/// 一个提供商预设。
final class ProviderPreset {
  /// 构造预设。
  const ProviderPreset({
    required this.id,
    required this.displayName,
    required this.protocol,
    required this.baseUrl,
    required this.authScheme,
    required this.status,
    required this.note,
  });

  /// 稳定标识（落库在 AiModel.preset 里；不改写）。
  ///
  /// 用稳定字符串而不是显示名：显示名会翻译、会调整措辞，而落库的值必须能被后续
  /// 版本重新识别（否则「这条记录当初选的是哪个预设」就丢了）。
  final String id;

  /// 界面显示名（产品专有名词，中英一致）。
  final String displayName;

  /// 该预设使用的协议。
  final AiProtocol protocol;

  /// Base URL。
  ///
  /// **这是「适配器要拼接的前缀」，不是「厂商官网列出的主机」**。两者在多数厂商上一致
  /// （DeepSeek 的 https://api.deepseek.com），但在 OpenAI 上不同：适配器按
  /// {base}/{protocol.path} 拼接，因此 Base URL 必须已经包含 /v1，否则会得到
  /// https://api.openai.com/chat/completions（缺 /v1，必然是 404）。差异在 [note] 里
  /// 写明，不靠用户猜。
  final String baseUrl;

  /// 认证方式。
  final PresetAuthScheme authScheme;

  /// 验证状态（本轮真的做到了哪一步）。
  final PresetVerificationStatus status;

  /// 注释：端点口径、待确认点、与厂商文档的差异。
  final String note;

  /// 适配器实际请求的完整端点（{base}/{protocol.path}）。
  ///
  /// 复刻 aiEndpointFor 的口径（去尾斜杠后追加路径）；单独给出是为了让「预设填进表单
  /// 后，最终会请求哪个地址」在数据层就能核对，而不必先在界面上点一遍。
  Uri get endpoint {
    final String trimmed = baseUrl.trim();
    final String withoutTrailingSlash = trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
    return Uri.parse('$withoutTrailingSlash/${protocol.path}');
  }

  /// 该预设是否可以标成「已支持」（只有实测才允许）。
  bool get isSupported => status == PresetVerificationStatus.liveVerified;
}

/// 预设目录（T028 的验证矩阵的**数据来源**）。
///
/// 端点与协议映射来自主代理提供的协议事实（检索于 2026-09-22）。状态是本轮的**真实
/// 结果**，逐条可核对：
///   - DeepSeek：实测 1 次成功（见 R026），因此 liveVerified；
///   - OpenAI CC / OpenAI Responses / Anthropic：适配器各有完整夹具级证据，但本轮
///     **没有**为它们做真实调用（无凭据），因此 fixtureVerified；
///   - Qwen / MiMo / OpenCode Zen：协议形状可用（CC 兼容），但**该端点的预设本身**未做
///     任何真实调用，因此 unverified（不因为它们「看起来像 CC」就升级状态）。
abstract final class PresetCatalog {
  /// 全部预设（顺序即界面下拉的顺序）。
  static const List<ProviderPreset> all = <ProviderPreset>[
    ProviderPreset(
      id: 'openai.chat_completions',
      displayName: 'OpenAI（Chat Completions）',
      protocol: AiProtocol.openAiChatCompletions,
      baseUrl: 'https://api.openai.com/v1',
      authScheme: PresetAuthScheme.bearer,
      status: PresetVerificationStatus.fixtureVerified,
      note:
          '厂商文档列出的主机是 https://api.openai.com；适配器按 {base}/chat/completions '
          '拼接，因此这里带 /v1，最终请求 https://api.openai.com/v1/chat/completions。'
          '适配器有完整夹具级证据；本轮无凭据，未做真实调用。',
    ),
    ProviderPreset(
      id: 'openai.responses',
      displayName: 'OpenAI（Responses）',
      protocol: AiProtocol.openAiResponses,
      baseUrl: 'https://api.openai.com/v1',
      authScheme: PresetAuthScheme.bearer,
      status: PresetVerificationStatus.fixtureVerified,
      note:
          '同一主机下的另一条路径（/v1/responses），请求体、事件流与 usage 字段名都与 '
          'Chat Completions 不同，因此是两个独立预设而不是一个参数。适配器有夹具级证据；'
          '本轮无凭据，未做真实调用。',
    ),
    ProviderPreset(
      id: 'anthropic.messages',
      displayName: 'Anthropic',
      protocol: AiProtocol.anthropicMessages,
      baseUrl: 'https://api.anthropic.com/v1',
      authScheme: PresetAuthScheme.anthropicApiKey,
      status: PresetVerificationStatus.fixtureVerified,
      note:
          '认证用 x-api-key 加 anthropic-version（不是 Authorization Bearer）；system 是'
          '顶层参数、max_tokens 必填。适配器在 T027 落地并有完整夹具级证据；本轮无凭据，'
          '未做真实调用。',
    ),
    ProviderPreset(
      id: 'deepseek',
      displayName: 'DeepSeek',
      protocol: AiProtocol.openAiChatCompletions,
      baseUrl: 'https://api.deepseek.com',
      authScheme: PresetAuthScheme.bearer,
      status: PresetVerificationStatus.liveVerified,
      note:
          'Chat Completions 兼容端点，路径 /chat/completions 由适配器追加。**本轮唯一'
          '实测的预设**：deepseek-chat 一次最小生成成功（709 ms / 20 输入 / 2 输出 token / '
          'finish=stop），见 R026。同账号其它模型未测。',
    ),
    ProviderPreset(
      id: 'qwen',
      displayName: '千问 / Qwen',
      protocol: AiProtocol.openAiChatCompletions,
      baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      authScheme: PresetAuthScheme.bearer,
      status: PresetVerificationStatus.unverified,
      note:
          'DashScope 的 OpenAI 兼容模式。协议形状是 Chat Completions（适配器已有夹具），'
          '但**该端点本身**本轮未做任何真实调用（无凭据），因此状态是待验证而不是'
          '「fixture 通过」——预设的端点必须逐个验证，不能因为共用协议就继承状态。',
    ),
    ProviderPreset(
      id: 'mimo',
      displayName: 'MiMo（小米开放平台）',
      protocol: AiProtocol.openAiChatCompletions,
      baseUrl: 'https://api.xiaomimimo.com',
      authScheme: PresetAuthScheme.bearer,
      status: PresetVerificationStatus.unverified,
      note:
          '**端点待真实验证**：主机与路径口径按主代理提供的协议事实登记，本轮未做任何'
          '真实调用（无凭据），因此实际可用的路径（是否需要 /v1 等）尚未确认，预设标注'
          '为待验证。',
    ),
    ProviderPreset(
      id: 'opencode.zen',
      displayName: 'OpenCode Zen',
      protocol: AiProtocol.openAiChatCompletions,
      baseUrl: 'https://opencode.ai/zen',
      authScheme: PresetAuthScheme.bearer,
      status: PresetVerificationStatus.unverified,
      note:
          '**端点待真实验证**：这是 OpenCode 的公开 API 产品（Zen），不是它的编码 CLI。'
          '本轮用无效 Key 探了一次 POST https://opencode.ai/zen/v1/chat/completions，'
          '返回 401，响应体是 type=error / error.type=ModelError 的形状——**不是** OpenAI '
          '的 error.type/error.code，且实际路径是否带 /v1 未确认，因此端点口径（是否需要 '
          '/v1、错误体是否兼容）仍需真实凭据验证。',
    ),
  ];

  /// 按稳定标识查找预设；未知标识返回 null（自定义模型没有预设）。
  static ProviderPreset? byId(String? id) {
    if (id == null) {
      return null;
    }
    for (final ProviderPreset preset in all) {
      if (preset.id == id) {
        return preset;
      }
    }
    return null;
  }

  /// 指定协议的预设（界面可在选完协议后只列出兼容的预设）。
  static List<ProviderPreset> forProtocol(AiProtocol protocol) => all
      .where((ProviderPreset preset) => preset.protocol == protocol)
      .toList(growable: false);

  /// 是否已有任何预设达到「实测」。
  static bool get hasLiveVerified =>
      all.any((ProviderPreset preset) => preset.isSupported);
}
