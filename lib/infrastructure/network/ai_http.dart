// AI 适配器的共用件：时限/取消、SSE、错误体读取、请求体构造与 usage 解析（T026）。
//
// 为什么这些放在 infrastructure/network 而不是 features/ai：
//   - 它们全部是**传输层细节**（HTTP 头、SSE 行、JSON 字段名），features 不得 import
//     HTTP 细节（架构 2.2 的依赖方向守卫会拦）；
//   - 两个适配器（Chat Completions / Responses）共用它们，因此必须比适配器更下层，
//     否则会形成「适配器 A import 适配器 B」的怪关系。
//
// 本文件**不含**任何协议判断（哪个字段对应哪个事件）——那是各自适配器的职责；
// 这里只有「两个协议都一样」的部分：错误体读取、usage 字段名的两种映射、
// 请求体的 JSON 形状。
//
// 安全约束：本文件不接收也不记录 API Key（Key 只在适配器里进 Authorization 头）。
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:flux/features/ai/domain/ai_message.dart';
import 'package:flux/features/ai/domain/ai_errors.dart';
import 'package:flux/core/core.dart';

export 'ai_stream_guard.dart';
export 'sse.dart';

/// 错误响应体的读取上限。
///
/// 错误体是**不可信输入**：一个配置错的 Base URL 可能返回几百 MB 的 HTML 错误页。
/// 读它只是为了取 error.type/error.code 这类结构性字段，因此 64 KiB 绰绰有余。
const int defaultAiMaxResponseBytes = 64 * 1024;

/// 构造 Chat Completions 的请求体。
Map<String, Object?> chatCompletionsRequestBody(
  AiRequest request,
  String modelId,
) => <String, Object?>{
  'model': modelId,
  'messages': <Map<String, Object?>>[
    for (final AiMessage message in request.messages)
      chatCompletionsMessage(message),
  ],
  'stream': true,
  // include_usage 让服务商在流的最后发一个只带 usage 的 chunk。不发它就拿不到
  // token 数，而「按服务商统计核算预算」（架构 4.5）依赖这个数字，不能靠本地估算。
  'stream_options': <String, Object?>{'include_usage': true},
  if (request.maxTokens != null) 'max_tokens': request.maxTokens,
  if (request.temperature != null) 'temperature': request.temperature,
  if (request.tools.isNotEmpty)
    'tools': <Map<String, Object?>>[
      for (final AiToolDeclaration tool in request.tools)
        <String, Object?>{
          'type': 'function',
          'function': <String, Object?>{
            'name': tool.name,
            'description': tool.description,
            'parameters': tool.parameters,
          },
        },
    ],
};

/// 把一条消息渲染成 Chat Completions 的 messages 项。
///
/// 工具结果的消息**必须**带 tool_call_id（协议要求）：缺它服务商会返回 400，而那条
/// 400 的表现是「任务失败」，用户完全看不出「只是因为没带上一个 id」。
Map<String, Object?> chatCompletionsMessage(AiMessage message) {
  if (message.role == AiRole.tool) {
    return <String, Object?>{
      'role': 'tool',
      // 没有 id 时不编一个：用一个假的 id 会让服务商把它当成一个不存在的调用
      // （错误更难懂），而缺字段至少是协议层面的明确拒绝。
      if (message.toolCallId != null) 'tool_call_id': message.toolCallId,
      'content': message.content,
    };
  }
  // 带图消息的 content 从**字符串变成分量数组**（T033）：这不是「在字符串里塞点别的」，
  // 而是协议要求的形状差异——把图片塞进字符串会让服务商把 base64 当正文朗读。
  if (message.hasImages) {
    return <String, Object?>{
      'role': message.role.wireName,
      'content': <Map<String, Object?>>[
        if (message.content.isNotEmpty)
          <String, Object?>{'type': 'text', 'text': message.content},
        for (final AiImagePart image in message.images)
          <String, Object?>{
            'type': 'image_url',
            'image_url': <String, Object?>{'url': image.dataUrl},
          },
      ],
    };
  }
  return <String, Object?>{
    'role': message.role.wireName,
    'content': message.content,
  };
}

/// 构造 Responses 的请求体。
///
/// 与 Chat Completions 的**结构差异**（不是改个字段名）：
///   - 输入叫 `input`，且每个 item 的 content 是**分量数组**而非字符串；
///   - 输出上限字段叫 `max_output_tokens`；
///   - 系统指令走顶层 `instructions`，**不是** input 里的一条 role=system。
///     这一点如果按 Chat Completions 的习惯把 system 消息塞进 input，协议并不接受。
Map<String, Object?> responsesRequestBody(AiRequest request, String modelId) {
  final StringBuffer instructions = StringBuffer();
  final List<Map<String, Object?>> input = <Map<String, Object?>>[];
  for (final AiMessage message in request.messages) {
    if (message.role == AiRole.system) {
      if (instructions.isNotEmpty) {
        instructions.write('\n\n');
      }
      instructions.write(message.content);
      continue;
    }
    // 工具结果在 Responses 里是**独立的输出项形状** function_call_output，而不是
    // input 里的一条 role=tool 消息：协议不接受后者。字段名也不是 tool_call_id 而是
    // call_id——这是「两个 OpenAI 协议不能只改 URL」的又一处具体体现。
    if (message.role == AiRole.tool) {
      input.add(<String, Object?>{
        'type': 'function_call_output',
        if (message.toolCallId != null) 'call_id': message.toolCallId,
        'output': message.content,
      });
      continue;
    }
    input.add(<String, Object?>{
      'role': message.role.wireName,
      'content': <Map<String, Object?>>[
        <String, Object?>{'type': 'input_text', 'text': message.content},
        // Responses 的图片分量形状与 Chat Completions 不同（T033）：这里的分量类型叫
        // input_image 且 image_url 是一个**平铺的字符串**，而 Chat Completions 是
        // {'type':'image_url','image_url':{'url': ...}} 的嵌套对象。两处各有夹具钉住。
        for (final AiImagePart image in message.images)
          <String, Object?>{'type': 'input_image', 'image_url': image.dataUrl},
      ],
    });
  }
  return <String, Object?>{
    'model': modelId,
    'input': input,
    if (instructions.isNotEmpty) 'instructions': instructions.toString(),
    if (request.maxTokens != null) 'max_output_tokens': request.maxTokens,
    if (request.temperature != null) 'temperature': request.temperature,
    if (request.tools.isNotEmpty || request.builtInWebSearch)
      'tools': <Map<String, Object?>>[
        if (request.builtInWebSearch)
          <String, Object?>{'type': 'web_search'},
        for (final AiToolDeclaration tool in request.tools)
          <String, Object?>{
            'type': 'function',
            'name': tool.name,
            'description': tool.description,
            'parameters': tool.parameters,
          },
      ],
    'stream': true,
  };
}

/// 解析 Chat Completions 的 usage（prompt_tokens/completion_tokens）。
AiUsage? parseChatCompletionsUsage(Object? raw) {
  if (raw is! Map<Object?, Object?>) {
    return null;
  }
  final int? prompt = _asInt(raw['prompt_tokens']);
  final int? completion = _asInt(raw['completion_tokens']);
  if (prompt == null && completion == null) {
    return null;
  }
  return AiUsage(
    inputTokens: prompt ?? 0,
    outputTokens: completion ?? 0,
    totalTokens: _asInt(raw['total_tokens']),
  );
}

/// 解析 Responses 的 usage（input_tokens/output_tokens）。
AiUsage? parseResponsesUsage(Object? raw) {
  if (raw is! Map<Object?, Object?>) {
    return null;
  }
  final int? input = _asInt(raw['input_tokens']);
  final int? output = _asInt(raw['output_tokens']);
  if (input == null && output == null) {
    return null;
  }
  return AiUsage(
    inputTokens: input ?? 0,
    outputTokens: output ?? 0,
    totalTokens: _asInt(raw['total_tokens']),
  );
}

// ---------------------------------------------------------------------------
// Anthropic Messages（T027）
// ---------------------------------------------------------------------------
//
// 与两个 OpenAI 协议一样，下面这些是**协议事实**（必需头、必需参数、内容块形状、
// 错误类型到状态码的语义），因此与请求体构造、usage 解析放在同一层：共用层必须比
// 适配器更下层，否则会形成「适配器 A import 适配器 B」的怪关系。适配器只负责
// 「哪个事件对应哪个统一事件」。

/// Anthropic 必需的版本头值（anthropic-version）。
///
/// 缺这个头服务商返回 400，**不会**回退到某个默认版本——因此它不是可选元数据，
/// 而是协议的一部分（与 OpenAI 的 Authorization 一样属于「不发就必然失败」）。
const String anthropicVersion = '2023-06-01';

/// Anthropic 特有的「服务过载」状态码。
///
/// 429 表示「你发得太快」（RateLimitError，服从 Retry-After），529 表示「我们这边
/// 过载」。若让 529 落进通用的 5xx 分类，它会变成一个**不可重试**的错误，而它恰恰
/// 是应当稍后重试的一类（重试策略属 T029）。
const int anthropicOverloadedStatus = 529;

/// 过载错误的稳定类别标识（写进 ProviderError.kind，不靠文案匹配）。
const String anthropicOverloadedKind = 'overloaded';

/// Anthropic 的 max_tokens 是**必填**参数（两个 OpenAI 协议都可以省略）。
///
/// 适配器无法从请求之外知道模型的真实输出预算，因此未指定时退回 SET-033 的保守输出
/// 预算（2048），而不是猜一个更大的数字——猜大会真实产生费用与超长报错。有用例断言
/// 这个常量与 ModelCapability.conservativeOutputBudget 保持一致。
const int anthropicDefaultMaxTokens = 2048;

/// 构造 Anthropic Messages 的请求体。
///
/// 与两个 OpenAI 协议的**结构差异**（不是改字段名）：
///   - 认证走头（x-api-key + anthropic-version），请求体里没有认证字段；
///   - 系统指令是**顶层 system**，不是 messages 里的一条 role=system——把 system
///     留在 messages 里会被服务商直接拒绝；
///   - max_tokens **必填**；
///   - 每条消息的 content 是**分量数组**（文本块 / 图片块），而不是字符串。
Map<String, Object?> anthropicMessagesRequestBody(
  AiRequest request,
  String modelId,
) {
  final StringBuffer system = StringBuffer();
  final List<Map<String, Object?>> messages = <Map<String, Object?>>[];
  for (final AiMessage message in request.messages) {
    if (message.role == AiRole.system) {
      if (system.isNotEmpty) {
        system.write('\n\n');
      }
      system.write(message.content);
      continue;
    }
    if (message.role == AiRole.tool) {
      // 工具结果是 user 消息里的一个 tool_result 内容块，且**必须**带 tool_use_id
      // （T027 当初就把这条记为「T032 要做的事」）。把它当普通文本发会让服务商
      // 拒绝或（更糟）让模型把工具产出误读成用户输入。
      messages.add(<String, Object?>{
        'role': 'user',
        'content': <Map<String, Object?>>[
          <String, Object?>{
            'type': 'tool_result',
            if (message.toolCallId != null) 'tool_use_id': message.toolCallId,
            'content': message.content,
          },
        ],
      });
      continue;
    }
    messages.add(<String, Object?>{
      'role': anthropicRoleOf(message.role),
      // 文本块在前、图片块在后（T033）：Anthropic 的图片是 base64 源
      // （source.type = "base64"），**不能**给 URL——协议不接受让服务商去远端取图。
      // 文字在前是因为这些图是「关于这段文字的配图」，倒过来读会让模型先看到图再知道
      // 要它做什么。
      'content': <Map<String, Object?>>[
        if (message.content.isNotEmpty) anthropicTextBlock(message.content),
        for (final AiImagePart image in message.images)
          anthropicImageBlock(
            mediaType: image.mimeType,
            base64Data: image.base64Data,
          ),
      ],
    });
  }
  return <String, Object?>{
    'model': modelId,
    'max_tokens': request.maxTokens ?? anthropicDefaultMaxTokens,
    'messages': messages,
    if (system.isNotEmpty) 'system': system.toString(),
    if (request.temperature != null) 'temperature': request.temperature,
    'stream': true,
    if (request.tools.isNotEmpty)
      'tools': <Map<String, Object?>>[
        for (final AiToolDeclaration tool in request.tools)
          <String, Object?>{
            'name': tool.name,
            'description': tool.description,
            // 与 OpenAI 的 parameters 不同：Anthropic 的字段名是 input_schema，
            // 且没有 {type: "function", function: {...}} 这层包装。
            'input_schema': tool.parameters,
          },
      ],
  };
}

/// Anthropic 的角色取值域只有 user / assistant（没有 system / tool）。
String anthropicRoleOf(AiRole role) => switch (role) {
  AiRole.system => 'user',
  AiRole.user => 'user',
  AiRole.assistant => 'assistant',
  // 规范的 tool_result 是 user 消息里的一个内容块且必须带 tool_use_id，工具结果在
  // 上面那条分支里已经按这个形状构造过了；走到这里只可能是「有人直接构造了一条
  // role=tool 的消息又没走工具分支」，按 user 兜底而不是抛错——静默丢弃会让多轮
  // 工具对话丢上下文，而「多带一段文本」远比「丢一半上下文」安全。
  AiRole.tool => 'user',
};

/// 一个文本内容块。
Map<String, Object?> anthropicTextBlock(String text) => <String, Object?>{
  'type': 'text',
  'text': text,
};

/// 一个图片内容块。
///
/// **图片是 base64 源，不是 URL**：协议不接受让服务商去远端取图（那会把一次请求变成
/// 一次不可控的出网），因此这里显式拼 source.type = "base64"。T027 只用它固化形状
/// 并测试；真正把图片接进请求属 T033 的多模态消息模型。
Map<String, Object?> anthropicImageBlock({
  required String mediaType,
  required String base64Data,
}) => <String, Object?>{
  'type': 'image',
  'source': <String, Object?>{
    'type': 'base64',
    'media_type': mediaType,
    'data': base64Data,
  },
};

/// 解析 Anthropic 的 usage（input_tokens/output_tokens）。
///
/// 协议**不给** total_tokens（与两个 OpenAI 协议不同），因此不在这里拼一个假的总量：
/// 交给 AiUsage.effectiveTotal 标为本地合计。
AiUsage? parseAnthropicUsage(Object? raw) {
  if (raw is! Map<Object?, Object?>) {
    return null;
  }
  final int? input = _asInt(raw['input_tokens']);
  final int? output = _asInt(raw['output_tokens']);
  if (input == null && output == null) {
    return null;
  }
  return AiUsage(inputTokens: input ?? 0, outputTokens: output ?? 0);
}

/// 把 Anthropic 的**错误类型**映射到状态码语义。
///
/// 为什么需要它：Anthropic 可以在 **HTTP 200 的事件流里**发一个 type = "error"
/// 事件。此时没有状态码可用，而共用的分类器只认状态码；若不留这一层，一个
/// 「限流」或「认证失败」会被归成一个 200 的 NetworkError，上层既不知道该等
/// 还是该去改 Key。映射只使用结构化的类型名，不做文案匹配。
int anthropicStatusForErrorType(String? errorType, int fallback) {
  if (errorType == null) {
    return fallback;
  }
  return switch (errorType.trim().toLowerCase()) {
    'authentication_error' => 401,
    'permission_error' => 403,
    'not_found_error' => 404,
    'request_too_large' => 413,
    'rate_limit_error' => 429,
    'api_error' => 500,
    'overloaded_error' => anthropicOverloadedStatus,
    'invalid_request_error' => 400,
    _ => fallback,
  };
}

/// 判断一个 Anthropic 错误是否是过载（状态码 529 或事件里的 overloaded 类型）。
bool isAnthropicOverload({required int statusCode, String? errorType}) {
  if (statusCode == anthropicOverloadedStatus) {
    return true;
  }
  return errorType != null && errorType.toLowerCase().contains('overload');
}

/// 把一个 Anthropic 错误翻译成类型化错误（Anthropic 专属口径）。
///
/// 两处与两个 OpenAI 协议不同，因此不能直接复用 mapAiHttpError：
///   1) **错误类型可能出现在事件流里**（HTTP 200 + type = "error"），此时没有状态码；
///      因此先用 anthropicStatusForErrorType 把类型名换成语义等价的状态码，再交给
///      共用的分类器。若直接用一个 200 兜底，限流与认证失败都会被归成网络错误。
///   2) **529（overloaded）是一个可重试的「稍后再试」**，而通用 5xx 分支把它变成
///      不可重试的 NetworkError。这里显式映射为带 kind 的 ProviderError，并标
///      isRetryable，让 T029 的退避策略能识别它。
///
/// 参数里的 detail 只放结构性字段（错误类型 / 服务商错误码），不放响应体文案。
AppError mapAnthropicError({
  required String provider,
  required Uri endpoint,
  required int statusCode,
  String? errorType,
  String? errorCode,
  Duration? retryAfter,
  Object? cause,
  StackTrace? stackTrace,
}) {
  final int effective = anthropicStatusForErrorType(errorType, statusCode);
  if (isAnthropicOverload(statusCode: effective, errorType: errorType)) {
    return ProviderError(
      provider: provider,
      kind: anthropicOverloadedKind,
      statusCode: effective,
      detail: describeErrorMarkers(errorType, errorCode),
      cause: cause,
      stackTrace: stackTrace,
      // 过载是暂时性的，重试可能成功——这正是它与 401/400 的根本区别。
      isRetryable: true,
    );
  }
  return mapAiHttpError(
    provider: provider,
    endpoint: endpoint,
    statusCode: effective,
    errorType: errorType,
    errorCode: errorCode,
    retryAfter: retryAfter,
    cause: cause,
    stackTrace: stackTrace,
  );
}

/// 有界地读取错误响应体并解析成 JSON 对象；任何失败都返回 null。
///
/// 为什么失败就返回 null 而不是抛错：调用方此刻**已经在处理一个错误**，再让
/// 「错误体读不出来/不是 JSON」覆盖掉真正的状态码信息，会让用户看到「解析失败」
/// 而看不到「401」。状态码与 Retry-After 头在流外已经拿到，足够给出正确分类。
Future<Map<String, Object?>?> readAiErrorBody(
  http.StreamedResponse response, {
  int maxBytes = defaultAiMaxResponseBytes,
}) async {
  try {
    final List<int> bytes = await response.stream
        .takeWhile(_ByteCounter(maxBytes).accept)
        .expand((List<int> chunk) => chunk)
        .toList();
    if (bytes.isEmpty) {
      return null;
    }
    final Object? decoded = jsonDecode(
      utf8.decode(bytes, allowMalformed: true),
    );
    return decoded is Map<String, Object?> ? decoded : null;
  } on Exception {
    return null;
  }
}

/// 计数并判定是否继续接收（超过上限即停止）。
final class _ByteCounter {
  _ByteCounter(this.limit);

  final int limit;
  int _seen = 0;

  bool accept(List<int> chunk) {
    _seen += chunk.length;
    return _seen <= limit;
  }
}

/// 把数值字段收敛为 int（协议有时用 double 表示整数计数）。
int? _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return null;
}

/// 由 Base URL 与协议路径拼接端点（Chat Completions / Responses 共用）。
///
/// 与 features 侧的 aiEndpointFor 保持同一口径（去掉末尾斜杠后追加路径、保留已有
/// 路径段），但**不复用**那个函数：它住在 features/ai/domain，而 infrastructure 反向
/// import features 会把「协议形状由谁决定」这件事弄反——实际上协议形状由服务商决定，
/// features 只登记标识。两处都是三行，且各有测试钉住（见 chat/responses 适配器用例）。
Uri aiEndpoint(String baseUrl, String path) {
  final String trimmed = baseUrl.trim();
  final String withoutTrailingSlash = trimmed.endsWith('/')
      ? trimmed.substring(0, trimmed.length - 1)
      : trimmed;
  return Uri.parse('$withoutTrailingSlash/$path');
}
