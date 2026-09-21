// T026：Responses 适配器（**独立**夹具与期望，不与 Chat Completions 共用）。
//
// 覆盖协议事实（主代理提供，检索于 2026-09-22）里的每一条：
//   - 请求体：input items（content 是分量数组）、instructions（系统指令在顶层）、
//     max_output_tokens（不是 max_tokens）；
//   - SSE 事件流：带 type 的事件对象，response.created / response.output_text.delta /
//     response.completed / response.failed / error；
//   - usage：response.completed 的 response.usage 里是 input_tokens/output_tokens；
//   - 未知事件类型必须被忽略（协议会继续加类型）；
//   - 错误映射与 Chat Completions 共用同一套状态码语义，但**字段路径不同**。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/domain/ai_message.dart';
import 'package:flux/infrastructure/network/ai_http.dart' show AiStreamTimeouts;
import 'package:flux/infrastructure/network/responses_adapter.dart';

import 'adapter_test_support.dart';

void main() {
  const String apiKey = 'sk-fixture-not-a-real-key-000000';

  ResponsesAdapter adapter({
    http.Client? client,
    AiStreamTimeouts timeouts = const AiStreamTimeouts(),
  }) => ResponsesAdapter(
    alias: 'openai',
    baseUrl: 'https://api.example.com',
    modelId: 'gpt-fixture',
    apiKey: apiKey,
    client: client,
    timeouts: timeouts,
  );

  AiRequest request({AiCancellation? cancellation, int? maxTokens}) =>
      AiRequest(
        modelId: 'gpt-fixture',
        messages: const <AiMessage>[
          AiMessage.system('你是助手'),
          AiMessage.user('回复：连接正常'),
        ],
        maxTokens: maxTokens,
        cancellation: cancellation,
      );

  group('请求形状（与 Chat Completions 结构不同）', () {
    test('端点、认证头与 input items 结构按协议发送', () async {
      http.BaseRequest? seen;
      final ResponsesAdapter sut = adapter(
        client: sseClient(
          readAiFixture('responses_stream.sse'),
          onRequest: (http.BaseRequest request) => seen = request,
        ),
      );
      await sut.generate(request(maxTokens: 64)).toList();

      expect(seen!.url.toString(), 'https://api.example.com/responses');
      expect(seen!.headers['Authorization'], 'Bearer $apiKey');
      expect(seen!.url.query, isEmpty);

      final Map<String, Object?> body =
          jsonDecode((seen as http.Request).body) as Map<String, Object?>;
      expect(body['model'], 'gpt-fixture');
      expect(body['stream'], isTrue);
      expect(
        body['max_output_tokens'],
        64,
        reason: 'Responses 用 max_output_tokens，不是 max_tokens',
      );
      expect(body.containsKey('max_tokens'), isFalse);
      expect(
        body['instructions'],
        '你是助手',
        reason: '系统指令走顶层 instructions，不是 input 里的一条 role=system',
      );

      final List<Object?> input = body['input']! as List<Object?>;
      expect(input, hasLength(1), reason: 'system 消息不进入 input');
      final Map<String, Object?> item = input.single! as Map<String, Object?>;
      expect(item['role'], 'user');
      final List<Object?> content = item['content']! as List<Object?>;
      expect(content.single, <String, Object?>{
        'type': 'input_text',
        'text': '回复：连接正常',
      }, reason: 'content 是分量数组，不是字符串');
    });

    test('没有系统消息时不发送 instructions 字段', () async {
      http.BaseRequest? seen;
      final ResponsesAdapter sut = adapter(
        client: sseClient(
          readAiFixture('responses_stream.sse'),
          onRequest: (http.BaseRequest request) => seen = request,
        ),
      );
      await sut
          .generate(
            AiRequest(
              modelId: 'gpt-fixture',
              messages: const <AiMessage>[AiMessage.user('hi')],
            ),
          )
          .toList();
      final Map<String, Object?> body =
          jsonDecode((seen as http.Request).body) as Map<String, Object?>;
      expect(body.containsKey('instructions'), isFalse);
    });

    test('Base URL 带路径前缀时端点保留前缀', () {
      final ResponsesAdapter sut = ResponsesAdapter(
        alias: 'gateway',
        baseUrl: 'https://api.example.com/openai/v1/',
        modelId: 'm',
        apiKey: apiKey,
      );
      expect(
        sut.endpoint.toString(),
        'https://api.example.com/openai/v1/responses',
      );
    });
  });

  group('事件流解析（type 事件）', () {
    test(
      '增量来自 response.output_text.delta，usage 来自 response.completed',
      () async {
        final ResponsesAdapter sut = adapter(
          client: sseClient(readAiFixture('responses_stream.sse')),
        );
        final List<AiEvent> events = await sut.generate(request()).toList();

        expect(events.whereType<AiDelta>().map((AiDelta e) => e.text), <String>[
          '连接',
          '正常',
        ]);
        final AiUsage usage = events.whereType<AiUsage>().single;
        expect(usage.inputTokens, 18);
        expect(
          usage.outputTokens,
          6,
          reason: 'Responses 的字段名是 input_tokens/output_tokens，映射到统一模型',
        );
        expect(usage.totalTokens, 24);
        expect(
          events.whereType<AiDone>().single.finishReason,
          'completed',
          reason: '结束原因来自 response.status',
        );
        expect(events.last, isA<AiDone>());
      },
    );

    test('CRLF 行尾与 event: 行都不影响解析', () async {
      final String crlf = readAiFixture('responses_stream.sse')
          .replaceAll('\n', '\r\n');
      final ResponsesAdapter sut = adapter(client: sseClient(crlf));
      final List<AiEvent> events = await sut.generate(request()).toList();
      expect(events.whereType<AiDelta>().map((AiDelta e) => e.text), <String>[
        '连接',
        '正常',
      ]);
      expect(events.whereType<AiUsage>().single.inputTokens, 18);
    });

    test('未知事件类型被忽略，成对的增量仍然按序产出', () async {
      final ResponsesAdapter sut = adapter(
        client: sseClient(readAiFixture('responses_multiline.sse')),
      );
      final List<AiEvent> events = await sut.generate(request()).toList();
      expect(events.whereType<AiDelta>().map((AiDelta e) => e.text), <String>[
        '甲',
        '乙',
      ], reason: '协议会继续加事件类型，未知类型必须被跳过而不是让流失败');
    });

    test('response.incomplete（输出被截断）按完成处理并带出状态', () async {
      final ResponsesAdapter sut = adapter(
        client: sseClient(readAiFixture('responses_multiline.sse')),
      );
      final List<AiEvent> events = await sut.generate(request()).toList();
      expect(events.whereType<AiDone>().single.finishReason, 'incomplete');
      expect(
        events.whereType<AiUsage>().single.outputTokens,
        4,
        reason: '被截断的输出同样要记账',
      );
    });

    test('没有 usage 时不产出 usage 事件（不编造 token 数）', () async {
      const String body =
          'data: {"type":"response.output_text.delta","delta":"x"}\n\n'
          'data: {"type":"response.completed","response":{"status":"completed"}}\n\n';
      final ResponsesAdapter sut = adapter(client: sseClient(body));
      final List<AiEvent> events = await sut.generate(request()).toList();
      expect(events.whereType<AiUsage>(), isEmpty);
      expect(events.whereType<AiDone>().single.finishReason, 'completed');
    });

    test('非 JSON 事件行被跳过，不终止整个流', () async {
      const String body =
          'data: not-json\n\n'
          'data: {"type":"response.output_text.delta","delta":"ok"}\n\n'
          'data: {"type":"response.completed","response":{"status":"completed"}}\n\n';
      final ResponsesAdapter sut = adapter(client: sseClient(body));
      final List<AiEvent> events = await sut.generate(request()).toList();
      expect(events.whereType<AiDelta>().single.text, 'ok');
    });
  });

  group('失败与断流', () {
    test('response.failed 的内嵌错误被翻译成类型化错误', () async {
      const String body =
          'data: {"type":"response.failed","response":{"status":"failed","error":{"code":"content_filter","type":"invalid_request_error"}}}\n\n';
      final ResponsesAdapter sut = adapter(client: sseClient(body));
      await expectLater(
        sut.generate(request()).toList(),
        throwsA(isA<ContentFilteredError>()),
      );
    });

    test('顶层 error 事件被翻译成类型化错误', () async {
      const String body =
          'data: {"type":"error","code":"server_error","message":"boom"}\n\n';
      final ResponsesAdapter sut = adapter(client: sseClient(body));
      await expectLater(
        sut.generate(request()).toList(),
        throwsA(isA<NetworkError>()),
      );
    });

    test('有增量但没有 response.completed：报断流错误', () async {
      final ResponsesAdapter sut = adapter(
        client: sseClient(readAiFixture('responses_truncated.sse')),
      );
      Object? error;
      try {
        await sut.generate(request()).toList();
      } on Object catch (e) {
        error = e;
      }
      expect(error, isA<NetworkError>());
      expect(
        (error! as NetworkError).message,
        contains('response.completed'),
        reason: '错误要说清缺的是哪一个事件，便于排查',
      );
    });

    test('完全没有事件就结束也报错（不是空成功）', () async {
      final ResponsesAdapter sut = adapter(client: sseClient(''));
      await expectLater(
        sut.generate(request()).toList(),
        throwsA(isA<NetworkError>()),
      );
    });

    test('400 content_filter 错误体映射为不可重试错误（路径与 CC 不同）', () async {
      final ResponsesAdapter sut = adapter(
        client: bodyClient(
          readAiFixture('responses_error_filter.json'),
          statusCode: 400,
        ),
      );
      final Object? error = await sut
          .generate(request())
          .toList()
          .then((_) => null, onError: (Object e) => e);
      expect(error, isA<ContentFilteredError>());
      expect((error! as ContentFilteredError).isRetryable, isFalse);
    });

    test('429 带 Retry-After 时映射为可重试的 RateLimitError', () async {
      final ResponsesAdapter sut = adapter(
        client: bodyClient(
          '{"error":{"message":"rate limited","type":"rate_limit_error","code":"rate_limit_exceeded"}}',
          statusCode: 429,
          headers: <String, String>{'retry-after': '3'},
        ),
      );
      final Object? error = await sut
          .generate(request())
          .toList()
          .then((_) => null, onError: (Object e) => e);
      expect(error, isA<RateLimitError>());
      expect((error! as RateLimitError).retryAfter, const Duration(seconds: 3));
    });

    test('错误消息里不出现 API Key', () async {
      final ResponsesAdapter sut = adapter(
        client: bodyClient('{"error":{"code":"x"}}', statusCode: 500),
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

  group('取消与超时（与 Chat Completions 同一套时限语义）', () {
    test('取消后流以 CancelledError 结束', () async {
      final AiCancellation cancellation = AiCancellation();
      final ResponsesAdapter sut = adapter(
        client: sseClient(
          readAiFixture('responses_stream.sse'),
          chunkSize: 4,
          gap: const Duration(milliseconds: 1),
        ),
      );
      bool sawDelta = false;
      Object? error;
      await sut
          .generate(request(cancellation: cancellation))
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
      expect(sawDelta, isTrue);
      expect(error, isA<CancelledError>());
    });

    test('已取消的信号在发出请求前就被识别', () async {
      bool sent = false;
      final ResponsesAdapter sut = adapter(
        client: sseClient(
          readAiFixture('responses_stream.sse'),
          onRequest: (http.BaseRequest request) => sent = true,
        ),
      );
      await expectLater(
        sut
            .generate(request(cancellation: AiCancellation()..cancel()))
            .toList(),
        throwsA(isA<CancelledError>()),
      );
      expect(sent, isFalse, reason: '已取消的请求一个字节都不该发出去');
    });

    test('流停滞超时以 DeadlineExceededError 结束', () async {
      final ResponsesAdapter sut = adapter(
        client: stalledClient(
          'data: {"type":"response.output_text.delta","delta":"半句"}\n\n',
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
  });
}
