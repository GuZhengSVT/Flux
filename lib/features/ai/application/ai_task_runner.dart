// 有预算的 AI 任务队列、五次无响应与跨模型故障转移（T029；D-09、架构 4.4/4.5、手册 6.3）。
//
// 职责：拿一个请求 + 一份**有序的启用模型列表**，在预算内把它跑成一次结果。
// 不在本层的事：真实协议细节（适配器，T026/T027）、持久化与缓存（T030）、
// 检索/视觉/工具（T032–T034）。本层只做「顺序尝试、计数、预算闸门、状态机接线」。
//
// 五条刻意的设计决定：
//
//   1) **故障转移是串行的**。架构 4.5 明确「不允许多个后台请求超时后仍并发挂着：
//      先取消上一尝试再重试」。并行竞速会同时向两家计费，并且「先到者胜」让产出模型
//      不确定——同一次任务的成本与内容来源都会变得不可复现。并发上限（SET-036 的 2）
//      约束的是「同任务内在途请求数」，不是让故障转移变成并行。
//
//   2) **每次尝试有自己的取消信号（子信号）**。单次硬时限到点时只取消这一次请求，
//      任务本身继续走故障转移；用户取消则通过父信号传播到所有子信号。把两者混成
//      一个信号会让「一次超时」把整个任务变成已取消，用户会以为是自己取消的。
//
//   3) **只有「无可用响应」消耗五次额度**。认证失败与内容拒绝既不计数也不换模型
//      （架构 4.5：Key 错/余额不足/模型不存在直接标配置错误；内容拒绝不得跨服务商
//      规避）。把这两类算进五次会发生「拿坏 Key 连打五个模型」这种真实浪费。
//
//   4) **半句话不当完整答案，但也不丢掉**。流中断且已收到部分文本时状态是
//      [TaskStatus.partial] 并带上失败原因；跨模型的半句话**从不拼接**（架构 4.5）。
//
//   5) **deadline 在任务创建时固定，之后不重置**（SET-059、TaskTransition 的既有规则）。
//      排队、退避、断网等待都计入同一个总时限，因此拖延不会换来更多时间。
library;

import 'dart:async';

import 'package:flux/core/core.dart';

import '../domain/ai_credential_store.dart';
import '../domain/ai_message.dart';
import '../domain/ai_model.dart';
import '../domain/ai_provider.dart';
import 'ai_failover.dart';
import 'ai_task_budget.dart';

/// 一次尝试的结构化记录（诊断与验收用）。
///
/// 只记**结构事实**：别名、结果类别、token 数、耗时。不记 prompt、不记模型输出正文、
/// 不记 Key（架构第 8 节）。
final class AiAttemptRecord {
  /// 构造记录。
  const AiAttemptRecord({
    required this.index,
    required this.alias,
    required this.modelId,
    required this.failureClass,
    required this.usage,
    required this.estimatedTokens,
    required this.elapsed,
    this.note,
  });

  /// 第几次 HTTP 尝试（1 起，全局，对应 SET-062 的 httpAttempts）。
  final int index;

  /// 提供商别名。
  final String alias;

  /// 服务商侧模型 ID。
  final String modelId;

  /// 失败类别；成功时为 null。
  final AiFailureClass? failureClass;

  /// 服务商给出的用量；未给出时为 null。
  final AiUsage? usage;

  /// 本次计入预算的 token（usage 优先，无 usage 时为估算）。
  final int estimatedTokens;

  /// 本次耗时。
  final Duration elapsed;

  /// 结构性备注（例如 retryAfterHonored、offlinePaused、truncated）。
  final String? note;

  /// 是否成功。
  bool get succeeded => failureClass == null;
}

/// 一次任务的产出。
final class AiTaskOutcome {
  /// 构造产出。
  const AiTaskOutcome({
    required this.snapshot,
    required this.status,
    required this.attempts,
    required this.consumedTokens,
    required this.error,
    this.text,
    this.usage,
    this.alias,
    this.modelId,
    this.finishReason,
  });

  /// 状态机最终快照（含 revision / deadline / startedAt / finishedAt）。
  final TaskSnapshot snapshot;

  /// 终态（succeeded / partial / failed / cancelled）。
  final TaskStatus status;

  /// 全部尝试记录（按发生顺序）。
  final List<AiAttemptRecord> attempts;

  /// 累计消耗 token（服务商统计 + 估算）。
  final int consumedTokens;

  /// 失败/取消的原因；成功时为 null。
  final AppError? error;

  /// 产出的完整文本；仅成功与部分成功时有值。
  ///
  /// **从不拼接跨尝试的文本**：只有产出这次结果的那一个模型的一条流会成为它。
  final String? text;

  /// 服务商给出的用量；未给出时为 null。
  final AiUsage? usage;

  /// 产出该结果的模型别名。
  final String? alias;

  /// 产出该结果的模型 ID。
  final String? modelId;

  /// 服务商给出的结束原因。
  final String? finishReason;

  /// 是否成功产出可用结果（完整或部分）。
  bool get hasResult => text != null && text!.isNotEmpty;

  /// 尝试次数（含失败尝试）。
  int get attemptCount => attempts.length;

  /// 消耗 token 是否为估算（服务商未给出 usage）。
  bool get consumedIsEstimated => usage == null;
}

/// 有预算的任务队列。
final class AiTaskRunner {
  /// 构造队列。
  const AiTaskRunner({
    required this.credentials,
    required this.factory,
    required this.diagnostics,
    required this.budget,
    required this.clock,
    this.delayScheduler = const RealAiDelayScheduler(),
    this.networkConditions,
    this.offlineRetryDelay = const Duration(seconds: 1),
    this.failoverThreshold = 5,
    this.onSnapshot,
  });

  /// 凭据读取（SET-031；Key 只在此处短暂存在，绝不进日志）。
  final AiCredentialStore credentials;

  /// 适配器工厂。
  final AiProviderFactory factory;

  /// 诊断记录。
  final DiagnosticSink diagnostics;

  /// 本次任务的预算（总时限 / 次数 / Token / 并发）。
  final AiTaskBudget budget;

  /// 时钟（测试注入假时钟）。
  final Clock clock;

  /// 等待调度（退避与 Retry-After 的等待）。
  final AiDelayScheduler delayScheduler;

  /// 网络状况端口；为空时不做「离线暂停」判定。
  final NetworkConditionPort? networkConditions;

  /// 判定为离线后让出多久再试（计入总时限）。
  final Duration offlineRetryDelay;

  /// 连续多少次无响应后切下一个模型（D-09 默认五次）。
  final int failoverThreshold;

  /// 每次状态迁移后的回调（T030 用它落库；T029 只做状态机接线）。
  final void Function(TaskSnapshot snapshot)? onSnapshot;

  /// 在预算内把一个请求跑成一次结果。
  ///
  /// [models] 必须是**已按故障转移顺序排序**的启用模型（调用方用
  /// ModelManager.loadEnabledModels 取；本层不再排序，否则「顺序」会有两个来源）。
  Future<AiTaskOutcome> run({
    required String taskId,
    required AiRequest request,
    required List<AiModel> models,
  }) async {
    final AiCancellation outerCancel = request.cancellation;
    final AiInFlightLimiter limiter = AiInFlightLimiter(budget.concurrency);
    final List<AiAttemptRecord> attempts = <AiAttemptRecord>[];

    // deadline 在创建时固定（SET-059）：排队、退避与断网等待都计入同一时限。
    TaskSnapshot snapshot = TaskSnapshot.pending(
      taskId: taskId,
      deadline: clock.now().add(budget.totalLimit),
    );
    _dispatch(snapshot);
    snapshot = _transition(snapshot, TaskStatus.running);

    if (models.isEmpty) {
      return _finishFailed(
        snapshot,
        attempts,
        0,
        ProviderError(
          provider: '-',
          kind: 'noEnabledModel',
          detail: '启用模型列表为空',
        ),
      );
    }
    if (outerCancel.isCancelled) {
      return _finishCancelled(
        snapshot,
        attempts,
        0,
        CancelledError(reason: '任务在开始前已取消'),
      );
    }

    // 输入侧 token 先估算并计入预算：SET-063 要求「调用前预留」，
    // 否则一次把上下文塞到超出剩余额度的请求会被真的发出去并计费。
    final int inputTokens = estimateRequestTokens(
      request.messages.map((AiMessage message) => message.content),
    );
    int consumed = inputTokens;
    if (consumed >= budget.tokenBudget) {
      return _finishFailed(
        snapshot,
        attempts,
        consumed,
        BudgetExhaustedError(
          limitKind: 'tokens',
          limit: budget.tokenBudget,
          consumed: consumed,
          detail: '输入已超过任务 Token 预算，未发起请求',
        ),
      );
    }

    AppError? lastError;
    String? partialText;
    String? partialAlias;
    String? partialModelId;
    String? lastFinishReason;
    bool sawOfflinePause = false;

    for (final AiModel model in models) {
      final AiFailoverTracker tracker = AiFailoverTracker(
        threshold: failoverThreshold,
      );
      int retryAfterHonored = 0;
      bool advanceToNextModel = false;

      while (!advanceToNextModel) {
        // ---- 预算闸门（每次调用前检查，SET-059/062/063） --------------------
        if (snapshot.isDeadlineExceededAt(clock.now())) {
          return _finishFailed(
            snapshot,
            attempts,
            consumed,
            DeadlineExceededError(
              limitKind: AiTaskBudget.taskDeadlineLimitKind,
              limit: budget.totalLimit,
              elapsed: budget.totalLimit,
            ),
            partial: partialText,
            partialAlias: partialAlias,
            partialModelId: partialModelId,
          );
        }
        if (attempts.length >= budget.maxHttpAttempts) {
          return _finishFailed(
            snapshot,
            attempts,
            consumed,
            BudgetExhaustedError(
              limitKind: 'httpAttempts',
              limit: budget.maxHttpAttempts,
              consumed: attempts.length,
            ),
            partial: partialText,
            partialAlias: partialAlias,
            partialModelId: partialModelId,
          );
        }
        if (consumed >= budget.tokenBudget) {
          return _finishFailed(
            snapshot,
            attempts,
            consumed,
            BudgetExhaustedError(
              limitKind: 'tokens',
              limit: budget.tokenBudget,
              consumed: consumed,
            ),
            partial: partialText,
            partialAlias: partialAlias,
            partialModelId: partialModelId,
          );
        }
        if (outerCancel.isCancelled) {
          return _finishCancelled(
            snapshot,
            attempts,
            consumed,
            CancelledError(reason: '任务已取消'),
          );
        }

        // ---- 取凭据与适配器（失败即配置错误，不换模型） ----------------------
        final AiProvider? provider = await _providerFor(model);
        if (provider == null) {
          return _finishFailed(
            snapshot,
            attempts,
            consumed,
            lastError ?? _credentialMissing(model),
            partial: partialText,
            partialAlias: partialAlias,
            partialModelId: partialModelId,
          );
        }

        // ---- 一次尝试（含在途额度、子取消、单次硬时限） ----------------------
        snapshot = _ensureRunning(snapshot);
        await limiter.acquire();
        final AiCancellation child = AiCancellation();
        void propagate() => child.cancel(reason: 'taskCancelled');
        outerCancel.addListener(propagate);
        final int index = attempts.length + 1;
        final Duration startedAt = clock.monotonic();
        _AttemptResult result;
        try {
          result = await _attempt(
            provider: provider,
            model: model,
            request: request,
            cancellation: child,
            limiter: limiter,
          );
        } finally {
          outerCancel.removeListener(propagate);
        }
        final Duration elapsed = clock.monotonic() - startedAt;

        // 计费记账：usage 优先，未给出时按字符保守估算（标记为估算）。
        final int attemptTokens = result.usage != null
            ? result.usage!.effectiveTotal
            : estimateAiTokens(result.text);
        consumed += attemptTokens;

        if (result.error == null) {
          final bool truncated = _isTruncated(result.finishReason);
          attempts.add(
            AiAttemptRecord(
              index: index,
              alias: model.alias,
              modelId: model.modelId,
              failureClass: null,
              usage: result.usage,
              estimatedTokens: attemptTokens,
              elapsed: elapsed,
              note: truncated ? 'truncated' : null,
            ),
          );
          tracker.recordSuccess();
          _log(
            '任务模型调用成功 task=$taskId alias=${model.alias} attempt=$index '
            'tokens=$attemptTokens truncated=$truncated',
            success: true,
          );
          final TaskStatus status = truncated
              ? TaskStatus.partial
              : TaskStatus.succeeded;
          snapshot = _transition(snapshot, status);
          return AiTaskOutcome(
            snapshot: snapshot,
            status: status,
            attempts: List<AiAttemptRecord>.unmodifiable(attempts),
            consumedTokens: consumed,
            error: null,
            text: result.text,
            usage: result.usage,
            alias: model.alias,
            modelId: model.modelId,
            finishReason: result.finishReason,
          );
        }

        final Object error = result.error!;
        final AiFailureClass failureClass = classifyAiFailure(error);
        attempts.add(
          AiAttemptRecord(
            index: index,
            alias: model.alias,
            modelId: model.modelId,
            failureClass: failureClass,
            usage: result.usage,
            estimatedTokens: attemptTokens,
            elapsed: elapsed,
            // 结构性备注：已经为这个模型服从过一次 Retry-After，再撞上 429 就按
            // 「一次无响应」计（不进入退避风暴）。把它记下来让诊断能区分这两种 429。
            note: retryAfterHonored > 0 ? 'retryAfterHonored' : null,
          ),
        );
        lastError = error is AppError ? error : null;
        lastFinishReason = result.finishReason ?? lastFinishReason;
        if (result.text.isNotEmpty) {
          partialText = result.text;
          partialAlias = model.alias;
          partialModelId = model.modelId;
        }

        // ---- 取消：立即终止，不再发任何请求 --------------------------------
        if (failureClass == AiFailureClass.cancelled) {
          return _finishCancelled(snapshot, attempts, consumed, error);
        }

        // ---- 内容拒绝：不换模型，直接失败该链（D-09、架构 4.5） --------------
        if (failureClass == AiFailureClass.contentRefused) {
          _log(
            '任务被内容拒绝停止 task=$taskId alias=${model.alias} '
            'attempt=$index（不跨服务商规避）',
            success: false,
          );
          return _finishFailed(
            snapshot,
            attempts,
            consumed,
            error,
            partial: partialText,
            partialAlias: partialAlias,
            partialModelId: partialModelId,
          );
        }

        // ---- 配置错误/格式错误/未类型化：不换模型，直接失败 ------------------
        if (failureClass == AiFailureClass.configuration ||
            failureClass == AiFailureClass.format ||
            failureClass == AiFailureClass.internal) {
          return _finishFailed(
            snapshot,
            attempts,
            consumed,
            error,
            partial: partialText,
            partialAlias: partialAlias,
            partialModelId: partialModelId,
          );
        }

        // ---- 预算/时限边界：终止（即使还没凑足五次） ------------------------
        if (failureClass == AiFailureClass.budget) {
          return _finishFailed(
            snapshot,
            attempts,
            consumed,
            error,
            partial: partialText,
            partialAlias: partialAlias,
            partialModelId: partialModelId,
          );
        }

        // ---- 429：服从 Retry-After 一次（每个模型一次） ----------------------
        if (error is RateLimitError &&
            error.retryAfter != null &&
            retryAfterHonored == 0) {
          retryAfterHonored++;
          final Duration wait = _clampWait(error.retryAfter!);
          _log(
            '任务服从 Retry-After task=$taskId alias=${model.alias} '
            'waitMs=${wait.inMilliseconds}',
            success: false,
          );
          await delayScheduler.delay(wait);
          continue;
        }

        // ---- 设备离线：暂停整条任务，不消耗五次额度（架构 4.5） --------------
        if (await _isOffline(error)) {
          sawOfflinePause = true;
          snapshot = _transition(snapshot, TaskStatus.waitingNetwork);
          _log(
            '任务因离线暂停 task=$taskId alias=${model.alias} attempt=$index',
            success: false,
          );
          await delayScheduler.delay(offlineRetryDelay);
          snapshot = _ensureRunning(snapshot);
          // 不计入五次：离线是设备状态，不是这个模型不响应。
          continue;
        }

        // ---- 无响应：计一次，攒够五次才切下一个模型 ------------------------
        _log(
          '任务模型无响应 task=$taskId alias=${model.alias} '
          'attempt=$index consecutive=${tracker.consecutive + 1} '
          'kind=${error is AppError ? error.kind : error.runtimeType}',
          success: false,
        );
        if (tracker.recordNoResponse()) {
          if (!budget.failoverEnabled) {
            return _finishFailed(
              snapshot,
              attempts,
              consumed,
              error,
              partial: partialText,
              partialAlias: partialAlias,
              partialModelId: partialModelId,
            );
          }
          _log(
            '任务切换下一个模型 task=$taskId from=${model.alias} '
            'after=${tracker.consecutive}',
            success: false,
          );
          advanceToNextModel = true;
        }
      }
    }

    // ---- 候选耗尽：failed（或带部分文本的 partial） -------------------------
    _log('任务模型列表耗尽 task=$taskId attempts=${attempts.length}', success: false);
    return _finishFailed(
      snapshot,
      attempts,
      consumed,
      lastError ??
          ProviderError(
            provider: models.last.alias,
            kind: sawOfflinePause ? 'offline' : 'noUsableResponse',
          ),
      partial: partialText,
      partialAlias: partialAlias,
      partialModelId: partialModelId,
      finishReason: lastFinishReason,
    );
  }

  /// 实际发起一次调用；返回文本、usage、结束原因或类型化错误。
  Future<_AttemptResult> _attempt({
    required AiProvider provider,
    required AiModel model,
    required AiRequest request,
    required AiCancellation cancellation,
    required AiInFlightLimiter limiter,
  }) async {
    final AiRequest attemptRequest = AiRequest(
      modelId: model.modelId,
      messages: request.messages,
      // 未声明输出上限时按 SET-033 的保守预算（2048），而不是「不发送」：
      // 不发送会让服务商用它自己的默认上限，可能远大于我们愿意为之付费的量。
      maxTokens: request.maxTokens ?? model.capability.effectiveOutputBudget,
      temperature: request.temperature,
      tools: request.tools,
      cancellation: cancellation,
    );
    final StringBuffer received = StringBuffer();
    AiUsage? usage;
    String? finishReason;
    try {
      await _withHardLimit(
        cancellation: cancellation,
        work: () async {
          await for (final AiEvent event in provider.generate(attemptRequest)) {
            switch (event) {
              case AiDelta(:final String text):
                received.write(text);
              case AiUsage():
                usage = event;
              case AiDone():
                // 直接读 event.finishReason：对象模式在这里会把类型推导退化成 Object?，
                // 需要一个多余的强转；读字段则类型就是 String?。
                finishReason = event.finishReason;
            }
          }
        },
      );
    } on Object catch (error) {
      // 单次硬时限到点时我们**主动取消**了这次尝试，适配器因此抛出取消错误。
      // 若原样上报，任务会被判成「用户取消」（终态 cancelled），而它实际上只是一次
      // 超时——那会让用户以为是自己取消了任务。这里按取消原因把它翻译回超时错误。
      final Object effective =
          error is CancelledError &&
              cancellation.reason == 'attemptHardLimit' &&
              !request.cancellation.isCancelled
          ? DeadlineExceededError(
              limitKind: AiTaskBudget.attemptHardLimitKind,
              limit: budget.attemptHardLimit,
            )
          : error;
      // 未类型化异常翻译成 NetworkError：原始异常的 toString 可能带上请求体
      // （适配器理论上只抛 AppError；到这里说明适配器有 bug）。
      final AppError typed = effective is AppError
          ? effective
          : NetworkError(
              uri: model.baseUrl,
              reason: '适配器抛出未类型化异常（${effective.runtimeType}）',
              cause: effective,
            );
      return _AttemptResult(
        text: received.toString(),
        // 失败的尝试也可能已经收到 usage（服务商在流里先发用量、随后断流）。
        // 丢掉它会让预算记账漏掉一次真实消耗——那正是「Token 以服务商统计为准」
        // 要避免的：一次断流后预算看起来没变，于是任务继续花钱。
        usage: usage,
        error: typed,
        finishReason: finishReason,
      );
    } finally {
      // 无论成功、失败还是超时都归还额度：漏掉释放会让任务「偶尔卡死」。
      limiter.release();
    }
    return _AttemptResult(
      text: received.toString(),
      usage: usage,
      finishReason: finishReason,
    );
  }

  /// 给一次调用套上单次硬时限与取消。
  ///
  /// 为什么必须是真的计时器（而不是像流守卫那样只在有事件时推进）：卡住的流不会有
  /// 任何事件到达，只靠事件驱动的检查永远等不到；这里用真实 [Timer] 保证「即使一个
  /// 字节都不来，也必须在硬时限内结束」。
  Future<void> _withHardLimit({
    required AiCancellation cancellation,
    required Future<void> Function() work,
  }) {
    final Duration? limit = budget.attemptHardLimit <= Duration.zero
        ? null
        : budget.attemptHardLimit;
    final Completer<void> completer = Completer<void>();
    Timer? timer;
    void onCancel() {
      if (!completer.isCompleted) {
        completer.completeError(CancelledError(reason: '请求已取消'));
      }
    }

    cancellation.addListener(onCancel);
    if (limit != null) {
      timer = Timer(limit, () {
        if (completer.isCompleted) {
          return;
        }
        // 先完成再取消：取消会同步触发 onCancel 回调，若顺序反过来，回调会先一步
        // 用一个取消错误完成 completer，随后的 completeError 直接抛「Future already
        // completed」。
        completer.completeError(
          DeadlineExceededError(
            limitKind: AiTaskBudget.attemptHardLimitKind,
            limit: limit,
          ),
        );
        // 只取消**这一次**尝试（子信号）：任务本身继续走故障转移。
        cancellation.cancel(reason: 'attemptHardLimit');
      });
    }
    work()
        .then(
          (void _) {
            if (!completer.isCompleted) {
              completer.complete();
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
          },
        )
        .whenComplete(() {
          timer?.cancel();
          cancellation.removeListener(onCancel);
        });
    return completer.future;
  }

  /// 取得某个模型可用的适配器；凭据或配置缺失时返回 null。
  Future<AiProvider?> _providerFor(AiModel model) async {
    final Result<String> key = await credentials.read(
      model.credentialIdentifier,
    );
    if (key.isErr) {
      diagnostics.warning(
        '任务缺少凭据 alias=${model.alias} kind=${key.errorOrNull!.kind}',
        tag: 'ai.task',
      );
      return null;
    }
    final Result<AiProvider> created = factory.create(
      alias: model.alias,
      protocolId: model.protocol.id,
      baseUrl: model.baseUrl,
      modelId: model.modelId,
      apiKey: key.valueOrNull!,
    );
    if (created.isErr) {
      diagnostics.warning(
        '任务无法创建适配器 alias=${model.alias} kind=${created.errorOrNull!.kind}',
        tag: 'ai.task',
      );
      return null;
    }
    return created.valueOrNull;
  }

  AppError _credentialMissing(AiModel model) => ModelConfigurationError(
    alias: model.alias,
    reason: 'credentialMissing',
    detail: '该别名没有可用的 API Key',
  );

  /// 是否应判定为「设备离线」。
  Future<bool> _isOffline(Object error) async {
    final NetworkConditionPort? port = networkConditions;
    if (port == null) {
      return false;
    }
    // 只在**连接层**失败（没有收到任何响应）时问端口：一个 HTTP 500 说明网络是通的，
    // 把它判成离线会让任务无意义地暂停。
    if (error is! NetworkError || error.statusCode != null) {
      return false;
    }
    try {
      return await port.isOffline();
    } on Object {
      // 端口约定永不抛异常；真抛了按「没有证据表明离线」处理（守卫方向是放行）。
      return false;
    }
  }

  /// 429 的等待时长夹取：单次等待不超过 60 秒，也不超过任务总时限。
  Duration _clampWait(Duration requested) {
    Duration wait = requested;
    if (wait > const Duration(seconds: 60)) {
      wait = const Duration(seconds: 60);
    }
    if (wait > budget.totalLimit) {
      wait = budget.totalLimit;
    }
    return wait < Duration.zero ? Duration.zero : wait;
  }

  /// 结束原因是否表示输出被截断（半句话不能当完整答案）。
  static bool _isTruncated(String? finishReason) {
    if (finishReason == null) {
      return false;
    }
    final String reason = finishReason.toLowerCase();
    return reason == 'length' ||
        reason == 'max_tokens' ||
        reason == 'incomplete' ||
        reason == 'max_output_tokens';
  }

  /// 确保快照处于 running（等待网络后恢复执行）。
  TaskSnapshot _ensureRunning(TaskSnapshot snapshot) =>
      snapshot.status == TaskStatus.running
      ? snapshot
      : _transition(snapshot, TaskStatus.running);

  TaskSnapshot _transition(TaskSnapshot snapshot, TaskStatus to) {
    final Result<TaskSnapshot> applied = TaskTransition.apply(
      current: snapshot,
      to: to,
      now: clock.now(),
    );
    if (applied.isErr) {
      // 非法迁移是编程错误（本层只按合法边迁移）；如实记录但不抛出——
      // 让任务仍然给出一个结果，比在迁移处崩掉对用户更有意义。
      diagnostics.error(
        'AI 任务状态迁移被拒绝 ${snapshot.status.name}->${to.name} '
        'kind=${applied.errorOrNull!.kind}',
        tag: 'ai.task',
      );
      return snapshot;
    }
    final TaskSnapshot next = applied.valueOrNull!;
    _dispatch(next);
    return next;
  }

  void _dispatch(TaskSnapshot snapshot) {
    // 直接调用而不是先赋给局部变量：中间变量在这里没有任何收益，反而多一个
    // 「null 检查与调用之间被改掉」的机会。
    onSnapshot?.call(snapshot);
  }

  AiTaskOutcome _finishCancelled(
    TaskSnapshot snapshot,
    List<AiAttemptRecord> attempts,
    int consumed,
    Object error,
  ) {
    final TaskSnapshot finished = _transition(snapshot, TaskStatus.cancelled);
    _log('任务已取消 task=${snapshot.taskId}', success: false);
    return AiTaskOutcome(
      snapshot: finished,
      status: TaskStatus.cancelled,
      attempts: List<AiAttemptRecord>.unmodifiable(attempts),
      consumedTokens: consumed,
      error: error is AppError ? error : CancelledError(),
    );
  }

  AiTaskOutcome _finishFailed(
    TaskSnapshot snapshot,
    List<AiAttemptRecord> attempts,
    int consumed,
    Object error, {
    String? partial,
    String? partialAlias,
    String? partialModelId,
    String? finishReason,
  }) {
    final bool hasPartial = partial != null && partial.isNotEmpty;
    // 有部分文本时是 partial（「部分结果清楚标注」），否则 failed。
    final TaskSnapshot finished = _transition(
      snapshot,
      hasPartial ? TaskStatus.partial : TaskStatus.failed,
    );
    if (!hasPartial) {
      _log(
        '任务失败 task=${snapshot.taskId} attempts=${attempts.length} '
        'kind=${error is AppError ? error.kind : error.runtimeType}',
        success: false,
      );
    }
    return AiTaskOutcome(
      snapshot: finished,
      status: hasPartial ? TaskStatus.partial : TaskStatus.failed,
      attempts: List<AiAttemptRecord>.unmodifiable(attempts),
      consumedTokens: consumed,
      error: error is AppError ? error : null,
      text: hasPartial ? partial : null,
      alias: partialAlias,
      modelId: partialModelId,
      finishReason: finishReason,
    );
  }

  void _log(String message, {required bool success}) {
    // 只记结构化事实；message 里没有任何一处插值 Key、prompt 或模型输出正文。
    if (success) {
      diagnostics.info(message, tag: 'ai.task');
    } else {
      diagnostics.warning(message, tag: 'ai.task');
    }
  }
}

/// 一次尝试的原始结果（内部类型）。
final class _AttemptResult {
  const _AttemptResult({
    required this.text,
    this.usage,
    this.error,
    this.finishReason,
  });

  final String text;
  final AiUsage? usage;
  final Object? error;
  final String? finishReason;
}
