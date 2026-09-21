// T025：统一 AIProvider 契约与错误映射。
//
// 覆盖三件在后续任务里会被反复依赖的事实：
//   1) 取消信号幂等，且**登记即在已取消时立即回调**（适配器在建立连接后才登记）；
//   2) 能力契约是五项独立布尔值 + 保守预算回退（不按模型名推断）；
//   3) HTTP 状态码 → 类型化错误的映射是全工程共用的（两个协议不能各写一套）。
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/domain/ai_errors.dart';
import 'package:flux/features/ai/domain/ai_message.dart';
import 'package:flux/features/ai/domain/ai_model.dart';
import 'package:flux/features/ai/domain/ai_protocol.dart';
import 'package:flux/features/ai/domain/ai_provider.dart';
import 'package:flux/features/ai/domain/model_capability.dart';

void main() {
  group('AiCancellation', () {
    test('首次取消返回 true，重复取消返回 false 且不重复派发', () {
      final AiCancellation cancellation = AiCancellation();
      int fired = 0;
      cancellation.addListener(() => fired++);

      expect(cancellation.cancel(reason: 'test'), isTrue);
      expect(cancellation.cancel(reason: 'again'), isFalse);
      expect(fired, 1, reason: '取消必须只派发一次');
      expect(cancellation.isCancelled, isTrue);
      expect(cancellation.reason, 'test', reason: '原因保留首次的，不被后续覆盖');
    });

    test('已经取消后再登记监听器会立即回调（适配器晚登记的常见路径）', () {
      final AiCancellation cancellation = AiCancellation();
      cancellation.cancel();

      int fired = 0;
      cancellation.addListener(() => fired++);
      expect(fired, 1, reason: '若只等待「未来的取消」，晚登记的适配器会挂到超时');
    });

    test('移除监听器后不再回调', () {
      final AiCancellation cancellation = AiCancellation();
      int fired = 0;
      void listener() => fired++;
      cancellation.addListener(listener);
      cancellation.removeListener(listener);
      cancellation.cancel();
      expect(fired, 0);
    });

    test('取消时在回调里移除自己不会影响本次派发', () {
      final AiCancellation cancellation = AiCancellation();
      final List<String> order = <String>[];
      void first() {
        order.add('first');
        cancellation.removeListener(first);
      }

      cancellation.addListener(first);
      cancellation.addListener(() => order.add('second'));
      cancellation.cancel();
      expect(order, <String>['first', 'second']);
    });
  });

  group('AiRequest 与消息角色', () {
    test('默认构造出可取消的请求，工具列表为空', () {
      final AiRequest request = AiRequest(
        modelId: 'deepseek-chat',
        messages: const <AiMessage>[AiMessage.user('hi')],
      );
      expect(request.cancellation.isCancelled, isFalse);
      expect(request.tools, isEmpty);
      expect(request.maxTokens, isNull, reason: '未指定输出上限时不发送该字段');
    });

    test('四种角色的线格式名与协议字段一致', () {
      expect(AiRole.system.wireName, 'system');
      expect(AiRole.user.wireName, 'user');
      expect(AiRole.assistant.wireName, 'assistant');
      expect(AiRole.tool.wireName, 'tool');
    });

    test('AiMessage.toString 不回显正文（诊断输出不该带用户内容）', () {
      const AiMessage message = AiMessage.user('这是一段用户正文');
      expect(message.toString(), contains('8 chars'));
      expect(message.toString(), isNot(contains('这是一段用户正文')));
    });
  });

  group('usage 统计', () {
    test('服务商给出总量时直接使用，不标估算', () {
      const AiUsage usage = AiUsage(
        inputTokens: 30,
        outputTokens: 12,
        totalTokens: 42,
      );
      expect(usage.effectiveTotal, 42);
      expect(usage.totalIsEstimated, isFalse);
    });

    test('服务商未给总量时用「输入 + 输出」并标为本地合计', () {
      const AiUsage usage = AiUsage(inputTokens: 30, outputTokens: 12);
      expect(usage.effectiveTotal, 42);
      expect(
        usage.totalIsEstimated,
        isTrue,
        reason: '预算与展示必须能区分「服务商统计」与「本地合计」',
      );
    });
  });

  group('协议登记', () {
    test('三个协议各有稳定标识与请求路径', () {
      expect(AiProtocol.openAiChatCompletions.path, 'chat/completions');
      expect(AiProtocol.openAiResponses.path, 'responses');
      expect(AiProtocol.anthropicMessages.path, 'messages');
      expect(AiProtocol.openAiChatCompletions.id, 'openai.chat_completions');
    });

    test('T025 期间只有两个 OpenAI 协议的适配器已实现', () {
      expect(AiProtocol.openAiChatCompletions.hasAdapter, isTrue);
      expect(AiProtocol.openAiResponses.hasAdapter, isTrue);
      expect(
        AiProtocol.anthropicMessages.hasAdapter,
        isFalse,
        reason: '适配器属 T027；「列出这个选项」不等于「真的能用」',
      );
    });

    test('由标识还原协议；未知标识返回 null', () {
      expect(AiProtocol.fromId('openai.responses'), AiProtocol.openAiResponses);
      expect(AiProtocol.fromId('unknown.protocol'), isNull);
      expect(AiProtocol.fromId(null), isNull);
    });
  });

  group('能力契约（SET-033）', () {
    test('五项能力互相独立，默认只开文本', () {
      const ModelCapability capability = ModelCapability();
      expect(capability.text, isTrue);
      expect(capability.vision, isFalse);
      expect(capability.streaming, isFalse);
      expect(capability.tools, isFalse);
      expect(capability.structured, isFalse);
    });

    test('未声明上限时回退到保守预算 8192 / 2048 并标记为保守', () {
      const ModelCapability capability = ModelCapability();
      expect(
        capability.effectiveContextBudget,
        ModelCapability.conservativeContextBudget,
      );
      expect(
        capability.effectiveOutputBudget,
        ModelCapability.conservativeOutputBudget,
      );
      expect(capability.contextIsConservative, isTrue);
      expect(capability.outputIsConservative, isTrue);
    });

    test('声明上限后按声明值使用且不再标保守', () {
      const ModelCapability capability = ModelCapability(
        contextWindow: 128000,
        maxOutput: 8192,
      );
      expect(capability.effectiveContextBudget, 128000);
      expect(capability.effectiveOutputBudget, 8192);
      expect(capability.contextIsConservative, isFalse);
      expect(capability.outputIsConservative, isFalse);
    });

    test('非正数上限按「未声明」处理（0 不等于无限制）', () {
      const ModelCapability capability = ModelCapability(
        contextWindow: 0,
        maxOutput: -5,
      );
      expect(
        capability.effectiveContextBudget,
        ModelCapability.conservativeContextBudget,
      );
      expect(
        capability.effectiveOutputBudget,
        ModelCapability.conservativeOutputBudget,
      );
    });

    test('satisfies 对每一项能力独立判定（视觉能力不蕴含工具能力）', () {
      const ModelCapability visionOnly = ModelCapability(vision: true);
      expect(visionOnly.satisfies(CapabilityRequirement.vision), isTrue);
      expect(visionOnly.satisfies(CapabilityRequirement.tools), isFalse);
      expect(visionOnly.satisfies(CapabilityRequirement.text), isTrue);
    });

    test('输出上限大于上下文窗口被拒绝', () {
      final Result<void> result = validateCapability(
        'SET-033',
        const ModelCapability(contextWindow: 4096, maxOutput: 8192),
      );
      expect(result.isErr, isTrue);
      final ValidationError error = result.errorOrNull! as ValidationError;
      expect(error.field, 'SET-033');
      expect(error.reason, contains('输出上限'));
    });

    test('合法的上下文/输出组合通过校验', () {
      expect(
        validateCapability(
          'SET-033',
          const ModelCapability(contextWindow: 32768, maxOutput: 4096),
        ).isOk,
        isTrue,
      );
      // 两者都未声明也是合法的（按保守值使用）。
      expect(
        validateCapability('SET-033', const ModelCapability()).isOk,
        isTrue,
      );
    });
  });

  group('模型记录校验（SET-030/032/033）', () {
    AiModel model({
      String alias = 'deepseek',
      String baseUrl = 'https://api.deepseek.com',
      String modelId = 'deepseek-chat',
      ModelCapability capability = const ModelCapability(),
    }) => AiModel(
      alias: alias,
      protocol: AiProtocol.openAiChatCompletions,
      baseUrl: baseUrl,
      modelId: modelId,
      capability: capability,
    );

    test('合法记录通过校验', () {
      expect(validateAiModel(model()).isOk, isTrue);
    });

    test('空别名被拒绝', () {
      final Result<void> result = validateAiModel(model(alias: '   '));
      expect(result.isErr, isTrue);
      expect((result.errorOrNull! as ValidationError).field, 'SET-030.alias');
    });

    test('别名含控制字符被拒绝（换行会伪造日志行）', () {
      expect(validateAiModel(model(alias: 'a\nb')).isErr, isTrue);
    });

    test('模型 ID 不能为空或含空白', () {
      expect(validateAiModel(model(modelId: '')).isErr, isTrue);
      expect(validateAiModel(model(modelId: 'gpt 4')).isErr, isTrue);
      expect(
        (validateAiModel(model(modelId: '')).errorOrNull! as ValidationError)
            .field,
        'SET-032.modelId',
      );
    });

    test('Base URL 只接受 http/https 且必须有主机', () {
      expect(validateAiBaseUrl('https://api.deepseek.com').isOk, isTrue);
      expect(validateAiBaseUrl('http://localhost:1234/v1').isOk, isTrue);
      expect(validateAiBaseUrl('file:///etc/passwd').isErr, isTrue);
      expect(validateAiBaseUrl('api.deepseek.com').isErr, isTrue);
      expect(validateAiBaseUrl('https://').isErr, isTrue);
      expect(validateAiBaseUrl('').isErr, isTrue);
    });

    test('端点拼接保留 Base URL 里已有的路径前缀', () {
      expect(
        aiEndpointFor(
          'https://api.deepseek.com',
          AiProtocol.openAiChatCompletions,
        ).toString(),
        'https://api.deepseek.com/chat/completions',
      );
      expect(
        aiEndpointFor(
          'https://api.deepseek.com/',
          AiProtocol.openAiChatCompletions,
        ).toString(),
        'https://api.deepseek.com/chat/completions',
        reason: '尾斜杠不应产生双斜杠',
      );
      expect(
        aiEndpointFor(
          'https://gateway.example.com/openai/v1',
          AiProtocol.openAiResponses,
        ).toString(),
        'https://gateway.example.com/openai/v1/responses',
        reason: '已有路径段必须保留（自建网关/代理的常见形态）',
      );
    });

    test('凭据标识按别名而不是按自增 id', () {
      const AiModel record = AiModel(
        id: 7,
        alias: 'deepseek',
        protocol: AiProtocol.openAiChatCompletions,
        baseUrl: 'https://api.deepseek.com',
        modelId: 'deepseek-chat',
      );
      expect(record.credentialIdentifier, 'deepseek');
    });
  });

  group('HTTP 错误映射（两个协议共用）', () {
    final Uri endpoint = Uri.parse('https://api.deepseek.com/chat/completions');

    test('429 映射为 RateLimitError，可重试且带 Retry-After', () {
      final AppError error = mapAiHttpError(
        provider: 'deepseek',
        endpoint: endpoint,
        statusCode: 429,
        errorType: 'rate_limit_exceeded',
        retryAfter: const Duration(seconds: 3),
      );
      expect(error, isA<RateLimitError>());
      expect(error.isRetryable, isTrue);
      expect((error as RateLimitError).retryAfter, const Duration(seconds: 3));
    });

    test('401 / 402 / 403 映射为不可重试的 AuthError', () {
      for (final int status in <int>[401, 402, 403]) {
        final AppError error = mapAiHttpError(
          provider: 'deepseek',
          endpoint: endpoint,
          statusCode: status,
        );
        expect(error, isA<AuthError>(), reason: 'HTTP $status');
        expect(error.isRetryable, isFalse, reason: 'Key 不会因为再试一次而变对（架构 4.5）');
      }
    });

    test('400 + 内容拒绝标记映射为不可重试的 ContentFilteredError', () {
      final AppError error = mapAiHttpError(
        provider: 'openai',
        endpoint: endpoint,
        statusCode: 400,
        errorCode: 'content_filter',
      );
      expect(error, isA<ContentFilteredError>());
      expect(error.isRetryable, isFalse, reason: '不得用跨服务商重试规避内容策略（架构 4.5）');
    });

    test('普通 400 不误判为内容拒绝（否则会阻止一次本可重试的请求）', () {
      final AppError error = mapAiHttpError(
        provider: 'openai',
        endpoint: endpoint,
        statusCode: 400,
        errorType: 'invalid_request_error',
      );
      expect(error, isA<NetworkError>());
      expect((error as NetworkError).statusCode, 400);
    });

    test('5xx 映射为可重试的 NetworkError', () {
      final AppError error = mapAiHttpError(
        provider: 'openai',
        endpoint: endpoint,
        statusCode: 503,
      );
      expect(error, isA<NetworkError>());
      expect((error as NetworkError).isServerSideFailure, isTrue);
    });

    test('错误消息只带结构性字段，不产生凭据（响应体从不进入消息）', () {
      final AppError error = mapAiHttpError(
        provider: 'deepseek',
        endpoint: endpoint,
        statusCode: 401,
        errorType: 'authentication_error',
        errorCode: 'invalid_api_key',
      );
      expect(error.message, contains('type=authentication_error'));
      expect(error.message, isNot(contains('Bearer')));
    });

    test('内容拒绝标记判定只认结构化值', () {
      expect(isContentFilterSignal(errorCode: 'content_filter'), isTrue);
      expect(
        isContentFilterSignal(errorType: 'CONTENT_POLICY_VIOLATION'),
        isTrue,
        reason: '大小写不应影响判定',
      );
      expect(
        isContentFilterSignal(errorType: 'the model refused to answer'),
        isFalse,
        reason: '自由文本不参与判定',
      );
    });
  });

  group('Retry-After 解析', () {
    test('秒数形式被解析', () {
      expect(parseRetryAfterHeader('7'), const Duration(seconds: 7));
      expect(parseRetryAfterHeader(' 12 '), const Duration(seconds: 12));
    });

    test('日期形式与非法值返回 null（不猜一个秒数）', () {
      expect(parseRetryAfterHeader('Wed, 21 Oct 2026 07:28:00 GMT'), isNull);
      expect(parseRetryAfterHeader('abc'), isNull);
      expect(parseRetryAfterHeader('-3'), isNull);
      expect(parseRetryAfterHeader(null), isNull);
    });
  });

  group('AIProvider 契约形状', () {
    test('generate 返回事件流（增量/用量/完成三态）', () {
      final _RecordingProvider provider = _RecordingProvider();
      final Stream<AiEvent> events = provider.generate(
        AiRequest(
          modelId: 'deepseek-chat',
          messages: const <AiMessage>[AiMessage.user('hi')],
        ),
      );
      expect(events, isA<Stream<AiEvent>>());
      expect(
        provider.lastRequest!.messages.single.content,
        'hi',
        reason: '契约把请求原样交给适配器，不在这一层改写',
      );
    });
  });
}

/// 一个只记录请求的最小 provider 实现（契约形状的编译期证据）。
final class _RecordingProvider implements AiProvider {
  AiRequest? lastRequest;

  @override
  Stream<AiEvent> generate(AiRequest request) {
    lastRequest = request;
    return const Stream<AiEvent>.empty();
  }
}
