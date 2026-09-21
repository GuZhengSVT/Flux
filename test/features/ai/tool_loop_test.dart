// T032：AI 任务队列里的受控工具循环。
//
// 这一组用例验证「工具调用会被执行并回填，然后模型再被问一次」，以及两条边界：
//   - 工具被拒绝时**照样回填**（模型必须看到拒绝原因，否则会一直重试同一件事）；
//   - 工具循环内的失败按既有分类处理（不换模型 / 计入五次）而不是另起一套。
//
// 断言的核心是**回填的消息序列**：模型第二次收到的 messages 里必须有 tool 角色、
// 带 toolCallId、内容含工具产出。这三条缺任何一条都意味着「模型看不到工具结果」，
// 而那种失败在界面上表现为「模型忽略了检索结果」。
import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/application/ai_task_budget.dart';
import 'package:flux/features/ai/application/ai_task_runner.dart';
import 'package:flux/features/ai/application/search_manager.dart';
import 'package:flux/features/ai/application/tool_executor.dart';
import 'package:flux/features/ai/domain/ai_message.dart';
import 'package:flux/features/ai/domain/ai_model.dart';
import 'package:flux/features/ai/domain/ai_protocol.dart';
import 'package:flux/features/ai/domain/search_protocol.dart';
import 'package:flux/features/ai/domain/search_service.dart';
import 'package:flux/features/ai/domain/tool_call.dart';
import 'package:flux/infrastructure/local/diagnostics.dart';
import 'package:flux/infrastructure/local/feed_store_adapter.dart'
    show DiagnosticLogSink;

import 'ai_runner_support.dart';
import 'tool_support.dart';

void main() {
  const AiModel model = AiModel(
    alias: 'deepseek',
    protocol: AiProtocol.openAiChatCompletions,
    baseUrl: 'https://api.example.com',
    modelId: 'deepseek-chat',
  );

  late FakeClock clock;
  late DiagnosticLog diagnostics;
  late FakeSearchServiceStore serviceStore;
  late FakeSearchCredentials credentials;
  late RecordingSearchFactory searchFactory;
  late FakePageFetcher pageFetcher;
  late FakeImageInspector imageInspector;

  setUp(() {
    clock = FakeClock(start: DateTime.utc(2026, 9, 22, 12));
    diagnostics = DiagnosticLog(level: DiagnosticLevel.info);
    serviceStore = FakeSearchServiceStore();
    credentials = FakeSearchCredentials();
    searchFactory = RecordingSearchFactory();
    pageFetcher = FakePageFetcher();
    imageInspector = FakeImageInspector();
  });

  ToolExecutor buildExecutor({int toolLimit = 30}) => ToolExecutor(
    budget: ToolCallBudget(limit: toolLimit),
    config: const ToolExecutorConfig(),
    searchManager: SearchManager(
      store: serviceStore,
      credentials: credentials,
      diagnostics: DiagnosticLogSink(diagnostics),
      factory: searchFactory,
    ),
    pageFetcher: pageFetcher,
    imageInspector: imageInspector,
    diagnostics: DiagnosticLogSink(diagnostics),
  );

  AiTaskRunner runner({
    required ScriptedAiFactory factory,
    ToolExecutor? tools,
  }) {
    // 剧本里的「调用中耗时」由工厂通过 scriptClock 推进，因此这里必须先把它接上
    // （与 ai_task_runner_test 的 harness 同一做法）。
    factory.scriptClock ??= clock;
    return AiTaskRunner(
      credentials: const AlwaysCredentialStore(),
      factory: factory,
      diagnostics: DiagnosticLogSink(diagnostics),
      budget: const AiTaskBudget(),
      clock: clock,
      delayScheduler: AdvancingDelayScheduler(clock),
      toolExecutor: tools,
    );
  }

  AiRequest request() => AiRequest(
    modelId: 'deepseek-chat',
    messages: const <AiMessage>[AiMessage.user('帮我查一下 flux 是什么')],
    tools: const <AiToolDeclaration>[
      AiToolDeclaration(
        name: 'search',
        description: '检索',
        parameters: <String, Object?>{'type': 'object'},
      ),
    ],
  );

  group('工具循环', () {
    test('模型请求 search → 工具执行 → 结果回填 → 模型给出最终答案', () async {
      await serviceStore.insert(
        const SearchService(
          label: 'main',
          protocol: SearchProtocol.tavily,
          baseUrl: 'https://api.example.com',
        ),
      );
      await credentials.write('main', 'k');

      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'deepseek': <AiAttemptScript>[
            // 第一轮：模型请求一个工具调用。
            const ScriptSuccess(
              deltas: <String>[],
              toolCalls: <ToolCall>[
                ToolCall(
                  id: 'call_1',
                  rawName: 'search',
                  args: <String, Object?>{'query': 'flux', 'count': 3},
                ),
              ],
              finishReason: 'tool_calls',
            ),
            // 第二轮：模型看到工具结果后给最终答案。
            const ScriptSuccess(deltas: <String>['Flux', ' 是阅读器']),
          ],
        },
      );

      final AiTaskOutcome outcome =
          await runner(factory: factory, tools: buildExecutor()).run(
            taskId: 'task-tools',
            request: request(),
            models: const <AiModel>[model],
          );

      expect(outcome.status, TaskStatus.succeeded);
      expect(outcome.text, 'Flux 是阅读器');
      // 工具**真的执行了**（一次检索）。
      expect(searchFactory.searches, 1);
      expect(searchFactory.lastQuery, 'flux');
      expect(searchFactory.lastCount, 3);

      // 第二次请求的消息序列里必须有回填的工具结果。
      expect(factory.requests, hasLength(2));
      final AiRequest second = factory.requests.last;
      final List<AiMessage> toolMessages = second.messages
          .where((AiMessage m) => m.role == AiRole.tool)
          .toList();
      expect(toolMessages, hasLength(1), reason: '工具结果必须回填成 tool 消息');
      expect(
        toolMessages.single.toolCallId,
        'call_1',
        reason: '回填必须带调用 id：三个协议都要求用它对应上（字段名不同但语义一致）',
      );
      expect(
        toolMessages.single.content,
        contains('example.com/a'),
        reason: '回填内容必须含真实检索到的材料',
      );
    });

    test('被拒绝的工具调用**照样回填**（带类型化原因，模型据此调整）', () async {
      // 没有配置搜索服务 → search 会被拒绝。
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'deepseek': <AiAttemptScript>[
            const ScriptSuccess(
              deltas: <String>[],
              toolCalls: <ToolCall>[
                ToolCall(
                  id: 'call_denied',
                  rawName: 'fetchPage',
                  args: <String, Object?>{
                    'url': 'http://169.254.169.254/latest/meta-data/',
                  },
                ),
              ],
              finishReason: 'tool_calls',
            ),
            const ScriptSuccess(deltas: <String>['没有可用资料']),
          ],
        },
      );

      final AiTaskOutcome outcome =
          await runner(factory: factory, tools: buildExecutor()).run(
            taskId: 'task-denied',
            request: request(),
            models: const <AiModel>[model],
          );

      expect(outcome.status, TaskStatus.succeeded);
      expect(pageFetcher.calls, 0, reason: '被拒绝的地址不得出网');
      final AiMessage toolMessage = factory.requests.last.messages.firstWhere(
        (AiMessage m) => m.role == AiRole.tool,
      );
      expect(toolMessage.content, contains('未执行'));
      expect(
        toolMessage.content,
        contains('forbiddenDestination'),
        reason: '必须告诉模型**为什么**被拒（否则它会重复请求同一目标）',
      );
    });

    test('没有接线执行器时：工具调用不被执行，但仍回填一条说明', () async {
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'deepseek': <AiAttemptScript>[
            const ScriptSuccess(
              deltas: <String>['我查不到'],
              toolCalls: <ToolCall>[
                ToolCall(
                  id: 'call_1',
                  rawName: 'search',
                  args: <String, Object?>{'query': 'x'},
                ),
              ],
              finishReason: 'tool_calls',
            ),
          ],
        },
      );

      final AiTaskOutcome outcome = await runner(factory: factory).run(
        taskId: 'task-notools',
        request: request(),
        models: const <AiModel>[model],
      );
      // 没有执行器时按「不执行任何工具」处理，直接把模型这一轮的文本作为结果。
      expect(outcome.status, TaskStatus.succeeded);
      expect(outcome.text, '我查不到');
      expect(searchFactory.searches, 0);
    });

    test('工具次数预算耗尽后，后续调用被拒且任务仍能给出结果', () async {
      await serviceStore.insert(
        const SearchService(
          label: 'main',
          protocol: SearchProtocol.tavily,
          baseUrl: 'https://api.example.com',
        ),
      );
      await credentials.write('main', 'k');

      // 预算只给 1 次，但模型连着请求两轮。
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'deepseek': <AiAttemptScript>[
            const ScriptSuccess(
              deltas: <String>[],
              toolCalls: <ToolCall>[
                ToolCall(
                  id: 'c1',
                  rawName: 'search',
                  args: <String, Object?>{'query': 'x'},
                ),
              ],
              finishReason: 'tool_calls',
            ),
            const ScriptSuccess(
              deltas: <String>[],
              toolCalls: <ToolCall>[
                ToolCall(
                  id: 'c2',
                  rawName: 'search',
                  args: <String, Object?>{'query': 'y'},
                ),
              ],
              finishReason: 'tool_calls',
            ),
            const ScriptSuccess(deltas: <String>['结束']),
          ],
        },
      );

      final AiTaskOutcome outcome =
          await runner(
            factory: factory,
            tools: buildExecutor(toolLimit: 1),
          ).run(
            taskId: 'task-budget',
            request: request(),
            models: const <AiModel>[model],
          );

      expect(outcome.status, TaskStatus.succeeded);
      expect(outcome.text, '结束');
      expect(searchFactory.searches, 1, reason: 'SET-062 的额度必须真的拦住第 2 次调用');
      // 第 3 次请求里既有成功回填，也有一条「次数用尽」的拒绝说明。
      final List<AiMessage> toolMessages = factory.requests.last.messages
          .where((AiMessage m) => m.role == AiRole.tool)
          .toList();
      expect(toolMessages, hasLength(2));
      expect(
        toolMessages[1].content,
        contains('budgetExhausted'),
        reason: '模型必须知道额度用尽，而不是以为「工具返回了空」',
      );
    });

    test('工具循环有**轮数**上限：模型一直要工具时也会收敛', () async {
      await serviceStore.insert(
        const SearchService(
          label: 'main',
          protocol: SearchProtocol.tavily,
          baseUrl: 'https://api.example.com',
        ),
      );
      await credentials.write('main', 'k');

      // 每一轮都请求工具（模型打转的场景）。
      final List<AiAttemptScript> scripts = <AiAttemptScript>[
        for (int i = 0; i < kMaxToolRounds + 3; i++)
          ScriptSuccess(
            deltas: <String>['第 $i 轮'],
            toolCalls: <ToolCall>[
              ToolCall(
                id: 'c$i',
                rawName: 'search',
                args: <String, Object?>{'query': 'x'},
              ),
            ],
            finishReason: 'tool_calls',
          ),
      ];
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{'deepseek': scripts},
      );

      final AiTaskOutcome outcome =
          await runner(factory: factory, tools: buildExecutor()).run(
            taskId: 'task-loop',
            request: request(),
            models: const <AiModel>[model],
          );

      // 收敛（不无限打转）：轮数用尽时把最后一轮文本当结果，并标为 partial
      // （它不是模型的最终答案，用户需要知道这一点）。
      expect(outcome.status, TaskStatus.partial);
      expect(
        factory.requests.length,
        lessThanOrEqualTo(kMaxToolRounds + 1),
        reason: '轮数上限必须真的起作用',
      );
    });
  });
}
