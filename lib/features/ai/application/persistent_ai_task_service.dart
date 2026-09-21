// 持久化 AI 任务用例：缓存命中、状态落库与中断恢复（T030；架构 4.4/4.5、手册 T030）。
//
// 这一层是 AiTaskRunner（T029，纯执行）与存储之间的**唯一**桥接点。它回答四件事：
//
//   1) **先查缓存再发请求**。缓存键由「任务类型 + 输入哈希 + 路由模型链 + 语言 +
//      参数」合成（架构 4.5），因此输入/模型/语言任一变化都会得到另一个键，
//      命中判定不需要任何「记得清缓存」的调用点。命中时返回的记录带 fromCache=真，
//      并且**一个请求都不发**（有用例用请求计数断言这一点）。
//
//   2) **成功才写缓存**。failed / cancelled / partial 都不写：把失败固化下来会让一次
//      网络抖动变成之后所有同输入任务的结论；partial 不写则是因为它本来就承认不完整，
//      用它命中下一次会让用户以为拿到了完整结果。
//
//   3) **任务状态与输入快照落库**。每次状态迁移都写一次（失败也不会让任务从列表里消失）。
//      输入快照是「当时发出去什么」的历史事实，进程重启后仍可复盘。
//
//   4) **启动时把活跃任务标成 interrupted，且绝不自动重发**。架构 4.5 明确「服务进程被
//      系统终止时记 interrupted，不能自动重放不确定是否计费的请求」——重发的代价是
//      用户可能为同一份内容付两次费，而收益只是省一次点击。
library;

import 'package:flux/core/core.dart';

import '../domain/ai_message.dart';
import '../domain/ai_model.dart';
import '../domain/ai_task_record.dart';
import '../domain/ai_task_store.dart';
import 'ai_task_budget.dart';
import 'ai_task_runner.dart';

/// 一次被请求执行的任务（调用方给出「要什么」，执行细节由本层与 runner 决定）。
final class AiTaskRequest {
  /// 构造请求。
  const AiTaskRequest({
    required this.taskId,
    required this.kind,
    required this.request,
    required this.models,
    this.language,
  });

  /// 任务标识（本机唯一；由调用方生成，便于把任务与界面上那次操作对应起来）。
  final String taskId;

  /// 任务类型（缓存键的组成部分）。
  final AiTaskKind kind;

  /// 统一的生成请求（消息、参数、取消信号）。
  final AiRequest request;

  /// 按故障转移顺序排列的启用模型。
  final List<AiModel> models;

  /// 目标语言（SET-011 的内容语言）。
  final String? language;
}

/// 一次任务的执行结果（含任务记录与是否来自缓存）。
final class AiTaskRunResult {
  /// 构造结果。
  const AiTaskRunResult({
    required this.record,
    required this.task,
    this.fromCache = false,
  });

  /// 落库后的任务记录（权威状态）。
  final AiTaskRecord record;

  /// 真实执行的产出；命中缓存时为 null。
  ///
  /// 为什么保留两个字段而不是统一成一个：命中缓存时**没有** attempt 记录、没有 usage、
  /// 没有失败原因，把它伪装成一次执行产出会让诊断显示一次并不存在的调用。
  final AiTaskOutcome? task;

  /// 本次结果是否直接来自缓存。
  final bool fromCache;
}

/// 中断恢复的汇总（启动时调用一次）。
final class AiInterruptionReport {
  /// 构造汇总。
  const AiInterruptionReport({required this.markedInterrupted});

  /// 被标记为 interrupted 的任务数。
  final int markedInterrupted;

  /// 是否有任务被中断（界面据此提示）。
  bool get hasInterrupted => markedInterrupted > 0;
}

/// 持久化 AI 任务用例。
final class PersistentAiTaskService {
  /// 构造用例。
  const PersistentAiTaskService({
    required this.tasks,
    required this.cache,
    required this.clock,
    required this.diagnostics,
    required this.budget,
    required this.runnerFactory,
  });

  /// 任务存储。
  final AiTaskStore tasks;

  /// 结果缓存。
  final AiResultCache cache;

  /// 时钟（测试注入假时钟）。
  final Clock clock;

  /// 诊断记录。
  final DiagnosticSink diagnostics;

  /// 本次运行的预算（deadline 按它计算并在创建时固定）。
  final AiTaskBudget budget;

  /// 执行器工厂：按 onSnapshot 回调构造一个 AiTaskRunner。
  ///
  /// 用工厂而不是直接持有一个 runner：runner 的快照回调必须绑到**这次任务**的持久化上，
  /// 共享一个实例会让两次并发任务的快照写进同一条记录。
  final AiTaskRunner Function(void Function(TaskSnapshot snapshot) onSnapshot)
  runnerFactory;

  /// 启动时把上次留下的活跃任务标成 interrupted。
  ///
  /// 为什么**不**顺手把它们重发：重发的代价是可能为同一份内容付两次费，而收益只是
  /// 省用户一次点击（架构 4.5「不能自动重放不确定是否计费的请求」）。
  Future<Result<AiInterruptionReport>> markInterruptedOnStartup() async {
    final Result<int> marked = await tasks.markActiveAsInterrupted(
      at: clock.now(),
    );
    if (marked.isErr) {
      // 失败时**不**静默放过：调用方需要知道「本次启动没能把上次的活跃任务标出来」，
      // 否则界面上会一直显示一个永远不会完成的运行中任务。
      return Err<AiInterruptionReport>(marked.errorOrNull!);
    }
    final int count = marked.valueOrNull!;
    if (count > 0) {
      diagnostics.warning('启动时把 $count 个未完成任务标记为已中断（不自动重发）', tag: 'ai.task');
    }
    return Ok<AiInterruptionReport>(
      AiInterruptionReport(markedInterrupted: count),
    );
  }

  /// 列出全部任务（含 interrupted 的历史任务，用户可在列表里看到并手动重开）。
  Future<Result<List<AiTaskRecord>>> listTasks() => tasks.loadAll();

  /// 计算一次任务的缓存键（供调用方在发请求前判断是否会命中）。
  Result<String> cacheKeyFor(AiTaskRequest request) {
    if (request.models.isEmpty) {
      return Err<String>(
        ProviderError(
          provider: '-',
          kind: 'noEnabledModel',
          detail: '没有可用于路由的启用模型',
        ),
      );
    }
    return Ok<String>(
      AiResultCacheKey.of(
        kind: request.kind,
        snapshot: AiInputSnapshot.fromRequest(
          request.request,
          language: request.language,
        ),
        routeModelIds: <String>[
          for (final AiModel model in request.models) model.modelId,
        ],
      ).value,
    );
  }

  /// 执行一次任务：先查缓存，未命中则真实执行并落库。
  Future<Result<AiTaskRunResult>> run(AiTaskRequest request) async {
    final DateTime now = clock.now();
    final AiInputSnapshot snapshot = AiInputSnapshot.fromRequest(
      request.request,
      language: request.language,
    );
    final Result<String> keyResult = cacheKeyFor(request);
    if (keyResult.isErr) {
      return Err<AiTaskRunResult>(keyResult.errorOrNull!);
    }
    final String cacheKey = keyResult.valueOrNull!;

    // ---- 1) 缓存命中：一个请求都不发 --------------------------------------
    final Result<AiResultCacheEntry?> hit = await cache.find(cacheKey);
    if (hit.isErr) {
      // 缓存读失败既不当成命中（那会返回一份来源不明的内容），也不直接让任务失败
      // （缓存是优化，不是任务的前提）。按「无法确认命中」继续，并留下事实：
      // 下面的记录 fromCache 仍为假，需要真实发请求。
      diagnostics.warning(
        'AI 结果缓存读取失败，按未命中处理 kind=${hit.errorOrNull!.kind}',
        tag: 'ai.task',
      );
    }
    final AiResultCacheEntry? entry = hit.valueOrNull;
    if (entry != null) {
      final AiTaskRecord record = AiTaskRecord(
        taskId: request.taskId,
        kind: request.kind,
        snapshot: snapshot,
        modelAliases: <String>[
          for (final AiModel model in request.models) model.alias,
        ],
        status: TaskStatus.succeeded,
        createdAt: now,
        updatedAt: now,
        resultText: entry.text,
        providerAlias: entry.providerAlias,
        cacheKey: cacheKey,
        fromCache: true,
      );
      final Result<void> saved = await tasks.save(record);
      if (saved.isErr) {
        return Err<AiTaskRunResult>(saved.errorOrNull!);
      }
      diagnostics.info(
        'AI 任务命中缓存 task=${request.taskId} kind=${request.kind.id} '
        'chars=${entry.text.length}',
        tag: 'ai.task',
      );
      return Ok<AiTaskRunResult>(
        AiTaskRunResult(record: record, task: null, fromCache: true),
      );
    }

    // ---- 2) 未命中：落一条 queued 记录，再真实执行 -------------------------
    AiTaskRecord record = AiTaskRecord(
      taskId: request.taskId,
      kind: request.kind,
      snapshot: snapshot,
      modelAliases: <String>[
        for (final AiModel model in request.models) model.alias,
      ],
      status: TaskStatus.queued,
      createdAt: now,
      updatedAt: now,
      // deadline 与 runner 内部固定的一致：创建时算一次，之后不重置（SET-059）。
      deadline: now.add(budget.totalLimit),
      cacheKey: cacheKey,
    );
    final Result<void> queued = await tasks.save(record);
    if (queued.isErr) {
      return Err<AiTaskRunResult>(queued.errorOrNull!);
    }

    // 每次迁移都落库：断在这里的进程会留下与真实进度一致的记录，而不会显示一个
    // 其实早就失败了的「运行中」。onSnapshot 是同步签名，因此把写入 Future 收起来，
    // 执行结束后统一等待（见下面的 _drain）。
    final List<Future<Result<void>>> pending = <Future<Result<void>>>[];
    final AiTaskRunner runner = runnerFactory((TaskSnapshot arc) {
      record = record.copyWith(
        status: arc.status,
        deadline: arc.deadline,
        updatedAt: clock.now(),
      );
      pending.add(tasks.save(record));
    });

    final AiTaskOutcome outcome = await runner.run(
      taskId: request.taskId,
      request: request.request,
      models: request.models,
    );
    await _drain(pending);

    // ---- 3) 落最终状态；成功才写缓存 --------------------------------------
    record = record.copyWith(
      status: outcome.status,
      deadline: outcome.snapshot.deadline,
      consumedTokens: outcome.consumedTokens,
      attemptCount: outcome.attemptCount,
      resultText: outcome.text,
      finishReason: outcome.finishReason,
      errorKind: outcome.error?.kind,
      providerAlias: outcome.alias,
      updatedAt: outcome.snapshot.finishedAt ?? clock.now(),
    );
    final Result<void> finished = await tasks.save(record);
    if (finished.isErr) {
      return Err<AiTaskRunResult>(finished.errorOrNull!);
    }

    if (outcome.status == TaskStatus.succeeded && outcome.hasResult) {
      final Result<void> cached = await cache.save(
        AiResultCacheEntry(
          key: cacheKey,
          text: outcome.text!,
          providerAlias: outcome.alias ?? '',
          modelId: outcome.modelId ?? '',
          createdAt: clock.now(),
        ),
      );
      if (cached.isErr) {
        // 缓存写失败不改变本次任务的成功结论（结果已经在 record 里），但必须留下事实：
        // 否则「下次还得再花一次钱」在日志里毫无线索。
        diagnostics.warning(
          'AI 结果缓存写入失败 task=${request.taskId} '
          'kind=${cached.errorOrNull!.kind}',
          tag: 'ai.task',
        );
      }
    }

    return Ok<AiTaskRunResult>(AiTaskRunResult(record: record, task: outcome));
  }

  /// 「重新开始」一个已结束的任务：**创建新任务**，旧任务保持原状态。
  ///
  /// 为什么不改旧记录的状态：状态机把 interrupted 定义成终态，「终态不可迁移」由
  /// TaskTransition 的表结构保证。用新任务承接既符合状态机，也让两段历史都能被看到
  /// （用户能对照「那次没跑完」与「这次的结果」）。
  ///
  /// [models] 必须由调用方传入**当前**的启用模型列表：旧快照里只有别名，而用户可能
  /// 已经停用或删除了那个模型——用旧配置硬跑会向一个用户以为已经关掉的端点发请求。
  Future<Result<AiTaskRunResult>> restart(
    AiTaskRecord previous, {
    required String newTaskId,
    required List<AiModel> models,
  }) async {
    if (!previous.status.isTerminal) {
      return Err<AiTaskRunResult>(
        ValidationError(
          field: 'aiTask.restart',
          reason: '只能重新开始已结束的任务',
          value: previous.status.name,
        ),
      );
    }
    // 带图任务**拒绝重放**（T033）：图片的字节不进快照（见 AiInputSnapshot.toJson），
    // 因此这里没有图可发。按纯文本重放等于用另一份输入去请求——用户看到的是「重新开始」
    // 按钮，花掉的却是一次与原来不同的调用。如实拒绝，让用户在原处重新发起。
    if (previous.snapshot.hasImages) {
      return Err<AiTaskRunResult>(
        ValidationError(
          field: 'aiTask.restart',
          reason: '这次任务包含图片，图片不进任务快照，无法原样重新开始',
          value: '${previous.snapshot.imageCount} images',
        ),
      );
    }
    return run(
      AiTaskRequest(
        taskId: newTaskId,
        kind: previous.kind,
        request: AiRequest(
          modelId: previous.snapshot.modelId,
          messages: previous.snapshot.messages,
          maxTokens: previous.snapshot.maxTokens,
          temperature: previous.snapshot.temperature,
        ),
        models: models,
        language: previous.snapshot.language,
      ),
    );
  }

  /// 等待全部迁移写入结束；失败只记诊断（任务的最终状态由下面那次写入决定）。
  Future<void> _drain(List<Future<Result<void>>> pending) async {
    for (final Future<Result<void>> write in pending) {
      final Result<void> result = await write;
      if (result.isErr) {
        diagnostics.warning(
          'AI 任务进度落库失败 kind=${result.errorOrNull!.kind}',
          tag: 'ai.task',
        );
      }
    }
  }
}
