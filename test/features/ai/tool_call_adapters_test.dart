// T032：三个适配器的工具调用解析与回填（各自独立，互不共用期望）。
//
// 三个协议的**形状不同**，这正是「不能只改 URL」的又一处体现：
//   Chat Completions：delta.tool_calls 分片到达，arguments 是 **JSON 字符串**，逐段拼；
//   Responses：output_item.done 里的 function_call 项，一层字段，arguments 也是字符串；
//   Anthropic：content_block_start 里的 tool_use 块 + partial_json 增量，input 是对象。
//
// 回填方向也不同：
//   Chat Completions：role=tool 的消息 + tool_call_id；
//   Responses：独立的 function_call_output 项 + call_id；
//   Anthropic：user 消息里的 tool_result 内容块 + tool_use_id。
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/features/ai/domain/ai_message.dart';
import 'package:flux/features/ai/domain/tool_call.dart';
import 'package:flux/infrastructure/network/ai_http.dart';
import 'package:flux/infrastructure/network/anthropic_messages_adapter.dart';
import 'package:flux/infrastructure/network/chat_completions_adapter.dart';
import 'package:flux/infrastructure/network/responses_adapter.dart';

import 'adapter_test_support.dart';

void main() {
  const String apiKey = 'sk-fixture-not-a-real-key-000000';

  AiRequest requestWithToolResult({
    required String id,
    required String content,
  }) => AiRequest(
    modelId: 'model-x',
    messages: <AiMessage>[
      const AiMessage.user('查一下'),
      AiMessage.tool(content, toolCallId: id),
    ],
  );

  group('Chat Completions：分片到达的 tool_calls', () {
    test('跨 chunk 的 arguments 按 index 归位拼接（两个并发调用不串参数）', () async {
      // 注意 JSON 里的转义层级：SSE 负载本身是 JSON 字符串，而 arguments 又是它内部
      // 的一个 JSON 字符串，因此这里是两层反斜杠。
      const String body =
          'data: {"choices":[{"delta":{"tool_calls":['
          '{"index":0,"id":"call_a","function":{"name":"search"}},'
          '{"index":1,"id":"call_b","function":{"name":"fetchPage"}}'
          ']},"index":0}]}\n'
          '\n'
          'data: {"choices":[{"delta":{"tool_calls":['
          '{"index":0,"function":{"arguments":"{\\"qu"}}'
          ']},"index":0}]}\n'
          '\n'
          'data: {"choices":[{"delta":{"tool_calls":['
          '{"index":1,"function":{"arguments":"{\\"url\\":\\"https://e.com\\"}"}}'
          ']},"index":0}]}\n'
          '\n'
          'data: {"choices":[{"delta":{"tool_calls":['
          '{"index":0,"function":{"arguments":"ery\\":\\"flux\\"}"}}'
          ']},"index":0}]}\n'
          '\n'
          'data: [DONE]\n'
          '\n';

      final ChatCompletionsAdapter sut = ChatCompletionsAdapter(
        alias: 'x',
        baseUrl: 'https://api.example.com',
        modelId: 'm',
        apiKey: apiKey,
        client: sseClient(body),
      );
      final List<Object?> events = await sut
          .generate(requestWithToolResult(id: 'x', content: 'y'))
          .toList();
      final List<AiToolCalls> toolEvents = events
          .whereType<AiToolCalls>()
          .toList();
      expect(toolEvents, hasLength(1));
      final List<ToolCall> calls = toolEvents.single.calls;
      expect(calls, hasLength(2));
      // 按 index 归位：0 号拿到 query，1 号拿到 url——**没有**互相接到对方身上。
      expect(calls[0].rawName, 'search');
      expect(calls[0].args['query'], 'flux');
      expect(calls[0].args.containsKey('url'), isFalse);
      expect(calls[1].rawName, 'fetchPage');
      expect(calls[1].args['url'], 'https://e.com');
      expect(calls[1].args.containsKey('query'), isFalse);
    });

    test('回填：role=tool + tool_call_id（缺 id 时不编一个假 id）', () {
      final Map<String, Object?> withId = chatCompletionsRequestBody(
        requestWithToolResult(id: 'call_a', content: '结果'),
        'm',
      );
      final List<Object?> messages = withId['messages']! as List<Object?>;
      final Map<String, Object?> tool = messages.last! as Map<String, Object?>;
      expect(tool['role'], 'tool');
      expect(tool['tool_call_id'], 'call_a');
      expect(tool['content'], '结果');

      final Map<String, Object?> withoutId = chatCompletionsRequestBody(
        AiRequest(
          modelId: 'm',
          messages: <AiMessage>[const AiMessage.tool('结果')],
        ),
        'm',
      );
      final Map<String, Object?> bare =
          (withoutId['messages']! as List<Object?>).single!
              as Map<String, Object?>;
      expect(bare.containsKey('tool_call_id'), isFalse);
    });

    test('tools 声明被发给服务商（形状为 {type:function, function:{...}}）', () {
      final AiRequest request = AiRequest(
        modelId: 'm',
        messages: const <AiMessage>[AiMessage.user('x')],
        tools: const <AiToolDeclaration>[
          AiToolDeclaration(
            name: 'search',
            description: '检索',
            parameters: <String, Object?>{'type': 'object'},
          ),
        ],
      );
      final Map<String, Object?> body = chatCompletionsRequestBody(
        request,
        'm',
      );
      final List<Object?> tools = body['tools']! as List<Object?>;
      final Map<String, Object?> first = tools.single! as Map<String, Object?>;
      expect(first['type'], 'function');
      final Map<String, Object?> function =
          first['function']! as Map<String, Object?>;
      expect(function['name'], 'search');
      expect(function['parameters'], <String, Object?>{'type': 'object'});
    });
  });

  group('Responses：function_call 输出项与 function_call_output 回填', () {
    test('output_item.done 里的 function_call 被解析成 ToolCall', () async {
      const String body =
          'data: {"type":"response.output_item.done","item":{'
          '"type":"function_call","call_id":"call_r1","name":"search",'
          '"arguments":"{\\"query\\":\\"flux\\"}"}}\n'
          '\n'
          'data: {"type":"response.completed","response":{'
          '"status":"completed","usage":{"input_tokens":10,"output_tokens":2}}}\n'
          '\n';

      final ResponsesAdapter sut = ResponsesAdapter(
        alias: 'x',
        baseUrl: 'https://api.example.com',
        modelId: 'm',
        apiKey: apiKey,
        client: sseClient(body),
      );
      final List<Object?> events = await sut
          .generate(
            AiRequest(
              modelId: 'm',
              messages: const <AiMessage>[AiMessage.user('x')],
            ),
          )
          .toList();
      final AiToolCalls toolEvent = events.whereType<AiToolCalls>().single;
      expect(toolEvent.calls.single.rawName, 'search');
      expect(toolEvent.calls.single.id, 'call_r1');
      expect(toolEvent.calls.single.args['query'], 'flux');
    });

    test('回填形状是独立的 function_call_output 项（字段名是 call_id）', () {
      final Map<String, Object?> body = responsesRequestBody(
        requestWithToolResult(id: 'call_r1', content: '材料'),
        'm',
      );
      final List<Object?> input = body['input']! as List<Object?>;
      final Map<String, Object?> output = input.last! as Map<String, Object?>;
      expect(output['type'], 'function_call_output');
      expect(output['call_id'], 'call_r1');
      expect(output['output'], '材料');
      // **不是** input 里的一条 role=tool 消息（协议不接受那种形状）。
      expect(output.containsKey('role'), isFalse);
    });

    test('tools 声明形状与 Chat Completions 不同（没有 function 包装）', () {
      final AiRequest request = AiRequest(
        modelId: 'm',
        messages: const <AiMessage>[AiMessage.user('x')],
        tools: const <AiToolDeclaration>[
          AiToolDeclaration(
            name: 'search',
            description: '检索',
            parameters: <String, Object?>{'type': 'object'},
          ),
        ],
      );
      final Map<String, Object?> body = responsesRequestBody(request, 'm');
      final Map<String, Object?> first =
          (body['tools']! as List<Object?>).single! as Map<String, Object?>;
      expect(first['name'], 'search');
      expect(first.containsKey('function'), isFalse);
      expect(first['type'], 'function');
    });
  });

  group('Anthropic：tool_use 块与 tool_result 回填', () {
    test('content_block_start + partial_json 增量拼成完整 input', () async {
      const String body =
          'event: message_start\n'
          'data: {"type":"message_start","message":{"usage":{"input_tokens":5,"output_tokens":0}}}\n'
          '\n'
          'event: content_block_start\n'
          'data: {"type":"content_block_start","index":0,"content_block":{'
          '"type":"tool_use","id":"toolu_1","name":"fetchPage","input":{}}}\n'
          '\n'
          'event: content_block_delta\n'
          'data: {"type":"content_block_delta","index":0,"delta":{'
          '"type":"input_json_delta","partial_json":"{\\"url\\""}}\n'
          '\n'
          'event: content_block_delta\n'
          'data: {"type":"content_block_delta","index":0,"delta":{'
          '"type":"input_json_delta","partial_json":":\\"https://e.com/x\\"}"}}\n'
          '\n'
          'event: content_block_stop\n'
          'data: {"type":"content_block_stop","index":0}\n'
          '\n'
          'event: message_delta\n'
          'data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":8}}\n'
          '\n'
          'event: message_stop\n'
          'data: {"type":"message_stop"}\n'
          '\n';

      final AnthropicMessagesAdapter sut = AnthropicMessagesAdapter(
        alias: 'x',
        baseUrl: 'https://api.example.com',
        modelId: 'm',
        apiKey: apiKey,
        client: sseClient(body),
      );
      final List<Object?> events = await sut
          .generate(
            AiRequest(
              modelId: 'm',
              messages: const <AiMessage>[AiMessage.user('x')],
            ),
          )
          .toList();
      final AiToolCalls toolEvent = events.whereType<AiToolCalls>().single;
      expect(toolEvent.calls, hasLength(1));
      expect(toolEvent.calls.single.rawName, 'fetchPage');
      expect(toolEvent.calls.single.id, 'toolu_1');
      expect(
        toolEvent.calls.single.args['url'],
        'https://e.com/x',
        reason: 'partial_json 分片必须被拼接（丢掉它会让参数成为空对象）',
      );
    });

    test('回填形状是 user 消息里的 tool_result 块（字段名是 tool_use_id）', () {
      final Map<String, Object?> body = anthropicMessagesRequestBody(
        requestWithToolResult(id: 'toolu_1', content: '材料'),
        'm',
      );
      final List<Object?> messages = body['messages']! as List<Object?>;
      final Map<String, Object?> last = messages.last! as Map<String, Object?>;
      expect(last['role'], 'user');
      final Map<String, Object?> block =
          (last['content']! as List<Object?>).single! as Map<String, Object?>;
      expect(block['type'], 'tool_result');
      expect(block['tool_use_id'], 'toolu_1');
      expect(block['content'], '材料');
    });

    test('tools 声明用 input_schema（不是 parameters，也没有 function 包装）', () {
      final AiRequest request = AiRequest(
        modelId: 'm',
        messages: const <AiMessage>[AiMessage.user('x')],
        tools: const <AiToolDeclaration>[
          AiToolDeclaration(
            name: 'search',
            description: '检索',
            parameters: <String, Object?>{'type': 'object'},
          ),
        ],
      );
      final Map<String, Object?> body = anthropicMessagesRequestBody(
        request,
        'm',
      );
      final Map<String, Object?> first =
          (body['tools']! as List<Object?>).single! as Map<String, Object?>;
      expect(first['name'], 'search');
      expect(first['input_schema'], <String, Object?>{'type': 'object'});
      expect(first.containsKey('parameters'), isFalse);
    });
  });

  group('统一事件顺序', () {
    test('工具调用事件在 done 之前发出（消费者据此决定是否执行）', () async {
      const String body =
          'data: {"choices":[{"delta":{"tool_calls":['
          '{"index":0,"id":"c1","function":{"name":"search","arguments":"{}"}}'
          ']},"index":0}]}\n'
          '\n'
          'data: [DONE]\n'
          '\n';
      final ChatCompletionsAdapter sut = ChatCompletionsAdapter(
        alias: 'x',
        baseUrl: 'https://api.example.com',
        modelId: 'm',
        apiKey: apiKey,
        client: sseClient(body),
      );
      final List<Object?> events = await sut
          .generate(
            AiRequest(
              modelId: 'm',
              messages: const <AiMessage>[AiMessage.user('x')],
            ),
          )
          .toList();
      final int toolIndex = events.indexWhere((Object? e) => e is AiToolCalls);
      final int doneIndex = events.indexWhere((Object? e) => e is AiDone);
      expect(toolIndex, greaterThanOrEqualTo(0));
      expect(
        toolIndex,
        lessThan(doneIndex),
        reason: 'done 表示本轮结束；调用点需要在它之前看到工具请求',
      );
    });
  });
}
