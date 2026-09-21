// T027：Anthropic Messages 适配器（**独立**夹具与期望，不与两个 OpenAI 协议共用）。
//
// 覆盖协议事实（主代理提供，检索于 2026-09-22）里的每一条：
//   - 认证头：x-api-key + anthropic-version，且**不含** Authorization；
//   - 请求体：model / max_tokens（必填）/ messages 的**分量数组** / 顶层 system；
//   - SSE：带 type 的事件流（message_start / content_block_delta / message_delta /
//     message_stop / error），生命周期事件被忽略；
//   - usage **拼合**：input 来自 message_start、output 来自 message_delta（累计值）；
//   - 错误映射：429 服从 Retry-After、401 不可重试、529 → 可重试的 overloaded；
//   - 取消 → CancelledError；首响应 45s / 停滞 30s（与 CC 同一份语义）；
//   - 断流检测；跨 chunk 的中文（复用 T026 的回归思路）；
//   - key 不进错误消息与诊断文本。
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/domain/ai_message.dart';
import 'package:flux/infrastructure/network/ai_http.dart'
    show AiStreamTimeouts, anthropicDefaultMaxTokens, anthropicImageBlock;
import 'package:flux/infrastructure/network/anthropic_messages_adapter.dart';

import 'adapter_test_support.dart';

void main() {
  const String apiKey = 'sk-ant-fixture-not-a-real-key-000000';

  AnthropicMessagesAdapter adapter({
    http.Client? client,
    AiStreamTimeouts timeouts = const AiStreamTimeouts(),
  }) => AnthropicMessagesAdapter(
    alias: 'anthropic',
    baseUrl: 'https://api.example.com',
    modelId: 'claude-fixture',
    apiKey: apiKey,
    client: client,
    timeouts: timeouts,
  );

  AiRequest request({AiCancellation? cancellation, int? maxTokens}) =>
      AiRequest(
        modelId: 'claude-fixture',
        messages: const <AiMessage>[
          AiMessage.system('你是助手'),
          AiMessage.user('回复：连接正常'),
        ],
        maxTokens: maxTokens,
        cancellation: cancellation,
      );

  group('请求形状（认证头与顶层 system）', () {
    test('用 x-api-key + anthropic-version，且**不含** Authorization', () async {
      http.BaseRequest? seen;
      final AnthropicMessagesAdapter sut = adapter(
        client: sseClient(
          readAiFixture('anthropic_stream.sse'),
          onRequest: (http.BaseRequest request) => seen = request,
        ),
      );
      await sut.generate(request(maxTokens: 64)).toList();

      expect(seen!.method, 'POST');
      expect(seen!.url.toString(), 'https://api.example.com/messages');
      // 这条断言是本任务最关键的一条：把 Anthropic 接到 OpenAI 的认证方式上
      // （Authorization: Bearer）会得到一个 401，而错误信息不会说「你用错了头」。
      expect(seen!.headers['x-api-key'], apiKey);
      expect(
        seen!.headers.containsKey('Authorization'),
        isFalse,
        reason: 'Anthropic 不用 Authorization: Bearer（用错会得到一个难定位的 401）',
      );
      expect(
        seen!.headers['anthropic-version'],
        '2023-06-01',
        reason: '版本头是协议必需项，缺它直接 400',
      );
      expect(seen!.url.query, isEmpty, reason: '凭据绝不进 query（会进日志与代理记录）');
      expect(seen!.headers['Accept'], contains('text/event-stream'));
    });

    test('system 是顶层参数，不进 messages；content 是分量数组', () async {
      http.BaseRequest? seen;
      final AnthropicMessagesAdapter sut = adapter(
        client: sseClient(
          readAiFixture('anthropic_stream.sse'),
          onRequest: (http.BaseRequest request) => seen = request,
        ),
      );
      await sut.generate(request(maxTokens: 64)).toList();

      final Map<String, Object?> body =
          jsonDecode((seen as http.Request).body) as Map<String, Object?>;
      expect(body['model'], 'claude-fixture');
      expect(body['stream'], isTrue);
      expect(
        body['system'],
        '你是助手',
        reason: 'system 是顶层参数；塞进 messages 会被服务商直接拒绝',
      );

      final List<Object?> messages = body['messages']! as List<Object?>;
      expect(messages, hasLength(1), reason: 'system 不占用一条 message');
      final Map<String, Object?> message =
          messages.single! as Map<String, Object?>;
      expect(message['role'], 'user');
      final List<Object?> content = message['content']! as List<Object?>;
      expect(content, hasLength(1), reason: 'content 是分量数组，不是字符串');
      final Map<String, Object?> block =
          content.single! as Map<String, Object?>;
      expect(block['type'], 'text');
      expect(block['text'], '回复：连接正常');
    });

    test('max_tokens 必填：未指定时退回保守输出预算，而不是省略字段', () async {
      http.BaseRequest? seen;
      final AnthropicMessagesAdapter sut = adapter(
        client: sseClient(
          readAiFixture('anthropic_stream.sse'),
          onRequest: (http.BaseRequest request) => seen = request,
        ),
      );
      await sut.generate(request()).toList();
      final Map<String, Object?> body =
          jsonDecode((seen as http.Request).body) as Map<String, Object?>;
      expect(
        body['max_tokens'],
        anthropicDefaultMaxTokens,
        reason: 'OpenAI 可以省略 max_tokens，Anthropic 不行——省略会被 400',
      );
      expect(body.containsKey('temperature'), isFalse);
    });

    test('三个 system 消息用空行拼接（不丢指令）', () async {
      http.BaseRequest? seen;
      final AnthropicMessagesAdapter sut = adapter(
        client: sseClient(
          readAiFixture('anthropic_stream.sse'),
          onRequest: (http.BaseRequest request) => seen = request,
        ),
      );
      await sut
          .generate(
            AiRequest(
              modelId: 'claude-fixture',
              messages: const <AiMessage>[
                AiMessage.system('第一条'),
                AiMessage.system('第二条'),
                AiMessage.user('hi'),
              ],
            ),
          )
          .toList();
      final Map<String, Object?> body =
          jsonDecode((seen as http.Request).body) as Map<String, Object?>;
      expect(body['system'], '第一条\n\n第二条');
    });

    test('Base URL 带路径前缀时端点保留前缀', () {
      final AnthropicMessagesAdapter sut = AnthropicMessagesAdapter(
        alias: 'gateway',
        baseUrl: 'https://api.example.com/anthropic/v1/',
        modelId: 'm',
        apiKey: apiKey,
      );
      expect(
        sut.endpoint.toString(),
        'https://api.example.com/anthropic/v1/messages',
      );
    });

    test('图片是 base64 源，不是 URL（形状由共用层固化）', () {
      final Map<String, Object?> block = anthropicImageBlock(
        mediaType: 'image/png',
        base64Data: 'iVBORw0KGgo=',
      );
      expect(block['type'], 'image');
      final Map<String, Object?> source =
          block['source']! as Map<String, Object?>;
      expect(source['type'], 'base64');
      expect(source['media_type'], 'image/png');
      expect(source['data'], 'iVBORw0KGgo=');
      expect(
        source.containsKey('url'),
        isFalse,
        reason: '协议只接受 base64 源；让服务商去远端取图会把一次请求变成一次不可控出网',
      );
    });
  });

  group('SSE 事件流解析（正常路径）', () {
    test('按顺序产出增量、拼接后的 usage 与完成事件', () async {
      final AnthropicMessagesAdapter sut = adapter(
        client: sseClient(readAiFixture('anthropic_stream.sse')),
      );
      final List<AiEvent> events = await sut.generate(request()).toList();

      final List<String> deltas = events
          .whereType<AiDelta>()
          .map((AiDelta e) => e.text)
          .toList();
      expect(deltas, <String>['连接', '正常']);

      final AiUsage usage = events.whereType<AiUsage>().single;
      expect(usage.inputTokens, 31, reason: '输入侧 token 来自 message_start');
      expect(usage.outputTokens, 6, reason: '输出侧 token 来自 message_delta（累计值）');
      // 协议**不给** total_tokens：不得本地编造一个「服务商统计」的总量。
      expect(usage.totalIsEstimated, isTrue);
      expect(usage.effectiveTotal, 37);

      final AiDone done = events.whereType<AiDone>().single;
      expect(
        done.finishReason,
        'end_turn',
        reason: 'stop_reason 在 message_delta 的 delta 里',
      );
      expect(events.last, isA<AiDone>(), reason: '完成事件必须是最后一个');
    });

    test('usage 事件在 done 之前（预算记账不能晚于结束）', () async {
      final AnthropicMessagesAdapter sut = adapter(
        client: sseClient(readAiFixture('anthropic_stream.sse')),
      );
      final List<AiEvent> events = await sut.generate(request()).toList();
      expect(
        events.indexWhere((AiEvent e) => e is AiUsage),
        lessThan(events.indexWhere((AiEvent e) => e is AiDone)),
      );
    });

    test('usage 只来自 message_delta 时输入侧记 0 而不是报错', () async {
      const String body =
          'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"hi"}}\n\n'
          'data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":3}}\n\n'
          'data: {"type":"message_stop"}\n\n';
      final AnthropicMessagesAdapter sut = adapter(client: sseClient(body));
      final List<AiEvent> events = await sut.generate(request()).toList();
      final AiUsage usage = events.whereType<AiUsage>().single;
      expect(usage.inputTokens, 0);
      expect(usage.outputTokens, 3);
    });

    test('output_tokens 是累计值：多次 message_delta 不累加成两倍', () async {
      const String body =
          'data: {"type":"message_start","message":{"usage":{"input_tokens":10,"output_tokens":0}}}\n\n'
          'data: {"type":"message_delta","delta":{},"usage":{"output_tokens":4}}\n\n'
          'data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":9}}\n\n'
          'data: {"type":"message_stop"}\n\n';
      final AnthropicMessagesAdapter sut = adapter(client: sseClient(body));
      final List<AiEvent> events = await sut.generate(request()).toList();
      final AiUsage usage = events.whereType<AiUsage>().single;
      expect(usage.outputTokens, 9, reason: '累计值直接覆盖；累加会把同一段输出算两遍');
      expect(usage.inputTokens, 10);
    });

    test('多 content block（分两次 message 段）按顺序拼接', () async {
      final AnthropicMessagesAdapter sut = adapter(
        client: sseClient(readAiFixture('anthropic_multiline.sse')),
      );
      final List<AiEvent> events = await sut.generate(request()).toList();
      expect(events.whereType<AiDelta>().map((AiDelta e) => e.text), <String>[
        '第一段',
        '第二',
        '段',
      ], reason: 'content_block_start/stop 不产生增量，只有 delta.text 产出');
      final AiUsage usage = events.whereType<AiUsage>().single;
      expect(usage.inputTokens, 12);
      expect(usage.outputTokens, 8);
    });

    test('stop_reason=max_tokens（触顶）如实传出，不当成错误', () async {
      const String body =
          'data: {"type":"message_start","message":{"usage":{"input_tokens":3,"output_tokens":0}}}\n\n'
          'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"截断"}}\n\n'
          'data: {"type":"message_delta","delta":{"stop_reason":"max_tokens"},"usage":{"output_tokens":5}}\n\n'
          'data: {"type":"message_stop"}\n\n';
      final AnthropicMessagesAdapter sut = adapter(client: sseClient(body));
      final List<AiEvent> events = await sut.generate(request()).toList();
      expect(events.whereType<AiDone>().single.finishReason, 'max_tokens');
    });
  });

  group('SSE 边界（CRLF、心跳、未知事件、字节切块）', () {
    test('CRLF 行尾被剥除，负载仍能解析', () async {
      final String crlf = readAiFixture('anthropic_stream.sse')
          .replaceAll('\n', '\r\n');
      final AnthropicMessagesAdapter sut = adapter(client: sseClient(crlf));
      final List<AiEvent> events = await sut.generate(request()).toList();
      expect(events.whereType<AiDelta>().map((AiDelta e) => e.text), <String>[
        '连接',
        '正常',
      ], reason: '负载尾部残留 \\r 会让 JSON 解析失败');
      expect(events.whereType<AiUsage>().single.inputTokens, 31);
    });

    test('ping/注释行被忽略，未知事件类型不终止整个流', () async {
      final AnthropicMessagesAdapter sut = adapter(
        client: sseClient(readAiFixture('anthropic_multiline.sse')),
      );
      final List<AiEvent> events = await sut.generate(request()).toList();
      expect(events.whereType<AiDone>().single.finishReason, 'end_turn');
    });

    test('完全未知的事件类型被忽略（协议会继续加类型）', () async {
      const String body =
          'data: {"type":"message_start","message":{"usage":{"input_tokens":1,"output_tokens":0}}}\n\n'
          'data: {"type":"some_future_event","payload":{"x":1}}\n\n'
          'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"ok"}}\n\n'
          'data: {"type":"message_stop"}\n\n';
      final AnthropicMessagesAdapter sut = adapter(client: sseClient(body));
      final List<AiEvent> events = await sut.generate(request()).toList();
      expect(events.whereType<AiDelta>().single.text, 'ok');
    });

    test('跨 chunk 的半个 JSON 行被正确拼回（按 1 字节切块，中文完整）', () async {
      final AnthropicMessagesAdapter sut = adapter(
        client: sseClient(readAiFixture('anthropic_stream.sse'), chunkSize: 1),
      );
      final List<AiEvent> events = await sut.generate(request()).toList();
      expect(events.whereType<AiDelta>().map((AiDelta e) => e.text), <String>[
        '连接',
        '正常',
      ], reason: '按块解码会把多字节字符解成替换字符——中文输出下几乎必然触发');
      expect(events.whereType<AiUsage>().single.inputTokens, 31);
    });

    test('非 JSON 的 data 行被跳过，不终止整个流', () async {
      const String body =
          'data: this-is-not-json\n\n'
          'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"ok"}}\n\n'
          'data: {"type":"message_stop"}\n\n';
      final AnthropicMessagesAdapter sut = adapter(client: sseClient(body));
      final List<AiEvent> events = await sut.generate(request()).toList();
      expect(events.whereType<AiDelta>().single.text, 'ok');
    });

    test('input_json_delta（工具参数增量）不产生文本增量', () async {
      const String body =
          'data: {"type":"message_start","message":{"usage":{"input_tokens":1,"output_tokens":0}}}\n\n'
          'data: {"type":"content_block_delta","delta":{"type":"input_json_delta","partial_json":"{\\"a\\":1}"}}\n\n'
          'data: {"type":"message_stop"}\n\n';
      final AnthropicMessagesAdapter sut = adapter(client: sseClient(body));
      final List<AiEvent> events = await sut.generate(request()).toList();
      expect(
        events.whereType<AiDelta>(),
        isEmpty,
        reason: '工具参数增量不是用户可见文本（T032 才消费）',
      );
    });
  });

  group('断流与异常终止', () {
    test('没有 message_stop 时报断流错误（不静默结束）', () async {
      final AnthropicMessagesAdapter sut = adapter(
        client: sseClient(readAiFixture('anthropic_truncated.sse')),
      );
      await expectLater(
        sut.generate(request()).toList(),
        throwsA(isA<NetworkError>()),
      );
    });

    test('一个事件都没有就结束时报错（200 但不是事件流）', () async {
      final AnthropicMessagesAdapter sut = adapter(
        client: sseClient('<html>not an event stream</html>'),
      );
      await expectLater(
        sut.generate(request()).toList(),
        throwsA(isA<NetworkError>()),
      );
    });

    test('有 message_start 与内容但无 message_stop：仍报断流', () async {
      const String body =
          'data: {"type":"message_start","message":{"usage":{"input_tokens":4,"output_tokens":0}}}\n\n'
          'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"半句"}}\n\n';
      final AnthropicMessagesAdapter sut = adapter(client: sseClient(body));
      await expectLater(
        sut.generate(request()).toList(),
        throwsA(isA<NetworkError>()),
      );
    });

    test('200 流里内嵌 error 事件被翻译成类型化错误', () async {
      const String body =
          'data: {"type":"message_start","message":{"usage":{"input_tokens":1,"output_tokens":0}}}\n\n'
          'data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}\n\n';
      final AnthropicMessagesAdapter sut = adapter(client: sseClient(body));
      final Object? error = await sut
          .generate(request())
          .toList()
          .then((_) => null, onError: (Object e) => e);
      expect(error, isA<ProviderError>());
      final ProviderError provider = error! as ProviderError;
      expect(provider.kind, 'overloaded');
      expect(provider.isRetryable, isTrue);
    });

    test('事件流里的 rate_limit_error 映射为可识别的限流（不是网络错误）', () async {
      const String body =
          'data: {"type":"error","error":{"type":"rate_limit_error","message":"slow down"}}\n\n';
      final AnthropicMessagesAdapter sut = adapter(client: sseClient(body));
      final Object? error = await sut
          .generate(request())
          .toList()
          .then((_) => null, onError: (Object e) => e);
      expect(
        error,
        isA<RateLimitError>(),
        reason: '200 流里的限流必须仍然被识别为限流，否则上层不知道该等还是该改 Key',
      );
    });
  });

  group('错误映射（状态码 + 错误体）', () {
    test('429 映射为 RateLimitError 并读取 Retry-After', () async {
      final AnthropicMessagesAdapter sut = adapter(
        client: bodyClient(
          readAiFixture('anthropic_error_429.json'),
          statusCode: 429,
          headers: <String, String>{'retry-after': '11'},
        ),
      );
      final Object? error = await sut
          .generate(request())
          .toList()
          .then((_) => null, onError: (Object e) => e);
      expect(error, isA<RateLimitError>());
      final RateLimitError rate = error! as RateLimitError;
      expect(rate.retryAfter, const Duration(seconds: 11));
      expect(rate.isRetryable, isTrue);
      expect(rate.message, contains('type=rate_limit_error'));
    });

    test('401 authentication_error 映射为不可重试的 AuthError', () async {
      final AnthropicMessagesAdapter sut = adapter(
        client: bodyClient(
          '{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}',
          statusCode: 401,
        ),
      );
      final Object? error = await sut
          .generate(request())
          .toList()
          .then((_) => null, onError: (Object e) => e);
      expect(error, isA<AuthError>());
      expect((error! as AuthError).isRetryable, isFalse);
    });

    test('529 overloaded 映射为**可重试**的 overloaded（这不是通用 5xx）', () async {
      final AnthropicMessagesAdapter sut = adapter(
        client: bodyClient(
          readAiFixture('anthropic_error_529.json'),
          statusCode: 529,
        ),
      );
      final Object? error = await sut
          .generate(request())
          .toList()
          .then((_) => null, onError: (Object e) => e);
      expect(error, isA<ProviderError>());
      final ProviderError provider = error! as ProviderError;
      expect(provider.kind, 'overloaded');
      expect(
        provider.isRetryable,
        isTrue,
        reason: '过载是暂时性的：与 401/400 的根本区别就在这里',
      );
      expect(provider.statusCode, 529);
    });

    test('400 invalid_request_error 映射为 NetworkError 且不是服务端故障', () async {
      final AnthropicMessagesAdapter sut = adapter(
        client: bodyClient(
          '{"type":"error","error":{"type":"invalid_request_error","message":"bad"}}',
          statusCode: 400,
        ),
      );
      final Object? error = await sut
          .generate(request())
          .toList()
          .then((_) => null, onError: (Object e) => e);
      expect(error, isA<NetworkError>());
      final NetworkError network = error! as NetworkError;
      expect(network.statusCode, 400);
      // 400 是「请求本身有问题」（例如 max_tokens 缺失），不是服务端故障。
      // 是否自动重试属 T029 的退避策略；这里只钉住「它没有被归成 5xx/429 那一类」。
      expect(network.isServerSideFailure, isFalse);
    });

    test('错误响应体不是 JSON 时仍按状态码分类', () async {
      final AnthropicMessagesAdapter sut = adapter(
        client: bodyClient('<html>502 Bad Gateway</html>', statusCode: 502),
      );
      final Object? error = await sut
          .generate(request())
          .toList()
          .then((_) => null, onError: (Object e) => e);
      expect(error, isA<NetworkError>());
      expect((error! as NetworkError).statusCode, 502);
    });

    test('错误消息里不出现 API Key（脱敏管道对 Anthropic 同样生效）', () async {
      final AnthropicMessagesAdapter sut = adapter(
        client: bodyClient(
          '{"type":"error","error":{"type":"authentication_error","message":"bad"}}',
          statusCode: 401,
        ),
      );
      final Object? error = await sut
          .generate(request())
          .toList()
          .then((_) => null, onError: (Object e) => e);
      final AppError typed = error! as AppError;
      expect(typed.message, isNot(contains(apiKey)));
      expect(typed.toLogString(), isNot(contains(apiKey)));
    });
  });

  group('取消', () {
    test('取消后流以 CancelledError 结束（不是安静地停下）', () async {
      final AiCancellation cancellation = AiCancellation();
      final AnthropicMessagesAdapter sut = adapter(
        client: sseClient(
          readAiFixture('anthropic_stream.sse'),
          chunkSize: 4,
          gap: const Duration(milliseconds: 1),
        ),
      );
      final Stream<AiEvent> stream = sut.generate(
        request(cancellation: cancellation),
      );
      bool sawDelta = false;
      Object? error;
      await stream
          .map((AiEvent event) {
            if (event is AiDelta && !sawDelta) {
              sawDelta = true;
              cancellation.cancel(reason: 'test');
            }
            return event;
          })
          .toList()
          .then<void>((List<AiEvent> _) {})
          .catchError((Object e) {
            error = e;
          });
      expect(sawDelta, isTrue, reason: '用例应当先收到至少一个增量');
      expect(error, isA<CancelledError>());
    });

    test('已经取消的信号会让请求在发出前就结束', () async {
      final AiCancellation cancellation = AiCancellation()..cancel();
      bool sent = false;
      final AnthropicMessagesAdapter sut = adapter(
        client: sseClient(
          readAiFixture('anthropic_stream.sse'),
          onRequest: (http.BaseRequest request) => sent = true,
        ),
      );
      await expectLater(
        sut.generate(request(cancellation: cancellation)).toList(),
        throwsA(isA<CancelledError>()),
      );
      expect(sent, isFalse, reason: '已取消的请求一个字节都不该发出去（可能计费）');
    });
  });

  group('超时（与两个 OpenAI 协议同一份语义）', () {
    test('流中途停滞会以 DeadlineExceededError 结束', () async {
      final AnthropicMessagesAdapter sut = adapter(
        client: stalledClient(
          'data: {"type":"message_start","message":{"usage":{"input_tokens":1,"output_tokens":0}}}\n\n'
          'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"半句"}}\n\n',
          hold: const Duration(seconds: 5),
        ),
        timeouts: const AiStreamTimeouts(
          streamStall: Duration(milliseconds: 60),
        ),
      );
      await expectLater(
        sut.generate(request()).toList(),
        throwsA(isA<DeadlineExceededError>()),
      );
    });

    test('首响应超时以 DeadlineExceededError(aiFirstResponse) 结束', () async {
      final AnthropicMessagesAdapter sut = adapter(
        client: stalledClient('', hold: const Duration(seconds: 5)),
        timeouts: const AiStreamTimeouts(
          firstResponse: Duration(milliseconds: 60),
        ),
      );
      Object? error;
      try {
        await sut.generate(request()).toList();
      } on Object catch (e) {
        error = e;
      }
      expect(error, isA<DeadlineExceededError>());
      expect((error! as DeadlineExceededError).limitKind, 'aiFirstResponse');
    });
  });
}
