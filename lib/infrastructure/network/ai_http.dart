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
      <String, Object?>{
        'role': message.role.wireName,
        'content': message.content,
      },
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
    input.add(<String, Object?>{
      'role': message.role.wireName,
      'content': <Map<String, Object?>>[
        <String, Object?>{'type': 'input_text', 'text': message.content},
      ],
    });
  }
  return <String, Object?>{
    'model': modelId,
    'input': input,
    if (instructions.isNotEmpty) 'instructions': instructions.toString(),
    if (request.maxTokens != null) 'max_output_tokens': request.maxTokens,
    if (request.temperature != null) 'temperature': request.temperature,
    if (request.tools.isNotEmpty)
      'tools': <Map<String, Object?>>[
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
