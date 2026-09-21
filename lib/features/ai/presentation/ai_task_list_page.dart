// AI 任务记录页（T030：中断恢复的界面落点）。
//
// 这一页存在的理由与「设置 → AI 服务」不同：那一页管**配置**，这一页管**历史**。
// 它承载手册 T030 的一条验收——「进程重启显示 interrupted」——因为 interrupted 只有
// 在用户能看到、并且能手动重新开始的时候才有意义；只把状态写进数据库而界面上没有
// 任何入口，等于用户永远不知道上次的任务没了。
//
// 三条刻意的设计：
//   1) **不提供「自动恢复」按钮**。页面上的动作是「重新开始」，它创建**新任务**，
//      旧记录保持 interrupted。架构 4.5 明确不能自动重放不确定是否计费的请求，
//      而一个叫「恢复」的按钮会让人以为不用重新付费。
//   2) **终态才允许重新开始**。活跃态任务正占着并发额度，重开同一份内容会让同一份
//      输入被发两次；因此按钮在这些行上是禁用态并给出原因。
//   3) **来自缓存的任务明确标注**。一次没有发请求就完成的任务与一次真实调用在界面上
//      看起来一样，会让用户对「到底花没花钱」产生误判。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';
import 'package:flux/l10n/l10n.dart';

import '../application/ai_task_providers.dart';
import '../application/model_manager_controller.dart';
import '../application/persistent_ai_task_service.dart';
import '../domain/ai_model.dart';
import '../domain/ai_task_record.dart';
import 'ai_failure_text.dart';

/// 任务列表状态。
final class AiTaskListState {
  /// 构造状态。
  const AiTaskListState({
    required this.tasks,
    this.loaded = false,
    this.failureKind,
    this.interruptedAtStartup = 0,
  });

  /// 任务记录（按创建时间倒序）。
  final List<AiTaskRecord> tasks;

  /// 是否成功读到列表。
  final bool loaded;

  /// 读取失败的类别；非空时 [tasks] 不可信。
  final String? failureKind;

  /// 本次启动时被标记为中断的任务数（0 表示没有）。
  final int interruptedAtStartup;
}

/// 任务列表控制器。
final class AiTaskListController extends AsyncNotifier<AiTaskListState> {
  @override
  Future<AiTaskListState> build() async {
    final PersistentAiTaskService service = ref.read(
      persistentAiTaskServiceProvider,
    );
    final Result<List<AiTaskRecord>> loaded = await service.listTasks();
    if (loaded.isErr) {
      return AiTaskListState(
        tasks: const <AiTaskRecord>[],
        failureKind: loaded.errorOrNull!.kind,
      );
    }
    return AiTaskListState(tasks: loaded.valueOrNull!, loaded: true);
  }

  /// 重新读取列表。
  Future<void> reload() async {
    state = const AsyncValue<AiTaskListState>.loading();
    state = AsyncValue<AiTaskListState>.data(await build());
  }

  /// 重新开始一个已结束的任务（创建新任务承接，旧任务保持原状态）。
  ///
  /// 返回类型化错误供界面显示：缺模型、写库失败都是用户能据此采取动作的原因。
  Future<Result<AiTaskRecord>> restart(AiTaskRecord previous) async {
    final AiTaskListState? current = state.value;
    if (current == null) {
      return Err<AiTaskRecord>(
        StorageError(operation: 'aiTask.restart', detail: '任务列表尚未载入'),
      );
    }
    // 用**当前**的启用模型：旧快照里只有别名，而那个模型可能已被停用或删除——
    // 用旧配置硬跑会向一个用户以为已经关掉的端点发请求。
    final List<AiModel> models =
        (await ref.read(modelManagerProvider).loadEnabledModels()).getOrElse(
          const <AiModel>[],
        );
    if (models.isEmpty) {
      return Err<AiTaskRecord>(
        ModelConfigurationError(
          alias: previous.snapshot.modelId,
          reason: 'credentialMissing',
          detail: '没有可用的启用模型',
        ),
      );
    }
    final PersistentAiTaskService service = ref.read(
      persistentAiTaskServiceProvider,
    );
    final Result<AiTaskRunResult> result = await service.restart(
      previous,
      newTaskId:
          'task-${previous.taskId}-${DateTime.now().microsecondsSinceEpoch}',
      models: models,
    );
    if (result.isErr) {
      return Err<AiTaskRecord>(result.errorOrNull!);
    }
    await reload();
    return Ok<AiTaskRecord>(result.valueOrNull!.record);
  }
}

/// 任务列表控制器 Provider。
final AsyncNotifierProvider<AiTaskListController, AiTaskListState>
aiTaskListControllerProvider =
    AsyncNotifierProvider<AiTaskListController, AiTaskListState>(
      AiTaskListController.new,
    );

// 任务预算 / 时钟 / 持久任务服务 / 队列的 Provider 已经在 T033 挪到
// application/ai_task_providers.dart（视觉与选词解释也要装配队列，不该 import 一个页面）。

/// AI 任务记录页。
class AiTaskListPage extends ConsumerWidget {
  /// 构造页面。
  const AiTaskListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<AiTaskListState> state = ref.watch(
      aiTaskListControllerProvider,
    );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.aiTaskListTitle)),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) => Center(
          child: Text(l10n.aiTaskListLoadFailed(error.runtimeType.toString())),
        ),
        data: (AiTaskListState value) => value.loaded
            ? _TaskList(state: value)
            : Center(
                child: Text(
                  l10n.aiTaskListLoadFailed(value.failureKind ?? 'unknown'),
                ),
              ),
      ),
    );
  }
}

class _TaskList extends ConsumerWidget {
  const _TaskList({required this.state});

  final AiTaskListState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    if (state.tasks.isEmpty) {
      return Center(child: Text(l10n.aiTaskListEmpty));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: state.tasks.length,
      separatorBuilder: (BuildContext context, int index) =>
          const Divider(height: 1),
      itemBuilder: (BuildContext context, int index) {
        final AiTaskRecord task = state.tasks[index];
        return ListTile(
          leading: Icon(_iconFor(task)),
          title: Text(
            '${l10n.aiTaskKindLabel(task.kind)} · '
            '${task.status == TaskStatus.succeeded && task.fromCache ? l10n.aiTaskFromCache : aiTaskStatusLabel(l10n, task.status)}',
            style: theme.textTheme.bodyLarge,
          ),
          subtitle: Text(
            l10n.aiTaskMeta(task.consumedTokens, task.attemptCount),
            style: theme.textTheme.bodySmall,
          ),
          // 只有终态可以重新开始：活跃任务正占着额度，重开会把同一份输入发两次。
          trailing: task.status.isTerminal
              ? TextButton(
                  onPressed: () => _restart(context, ref, task),
                  child: Text(l10n.aiTaskRestart),
                )
              : Tooltip(
                  message: l10n.aiTaskRestartBlocked,
                  child: const TextButton(onPressed: null, child: Text('—')),
                ),
        );
      },
    );
  }

  static IconData _iconFor(AiTaskRecord task) {
    if (task.status == TaskStatus.succeeded) {
      return task.fromCache ? Icons.bolt_outlined : Icons.check_circle_outline;
    }
    return switch (task.status) {
      TaskStatus.partial => Icons.indeterminate_check_box_outlined,
      TaskStatus.failed => Icons.error_outline,
      TaskStatus.cancelled => Icons.cancel_outlined,
      TaskStatus.interrupted => Icons.pause_circle_outline,
      _ => Icons.hourglass_empty_outlined,
    };
  }

  Future<void> _restart(
    BuildContext context,
    WidgetRef ref,
    AiTaskRecord task,
  ) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final Result<AiTaskRecord> result = await ref
        .read(aiTaskListControllerProvider.notifier)
        .restart(task);
    if (result.isErr) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            describeAiFailure(
              l10n,
              AiFailureReason.classify(result.errorOrNull!),
            ),
          ),
        ),
      );
      return;
    }
    // 旧任务的标识写在回执里：用户需要确认「原来那条还在、没有被我这次操作改掉」。
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${l10n.aiTaskRestartSuccess}（${task.taskId} → '
          '${result.valueOrNull!.taskId}）',
        ),
      ),
    );
  }
}

/// 把九态翻译成界面文案。
String aiTaskStatusLabel(AppLocalizations l10n, TaskStatus status) =>
    switch (status) {
      TaskStatus.queued => l10n.aiTaskStatusQueued,
      TaskStatus.running => l10n.aiTaskStatusRunning,
      TaskStatus.waitingConfiguration => l10n.aiTaskStatusWaitingConfiguration,
      TaskStatus.waitingNetwork => l10n.aiTaskStatusWaitingNetwork,
      TaskStatus.succeeded => l10n.aiTaskStatusSucceeded,
      TaskStatus.partial => l10n.aiTaskStatusPartial,
      TaskStatus.failed => l10n.aiTaskStatusFailed,
      TaskStatus.cancelled => l10n.aiTaskStatusCancelled,
      TaskStatus.interrupted => l10n.aiTaskStatusInterrupted,
    };

/// 任务类型的界面文案（与任务类型枚举一一对应）。
extension AiTaskKindLabel on AppLocalizations {
  /// 任务类型的展示名。
  String aiTaskKindLabel(AiTaskKind kind) => switch (kind) {
    AiTaskKind.summary => aiTaskKindSummary,
    AiTaskKind.explain => aiTaskKindExplain,
    AiTaskKind.translate => aiTaskKindTranslate,
    AiTaskKind.news => aiTaskKindNews,
    AiTaskKind.other => aiTaskKindOther,
  };
}
