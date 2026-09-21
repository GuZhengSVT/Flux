// OpenAI Chat Completions 适配器（T026；协议事实来源：主代理提供，检索于 2026-09-22）。
//
// 请求（POST {base}/chat/completions）：
//   {model, messages:[{role, content}], stream:true,
//    stream_options:{include_usage:true}, max_tokens, temperature, tools?}
//
// SSE：行 "data: {json}"，终止 "data: [DONE]"；
//   chunk 形状 {choices:[{delta:{content?, tool_calls?}}], usage?}，
//   **usage 通常只在最后一个 choices 为空数组的 chunk 里出现**（include_usage 时）。
//
// 错误体：{"error":{"message","type","code"}}；
//   429 rate_limit_exceeded（带 Retry-After 时服从）、401 authentication、
//   400 content_filter。
//
// 与 Responses 的**本质差别**（因此不能只改 URL）：
//   - 请求体是 messages 而不是 input items；
//   - 输出是 chunk 里的 choices[].delta，而不是带 type 的事件对象；
//   - usage 字段名是 prompt_tokens/completion_tokens，而不是 input_tokens/output_tokens；
//   - 结束原因是 chunk 里的 finish_reason，而不是 response.completed 的 response.status。
//   这些差异各自有 fixture（见 test/features/ai/chat_completions_adapter_test.dart）。
//
// 安全边界：API Key 只出现在 Authorization 头里，**从不**拼进 URL、日志或异常消息；
// 本文件里没有任何一处把 key 插值进字符串。
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/domain/ai_errors.dart';
import 'package:flux/features/ai/domain/ai_message.dart';
import 'package:flux/features/ai/domain/ai_provider.dart';
import 'package:flux/features/ai/domain/tool_call.dart';
import 'package:flux/features/ai/domain/tool_call_parser.dart';

import 'ai_http.dart';

/// Chat Completions 适配器。
final class ChatCompletionsAdapter implements AiProvider {
  /// 构造适配器。
  ChatCompletionsAdapter({
    required this.alias,
    required this.baseUrl,
    required this.modelId,
    required this.apiKey,
    this.client,
    this.timeouts = const AiStreamTimeouts(),
    this.maxResponseBytes = defaultAiMaxResponseBytes,
  });

  /// 提供商别名（只用于错误信息与诊断，不参与请求）。
  final String alias;

  /// Base URL。
  final String baseUrl;

  /// 模型 ID。
  final String modelId;

  /// API Key（只用于 Authorization 头）。
  final String apiKey;

  /// 时限（SET-036 默认值）。
  final AiStreamTimeouts timeouts;

  /// 错误响应体上限（防止把巨大错误页读进内存）。
  final int maxResponseBytes;

  /// 可注入的 HTTP 客户端（测试用 MockClient）；为空时每次请求自建。
  final http.Client? client;

  /// 端点（{base}/chat/completions）。
  Uri get endpoint => aiEndpoint(baseUrl, 'chat/completions');

  @override
  Stream<AiEvent> generate(AiRequest request) async* {
    // 已取消的信号必须在**发出任何字节之前**被识别：一次已经作废的请求如果还是
    // 发了出去，服务商会真实计费（架构 4.5 不承诺恰好计费一次），因此能做的是
    // 不要主动制造这种请求。
    if (request.cancellation.isCancelled) {
      throw CancelledError(reason: '请求在发出前已取消');
    }
    final http.Client? owned = client == null ? http.Client() : null;
    final http.Client effective = owned ?? client!;
    try {
      final http.Request httpRequest = http.Request('POST', endpoint)
        ..headers['Authorization'] = 'Bearer $apiKey'
        ..headers['Content-Type'] = 'application/json'
        ..headers['Accept'] = 'text/event-stream'
        ..body = jsonEncode(chatCompletionsRequestBody(request, modelId));

      final http.StreamedResponse response;
      try {
        response = await effective
            .send(httpRequest)
            .timeout(
              timeouts.firstResponse,
              onTimeout: () => throw DeadlineExceededError(
                limitKind: 'aiFirstResponse',
                limit: timeouts.firstResponse,
              ),
            );
      } on DeadlineExceededError {
        rethrow;
      } on http.ClientException catch (error) {
        throw NetworkError(
          uri: endpoint.toString(),
          reason: '连接失败',
          cause: error,
        );
      } on Exception catch (error) {
        throw NetworkError(
          uri: endpoint.toString(),
          reason: '请求失败（${error.runtimeType}）',
          cause: error,
        );
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw await _mapErrorResponse(response);
      }

      final Stream<List<int>> guarded = guardAiByteStream(
        response.stream,
        endpoint: endpoint,
        timeouts: timeouts,
        cancellation: request.cancellation,
        limitKindPrefix: 'ai',
      );

      String? finishReason;
      AiUsage? usage;
      bool sawDone = false;
      // 工具调用会跨多个 chunk 分片到达（见 ToolCallAccumulator 的说明），因此这里
      // 逐片喂入、流结束时统一收尾。
      final ToolCallAccumulator toolCalls = ToolCallAccumulator();

      await for (final String payload in sseEventPayloads(
        guarded,
        endpoint: endpoint,
      )) {
        if (request.cancellation.isCancelled) {
          throw CancelledError(reason: '请求已取消');
        }
        // 终止标记：协议约定 "[DONE]"。它**不是** JSON，必须在解析前判掉——
        // 否则会把每个正常的流都以一个 JSON 解析错误结束。
        if (payload.trim() == '[DONE]') {
          sawDone = true;
          break;
        }
        final Map<String, Object?>? decoded = _decodeObject(payload);
        if (decoded == null) {
          // 单个坏 chunk 不终止整个流：服务商偶发地发一行非 JSON（例如某些代理的
          // keep-alive 文本）不该丢掉用户已经看到的全部内容。但如果连一个有效 chunk
          // 都没收到、也没收到 [DONE]，下面的断言会把这种「全是垃圾」的情况报出来。
          continue;
        }
        // 协议内嵌错误：有些网关在 200 的流里发 {"error": {...}}。
        final Object? error = decoded['error'];
        if (error is Map<Object?, Object?>) {
          throw mapAiHttpError(
            provider: alias,
            endpoint: endpoint,
            statusCode: response.statusCode,
            errorType: error['type'] as String?,
            errorCode: error['code'] as String?,
          );
        }

        final AiUsage? chunkUsage = parseChatCompletionsUsage(decoded['usage']);
        if (chunkUsage != null) {
          usage = chunkUsage;
        }

        final Object? choices = decoded['choices'];
        if (choices is! List<Object?>) {
          continue;
        }
        for (final Object? choice in choices) {
          if (choice is! Map<Object?, Object?>) {
            continue;
          }
          final Object? reason = choice['finish_reason'];
          if (reason is String && reason.isNotEmpty) {
            finishReason = reason;
          }
          final Object? delta = choice['delta'];
          if (delta is! Map<Object?, Object?>) {
            continue;
          }
          final Object? content = delta['content'];
          if (content is String && content.isNotEmpty) {
            yield AiDelta(content);
          }
          // tool_calls 是**增量**（分片到达），按 index 归位累加；不解析、也不丢弃整个
          // chunk：「有工具调用就整块跳过」会连带丢掉同一 chunk 里可能存在的正文。
          toolCalls.addDelta(delta['tool_calls']);
        }
      }

      if (usage != null) {
        yield usage;
      }
      // 收集到的调用作为一个独立事件发出（在 done 之前）：调用点据此决定要不要执行，
      // 而不必从 finishReason 字符串反推「这一轮其实是工具调用」。
      final List<ToolCall> calls = toolCalls.build();
      if (calls.isNotEmpty) {
        yield AiToolCalls(calls);
      }
      if (!sawDone && finishReason == null && calls.isEmpty) {
        // 既没有 [DONE] 也没有 finish_reason：流被中途截断（网络断开或服务商异常）。
        // 必须报出来而不是安静地结束——安静结束会让上层把半句话当成完整答案保存。
        // （有工具调用但没有 [DONE] 的流不算截断：有些实现直接以工具调用结束流。）
        throw NetworkError(
          uri: endpoint.toString(),
          reason: '流在中途结束，既未收到 [DONE] 也未收到结束原因',
        );
      }
      yield AiDone(finishReason: finishReason);
    } finally {
      owned?.close();
    }
  }

  /// 把非 2xx 响应翻译成类型化错误。
  Future<AppError> _mapErrorResponse(http.StreamedResponse response) async {
    final Map<String, Object?>? body = await readAiErrorBody(
      response,
      maxBytes: maxResponseBytes,
    );
    final Object? error = body?['error'];
    final Map<Object?, Object?>? detail = error is Map<Object?, Object?>
        ? error
        : null;
    return mapAiHttpError(
      provider: alias,
      endpoint: endpoint,
      statusCode: response.statusCode,
      errorType: detail?['type'] as String?,
      // Chat Completions 的错误体里 code 可能是字符串，也可能是 null。
      errorCode: detail?['code'] as String?,
      retryAfter: parseRetryAfterHeader(response.headers['retry-after']),
    );
  }

  /// 解析单行 JSON；非对象或非法 JSON 返回 null（调用方决定是否忽略）。
  static Map<String, Object?>? _decodeObject(String payload) {
    final Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException {
      return null;
    }
    return decoded is Map<String, Object?> ? decoded : null;
  }
}
