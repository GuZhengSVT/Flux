// T030：持久任务、结果缓存与中断恢复（架构 4.5、5.1、手册 T030）。
//
// 手册 T030 点名的四条验收都在这里逐条验证：
//   1) 输入 / prompt / 模型 / 语言变化使缓存失效；
//   2) 进程重启显示 interrupted，**不自动重发付费请求**；
//   3) 缓存命中不发请求（用请求计数断言，而不是「返回得快」这种观察）；
//   4) 成功版本不被草稿覆盖。
//
// 全部用真实的内存数据库 + 假时钟：缓存判定与中断标记都是**存储行为**，
// 用替身存储验证只能证明「调用了一个方法」。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/ai/application/ai_failover.dart';
import 'package:flux/features/ai/application/ai_task_budget.dart';
import 'package:flux/features/ai/application/ai_task_runner.dart';
import 'package:flux/features/ai/application/persistent_ai_task_service.dart';
import 'package:flux/features/ai/domain/ai_message.dart';
import 'package:flux/features/ai/domain/ai_model.dart';
import 'package:flux/features/ai/domain/ai_task_record.dart';
import 'package:flux/infrastructure/local/ai_task_store.dart';
import 'package:flux/infrastructure/local/database.dart';

import 'ai_runner_support.dart';

/// 一次任务请求的公共构造（内容可变，便于验证缓存失效）。
AiTaskRequest taskRequest({
  required String taskId,
  required String prompt,
  AiTaskKind kind = AiTaskKind.summary,
  String? language,
  List<AiModel>? models,
  double? temperature,
}) => AiTaskRequest(
  taskId: taskId,
  kind: kind,
  request: AiRequest(
    modelId: 'primary-model',
    messages: <AiMessage>[AiMessage.user(prompt)],
    temperature: temperature,
  ),
  models: models ?? scriptedModels(<String>['primary']),
  language: language,
);

void main() {
  late AppDatabase db;
  late DriftAiTaskStore taskStore;
  late DriftAiResultCache cache;
  late FakeClock clock;
  late RecordingSink sink;
  late ScriptedAiFactory factory;

  /// 构造一个绑定到当前内存库的服务。
  PersistentAiTaskService buildService({ScriptedAiFactory? overrideFactory}) {
    final ScriptedAiFactory effective = overrideFactory ?? factory;
    return PersistentAiTaskService(
      tasks: taskStore,
      cache: cache,
      clock: clock,
      diagnostics: sink,
      budget: const AiTaskBudget(),
      runnerFactory: (void Function(TaskSnapshot) onSnapshot) => AiTaskRunner(
        credentials: const AlwaysCredentialStore(),
        factory: effective,
        diagnostics: sink,
        budget: const AiTaskBudget(),
        clock: clock,
        delayScheduler: AdvancingDelayScheduler(clock),
        onSnapshot: onSnapshot,
      ),
    );
  }

  setUp(() async {
    db = AppDatabase.memory();
    await db.customSelect('SELECT 1').get();
    taskStore = DriftAiTaskStore(db);
    cache = DriftAiResultCache(db);
    clock = FakeClock();
    sink = RecordingSink();
    factory = ScriptedAiFactory(<String, List<AiAttemptScript>>{
      'primary': <AiAttemptScript>[
        const ScriptSuccess(deltas: <String>['摘要', '正文']),
      ],
    }, scriptClock: clock);
  });

  tearDown(() async {
    await db.close();
  });

  group('结果缓存', () {
    test('第一次真实执行；第二次同输入命中缓存且**不发任何请求**', () async {
      final PersistentAiTaskService service = buildService();

      final AiTaskRunResult first = (await service.run(
        taskRequest(taskId: 't-1', prompt: '总结这段内容'),
      )).unwrap();
      expect(first.fromCache, isFalse);
      expect(first.record.status, TaskStatus.succeeded);
      expect(first.record.resultText, '摘要正文');
      expect(factory.totalIssued, 1);

      final AiTaskRunResult second = (await service.run(
        taskRequest(taskId: 't-2', prompt: '总结这段内容'),
      )).unwrap();

      expect(second.fromCache, isTrue);
      expect(second.record.resultText, '摘要正文');
      expect(second.record.fromCache, isTrue);
      expect(factory.totalIssued, 1, reason: '命中缓存必须一个请求都不发（这是「不重复付费」的落点）');
      // 命中缓存的任务不应伪装成一次执行产出。
      expect(second.task, isNull);

      // 两条任务记录都在（缓存命中也要留一条事实）。
      final List<AiTaskRecord> all = (await service.listTasks()).unwrap();
      expect(all, hasLength(2));
    });

    test('输入变化 → 缓存失效（重新真实请求）', () async {
      final PersistentAiTaskService service = buildService();
      await service.run(taskRequest(taskId: 't-1', prompt: '版本一'));
      expect(factory.totalIssued, 1);

      final AiTaskRunResult changed = (await service.run(
        taskRequest(taskId: 't-2', prompt: '版本二'),
      )).unwrap();

      expect(changed.fromCache, isFalse);
      expect(factory.totalIssued, 2);
    });

    test('语言变化 → 缓存失效（同一份输入的中文与英文是两次结果）', () async {
      final PersistentAiTaskService service = buildService();
      await service.run(
        taskRequest(taskId: 't-1', prompt: '同一份输入', language: 'zh-Hans'),
      );
      expect(factory.totalIssued, 1);

      final AiTaskRunResult other = (await service.run(
        taskRequest(taskId: 't-2', prompt: '同一份输入', language: 'en'),
      )).unwrap();

      expect(
        other.fromCache,
        isFalse,
        reason: '语言是缓存键的组成项：命中另一语言的结果会给出语言不对的答案',
      );
      expect(factory.totalIssued, 2);
    });

    test('模型变化 → 缓存失效（换了主用模型就是另一次缓存）', () async {
      final PersistentAiTaskService service = buildService();
      await service.run(
        taskRequest(
          taskId: 't-1',
          prompt: '同一份输入',
          models: scriptedModels(<String>['primary']),
        ),
      );
      expect(factory.totalIssued, 1);

      final AiTaskRunResult other = (await service.run(
        taskRequest(
          taskId: 't-2',
          prompt: '同一份输入',
          models: scriptedModels(<String>['secondary']),
        ),
      )).unwrap();

      expect(other.fromCache, isFalse);
      expect(factory.totalIssued, 2, reason: '换了模型就要真的去问那个模型');
    });

    test('任务类型变化 → 缓存失效', () async {
      final PersistentAiTaskService service = buildService();
      await service.run(taskRequest(taskId: 't-1', prompt: '同一份输入'));
      final AiTaskRunResult other = (await service.run(
        taskRequest(taskId: 't-2', prompt: '同一份输入', kind: AiTaskKind.translate),
      )).unwrap();
      expect(other.fromCache, isFalse);
      expect(factory.totalIssued, 2);
    });

    test('温度变化 → 缓存失效（参数会影响产出）', () async {
      final PersistentAiTaskService service = buildService();
      await service.run(taskRequest(taskId: 't-1', prompt: '同一份输入'));
      final AiTaskRunResult other = (await service.run(
        taskRequest(taskId: 't-2', prompt: '同一份输入', temperature: 1.5),
      )).unwrap();
      expect(other.fromCache, isFalse);
      expect(factory.totalIssued, 2);
    });

    test('缓存键是确定性摘要：同输入同参数得到同一个键', () {
      final String a = AiResultCacheKey.of(
        kind: AiTaskKind.summary,
        snapshot: const AiInputSnapshot(
          messages: <AiMessage>[AiMessage.user('同一份输入')],
          modelId: 'primary-model',
        ),
        routeModelIds: const <String>['primary-model'],
      ).value;
      final String b = AiResultCacheKey.of(
        kind: AiTaskKind.summary,
        snapshot: const AiInputSnapshot(
          messages: <AiMessage>[AiMessage.user('同一份输入')],
          modelId: 'primary-model',
        ),
        routeModelIds: const <String>['primary-model'],
      ).value;
      expect(a, b);
      expect(a, hasLength(64), reason: 'SHA-256 十六进制摘要');
    });

    test('失败不写缓存：一次网络抖动不会固化成后续所有任务的结果', () async {
      final ScriptedAiFactory failing = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'primary': <AiAttemptScript>[
            ScriptFailure(
              error: AuthError(provider: 'primary', statusCode: 401),
            ),
          ],
        },
        scriptClock: clock,
      );
      final PersistentAiTaskService service = buildService(
        overrideFactory: failing,
      );

      final AiTaskRunResult failed = (await service.run(
        taskRequest(taskId: 't-1', prompt: '会失败的内容'),
      )).unwrap();
      expect(failed.record.status, TaskStatus.failed);
      expect(failed.record.hasResult, isFalse);

      // 再跑一次：必须**重新**发请求（缓存里不能有一条失败记录）。
      await service.run(taskRequest(taskId: 't-2', prompt: '会失败的内容'));
      expect(failing.totalIssued, 2, reason: '失败结果不进缓存');
    });

    test('partial（截断）不写缓存：不完整结果不该被当成完整答案复用', () async {
      final ScriptedAiFactory truncated = ScriptedAiFactory(
        <String, List<AiAttemptScript>>{
          'primary': <AiAttemptScript>[
            const ScriptSuccess(
              deltas: <String>['只有一半'],
              finishReason: 'length',
            ),
          ],
        },
        scriptClock: clock,
      );
      final PersistentAiTaskService service = buildService(
        overrideFactory: truncated,
      );

      final AiTaskRunResult first = (await service.run(
        taskRequest(taskId: 't-1', prompt: '长内容'),
      )).unwrap();
      expect(first.record.status, TaskStatus.partial);

      await service.run(taskRequest(taskId: 't-2', prompt: '长内容'));
      expect(truncated.totalIssued, 2, reason: 'partial 不进缓存');
    });
  });

  group('持久任务与状态', () {
    test('逐次迁移落库：任务记录里能看到终态、消耗与尝试次数', () async {
      final PersistentAiTaskService service = buildService();
      final AiTaskRunResult result = (await service.run(
        taskRequest(taskId: 't-1', prompt: '记录状态'),
      )).unwrap();

      final AiTaskRecord? stored = (await taskStore.findById('t-1')).unwrap();
      expect(stored, isNotNull);
      expect(stored!.status, TaskStatus.succeeded);
      expect(stored.resultText, '摘要正文');
      expect(stored.attemptCount, 1);
      expect(stored.consumedTokens, greaterThan(0));
      expect(stored.kind, AiTaskKind.summary);
      expect(stored.modelAliases, <String>['primary']);
      expect(stored.cacheKey, result.record.cacheKey);
      expect(stored.snapshot.messages.single.content, '记录状态');
      expect(stored.deadline, isNotNull, reason: 'deadline 落库以便重启后仍受同一时限约束');

      // 输入快照往返：重启之后仍能读到「当时发出去什么」。
      final AiInputSnapshot roundTrip = stored.snapshot;
      expect(roundTrip.messages.single.content, '记录状态');
      expect(roundTrip.modelId, 'primary-model');
    });

    test('输入快照的 JSON 往返无损（含语言与参数）', () {
      const AiInputSnapshot original = AiInputSnapshot(
        messages: <AiMessage>[
          AiMessage.system('你是总结助手'),
          AiMessage.user('把这段总结一下：你好世界'),
        ],
        modelId: 'deepseek-chat',
        language: 'zh-Hans',
        temperature: 0.3,
        maxTokens: 512,
      );
      final AiInputSnapshot? restored = AiInputSnapshot.fromJson(
        original.toJson(),
      );
      expect(restored, isNotNull);
      expect(restored!.modelId, original.modelId);
      expect(restored.language, original.language);
      expect(restored.temperature, original.temperature);
      expect(restored.maxTokens, original.maxTokens);
      expect(restored.messages.length, 2);
      expect(restored.messages.first.role, AiRole.system);
      expect(restored.messages.first.content, '你是总结助手');
      expect(restored.promptHash, original.promptHash);
    });

    test('快照结构损坏时返回 null（不猜内容）', () {
      expect(AiInputSnapshot.fromJson(<String, Object?>{}), isNull);
      expect(
        AiInputSnapshot.fromJson(<String, Object?>{
          'modelId': 'm',
          'messages': <Object?>[
            <String, Object?>{'role': '不存在的角色', 'content': 'x'},
          ],
        }),
        isNull,
      );
    });
  });

  group('中断语义（进程重启）', () {
    test('启动把 running/waiting 标成 interrupted，且**不自动重发**', () async {
      // 造一条「上次进程结束时还在跑」的记录。
      final DateTime startedAt = clock.now();
      await taskStore.save(
        AiTaskRecord(
          taskId: 't-running',
          kind: AiTaskKind.summary,
          snapshot: const AiInputSnapshot(
            messages: <AiMessage>[AiMessage.user('上次没跑完')],
            modelId: 'primary-model',
          ),
          modelAliases: const <String>['primary'],
          status: TaskStatus.running,
          createdAt: startedAt,
          updatedAt: startedAt,
          deadline: startedAt.add(const Duration(minutes: 10)),
        ),
      );
      await taskStore.save(
        AiTaskRecord(
          taskId: 't-waiting',
          kind: AiTaskKind.summary,
          snapshot: const AiInputSnapshot(
            messages: <AiMessage>[AiMessage.user('断网等待')],
            modelId: 'primary-model',
          ),
          modelAliases: const <String>['primary'],
          status: TaskStatus.waitingNetwork,
          createdAt: startedAt,
          updatedAt: startedAt,
        ),
      );

      // 模拟重启：时间前进，然后跑一次启动标记。
      clock.advance(const Duration(minutes: 3));
      final PersistentAiTaskService service = buildService();
      final AiInterruptionReport report =
          (await service.markInterruptedOnStartup()).unwrap();

      expect(report.markedInterrupted, 2);
      expect(report.hasInterrupted, isTrue);

      final AiTaskRecord running = (await taskStore.findById('t-running'))
          .unwrap()!;
      final AiTaskRecord waiting = (await taskStore.findById('t-waiting'))
          .unwrap()!;
      expect(running.status, TaskStatus.interrupted);
      expect(waiting.status, TaskStatus.interrupted);
      expect(
        running.deadline,
        startedAt.add(const Duration(minutes: 10)),
        reason: '标中断不得改动 deadline',
      );

      expect(factory.totalIssued, 0, reason: '架构 4.5：不能自动重放不确定是否计费的请求');
    });

    test('已结束（终态）的任务不被启动标记覆盖', () async {
      final DateTime at = clock.now();
      await taskStore.save(
        AiTaskRecord(
          taskId: 't-done',
          kind: AiTaskKind.summary,
          snapshot: const AiInputSnapshot(
            messages: <AiMessage>[AiMessage.user('已经成功')],
            modelId: 'primary-model',
          ),
          modelAliases: const <String>['primary'],
          status: TaskStatus.succeeded,
          createdAt: at,
          updatedAt: at,
          resultText: '成功的结果',
        ),
      );

      clock.advance(const Duration(minutes: 1));
      final AiInterruptionReport report =
          (await buildService().markInterruptedOnStartup()).unwrap();

      expect(report.markedInterrupted, 0);
      final AiTaskRecord kept = (await taskStore.findById('t-done')).unwrap()!;
      expect(kept.status, TaskStatus.succeeded);
      expect(kept.resultText, '成功的结果', reason: '成功版本不被后续任何状态覆盖（手册 T030 验收）');
    });

    test('interrupted 任务显示在任务列表里，用户可以手动重新开始（新任务承接）', () async {
      final DateTime at = clock.now();
      await taskStore.save(
        AiTaskRecord(
          taskId: 't-old',
          kind: AiTaskKind.summary,
          snapshot: const AiInputSnapshot(
            messages: <AiMessage>[AiMessage.user('中断的内容')],
            modelId: 'primary-model',
          ),
          modelAliases: const <String>['primary'],
          status: TaskStatus.interrupted,
          createdAt: at,
          updatedAt: at,
        ),
      );

      final PersistentAiTaskService service = buildService();
      final List<AiTaskRecord> listed = (await service.listTasks()).unwrap();
      expect(listed, hasLength(1));
      expect(listed.single.isInterrupted, isTrue);

      // 用户手动「重新开始」：新任务承接，旧任务保持 interrupted。
      final AiTaskRunResult restarted = (await service.restart(
        listed.single,
        newTaskId: 't-new',
        models: scriptedModels(<String>['primary']),
      )).unwrap();

      expect(restarted.record.taskId, 't-new');
      expect(restarted.record.status, TaskStatus.succeeded);
      expect(restarted.record.resultText, '摘要正文');

      final AiTaskRecord old = (await taskStore.findById('t-old')).unwrap()!;
      expect(
        old.status,
        TaskStatus.interrupted,
        reason: '恢复由新任务承接，旧任务保持 interrupted 作为事实记录',
      );

      // 两个任务都在列表里（用户能对照两段历史）。
      final List<AiTaskRecord> after = (await service.listTasks()).unwrap();
      expect(
        after.map((AiTaskRecord r) => r.taskId),
        containsAll(<String>['t-old', 't-new']),
      );
    });

    test('只能重新开始已结束的任务（活跃态任务不接受 restart）', () async {
      final DateTime at = clock.now();
      final AiTaskRecord active = AiTaskRecord(
        taskId: 't-active',
        kind: AiTaskKind.summary,
        snapshot: const AiInputSnapshot(
          messages: <AiMessage>[AiMessage.user('还在跑')],
          modelId: 'primary-model',
        ),
        modelAliases: const <String>['primary'],
        status: TaskStatus.running,
        createdAt: at,
        updatedAt: at,
      );
      final Result<AiTaskRunResult> result = await buildService().restart(
        active,
        newTaskId: 't-new',
        models: scriptedModels(<String>['primary']),
      );
      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<ValidationError>());
      expect(factory.totalIssued, 0);
    });
  });

  group('机制边界', () {
    test('缓存键需要至少一个候选模型（否则明确报错，不猜一个）', () {
      final PersistentAiTaskService service = buildService();
      final Result<String> key = service.cacheKeyFor(
        AiTaskRequest(
          taskId: 't-1',
          kind: AiTaskKind.summary,
          request: AiRequest(
            modelId: 'm',
            messages: const <AiMessage>[AiMessage.user('x')],
          ),
          models: const <AiModel>[],
        ),
      );
      expect(key.isErr, isTrue);
    });

    test('缺失的 taskId 读作 null（区别于「读取失败」）', () async {
      final Result<AiTaskRecord?> missing = await taskStore.findById('不存在');
      expect(missing.isOk, isTrue);
      expect(missing.valueOrNull, isNull);
    });

    test('清空缓存只清缓存，不删任务记录（T047 的边界）', () async {
      final PersistentAiTaskService service = buildService();
      await service.run(taskRequest(taskId: 't-1', prompt: '留下记录'));
      expect((await service.listTasks()).unwrap(), hasLength(1));

      (await cache.clear()).unwrap();

      expect((await service.listTasks()).unwrap(), hasLength(1));
      // 清缓存之后再跑一次：必须重新发请求（缓存真的没了）。
      await service.run(taskRequest(taskId: 't-2', prompt: '留下记录'));
      expect(factory.totalIssued, 2);
    });
  });

  group('Token 估算（供缓存与预算共用）', () {
    test('空消息与消息结构开销都计入估算', () {
      expect(estimateRequestTokens(const <String>[]), 0);
      // 一条空消息仍有一条消息的结构开销（角色/分隔），而不是 0。
      expect(estimateRequestTokens(const <String>['']), 4);
      expect(
        estimateRequestTokens(const <String>['你好']),
        greaterThan(estimateRequestTokens(const <String>[''])),
      );
    });
  });
}
