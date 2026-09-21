// AI 请求、消息与事件（T025；架构 4.3、4.5）。
//
// 这一层刻意**只描述统一语义**，不含任何一家服务商的字段名：
//   - Chat Completions 的 `messages[{role, content}]` 与
//     Responses 的 `input[{role, content:[{type, text}]}]` 形状完全不同，
//     统一到 [AiMessage] 之后由各自适配器负责翻译（T026）；
//   - usage 字段名也不同（prompt_tokens/completion_tokens vs input_tokens/output_tokens），
//     统一到 [AiUsage]。
//
// 为什么不在这里放 HTTP 细节（状态码、头、body 文本）：那是适配器的职责；
// 领域层带上一半的传输语义会让「换协议不改业务」这条设计目标失效。
library;

/// 消息角色（四类，与 OpenAI 兼容协议一致）。
enum AiRole {
  /// 系统指令。
  system,

  /// 用户输入。
  user,

  /// 模型输出（多轮对话里回填历史）。
  assistant,

  /// 工具执行结果（T032 的工具执行器回填）。
  tool;

  /// 线格式名（协议字段值）。
  String get wireName => name;
}

/// 一条消息（文本形态；图片等多模态分量属 T033）。
final class AiMessage {
  /// 构造一条消息。
  const AiMessage({required this.role, required this.content});

  /// 便捷构造：系统指令。
  const AiMessage.system(this.content) : role = AiRole.system;

  /// 便捷构造：用户输入。
  const AiMessage.user(this.content) : role = AiRole.user;

  /// 便捷构造：模型输出。
  const AiMessage.assistant(this.content) : role = AiRole.assistant;

  /// 便捷构造：工具结果。
  const AiMessage.tool(this.content) : role = AiRole.tool;

  /// 角色。
  final AiRole role;

  /// 文本内容。
  final String content;

  @override
  String toString() => 'AiMessage(${role.wireName}, ${content.length} chars)';
}

/// 一次生成请求。
///
/// [cancellation] 是**统一取消信号**：取消不是异常路径的附带品，而是显式字段，
/// 这样适配器（T026）与队列（T029）都在同一个语义上工作，审查时也能看到
/// 「这个请求是否可取消」。
final class AiRequest {
  /// 构造请求。
  AiRequest({
    required this.modelId,
    required this.messages,
    this.maxTokens,
    this.temperature,
    this.tools = const <AiToolDeclaration>[],
    AiCancellation? cancellation,
  }) : cancellation = cancellation ?? AiCancellation();

  /// 模型 ID（服务商侧的模型名，例如 `deepseek-chat`）。
  final String modelId;

  /// 消息序列（顺序即上下文顺序）。
  final List<AiMessage> messages;

  /// 输出上限（token）；null 表示交给服务商默认值。
  ///
  /// 注意：这不等于模型的上下文上限——上下文预算由
  /// [ModelCapability.contextWindow] 决定（SET-033）。
  final int? maxTokens;

  /// 采样温度；null 表示不发送该字段（用服务商默认）。
  final double? temperature;

  /// 工具声明（T032 使用；空列表表示不发送 tools 字段）。
  final List<AiToolDeclaration> tools;

  /// 取消信号。
  final AiCancellation cancellation;
}

/// 工具声明（架构 4.3 的工具层：search / fetchPage / inspectImage）。
///
/// T025 只定义**声明**（名称、说明、参数 JSON Schema）；执行器与安全边界属 T032。
final class AiToolDeclaration {
  /// 声明一个函数式工具。
  const AiToolDeclaration({
    required this.name,
    required this.description,
    required this.parameters,
  });

  /// 工具名（模型回填时用它匹配）。
  final String name;

  /// 用途说明。
  final String description;

  /// 参数 JSON Schema（原样发给服务商，不做本地改写）。
  final Map<String, Object?> parameters;
}

/// 流式事件（统一三态：增量文本、用量、完成）。
sealed class AiEvent {
  const AiEvent();
}

/// 一段增量文本。
final class AiDelta extends AiEvent {
  /// 构造增量文本。
  const AiDelta(this.text);

  /// 本次增量（可以是空串：协议允许空 delta，例如只带角色或只带 usage 的 chunk）。
  final String text;
}

/// 用量统计。
///
/// 为什么把 usage 单独作为事件而不是塞进 [AiDone]：两个协议给出 usage 的时机不同
/// （Chat Completions 常在最后一个 `choices: []` 的 chunk 里，Responses 在
/// `response.completed` 事件里），而**计费与预算**只关心「拿到了没有」。
/// 拆开之后消费者不必猜「done 里到底有没有 usage」。
final class AiUsage extends AiEvent {
  /// 构造用量。
  const AiUsage({
    required this.inputTokens,
    required this.outputTokens,
    this.totalTokens,
  });

  /// 输入（提示）token 数。
  final int inputTokens;

  /// 输出（补全）token 数。
  final int outputTokens;

  /// 总 token 数；服务商未给出时为 null（不要本地拼一个假的数字当事实）。
  final int? totalTokens;

  /// 总量：服务商给了就用，没给则用输入 + 输出，并标记为**本地合计**。
  int get effectiveTotal => totalTokens ?? (inputTokens + outputTokens);

  /// 总量是否为本地合计（而非服务商统计）。预算与展示需要区分这一点。
  bool get totalIsEstimated => totalTokens == null;
}

/// 生成完成。
final class AiDone extends AiEvent {
  /// 构造完成事件。
  const AiDone({this.finishReason});

  /// 服务商给出的结束原因（例如 `stop`、`length`）；未给出时为 null。
  final String? finishReason;
}

/// 取消信号。
///
/// 两条实现契约：
///   1) **幂等**：重复取消无害，只有第一次算触发；
///   2) **登记即在取消后立刻回调**：适配器可能在建立连接之后才登记回调，此时取消
///      若已发生，只等待「未来的取消」会让它一直挂到超时。
final class AiCancellation {
  /// 构造未取消的信号。
  AiCancellation();

  final List<void Function()> _listeners = <void Function()>[];
  bool _cancelled = false;
  String? _reason;

  /// 是否已取消。
  bool get isCancelled => _cancelled;

  /// 取消原因（仅诊断用，不含用户内容）。
  String? get reason => _reason;

  /// 取消；重复调用无害。返回是否**首次**触发取消。
  bool cancel({String? reason}) {
    if (_cancelled) {
      return false;
    }
    _reason = reason;
    _cancelled = true;
    // 复制一份再遍历：回调里移除自己是常见写法，不应影响本次派发。
    for (final void Function() listener in List<void Function()>.of(
      _listeners,
    )) {
      listener();
    }
    _listeners.clear();
    return true;
  }

  /// 注册一次取消回调；若**已经**取消则立即同步调用一次。
  void addListener(void Function() listener) {
    if (_cancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  /// 移除回调（重复移除无害）。
  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }
}
