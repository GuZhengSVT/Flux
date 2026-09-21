// OpenAI Responses 适配器（T026；协议事实来源：主代理提供，检索于 2026-09-22）。
//
// 请求（POST {base}/responses）：
//   {model, input:[{role, content:[{type:"input_text"|"input_image", text|image_url}]}],
//    max_output_tokens, stream:true, instructions?, tools?}
//
// SSE 事件流（事件对象带 type 字段）：
//   response.created / response.output_text.delta（增量在 delta 字段）/
//   response.completed（usage 在 response.usage：input_tokens/output_tokens）/
//   response.failed（错误在 response.error）/ error
//
// 与 Chat Completions 的**独立建模**（架构 4.3「三种独立适配器，不能只改 URL」）：
//   - 输入结构完全不同（input items vs messages，系统指令走顶层 instructions）；
//   - 输出事件结构不同（带 type 的事件 vs chunk 里的 choices[].delta）；
//   - usage 字段名不同（input_tokens/output_tokens vs prompt_tokens/completion_tokens）。
//
// 安全边界：Key 只进 Authorization 头；本文件没有任何一处把它插值进字符串。
// 事件里的错误只取 code/type 这类结构性字段，**不把 message 原文**放进错误消息
// （服务商的错误文本可能回显请求内容，架构第 8 节）。
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

/// Responses 适配器。
final class ResponsesAdapter implements AiProvider {
  /// 构造适配器。
  ResponsesAdapter({
    required this.alias,
    required this.baseUrl,
    required this.modelId,
    required this.apiKey,
    this.client,
    this.timeouts = const AiStreamTimeouts(),
    this.maxResponseBytes = defaultAiMaxResponseBytes,
  });

  /// 提供商别名（只用于错误信息，不参与请求）。
  final String alias;

  /// Base URL。
  final String baseUrl;

  /// 模型 ID。
  final String modelId;

  /// API Key（只用于 Authorization 头）。
  final String apiKey;

  /// 时限（SET-036 默认值）。
  final AiStreamTimeouts timeouts;

  /// 错误响应体上限。
  final int maxResponseBytes;

  /// 可注入的 HTTP 客户端（测试用 MockClient）；为空时每次请求自建。
  final http.Client? client;

  /// 端点（{base}/responses）。
  Uri get endpoint => aiEndpoint(baseUrl, 'responses');

  @override
  Stream<AiEvent> generate(AiRequest request) async* {
    // 同 Chat Completions：已取消的请求不得发出（见那里的说明）。
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
        ..body = jsonEncode(responsesRequestBody(request, modelId));

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

      AiUsage? usage;
      String? finishReason;
      bool completed = false;
      bool sawAnyEvent = false;
      // Responses 把 function_call 作为**完整的输出项**给出（不是流式分片），
      // 因此直接收集列表，不需要累加器。
      final List<ToolCall> collectedCalls = <ToolCall>[];

      await for (final String payload in sseEventPayloads(
        guarded,
        endpoint: endpoint,
      )) {
        if (request.cancellation.isCancelled) {
          throw CancelledError(reason: '请求已取消');
        }
        // Responses 不使用 "[DONE]" 终止标记，事件类型在负载的 type 字段里。
        // 但若某个兼容实现发了它，按终止处理比崩溃更合理。
        if (payload.trim() == '[DONE]') {
          completed = true;
          break;
        }
        final Map<String, Object?>? event = _decodeObject(payload);
        if (event == null) {
          continue;
        }
        final String? type = event['type'] as String?;
        if (type == null) {
          continue;
        }
        sawAnyEvent = true;

        switch (type) {
          case 'response.output_text.delta':
            final Object? delta = event['delta'];
            if (delta is String && delta.isNotEmpty) {
              yield AiDelta(delta);
            }
          case 'response.output_item.done':
            // 一个输出项完成。function_call 项在这里到达（**不是**流式分片：Responses
            // 把整项一次性给出），因此直接收集，不需要累加器。
            final Object? item = event['item'];
            collectedCalls.addAll(parseResponsesToolCalls(<Object?>[item]));
          case 'response.completed':
            completed = true;
            final Object? body = event['response'];
            if (body is Map<Object?, Object?>) {
              usage = parseResponsesUsage(body['usage']);
              finishReason = _statusOf(body);
              // 完成事件里若带 output 数组，也一并收集：两种到达方式都要覆盖
              // （有的实现只在 completed 里给完整 output）。
              collectedCalls.addAll(parseResponsesToolCalls(body['output']));
            }
          case 'response.failed':
            // 失败事件的错误在 response.error 里。
            final Object? body = event['response'];
            final Object? error = body is Map<Object?, Object?>
                ? body['error']
                : event['error'];
            throw _mapEventError(error, statusCode: response.statusCode);
          case 'error':
            throw _mapEventError(event, statusCode: response.statusCode);
          case 'response.incomplete':
            // 输出被截断（例如达到 max_output_tokens）：内容仍然有效，按完成处理
            // 并把原因带出去，让上层能区分「说完」与「被截断」。
            completed = true;
            final Object? body = event['response'];
            if (body is Map<Object?, Object?>) {
              usage = parseResponsesUsage(body['usage']);
              finishReason = _statusOf(body) ?? 'incomplete';
            }
          default:
            // response.created / response.in_progress / response.output_item.* 等
            // 生命周期事件：本适配器不消费（T032 的工具输出项会用到 output_item）。
            // 显式列出 default 而不是穷尽匹配：协议会继续加事件类型，未知事件必须
            // 被忽略而不是让整个流失败。
            break;
        }
      }

      if (usage != null) {
        yield usage;
      }
      if (collectedCalls.isNotEmpty) {
        yield AiToolCalls(List<ToolCall>.unmodifiable(collectedCalls));
      }
      if (!completed && !sawAnyEvent) {
        throw NetworkError(
          uri: endpoint.toString(),
          reason: '事件流在没有任何事件的情况下结束',
        );
      }
      if (!completed) {
        // 有事件但没有完成事件：流被截断。静默结束会让上层把半句话存成完整答案。
        throw NetworkError(
          uri: endpoint.toString(),
          reason: '事件流未收到 response.completed（中途结束）',
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
      errorCode: detail?['code'] as String?,
      retryAfter: parseRetryAfterHeader(response.headers['retry-after']),
    );
  }

  /// 把事件内嵌的错误翻译成类型化错误。
  ///
  /// 只取 code/type：**不使用** message 原文（可能回显请求内容）。
  AppError _mapEventError(Object? error, {required int statusCode}) {
    final Map<Object?, Object?>? detail = error is Map<Object?, Object?>
        ? error
        : null;
    return mapAiHttpError(
      provider: alias,
      endpoint: endpoint,
      statusCode: statusCode,
      errorType: detail?['type'] as String?,
      errorCode: detail?['code'] as String?,
    );
  }

  /// 取 response.status（`completed` / `incomplete` 等）。
  static String? _statusOf(Map<Object?, Object?> body) {
    final Object? status = body['status'];
    return status is String && status.isNotEmpty ? status : null;
  }

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
