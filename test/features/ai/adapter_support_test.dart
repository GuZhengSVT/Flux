// T026：SSE 解析、夹具独立性与适配器工厂（协议无关的共用层）。
//
// 三条断言：
//   1) SSE 层的四条边界（按字节切行、CRLF、多行 data、上限）行为正确；
//   2) **两个协议的夹具与期望是分开的**（架构 4.3 要求独立建模、不能只改 URL）——
//      这条用「两份正常流夹具的负载形状确实不同」来钉住，避免以后有人为了省事
//      把它们合并成一份，从而让「把 Responses 解析器接到 CC 上」看不出区别；
//   3) 工厂对未实现/非法配置返回类型化错误，而不是抛异常或造出一个会发错请求的适配器。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/domain/ai_message.dart';
import 'package:flux/features/ai/domain/ai_protocol.dart';
import 'package:flux/features/ai/domain/ai_provider.dart';
import 'package:flux/infrastructure/network/ai_provider_factory.dart';
import 'package:flux/infrastructure/network/ai_http.dart'
    show parseAnthropicUsage, parseChatCompletionsUsage, parseResponsesUsage;
import 'package:flux/infrastructure/network/anthropic_messages_adapter.dart';
import 'package:flux/infrastructure/network/chat_completions_adapter.dart';
import 'package:flux/infrastructure/network/responses_adapter.dart';
import 'package:flux/infrastructure/network/sse.dart';

import 'adapter_test_support.dart';

void main() {
  group('SSE 解析', () {
    final Uri endpoint = Uri.parse('https://api.example.com/x');

    Future<List<String>> payloads(String body, {int chunkSize = 5}) =>
        sseEventPayloads(
          chunkedBytes(body, chunkSize: chunkSize),
          endpoint: endpoint,
        ).toList();

    test('按空行切分事件，多行 data 用换行拼接', () async {
      final List<String> result = await payloads(
        'data: line-a\ndata: line-b\n\n',
      );
      expect(result, <String>['line-a\nline-b']);
    });

    test('注释行被忽略，且不产生空事件', () async {
      final List<String> result = await payloads(': heartbeat\n\ndata: x\n\n');
      expect(result, <String>['x']);
    });

    test('CRLF 行尾被剥除', () async {
      final List<String> result = await payloads('data: x\r\n\r\n');
      expect(result, <String>['x']);
    });

    test('只剥掉 data: 后的一个空格（多余空白属于负载）', () async {
      expect(await payloads('data:  two-spaces\n\n'), <String>[' two-spaces']);
    });

    test('event:/id: 行被忽略（事件类型在负载内部）', () async {
      final List<String> result = await payloads(
        'event: response.delta\nid: 42\ndata: payload\n\n',
      );
      expect(result, <String>['payload']);
    });

    test('流结束时未闭合的最后一行也被派发（少发空行是常见偏差）', () async {
      expect(await payloads('data: tail'), <String>['tail']);
    });

    test('中文在多字节字符被切开时依然完整（按字节切行再解码）', () async {
      // 每 1 字节切一次：任何一个中文都会被切开多次。
      final List<String> result = await payloads(
        'data: {"t":"连接正常"}\n\n',
        chunkSize: 1,
      );
      expect(result, hasLength(1));
      final Map<String, Object?> decoded =
          jsonDecode(result.single) as Map<String, Object?>;
      expect(decoded['t'], '连接正常', reason: '按块解码会把多字节字符解成替换字符——中文输出下几乎必然触发');
    });

    test('非 data 开头的普通文本行被忽略', () async {
      expect(await payloads('hello\n\ndata: real\n\n'), <String>['real']);
    });

    test('超过字节上限的流抛出类型化错误', () async {
      // 造一个超过 16 MiB 的流（每块 64 KiB，共 300 块 ≈ 19 MiB）。
      Stream<List<int>> flood() async* {
        final List<int> chunk = List<int>.filled(64 * 1024, 0x41);
        for (int i = 0; i < 300; i++) {
          yield chunk;
        }
      }

      await expectLater(
        sseEventPayloads(flood(), endpoint: endpoint).toList(),
        throwsA(isA<NetworkError>()),
      );
    });
  });

  group('夹具独立性（架构 4.3：不能只改 URL）', () {
    test('两个协议的正常流夹具形状确实不同', () {
      final String chat = readAiFixture('chat_completions_stream.sse');
      final String responses = readAiFixture('responses_stream.sse');

      expect(
        chat,
        contains('"choices"'),
        reason: 'Chat Completions 靠 chunk 里的 choices[].delta',
      );
      expect(chat, contains('data: [DONE]'), reason: 'CC 用 [DONE] 终止');
      expect(
        chat,
        contains('prompt_tokens'),
        reason: 'CC 的 usage 字段名是 prompt_tokens/completion_tokens',
      );

      expect(
        responses,
        contains('"type":"response.output_text.delta"'),
        reason: 'Responses 靠带 type 的事件对象',
      );
      expect(responses, contains('response.completed'));
      expect(
        responses,
        contains('input_tokens'),
        reason: 'Responses 的 usage 字段名是 input_tokens/output_tokens',
      );
      expect(
        responses,
        isNot(contains('data: [DONE]')),
        reason: 'Responses 不用 [DONE] 终止（用 event 语法与 completed 事件）',
      );
    });

    test('两个协议的 usage 解析互不通用（字段名不同）', () {
      // 这是「独立建模」的可执行证据：把 Responses 的 usage 喂给 CC 的解析器会得到 null。
      final Map<String, Object?> responsesUsage = jsonDecode(
        '{"input_tokens":18,"output_tokens":6,"total_tokens":24}',
      ) as Map<String, Object?>;
      final Map<String, Object?> chatUsage = jsonDecode(
        '{"prompt_tokens":31,"completion_tokens":6,"total_tokens":37}',
      ) as Map<String, Object?>;

      expect(parseChatCompletionsUsage(chatUsage)!.inputTokens, 31);
      expect(
        parseChatCompletionsUsage(responsesUsage),
        isNull,
        reason: '两种 usage 的字段名不同，不能互相解析',
      );
      expect(parseResponsesUsage(responsesUsage)!.inputTokens, 18);
      expect(parseResponsesUsage(chatUsage), isNull, reason: '反向同样不通用');
    });

    test('Anthropic 的第三份正常流夹具形状与前两者都不同', () {
      final String anthropic = readAiFixture('anthropic_stream.sse');
      expect(
        anthropic,
        contains('"type":"message_start"'),
        reason: 'Anthropic 靠带 type 的事件对象（且事件名与 Responses 不同）',
      );
      expect(anthropic, contains('"type":"content_block_delta"'));
      expect(anthropic, contains('"type":"text_delta"'));
      expect(
        anthropic,
        contains('message_stop'),
        reason: 'Anthropic 用 message_stop 终止，不是 [DONE] 也不是 response.completed',
      );
      expect(anthropic, isNot(contains('data: [DONE]')));
      expect(anthropic, isNot(contains('"choices"')));
      expect(anthropic, isNot(contains('response.completed')));
    });

    test('Anthropic 的 usage 只给 input/output（无 total），且与另两种不通用', () {
      final Map<String, Object?> anthropicUsage = jsonDecode(
        '{"input_tokens":31,"output_tokens":6}',
      ) as Map<String, Object?>;
      final AiUsage? parsed = parseAnthropicUsage(anthropicUsage);
      expect(parsed!.inputTokens, 31);
      expect(parsed.outputTokens, 6);
      expect(
        parsed.totalIsEstimated,
        isTrue,
        reason: '协议不给 total_tokens：不能本地编造一个「服务商统计」的总量',
      );

      // 与 CC 的字段名（prompt/completion）不同。
      expect(
        parseChatCompletionsUsage(anthropicUsage),
        isNull,
        reason: 'Anthropic 的 usage 不能被 Chat Completions 的解析器读出',
      );
      // 注意：Anthropic 的 usage **字段名**恰好与 Responses 相同
      // （input_tokens/output_tokens）。因此「复用 Responses 的解析器」在单个
      // usage 对象上看起来能通过——这正是要显式记下的一处陷阱。真正的差异不在
      // 字段名，而在**到达方式**：Anthropic 把 input 放在 message_start、把
      // output 放在 message_delta，必须在适配器里拼合（见
      // anthropic_messages_adapter_test 的「usage 拼合」用例）。Responses 从不
      // 这样分两处给。这里断言两个解析器对同一对象给出相同结果，把这个事实固定下来。
      expect(
        parseResponsesUsage(anthropicUsage)!.inputTokens,
        parsed.inputTokens,
        reason: '字段名相同是巧合，不是可复用的证据——差异在事件的到达方式',
      );
    });

    test('夹具里没有真实凭据（只有明显的假值）', () {
      for (final String name in <String>[
        'chat_completions_stream.sse',
        'chat_completions_error_429.json',
        'responses_stream.sse',
        'responses_error_filter.json',
        'anthropic_stream.sse',
        'anthropic_error_429.json',
        'anthropic_error_529.json',
      ]) {
        final String body = readAiFixture(name);
        final Iterable<RegExpMatch> keys = RegExp(r'sk-[A-Za-z0-9_-]{8,}')
            .allMatches(body);
        for (final RegExpMatch match in keys) {
          expect(
            match.group(0),
            anyOf(startsWith('sk-fixture')),
            reason: '$name 里出现了非夹具形态的 Key',
          );
        }
      }
    });
  });

  group('适配器工厂', () {
    const OpenAiProviderFactory factory = OpenAiProviderFactory();

    Result<AiProvider> create({
      String protocolId = 'openai.chat_completions',
      String baseUrl = 'https://api.example.com',
      String apiKey = 'sk-fixture',
    }) => factory.create(
      alias: 'x',
      protocolId: protocolId,
      baseUrl: baseUrl,
      modelId: 'm',
      apiKey: apiKey,
    );

    test('Chat Completions 标识产出 ChatCompletionsAdapter', () {
      final Result<AiProvider> result = create();
      expect(result.isOk, isTrue, reason: result.errorOrNull?.message);
      expect(result.valueOrNull, isA<ChatCompletionsAdapter>());
    });

    test('Responses 标识产出 ResponsesAdapter（不是同一个实现）', () {
      final Result<AiProvider> result = create(
        protocolId: AiProtocol.openAiResponses.id,
      );
      expect(result.valueOrNull, isA<ResponsesAdapter>());
    });

    test('Anthropic 标识在 T027 之后产出 AnthropicMessagesAdapter', () {
      final Result<AiProvider> result = create(
        protocolId: AiProtocol.anthropicMessages.id,
      );
      expect(result.isOk, isTrue, reason: result.errorOrNull?.message);
      expect(result.valueOrNull, isA<AnthropicMessagesAdapter>());
      // 三个协议必须是**三个不同的实现**，工厂不能把 Anthropic 悄悄接到 CC 上。
      expect(result.valueOrNull, isNot(isA<ChatCompletionsAdapter>()));
      expect(result.valueOrNull, isNot(isA<ResponsesAdapter>()));
    });

    test('三个协议的适配器互不相同（不能只改 URL）', () {
      final AiProvider chat = create().unwrap();
      final AiProvider responses = create(
        protocolId: AiProtocol.openAiResponses.id,
      ).unwrap();
      final AiProvider anthropic = create(
        protocolId: AiProtocol.anthropicMessages.id,
      ).unwrap();
      expect(
        <Type>{
          chat.runtimeType,
          responses.runtimeType,
          anthropic.runtimeType,
        }.length,
        3,
      );
    });

    test('未知协议标识返回 unknownProtocol', () {
      final Result<AiProvider> result = create(protocolId: 'nope.nope');
      expect(
        (result.errorOrNull! as ModelConfigurationError).reason,
        'unknownProtocol',
      );
    });

    test('空 Key 被拒绝（不发一个必然 401 的请求）', () {
      final Result<AiProvider> result = create(apiKey: '');
      expect(
        (result.errorOrNull! as ModelConfigurationError).reason,
        'credentialMissing',
      );
    });

    test('非 http(s) 或缺失主机的 Base URL 被拒绝', () {
      for (final String bad in <String>[
        'file:///tmp/x',
        'ftp://api.example.com',
        'api.example.com',
        'https://',
      ]) {
        final Result<AiProvider> result = create(baseUrl: bad);
        expect(result.isErr, isTrue, reason: bad);
        expect(
          (result.errorOrNull! as ModelConfigurationError).reason,
          'invalidBaseUrl',
          reason: bad,
        );
      }
    });
  });
}
