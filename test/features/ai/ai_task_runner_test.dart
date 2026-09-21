// T029：有预算的队列、五次无响应与跨模型故障转移（D-09、架构 4.4/4.5、手册 6.3）。
//
// 本文件是 T029 的**验收核心**：手册 6.3「必测高风险用例」点名了五次规则的四条
// （第五次才切下一个、成功重置、总 10 分钟早于第五次则停止、取消不多发请求、
// 拒绝不规避），这里逐条用**假时钟**验证，并补齐预算闸门（次数/Token/并发/429）。
//
// 为什么全部用假时钟而不是真实等待：这些规则的正确性只取决于「时间/次数的先后关系」，
// 真实等待既慢又不可复现（CI 上 10 分钟总时限根本跑不了）。真实计时器只在
// 「单次硬时限打断一个卡住的流」这一条上使用，且把时限设成几十毫秒。
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/application/ai_failover.dart';
import 'package:flux/features/ai/application/ai_task_budget.dart';
import 'package:flux/features/ai/application/ai_task_runner.dart';
import 'package:flux/features/ai/application/model_manager.dart'
    show SettingsReader;
import 'package:flux/features/ai/domain/ai_message.dart';
import 'package:flux/features/ai/domain/ai_model.dart';

import 'ai_runner_support.dart';

/// 构造一个确定性的队列（假时钟 + 立即返回的等待调度）。
({AiTaskRunner runner, FakeClock clock, AdvancingDelayScheduler scheduler})
buildRunner(
  ScriptedAiFactory factory, {
  AiTaskBudget budget = const AiTaskBudget(),
  RecordingSink? sink,
  FakeClock? clock,
  ScriptedNetworkConditions? network,
}) {
  final FakeClock resolved = clock ?? FakeClock();
  factory.scriptClock ??= resolved;
  final AdvancingDelayScheduler scheduler = AdvancingDelayScheduler(resolved);
  return (
    runner: AiTaskRunner(
      credentials: const AlwaysCredentialStore(),
      factory: factory,
      diagnostics: sink ?? RecordingSink(),
      budget: budget,
      clock: resolved,
      delayScheduler: scheduler,
      networkConditions: network,
      offlineRetryDelay: const Duration(seconds: 30),
    ),
    clock: resolved,
    scheduler: scheduler,
  );
}

AiRequest requestFor(String modelId) => AiRequest(
  modelId: modelId,
  messages: const <AiMessage>[AiMessage.user('写一句话')],
);

/// 某个别名已发生的调用次数（没被调用过时为 0）。
///
/// 直接读 `issuedByAlias[alias]` 会拿到 null，于是「没有被调用」这个断言会以
/// 「null 不等于 0」失败——那报出来的是断言写法问题，不是行为问题。
int issued(ScriptedAiFactory factory, String alias) =>
    factory.issuedByAlias[alias] ?? 0;

/// 一个「每次尝试都断流、但服务商已经发过 usage」的剧本序列。
///
/// 意图：每次真实请求都消耗 100 token，因此 8 次之后 800 的 Token 预算必然先于
/// 「尝试次数」耗尽——这正是 SET-063「仅靠次数与时间不能控制费用」要证明的一面。
List<AiAttemptScript> tokenBurningScripts() => <AiAttemptScript>[
  for (int index = 0; index < 10; index++)
    ScriptFailure(
      error: NetworkError(uri: 'https://a.example.com', reason: '断流'),
      usage: const AiUsage(inputTokens: 60, outputTokens: 40, totalTokens: 100),
    ),
];

/// 一次「无响应」：连接层失败（无状态码），计入五次。
ScriptFailure timeoutScript = ScriptFailure(
  error: NetworkError(uri: 'https://a.example.com', reason: '连接失败'),
);

void main() {
  group('五次规则（D-09 / 手册 6.3）', () {
    test('第 5 次才切下一个模型：1–4 次都留在同一个模型', () async {
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'primary': <AiAttemptScript>[
            timeoutScript,
            timeoutScript,
            timeoutScript,
            timeoutScript,
            timeoutScript,
          ],
          'secondary': <AiAttemptScript>[const ScriptSuccess()],
        },
      );
      final harness = buildRunner(factory);
      final List<AiModel> models = scriptedModels(<String>[
        'primary',
        'secondary',
      ]);

      final AiTaskOutcome outcome = await harness.runner.run(
        taskId: 't-five',
        request: requestFor('primary-model'),
        models: models,
      );

      expect(issued(factory, 'primary'), 5, reason: '前四次不切模型');
      expect(issued(factory, 'secondary'), 1, reason: '第五次之后才用下一个');
      expect(factory.callOrder, <String>[
        'primary',
        'primary',
        'primary',
        'primary',
        'primary',
        'secondary',
      ]);
      expect(outcome.status, TaskStatus.succeeded);
      expect(outcome.attemptCount, 6);
    });

    test('成功重置计数：3 次失败 + 1 次成功 + 再 4 次失败仍不切模型', () async {
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'primary': <AiAttemptScript>[
            timeoutScript,
            timeoutScript,
            timeoutScript,
            // 第 4 次：带一段文本的成功（有字节到达即算「有响应」）。
            const ScriptSuccess(deltas: <String>['中途', '成功']),
            timeoutScript,
            timeoutScript,
            timeoutScript,
            timeoutScript,
            const ScriptSuccess(deltas: <String>['最终答案']),
          ],
        },
      );
      final harness = buildRunner(factory);

      // 第一个任务：3 失败 + 1 成功 → 成功即结束（计数被清零的是过程，不是结果）。
      final AiTaskOutcome first = await harness.runner.run(
        taskId: 't-reset-1',
        request: requestFor('primary-model'),
        models: scriptedModels(<String>['primary']),
      );
      expect(first.status, TaskStatus.succeeded);
      expect(first.text, '中途成功');
      expect(issued(factory, 'primary'), 4);

      // 第二个任务：连续 4 次失败不得切模型（因为上一个任务的成功已把计数清零）。
      final AiTaskOutcome second = await harness.runner.run(
        taskId: 't-reset-2',
        request: requestFor('primary-model'),
        models: scriptedModels(<String>['primary']),
      );
      expect(
        issued(factory, 'primary'),
        9,
        reason: '第 4 次失败仍留在同一模型，第 5 次调用还是它（并成功）',
      );
      expect(issued(factory, 'secondary'), 0, reason: '始终没有切到下一个模型');
      expect(second.status, TaskStatus.succeeded);
    });

    test('计数按模型独立：切换后的新模型重新从零开始攒自己的五次', () async {
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'primary': <AiAttemptScript>[timeoutScript],
          // 新模型也要攒够自己的五次：若计数在切换时被继承（或全局共享），
          // 这里会在不足五次时就再次切换/终止。
          'secondary': <AiAttemptScript>[
            timeoutScript,
            timeoutScript,
            timeoutScript,
            timeoutScript,
            const ScriptSuccess(deltas: <String>['第二个模型']),
          ],
        },
      );
      final harness = buildRunner(factory);

      final AiTaskOutcome outcome = await harness.runner.run(
        taskId: 't-per-model',
        request: requestFor('primary-model'),
        models: scriptedModels(<String>['primary', 'secondary']),
      );

      expect(issued(factory, 'primary'), 5);
      expect(issued(factory, 'secondary'), 5, reason: '新模型有自己的五次额度');
      expect(outcome.status, TaskStatus.succeeded);
      expect(outcome.text, '第二个模型');
      expect(outcome.alias, 'secondary');
    });

    test('总 10 分钟先到：第 3 次尝试时 deadline 到 → 停止，不等第 5 次', () async {
      // 每次失败的剧本自身「耗时」4 分钟；第 3 次调用开始时已经过去 8 分钟，
      // 第 3 次结束后累计 12 分钟 → 必须在第 4 次调用之前终止。
      final ScriptFailure slowTimeout = ScriptFailure(
        error: NetworkError(uri: 'https://a.example.com', reason: '超时'),
        advanceClockBy: const Duration(minutes: 4),
      );
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'primary': <AiAttemptScript>[slowTimeout, slowTimeout, slowTimeout],
          'secondary': <AiAttemptScript>[const ScriptSuccess()],
        },
      );
      final harness = buildRunner(
        factory,
        budget: const AiTaskBudget(totalLimit: Duration(minutes: 10)),
      );

      final AiTaskOutcome outcome = await harness.runner.run(
        taskId: 't-deadline',
        request: requestFor('primary-model'),
        models: scriptedModels(<String>['primary', 'secondary']),
      );

      expect(
        issued(factory, 'primary'),
        3,
        reason: '第三次调用结束后累计耗时已到 12 分钟，不再发起第四次',
      );
      expect(issued(factory, 'secondary'), 0, reason: '总时限优先于五次规则');
      expect(outcome.status, TaskStatus.failed);
      expect(outcome.error, isA<DeadlineExceededError>());
      expect(
        (outcome.error! as DeadlineExceededError).limitKind,
        AiTaskBudget.taskDeadlineLimitKind,
      );
    });

    test('取消：第 2 次尝试中取消 → cancelled，且不再有后续请求', () async {
      final AiCancellation cancellation = AiCancellation();
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'primary': <AiAttemptScript>[
            timeoutScript,
            ScriptHang(onStart: () => cancellation.cancel(reason: '用户取消')),
            // 若取消没生效，会走到这里（一个会成功的剧本），断言就能抓到。
            const ScriptSuccess(deltas: <String>['不应该发生']),
            const ScriptSuccess(deltas: <String>['不应该发生']),
            const ScriptSuccess(deltas: <String>['不应该发生']),
          ],
          'secondary': <AiAttemptScript>[
            const ScriptSuccess(deltas: <String>['不应该发生']),
          ],
        },
      );
      final harness = buildRunner(factory);
      final AiRequest request = AiRequest(
        modelId: 'primary-model',
        messages: const <AiMessage>[AiMessage.user('写一句话')],
        cancellation: cancellation,
      );

      final AiTaskOutcome outcome = await harness.runner.run(
        taskId: 't-cancel',
        request: request,
        models: scriptedModels(<String>['primary', 'secondary']),
      );

      expect(outcome.status, TaskStatus.cancelled);
      expect(issued(factory, 'primary'), 2, reason: '第 2 次之后就停了');
      expect(issued(factory, 'secondary'), 0);
      expect(outcome.status.isTerminal, isTrue);
    });

    test('内容拒绝：第 1 次就拒绝 → 不切模型、直接失败该链（不跨服务商规避）', () async {
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'primary': <AiAttemptScript>[
            ScriptFailure(
              error: ContentFilteredError(provider: 'primary', statusCode: 400),
            ),
          ],
          'secondary': <AiAttemptScript>[const ScriptSuccess()],
        },
      );
      final harness = buildRunner(factory);

      final AiTaskOutcome outcome = await harness.runner.run(
        taskId: 't-refuse',
        request: requestFor('primary-model'),
        models: scriptedModels(<String>['primary', 'secondary']),
      );

      expect(outcome.status, TaskStatus.failed);
      expect(outcome.error, isA<ContentFilteredError>());
      expect(issued(factory, 'primary'), 1);
      expect(
        issued(factory, 'secondary'),
        0,
        reason: '换服务商再问一遍就是绕过内容策略（架构 4.5 禁止）',
      );
    });

    test('认证失败：不切模型，直接失败（换服务商不会修好一个坏 Key）', () async {
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'primary': <AiAttemptScript>[
            ScriptFailure(
              error: AuthError(provider: 'primary', statusCode: 401),
            ),
          ],
          'secondary': <AiAttemptScript>[const ScriptSuccess()],
        },
      );
      final harness = buildRunner(factory);

      final AiTaskOutcome outcome = await harness.runner.run(
        taskId: 't-auth',
        request: requestFor('primary-model'),
        models: scriptedModels(<String>['primary', 'secondary']),
      );

      expect(outcome.status, TaskStatus.failed);
      expect(outcome.error, isA<AuthError>());
      expect(issued(factory, 'primary'), 1);
      expect(issued(factory, 'secondary'), 0, reason: '不消耗五次额度去重复同一个错误');
    });

    test('429 + Retry-After：服从一次；第二次 429 计为该模型一次无响应', () async {
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'primary': <AiAttemptScript>[
            ScriptFailure(
              error: RateLimitError(
                provider: 'primary',
                retryAfter: const Duration(seconds: 7),
              ),
            ),
            ScriptFailure(
              error: RateLimitError(
                provider: 'primary',
                retryAfter: const Duration(seconds: 7),
              ),
            ),
            const ScriptSuccess(),
          ],
        },
      );
      final harness = buildRunner(factory);

      final AiTaskOutcome outcome = await harness.runner.run(
        taskId: 't-429',
        request: requestFor('primary-model'),
        models: scriptedModels(<String>['primary']),
      );

      expect(outcome.status, TaskStatus.succeeded);
      expect(harness.scheduler.waits, <Duration>[const Duration(seconds: 7)]);
      expect(issued(factory, 'primary'), 3);
      // 第二次 429 计为一次无响应（note 标记），因此第 2 条失败记录带备注。
      expect(outcome.attempts[1].note, 'retryAfterHonored');
      expect(outcome.attempts[1].failureClass, AiFailureClass.noResponse);
    });

    test('并发 2 上限：同一任务内在途调用数不超过 SET-036 的并发', () async {
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'primary': <AiAttemptScript>[timeoutScript, timeoutScript],
        },
      );
      final harness = buildRunner(
        factory,
        budget: const AiTaskBudget(concurrency: 2),
      );
      await harness.runner.run(
        taskId: 't-concurrency',
        request: requestFor('primary-model'),
        models: scriptedModels(<String>['primary']),
      );
      expect(factory.peakInFlight, lessThanOrEqualTo(2));
    });

    test('Token 预算耗尽终止：即使还有剩余尝试次数也不继续', () async {
      // 每次断流都带 usage（100 token），因此 Token 预算会先于尝试次数耗尽。
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{'primary': tokenBurningScripts()},
      );
      // 输入估算 8 + 每次 100 token：第 3 次之后 308 已越过 300 的预算。
      final harness = buildRunner(
        factory,
        budget: const AiTaskBudget(tokenBudget: 300),
      );

      final AiTaskOutcome outcome = await harness.runner.run(
        taskId: 't-tokens',
        request: requestFor('primary-model'),
        models: scriptedModels(<String>['primary', 'secondary']),
      );

      expect(outcome.status, TaskStatus.failed);
      expect(outcome.error, isA<BudgetExhaustedError>());
      expect(
        (outcome.error! as BudgetExhaustedError).limitKind,
        'tokens',
        reason: '是 Token 预算而不是次数预算先到',
      );
      expect(outcome.consumedTokens, 308);
      expect(outcome.attemptCount, 3, reason: '预算耗尽后不再发起第 4 次');
      expect(outcome.attempts.last.usage?.effectiveTotal, 100);
    });

    test('全模型耗尽 → failed，且保留最后一次失败原因', () async {
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'primary': <AiAttemptScript>[timeoutScript],
          'secondary': <AiAttemptScript>[timeoutScript],
        },
      );
      final harness = buildRunner(factory);

      final AiTaskOutcome outcome = await harness.runner.run(
        taskId: 't-exhausted',
        request: requestFor('primary-model'),
        models: scriptedModels(<String>['primary', 'secondary']),
      );

      expect(outcome.status, TaskStatus.failed);
      expect(issued(factory, 'primary'), 5);
      expect(issued(factory, 'secondary'), 5);
      expect(outcome.error, isA<NetworkError>());
    });

    test('没有可用的启用模型 → failed（不猜一个模型去用）', () async {
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{},
      );
      final harness = buildRunner(factory);
      final AiTaskOutcome outcome = await harness.runner.run(
        taskId: 't-empty',
        request: requestFor('x'),
        models: const <AiModel>[],
      );
      expect(outcome.status, TaskStatus.failed);
      expect(factory.totalIssued, 0);
    });

    test('SET-035 关闭故障转移：五次之后只终止，不换模型', () async {
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'primary': <AiAttemptScript>[timeoutScript],
          'secondary': <AiAttemptScript>[const ScriptSuccess()],
        },
      );
      final harness = buildRunner(
        factory,
        budget: const AiTaskBudget(failoverEnabled: false),
      );

      final AiTaskOutcome outcome = await harness.runner.run(
        taskId: 't-nofailover',
        request: requestFor('primary-model'),
        models: scriptedModels(<String>['primary', 'secondary']),
      );

      expect(outcome.status, TaskStatus.failed);
      expect(issued(factory, 'primary'), 5);
      expect(issued(factory, 'secondary'), 0);
    });
  });

  group('状态机接线与产出语义', () {
    test('经过 queued → running → succeeded，且 deadline 在创建时固定', () async {
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'primary': <AiAttemptScript>[const ScriptSuccess()],
        },
      );
      final harness = buildRunner(factory);
      final SnapshotRecorder recorder = SnapshotRecorder();
      final AiTaskRunner runner = AiTaskRunner(
        credentials: const AlwaysCredentialStore(),
        factory: factory,
        diagnostics: RecordingSink(),
        budget: const AiTaskBudget(),
        clock: harness.clock,
        delayScheduler: harness.scheduler,
        onSnapshot: recorder.call,
      );

      final AiTaskOutcome outcome = await runner.run(
        taskId: 't-states',
        request: requestFor('primary-model'),
        models: scriptedModels(<String>['primary']),
      );

      expect(recorder.statuses.first, TaskStatus.queued);
      expect(recorder.statuses, contains(TaskStatus.running));
      expect(recorder.statuses.last, TaskStatus.succeeded);
      expect(outcome.snapshot.isTerminal, isTrue);
      expect(
        outcome.snapshot.deadline,
        harness.clock.now().add(const Duration(minutes: 10)),
        reason: 'deadline 在任务创建时固定，之后不重置',
      );
      expect(outcome.snapshot.finishedAt, isNotNull);
    });

    test('流中断但已收到部分文本 → partial，且半句话不与后续模型的输出拼接', () async {
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'primary': <AiAttemptScript>[
            ScriptFailure(
              error: NetworkError(
                uri: 'https://a.example.com',
                reason: '流在中途结束',
              ),
              partialText: '半句话',
            ),
          ],
          'secondary': <AiAttemptScript>[
            const ScriptSuccess(deltas: <String>['完整', '答案']),
          ],
        },
      );
      final harness = buildRunner(factory);

      final AiTaskOutcome outcome = await harness.runner.run(
        taskId: 't-partial',
        request: requestFor('primary-model'),
        models: scriptedModels(<String>['primary', 'secondary']),
      );

      // primary 的 5 次失败（第 1 次带半句话，后续为空）后切到 secondary 并成功。
      expect(outcome.status, TaskStatus.succeeded);
      expect(outcome.text, '完整答案', reason: '不允许拼接 primary 的半句话');
      expect(outcome.alias, 'secondary');
    });

    test('全部候选失败但有半句话 → partial（部分结果清楚标注）', () async {
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'primary': <AiAttemptScript>[
            ScriptFailure(
              error: NetworkError(uri: 'https://a.example.com', reason: '断流'),
              partialText: '写了一半',
            ),
          ],
        },
      );
      final harness = buildRunner(factory);

      final AiTaskOutcome outcome = await harness.runner.run(
        taskId: 't-partial-only',
        request: requestFor('primary-model'),
        models: scriptedModels(<String>['primary']),
      );

      expect(outcome.status, TaskStatus.partial);
      expect(outcome.text, '写了一半');
      expect(outcome.error, isNotNull, reason: '部分成功也要带失败原因');
    });

    test('被截断的结束原因（length）算 partial 而不是 succeeded', () async {
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'primary': <AiAttemptScript>[
            const ScriptSuccess(
              deltas: <String>['被截断'],
              finishReason: 'length',
            ),
          ],
        },
      );
      final harness = buildRunner(factory);
      final AiTaskOutcome outcome = await harness.runner.run(
        taskId: 't-truncated',
        request: requestFor('primary-model'),
        models: scriptedModels(<String>['primary']),
      );
      expect(outcome.status, TaskStatus.partial);
      expect(outcome.finishReason, 'length');
    });

    test('未声明输出上限时按 SET-033 的保守预算发送 maxTokens', () async {
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'primary': <AiAttemptScript>[const ScriptSuccess()],
        },
      );
      final harness = buildRunner(factory);
      await harness.runner.run(
        taskId: 't-maxtokens',
        request: requestFor('primary-model'),
        models: scriptedModels(<String>['primary']),
      );
      expect(factory.requests.single.maxTokens, 2048);
    });

    test('缺凭据是配置错误：不消耗五次、不换模型', () async {
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'primary': <AiAttemptScript>[const ScriptSuccess()],
          'secondary': <AiAttemptScript>[const ScriptSuccess()],
        },
      );
      final AiTaskRunner runner = AiTaskRunner(
        credentials: const MissingCredentialStore(),
        factory: factory,
        diagnostics: RecordingSink(),
        budget: const AiTaskBudget(),
        clock: FakeClock(),
        delayScheduler: AdvancingDelayScheduler(FakeClock()),
      );
      final AiTaskOutcome outcome = await runner.run(
        taskId: 't-nocredential',
        request: requestFor('primary-model'),
        models: scriptedModels(<String>['primary', 'secondary']),
      );
      expect(outcome.status, TaskStatus.failed);
      expect(factory.totalIssued, 0, reason: '没有 Key 就不该发请求');
    });

    test('设备离线：暂停为 waitingNetwork，且不计入五次额度', () async {
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'primary': <AiAttemptScript>[
            ScriptFailure(
              error: NetworkError(uri: 'https://a.example.com', reason: '无网络'),
            ),
            const ScriptSuccess(),
          ],
        },
      );
      final ScriptedNetworkConditions network = ScriptedNetworkConditions(
        offline: true,
      );
      final harness = buildRunner(factory, network: network);
      final SnapshotRecorder recorder = SnapshotRecorder();
      final AiTaskRunner runner = AiTaskRunner(
        credentials: const AlwaysCredentialStore(),
        factory: factory,
        diagnostics: RecordingSink(),
        budget: const AiTaskBudget(),
        clock: harness.clock,
        delayScheduler: harness.scheduler,
        networkConditions: network,
        offlineRetryDelay: const Duration(seconds: 30),
        onSnapshot: recorder.call,
      );

      final AiTaskOutcome outcome = await runner.run(
        taskId: 't-offline',
        request: requestFor('primary-model'),
        models: scriptedModels(<String>['primary']),
      );

      expect(recorder.statuses, contains(TaskStatus.waitingNetwork));
      expect(recorder.statuses.last, TaskStatus.succeeded);
      expect(harness.scheduler.waits, contains(const Duration(seconds: 30)));
      expect(outcome.status, TaskStatus.succeeded);
    });

    test('建议：诊断日志不含 prompt 与 Key', () async {
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'primary': <AiAttemptScript>[timeoutScript, const ScriptSuccess()],
        },
      );
      final RecordingSink sink = RecordingSink();
      final harness = buildRunner(factory, sink: sink);
      await harness.runner.run(
        taskId: 't-log',
        request: requestFor('primary-model'),
        models: scriptedModels(<String>['primary']),
      );
      for (final String message in sink.messages) {
        expect(message, isNot(contains('写一句话')));
        expect(message, isNot(contains('test-key')));
      }
    });
  });

  group('单次硬时限（真实计时器）', () {
    test('卡住的流会在硬时限内被打断，并计入一次无响应', () async {
      final ScriptedAiFactory factory = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'primary': <AiAttemptScript>[const ScriptHang()],
          'secondary': <AiAttemptScript>[const ScriptSuccess()],
        },
      );
      final AiTaskRunner runner = AiTaskRunner(
        credentials: const AlwaysCredentialStore(),
        factory: factory,
        diagnostics: RecordingSink(),
        budget: const AiTaskBudget(
          attemptHardLimit: Duration(milliseconds: 80),
        ),
        clock: FakeClock(),
        delayScheduler: AdvancingDelayScheduler(FakeClock()),
      );

      final AiTaskOutcome outcome = await runner
          .run(
            taskId: 't-hardlimit',
            request: requestFor('primary-model'),
            models: scriptedModels(<String>['primary', 'secondary']),
          )
          .timeout(const Duration(seconds: 10));

      // 5 次都被硬时限打断 → 切到 secondary 成功。
      expect(issued(factory, 'primary'), 5);
      expect(issued(factory, 'secondary'), 1);
      expect(outcome.status, TaskStatus.succeeded);
    });
  });

  group('预算读取（SET-035/036/059/062/063）', () {
    test('从设置读取：默认值即注册表默认（10 分钟 / 30 次 / 100000 / 并发 2 / 故障转移开）', () async {
      final AiTaskBudget budget = await AiTaskBudget.fromSettingsReader(
        const _EmptySettingsReader(),
      );
      expect(budget.totalLimit, const Duration(minutes: 10));
      expect(budget.maxHttpAttempts, 30);
      expect(budget.tokenBudget, 100000);
      expect(budget.concurrency, 2);
      expect(budget.failoverEnabled, isTrue);
    });

    test('读到用户值：逐项生效', () async {
      final AiTaskBudget budget = await AiTaskBudget.fromSettingsReader(
        const _EmptySettingsReader(<String, Object?>{
          'SET-059': 3,
          'SET-062': <String, Object?>{'httpAttempts': 7, 'toolCalls': 30},
          'SET-063': 5000,
          'SET-036': <String, Object?>{'concurrency': 4},
          'SET-035': <String, Object?>{'enabled': false},
        }),
      );
      expect(budget.totalLimit, const Duration(minutes: 3));
      expect(budget.maxHttpAttempts, 7);
      expect(budget.tokenBudget, 5000);
      expect(budget.concurrency, 4);
      expect(budget.failoverEnabled, isFalse);
    });

    test('读取失败回退注册表默认值（不会因为一次读失败就不做任何事）', () async {
      final AiTaskBudget budget = await AiTaskBudget.fromSettingsReader(
        const _FailingSettingsReader(),
      );
      expect(budget.totalLimit, const Duration(minutes: 10));
      expect(budget.maxHttpAttempts, 30);
      expect(budget.tokenBudget, 100000);
      expect(budget.concurrency, 2);
    });
  });

  group('Token 估算与失败分类（纯函数）', () {
    test('中文按 1 字符 1 token，英文按 4 字符 1 token（保守方向）', () {
      expect(estimateAiTokens('你好世界'), 4);
      expect(estimateAiTokens('abcd'), 1);
      expect(estimateAiTokens('abcde'), 2, reason: '非 CJK 向上取整');
      expect(estimateAiTokens(''), 0);
    });

    test('失败分类：只有无响应类才消耗五次额度', () {
      expect(
        classifyAiFailure(NetworkError(uri: 'https://a.example.com')),
        AiFailureClass.noResponse,
      );
      expect(
        classifyAiFailure(
          DeadlineExceededError(limitKind: 'x', limit: Duration.zero),
        ),
        AiFailureClass.noResponse,
      );
      expect(
        classifyAiFailure(RateLimitError(provider: 'p')),
        AiFailureClass.noResponse,
      );
      expect(
        classifyAiFailure(AuthError(provider: 'p', statusCode: 401)),
        AiFailureClass.configuration,
      );
      expect(
        classifyAiFailure(ContentFilteredError(provider: 'p', statusCode: 400)),
        AiFailureClass.contentRefused,
      );
      expect(
        classifyAiFailure(ParseError(source: 'ai.result', detail: 'bad json')),
        AiFailureClass.format,
      );
      expect(classifyAiFailure(CancelledError()), AiFailureClass.cancelled);
    });
  });

  group('在途额度（SET-036 并发）', () {
    test('上限内立即拿到；超出时排队，按释放顺序唤醒', () async {
      final AiInFlightLimiter limiter = AiInFlightLimiter(2);
      await limiter.acquire();
      await limiter.acquire();
      expect(limiter.inFlight, 2);

      final Completer<void> reached = Completer<void>();
      final Future<void> third = limiter.acquire().then((_) {
        reached.complete();
      });
      await Future<void>.delayed(Duration.zero);
      expect(limiter.waiting, 1);
      expect(limiter.inFlight, 2, reason: '没有额度就不该进入在途');

      limiter.release();
      await third;
      expect(reached.isCompleted, isTrue);
      expect(limiter.inFlight, 2, reason: '额度是转交而不是凭空增加');
      expect(limiter.peak, 2);
      limiter.release();
      limiter.release();
      expect(limiter.inFlight, 0);
    });

    test('多释放是编程错误（不静默放大上限）', () {
      final AiInFlightLimiter limiter = AiInFlightLimiter(1);
      expect(limiter.release, throwsStateError);
    });
  });
}

/// 一个按键返回固定值的设置读取端口（默认值走注册表）。
final class _EmptySettingsReader implements SettingsReader {
  const _EmptySettingsReader([this.values = const <String, Object?>{}]);

  final Map<String, Object?> values;

  @override
  Future<Result<Object?>> readSetting(SettingId id) async =>
      Ok<Object?>(values[id.code]);
}

/// 一个读取必然失败的设置端口。
final class _FailingSettingsReader implements SettingsReader {
  const _FailingSettingsReader();

  @override
  Future<Result<Object?>> readSetting(SettingId id) async =>
      Err<Object?>(StorageError(operation: 'read', detail: 'boom'));
}
