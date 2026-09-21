// Anthropic Messages 适配器（T027；协议事实来源：主代理提供，检索于 2026-09-22）。
//
// 请求（POST {base}/messages）：
//   {model, max_tokens（**必填**）, messages:[{role:"user"|"assistant",
//    content:[{type:"text",text}|{type:"image",source:{type:"base64",media_type,data}}]}],
//    system?（**顶层参数**，不进 messages）, stream:true, temperature?, tools?}
//   头：x-api-key: <key>（**不是** Authorization: Bearer）+ anthropic-version: 2023-06-01（必需）
//
// SSE：行仍是 "data: {json}"，但**每个负载都带 type 字段**（这是与两个 OpenAI 协议
// 最本质的差别——事件类型不在传输层语法里，而在负载内部）：
//   message_start       （内含 message.usage.input_tokens；还没有输出）
//   content_block_delta （delta.type = "text_delta"，增量在 delta.text）
//   message_delta       （usage.output_tokens 是**累计值**）
//   message_stop        （流结束）
//   error               （{type:"error", error:{type,message}}，可能在 200 流里出现）
// 另有 content_block_start / content_block_stop / message_delta 等生命周期事件必须被忽略
// （协议会继续加类型；未知事件让整个流失败会把一次正常回答变成错误）。
//
// 独立建模（架构 4.3「三种独立适配器，不能只改 URL」）——四处具体差异：
//   1) 认证头不同（x-api-key + version，而不是 Authorization Bearer）；
//   2) 系统指令是顶层 system，不是 messages 里的一条；
//   3) max_tokens 必填，而 OpenAI 可以省略；
//   4) usage 分两处到达（message_start 的 input、message_delta 的 output），
//      且**没有 total_tokens**，必须由上层的 effectiveTotal 标为本地合计。
//
// 安全边界：Key 只出现在 x-api-key 头里，**从不**拼进 URL、日志或异常消息；
// 本文件里没有任何一处把 key 插值进字符串。
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/domain/ai_errors.dart';
import 'package:flux/features/ai/domain/ai_message.dart';
import 'package:flux/features/ai/domain/ai_provider.dart';

import 'ai_http.dart';

/// Anthropic Messages 适配器。
final class AnthropicMessagesAdapter implements AiProvider {
  /// 构造适配器。
  AnthropicMessagesAdapter({
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

  /// API Key（只用于 x-api-key 头）。
  final String apiKey;

  /// 时限（SET-036 默认值；与两个 OpenAI 协议共用同一份流内时限语义）。
  final AiStreamTimeouts timeouts;

  /// 错误响应体上限。
  final int maxResponseBytes;

  /// 可注入的 HTTP 客户端（测试用 MockClient）；为空时每次请求自建。
  final http.Client? client;

  /// 端点（{base}/messages）。
  Uri get endpoint => aiEndpoint(baseUrl, 'messages');

  @override
  Stream<AiEvent> generate(AiRequest request) async* {
    // 与两个 OpenAI 协议同一条纪律：已取消的信号不得发出任何字节（可能计费）。
    if (request.cancellation.isCancelled) {
      throw CancelledError(reason: '请求在发出前已取消');
    }
    final http.Client? owned = client == null ? http.Client() : null;
    final http.Client effective = owned ?? client!;
    try {
      final http.Request httpRequest = http.Request('POST', endpoint)
        // **不是** Authorization: Bearer——用错头会被服务商当成未认证（401），
        // 而错误信息通常不会指出「你用错了认证头」，因此这条差异必须由用例钉住。
        ..headers['x-api-key'] = apiKey
        // 版本头是协议必需项：缺它直接 400，不会回退到默认版本。
        ..headers['anthropic-version'] = anthropicVersion
        ..headers['Content-Type'] = 'application/json'
        ..headers['Accept'] = 'text/event-stream'
        ..body = jsonEncode(anthropicMessagesRequestBody(request, modelId));

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

      // usage 分两处到达：message_start 给 input_tokens，message_delta 给
      // 累计的 output_tokens。两者必须**拼合**成一个 AiUsage——只看 message_delta
      // 会丢掉输入侧记账，只看 message_start 会把输出记成 0。
      int? inputTokens;
      int? outputTokens;
      String? finishReason;
      bool sawMessageStop = false;
      bool sawMessageStart = false;

      await for (final String payload in sseEventPayloads(
        guarded,
        endpoint: endpoint,
      )) {
        if (request.cancellation.isCancelled) {
          throw CancelledError(reason: '请求已取消');
        }
        // Anthropic 不用 "[DONE]" 终止；但若某兼容代理发了它，按结束处理比崩溃好。
        if (payload.trim() == '[DONE]') {
          sawMessageStop = true;
          break;
        }
        final Map<String, Object?>? event = _decodeObject(payload);
        if (event == null) {
          // 单个坏行不终止整个流：中间代理的 keep-alive 文本不该丢掉已收到的内容。
          continue;
        }
        final String? type = event['type'] as String?;
        if (type == null) {
          continue;
        }

        switch (type) {
          case 'message_start':
            sawMessageStart = true;
            final Object? message = event['message'];
            if (message is Map<Object?, Object?>) {
              final AiUsage? usage = parseAnthropicUsage(message['usage']);
              if (usage != null) {
                inputTokens = usage.inputTokens;
                // Anthropic 的 message_start 里 output_tokens 通常是 0；只在
                // message_delta 尚未给出时用它，避免把 0 当结果。
                outputTokens ??= usage.outputTokens;
              }
              final Object? reason = message['stop_reason'];
              if (reason is String && reason.isNotEmpty) {
                finishReason = reason;
              }
            }
          case 'content_block_delta':
            final Object? delta = event['delta'];
            if (delta is Map<Object?, Object?>) {
              // delta.type == "text_delta" 的增量在 delta.text；其它 delta 类型
              // （input_json_delta 等，属工具调用/T032）不产生文本增量。
              final Object? text = delta['text'];
              if (text is String && text.isNotEmpty) {
                yield AiDelta(text);
              }
            }
          case 'message_delta':
            final AiUsage? usage = parseAnthropicUsage(event['usage']);
            if (usage != null) {
              // 这里的 output_tokens 是**累计值**（不是增量），因此直接覆盖而不是累加；
              // 累加会把同一段输出算两遍，预算直接翻倍。
              outputTokens = usage.outputTokens;
            }
            final Object? delta = event['delta'];
            if (delta is Map<Object?, Object?>) {
              final Object? reason = delta['stop_reason'];
              if (reason is String && reason.isNotEmpty) {
                finishReason = reason;
              }
            }
          case 'message_stop':
            sawMessageStop = true;
          case 'error':
            // 200 的流里内嵌错误：错误类型在 event.error.type，需要翻译成语义状态码。
            throw _mapEventError(event);
          default:
            // content_block_start / content_block_stop / ping 等生命周期事件：
            // 显式列出 default 而不是穷尽匹配——协议会继续加事件类型，未知事件
            // 必须被忽略，而不是让整个流失败。
            break;
        }
      }

      if (inputTokens != null || outputTokens != null) {
        yield AiUsage(
          inputTokens: inputTokens ?? 0,
          outputTokens: outputTokens ?? 0,
        );
      }
      if (!sawMessageStop && !sawMessageStart) {
        // 一个事件都没收到：多半是中间代理返回了 200 但内容不是事件流。
        throw NetworkError(
          uri: endpoint.toString(),
          reason: '事件流在没有任何事件的情况下结束',
        );
      }
      if (!sawMessageStop) {
        // 有事件但没有 message_stop：流被中途截断。静默结束会让上层把半句话
        // 当成完整答案保存（与两个 OpenAI 协议同一条纪律）。
        throw NetworkError(
          uri: endpoint.toString(),
          reason: '事件流未收到 message_stop（中途结束）',
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
    return mapAnthropicError(
      provider: alias,
      endpoint: endpoint,
      statusCode: response.statusCode,
      errorType: detail?['type'] as String?,
      errorCode: detail?['code'] as String?,
      retryAfter: parseRetryAfterHeader(response.headers['retry-after']),
    );
  }

  /// 把事件里内嵌的错误翻译成类型化错误。
  ///
  /// 只取 type：**不使用** message 原文（可能回显请求内容，架构第 8 节）。
  AppError _mapEventError(Map<String, Object?> event) {
    final Object? error = event['error'];
    final Map<Object?, Object?>? detail = error is Map<Object?, Object?>
        ? error
        : null;
    return mapAnthropicError(
      provider: alias,
      endpoint: endpoint,
      // 事件里的错误没有 HTTP 状态码；用一个能表达「未收到状态码」的 500 兜底，
      // 真实语义由 errorType 决定（映射函数会覆盖它）。
      statusCode: 500,
      errorType: detail?['type'] as String?,
      errorCode: detail?['code'] as String?,
    );
  }

  /// 解析单行 JSON；非对象或非法 JSON 返回 null。
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
