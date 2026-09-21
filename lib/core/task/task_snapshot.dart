// AI 任务快照与不可变 deadline（T007）。
//
// 对应的实体概念见架构第 5.1 节 AITask / Attempt：「输入/模板版本、阶段、deadline、
// 消耗、错误、输出校验、成功结果及草稿；中断后不默认重付费恢复」。本文件只落地
// 状态与 deadline 这两个在 T007 就需要冻结的规则，消耗/结果等字段在 T009 建表时补。
library;

import 'task_status.dart';

/// 任务在某一时刻的不可变快照。
///
/// 状态机不修改原对象，而是返回新的快照，因此调用方拿到的旧引用不会被悄悄改写
/// （避免 UI 持有快照时出现“看不到的并发变化”）。
class TaskSnapshot {
  const TaskSnapshot({
    required this.taskId,
    required this.status,
    this.deadline,
    this.startedAt,
    this.finishedAt,
    this.revision = 0,
    this.attemptCount = 0,
  });

  /// 新建一个尚未开始的 [TaskStatus.queued] 任务。
  ///
  /// [deadline] 在创建时就固定下来；按 SET-059，它包含任务的全部阶段。
  factory TaskSnapshot.pending({required String taskId, DateTime? deadline}) =>
      TaskSnapshot(
        taskId: taskId,
        status: TaskStatus.queued,
        deadline: deadline,
      );

  /// 任务标识（本机唯一）。
  final String taskId;

  /// 当前状态。
  final TaskStatus status;

  /// 任务总时限的绝对时刻；null 表示尚无时限或创建时未指定。
  ///
  /// 一旦设定，之后只能保持不变或提前（见 TaskTransition 的 deadline 规则）。
  final DateTime? deadline;

  /// 进入 [TaskStatus.running] 的时刻。
  final DateTime? startedAt;

  /// 进入终态的时刻。
  final DateTime? finishedAt;

  /// 乐观并发版本号；每次成功迁移 +1。
  final int revision;

  /// 已进行的模型调用尝试次数（配合 SET-062 的尝试总数上限）。
  final int attemptCount;

  /// 状态是否为终态（不会再有合法迁移）。
  bool get isTerminal => status.isTerminal;

  /// 是否已完成（succeeded 或 partial），此时应有可用产出。
  bool get isCompleted => status.isCompleted;

  /// 是否仍可被取消。
  bool get isCancellable => status.isActive;

  /// 在 [now] 时刻是否已超过 deadline；无 deadline 时恒为 false。
  bool isDeadlineExceededAt(DateTime now) {
    final DateTime? limit = deadline;
    return limit != null && !now.isBefore(limit);
  }

  /// 相对 [now] 的剩余时间；无 deadline 时为 null，已超时则为 [Duration.zero]。
  Duration? remainingAt(DateTime now) {
    final DateTime? limit = deadline;
    if (limit == null) {
      return null;
    }
    final Duration left = limit.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  /// 复制并替换部分字段；不参与状态机规则校验，仅供状态机内部与测试构造使用。
  TaskSnapshot copyWith({
    TaskStatus? status,
    DateTime? deadline,
    DateTime? startedAt,
    DateTime? finishedAt,
    int? revision,
    int? attemptCount,
  }) => TaskSnapshot(
    taskId: taskId,
    status: status ?? this.status,
    deadline: deadline ?? this.deadline,
    startedAt: startedAt ?? this.startedAt,
    finishedAt: finishedAt ?? this.finishedAt,
    revision: revision ?? this.revision,
    attemptCount: attemptCount ?? this.attemptCount,
  );

  @override
  String toString() =>
      'TaskSnapshot($taskId, ${status.name}, rev=$revision, '
      'deadline=${deadline?.toIso8601String() ?? '-'}, attempts=$attemptCount)';
}
