// AI 请求、消息与事件（T025；架构 4.3、4.5；多模态图像分量属 T033）。
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

import 'dart:convert';
import 'dart:typed_data';

import 'package:flux/core/core.dart';

import 'tool_call.dart';

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

/// 一条消息（文本 + 可选的图像分量；图像的多模态输入属 T033）。
final class AiMessage {
  /// 构造一条消息。
  const AiMessage({
    required this.role,
    required this.content,
    this.toolCallId,
    this.images = const <AiImagePart>[],
  });

  /// 便捷构造：系统指令。
  const AiMessage.system(this.content)
    : role = AiRole.system,
      toolCallId = null,
      images = const <AiImagePart>[];

  /// 便捷构造：用户输入。
  ///
  /// [images] 是本条消息要发送的图片（T033）。**空列表表示纯文本消息**，适配器据此
  /// 决定把 content 发成字符串还是分量数组；三个协议都不接受一个空的图片数组，因此
  /// 「没有图」在类型上用空列表表达比 null 更不容易在某处漏判。
  const AiMessage.user(this.content, {this.images = const <AiImagePart>[]})
    : role = AiRole.user,
      toolCallId = null;

  /// 便捷构造：模型输出。
  const AiMessage.assistant(this.content)
    : role = AiRole.assistant,
      toolCallId = null,
      images = const <AiImagePart>[];

  /// 便捷构造：工具结果。
  ///
  /// toolCallId 是**协议要求**的回填依据：
  ///   - Chat Completions 的 role=tool 消息必须带 tool_call_id；
  ///   - Responses 的 function_call_output 项必须带 call_id；
  ///   - Anthropic 的 tool_result 内容块必须带 tool_use_id。
  /// 三者字段名不同但语义一致，因此统一到这一个字段（T027 当初把它记为「T032 要做的
  /// 事」，本轮补上）。为 null 表示这条工具结果没有对应的调用 id（例如历史数据或
  /// 手工构造），此时按「没有 id 可填」如实处理，而不是编一个。
  const AiMessage.tool(this.content, {this.toolCallId})
    : role = AiRole.tool,
      images = const <AiImagePart>[];

  /// 角色。
  final AiRole role;

  /// 文本内容。
  final String content;

  /// 工具调用 id（仅 role=tool 时使用；其余角色为 null）。
  final String? toolCallId;

  /// 本条消息携带的图片（T033 的多模态输入）。
  ///
  /// 只在 role=user 上有意义：三个协议的图片分量都挂在**用户消息**上，把图挂在助手/
  /// 工具消息上既没有协议支持，也会让「这段文字是谁说的」变得含糊。因此 assistant 与
  /// tool 的便捷构造把这里写死为空列表，而不是各留一个可填参数。
  final List<AiImagePart> images;

  /// 是否携带图片（适配器据此选择 content 形状）。
  bool get hasImages => images.isNotEmpty;

  @override
  String toString() =>
      'AiMessage(${role.wireName}, ${content.length} chars'
      '${images.isEmpty ? '' : ', ${images.length} images'})';
}

/// 一条消息里的一张图片（T033）。
///
/// 为什么领域层持有**字节**而不是地址：三个协议的图片分量都是「把图交给服务商」，
/// 而 Anthropic 只接受 base64（不接受让服务商去远端取图）；OpenAI 两协议虽然接受
/// URL，但让服务商去取图会把一次受控请求变成一次我们看不到的出网。本工程已用 T021 的
/// 受控管线把图取到本机并校验过（MIME 白名单 + 魔数 + 体积上限 + 解码像素上限），因此
/// 统一以字节形态进入请求，由三个适配器各自编码成自己协议的形状。
///
/// 同时给出 [base64Data] 与 [dataUrl] 而不是在领域层挑一个形状：Anthropic 需要分开的
/// media_type 与 data 两字段，两个 OpenAI 协议需要 data URL。领域层替某一家的形状做
/// 决定，会让「换协议不改业务」这条目标在这一处失效。
final class AiImagePart {
  /// 构造图片分量。
  const AiImagePart({
    required this.bytes,
    required this.mimeType,
    required this.width,
    required this.height,
    this.downsampled = false,
    this.sourceRef,
  });

  /// 图片字节（已过 T021 的 MIME/体积/魔数校验）。
  final Uint8List bytes;

  /// MIME（由魔数嗅探并与其他声明交叉校验后的类型）。
  final String mimeType;

  /// 宽（像素，原始图的尺寸）。
  final int width;

  /// 高（像素，原始图的尺寸）。
  final int height;

  /// 是否为降采样后的产物（SET-065 的单图上限被触发过）。
  ///
  /// 这个标记必须跟着图片一起走到界面与诊断：用户看到「图已缩过」与「图原样送出」是
  /// 两件不同的事，而两者的结果文本会长得一样。
  final bool downsampled;

  /// 图片引用（客户端的材料引用或正文地址）；**只用于诊断与结果标注，不进请求**。
  final String? sourceRef;

  /// 字节数。
  int get byteLength => bytes.length;

  /// base64 数据（Anthropic 的 source.data）。
  String get base64Data => base64Encode(bytes);

  /// data URL（两个 OpenAI 协议的 image_url.url）。
  String get dataUrl => 'data:$mimeType;base64,$base64Data';

  /// 内容摘要：缓存键与「输入变了」的判据用它，而不是地址。
  ///
  /// 用内容哈希而不是地址：同一张图换一个 CDN 地址仍是同一张图（不该让缓存整体失效），
  /// 而同一个地址换了内容则必须失效（否则会把旧图的结论复用到新图上）。
  String get digest => sha256Hex(bytes);

  @override
  String toString() =>
      'AiImagePart($mimeType, ${width}x$height, $byteLength bytes'
      '${downsampled ? ', downsampled' : ''})';
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

/// 模型请求的工具调用（T032）。
///
/// 为什么作为一个**独立事件**而不是塞进 [AiDone] 或 [AiDelta]：
///   - 工具调用不是文本：把它混进 delta 会让「把模型输出当总结文本保存」的调用点
///     悄悄把一段 JSON 存成正文；
///   - 它与 done 的时机也不同：流可能在工具调用之后继续（多轮），而 done 表示本轮结束。
///     协议里 finish_reason=tool_calls 时**没有**终态文本，若只靠 done 传递，调用点
///     必须从 finishReason 字符串反推「这一轮其实是工具调用」——那是一次字符串判断，
///     而字符串判断必然会漏掉某个协议的某一种写法。
///
/// [calls] 由协议响应里的结构化字段解析而来（见 tool_call_parser.dart）。这是**唯一**
/// 的构造路径，因此模型输出的自由文本（含「请调用 fetchPage ...」这类注入）在类型上
/// 没有通往执行器的路。
final class AiToolCalls extends AiEvent {
  /// 构造工具调用事件。
  const AiToolCalls(this.calls);

  /// 本轮流式响应里请求的全部调用（按服务商给出的顺序）。
  final List<ToolCall> calls;

  @override
  String toString() => 'AiToolCalls(${calls.length} calls)';
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
