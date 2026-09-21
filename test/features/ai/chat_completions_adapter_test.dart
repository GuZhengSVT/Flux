// T026：Chat Completions 适配器（**独立**夹具与期望，不与 Responses 共用）。
//
// 覆盖协议事实（主代理提供，检索于 2026-09-22）里的每一条：
//   - 请求体形状：model / messages / stream / stream_options.include_usage / max_tokens；
//   - SSE：`data: {json}` 与终止 `data: [DONE]`；
//   - chunk 形状：choices[].delta.content，finish_reason 在同级；
//   - usage 只在最后一个 choices 为空的 chunk 里出现（include_usage 时）；
//   - 错误体 {"error":{"message","type","code"}}，429 服从 Retry-After；
//   - 取消 → CancelledError；首响应 45s / 停滞 30s 超时（SET-036 默认值）；
//   - key 不进日志（用 Authorization 头断言，并检查错误消息里没有它）。
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/domain/ai_message.dart';
import 'package:flux/infrastructure/network/ai_http.dart' show AiStreamTimeouts;
import 'package:flux/infrastructure/network/chat_completions_adapter.dart';

import 'adapter_test_support.dart';

void main() {
  const String apiKey = 'sk-fixture-not-a-real-key-000000';

  ChatCompletionsAdapter adapter({
    http.Client? client,
    AiStreamTimeouts timeouts = const AiStreamTimeouts(),
  }) => ChatCompletionsAdapter(
    alias: 'deepseek',
    baseUrl: 'https://api.example.com',
    modelId: 'deepseek-chat',
    apiKey: apiKey,
    client: client,
    timeouts: timeouts,
  );

  AiRequest request({AiCancellation? cancellation, int? maxTokens}) =>
      AiRequest(
        modelId: 'deepseek-chat',
        messages: const <AiMessage>[
          AiMessage.system('你是助手'),
          AiMessage.user('回复：连接正常'),
        ],
        maxTokens: maxTokens,
        cancellation: cancellation,
      );

  group('请求形状', () {
    test('端点、认证头、SSE 接受头与 include_usage 都按协议发送', () async {
      http.BaseRequest? seen;
      final ChatCompletionsAdapter sut = adapter(
        client: sseClient(
          readAiFixture('chat_completions_stream.sse'),
          onRequest: (http.BaseRequest request) => seen = request,
        ),
      );
      await sut.generate(request(maxTokens: 64)).toList();

      expect(seen!.method, 'POST');
      expect(seen!.url.toString(), 'https://api.example.com/chat/completions');
      // Key 只出现在 Authorization 头里，不出现于 URL。
      expect(seen!.headers['Authorization'], 'Bearer $apiKey');
      expect(seen!.url.query, isEmpty, reason: '凭据绝不进 query（会进日志与代理记录）');
      expect(seen!.headers['Accept'], contains('text/event-stream'));

      final Map<String, Object?> body =
          jsonDecode((seen as http.Request).body) as Map<String, Object?>;
      expect(body['model'], 'deepseek-chat');
      expect(body['stream'], isTrue);
      expect(body['stream_options'], <String, Object?>{
        'include_usage': true,
      }, reason: '不发 include_usage 就拿不到服务商统计的 token 数');
      expect(body['max_tokens'], 64);
      final List<Object?> messages = body['messages']! as List<Object?>;
      expect(messages, hasLength(2));
      expect((messages.first! as Map<String, Object?>)['role'], 'system');
      expect((messages.last! as Map<String, Object?>)['content'], '回复：连接正常');
    });

    test('未指定 max_tokens / temperature 时不发送这两个字段', () async {
      http.BaseRequest? seen;
      final ChatCompletionsAdapter sut = adapter(
        client: sseClient(
          readAiFixture('chat_completions_stream.sse'),
          onRequest: (http.BaseRequest request) => seen = request,
        ),
      );
      await sut.generate(request()).toList();
      final Map<String, Object?> body =
          jsonDecode((seen as http.Request).body) as Map<String, Object?>;
      expect(body.containsKey('max_tokens'), isFalse);
      expect(body.containsKey('temperature'), isFalse);
    });

    test('Base URL 带路径前缀时端点保留前缀', () {
      final ChatCompletionsAdapter sut = ChatCompletionsAdapter(
        alias: 'gateway',
        baseUrl: 'https://api.example.com/openai/v1/',
        modelId: 'm',
        apiKey: apiKey,
      );
      expect(
        sut.endpoint.toString(),
        'https://api.example.com/openai/v1/chat/completions',
      );
    });
  });

  group('SSE 流解析（正常路径）', () {
    test('按顺序产出增量、usage 与完成事件', () async {
      final ChatCompletionsAdapter sut = adapter(
        client: sseClient(readAiFixture('chat_completions_stream.sse')),
      );
      final List<AiEvent> events = await sut.generate(request()).toList();

      final List<String> deltas = events
          .whereType<AiDelta>()
          .map((AiDelta e) => e.text)
          .toList();
      expect(deltas, <String>['连接', '正常'], reason: '角色 chunk 的空 content 不产生增量');

      final AiUsage usage = events.whereType<AiUsage>().single;
      expect(usage.inputTokens, 31);
      expect(usage.outputTokens, 6);
      expect(usage.totalTokens, 37);
      expect(usage.totalIsEstimated, isFalse, reason: '服务商给了总量就不该标成本地合计');

      final AiDone done = events.whereType<AiDone>().single;
      expect(done.finishReason, 'stop');
      expect(events.last, isA<AiDone>(), reason: '完成事件必须是最后一个（消费者据此认为流已结束）');
    });

    test('usage 事件在 done 之前（预算记账不能晚于结束）', () async {
      final ChatCompletionsAdapter sut = adapter(
        client: sseClient(readAiFixture('chat_completions_stream.sse')),
      );
      final List<AiEvent> events = await sut.generate(request()).toList();
      expect(
        events.indexWhere((AiEvent e) => e is AiUsage),
        lessThan(events.indexWhere((AiEvent e) => e is AiDone)),
      );
    });

    test('服务商只给 prompt/completion、不给 total 时标为本地合计', () async {
      final ChatCompletionsAdapter sut = adapter(
        client: sseClient(readAiFixture('chat_completions_multiline.sse')),
      );
      final List<AiEvent> events = await sut.generate(request()).toList();
      final AiUsage usage = events.whereType<AiUsage>().single;
      expect(usage.inputTokens, 12);
      expect(usage.outputTokens, 8);
      expect(usage.totalIsEstimated, isTrue);
      expect(usage.effectiveTotal, 20);
    });

    test('finish_reason=length（触顶）如实传出，不当成错误', () async {
      const String body =
          'data: {"choices":[{"index":0,"delta":{"content":"截断"},"finish_reason":null}]}\n\n'
          'data: {"choices":[{"index":0,"delta":{},"finish_reason":"length"}]}\n\n'
          'data: [DONE]\n\n';
      final ChatCompletionsAdapter sut = adapter(client: sseClient(body));
      final List<AiEvent> events = await sut.generate(request()).toList();
      expect(events.whereType<AiDone>().single.finishReason, 'length');
    });
  });

  group('SSE 边界（CRLF、心跳、多行、空 delta）', () {
    test('CRLF 行尾被剥除，负载仍能解析', () async {
      // 把夹具改写成 CRLF：真实服务商与中间代理都可能这样发。
      final String crlf = readAiFixture('chat_completions_stream.sse')
          .replaceAll('\n', '\r\n');
      final ChatCompletionsAdapter sut = adapter(client: sseClient(crlf));
      final List<AiEvent> events = await sut.generate(request()).toList();
      expect(events.whereType<AiDelta>().map((AiDelta e) => e.text), <String>[
        '连接',
        '正常',
      ], reason: '负载尾部残留 \\r 会让 JSON 解析失败（这是最容易漏的一条边界）');
      expect(events.whereType<AiUsage>().single.inputTokens, 31);
    });

    test('注释心跳行被忽略，delta:null 的 chunk 不产生增量', () async {
      final ChatCompletionsAdapter sut = adapter(
        client: sseClient(readAiFixture('chat_completions_multiline.sse')),
      );
      final List<AiEvent> events = await sut.generate(request()).toList();
      expect(events.whereType<AiDelta>().map((AiDelta e) => e.text), <String>[
        '第一段',
        '第二',
        '段',
      ], reason: '心跳行不能变成增量；delta:null 与空 content 都不产出');
    });

    test('跨 chunk 的半个 JSON 行被正确拼回（按 3 字节切块）', () async {
      final ChatCompletionsAdapter sut = adapter(
        client: sseClient(
          readAiFixture('chat_completions_stream.sse'),
          chunkSize: 3,
        ),
      );
      final List<AiEvent> events = await sut.generate(request()).toList();
      expect(events.whereType<AiDelta>().map((AiDelta e) => e.text), <String>[
        '连接',
        '正常',
      ]);
    });

    test('单个非 JSON 的 data 行被跳过，不终止整个流', () async {
      const String body =
          'data: this-is-not-json\n\n'
          'data: {"choices":[{"index":0,"delta":{"content":"ok"},"finish_reason":"stop"}]}\n\n'
          'data: [DONE]\n\n';
      final ChatCompletionsAdapter sut = adapter(client: sseClient(body));
      final List<AiEvent> events = await sut.generate(request()).toList();
      expect(
        events.whereType<AiDelta>().single.text,
        'ok',
        reason: '一个坏 chunk 不该让用户已看到的内容全部作废',
      );
    });
  });

  group('断流与异常终止', () {
    test('没有 [DONE]、也没有 finish_reason 时报断流错误', () async {
      final ChatCompletionsAdapter sut = adapter(
        client: sseClient(readAiFixture('chat_completions_truncated.sse')),
      );
      await expectLater(
        sut.generate(request()).toList(),
        throwsA(isA<NetworkError>()),
      );
    });

    test('只有一个有效的空 chunk 也可能合法（有 finish_reason 即可）', () async {
      const String body =
          'data: {"choices":[{"index":0,"delta":{"content":"x"},"finish_reason":"stop"}]}\n\n';
      final ChatCompletionsAdapter sut = adapter(client: sseClient(body));
      // 没有 [DONE] 但有 finish_reason：按成功结束（有些兼容实现不发 [DONE]）。
      final List<AiEvent> events = await sut.generate(request()).toList();
      expect(events.whereType<AiDone>().single.finishReason, 'stop');
    });

    test('200 流里内嵌 {"error":...} 被翻译成类型化错误', () async {
      const String body =
          'data: {"error":{"message":"boom","type":"server_error","code":"internal"}}\n\n';
      final ChatCompletionsAdapter sut = adapter(client: sseClient(body));
      await expectLater(
        sut.generate(request()).toList(),
        throwsA(isA<NetworkError>()),
      );
    });
  });

  group('错误映射（状态码 + 错误体）', () {
    test('429 映射为 RateLimitError 并读取 Retry-After', () async {
      final ChatCompletionsAdapter sut = adapter(
        client: bodyClient(
          readAiFixture('chat_completions_error_429.json'),
          statusCode: 429,
          headers: <String, String>{'retry-after': '7'},
        ),
      );
      final Object? error = await sut
          .generate(request())
          .toList()
          .then((_) => null, onError: (Object e) => e);
      expect(error, isA<RateLimitError>());
      final RateLimitError rate = error! as RateLimitError;
      expect(rate.retryAfter, const Duration(seconds: 7));
      expect(rate.isRetryable, isTrue);
      expect(
        rate.message,
        contains('type=requests'),
        reason: '只带结构性字段（type/code），不带响应体文案',
      );
    });

    test('401 映射为不可重试的 AuthError', () async {
      final ChatCompletionsAdapter sut = adapter(
        client: bodyClient(
          '{"error":{"message":"Incorrect API key provided","type":"invalid_request_error","code":"invalid_api_key"}}',
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

    test('400 content_filter 映射为不可重试的 ContentFilteredError', () async {
      final ChatCompletionsAdapter sut = adapter(
        client: bodyClient(
          '{"error":{"message":"filtered","type":"invalid_request_error","code":"content_filter"}}',
          statusCode: 400,
        ),
      );
      final Object? error = await sut
          .generate(request())
          .toList()
          .then((_) => null, onError: (Object e) => e);
      expect(error, isA<ContentFilteredError>());
    });

    test('错误响应体不是 JSON 时仍按状态码分类（读不出体不影响判断）', () async {
      final ChatCompletionsAdapter sut = adapter(
        client: bodyClient('<html>502 Bad Gateway</html>', statusCode: 502),
      );
      final Object? error = await sut
          .generate(request())
          .toList()
          .then((_) => null, onError: (Object e) => e);
      expect(error, isA<NetworkError>());
      expect((error! as NetworkError).statusCode, 502);
    });

    test('错误消息里不出现 API Key', () async {
      final ChatCompletionsAdapter sut = adapter(
        client: bodyClient(
          '{"error":{"message":"bad","type":"invalid_request_error","code":"x"}}',
          statusCode: 400,
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
      final ChatCompletionsAdapter sut = adapter(
        client: sseClient(
          readAiFixture('chat_completions_stream.sse'),
          chunkSize: 4,
          gap: const Duration(milliseconds: 1),
        ),
      );
      final Stream<AiEvent> stream = sut.generate(
        request(cancellation: cancellation),
      );
      // 同一个 Stream 只能订阅一次，因此不能用「另一个 future 里 first()」与
      // toList() 共享它；改成在 map 里消费第一个增量时取消。
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
      final ChatCompletionsAdapter sut = adapter(
        client: sseClient(
          readAiFixture('chat_completions_stream.sse'),
          onRequest: (http.BaseRequest request) => sent = true,
        ),
      );
      await expectLater(
        sut.generate(request(cancellation: cancellation)).toList(),
        throwsA(isA<CancelledError>()),
      );
      expect(sent, isFalse, reason: '已取消的请求一个字节都不该发出去（可能会计费）');
    });
  });

  group('超时（SET-036 默认值）', () {
    test('默认首响应 45 秒、停滞 30 秒', () {
      const AiStreamTimeouts defaults = AiStreamTimeouts();
      expect(defaults.firstResponse, const Duration(seconds: 45));
      expect(defaults.streamStall, const Duration(seconds: 30));
    });

    test('流中途停滞会以 DeadlineExceededError 结束，不无限等待', () async {
      final ChatCompletionsAdapter sut = adapter(
        client: stalledClient(
          'data: {"choices":[{"index":0,"delta":{"content":"半句"},"finish_reason":null}]}\n\n',
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

    test('首响应超时（连接建立后不吐字节）以 DeadlineExceededError 结束', () async {
      final ChatCompletionsAdapter sut = adapter(
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
