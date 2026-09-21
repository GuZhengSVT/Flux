// AI 任务状态机（T007，手册 6.4 与 SET-056/059/062）。
//
// 只做一件事：判断并执行状态迁移，**不**发网络请求、不写数据库、不读时钟。
// 这样规则能被完整枚举测试，且 UI/调度层无法绕过规则直接改状态。
library;

import '../error/app_error.dart';
import '../result.dart';
import 'task_snapshot.dart';
import 'task_status.dart';

/// 任务状态迁移规则。
///
/// 合法迁移表是本文件的唯一权威来源；[isLegal] 与 [apply] 都由它推导，避免
/// “表里能过、代码里拦住”之类的不一致。
abstract final class TaskTransition {
  /// 合法迁移表。
  ///
  /// 解读：
  /// - `queued -> running`：调度器取到任务，开始执行。
  /// - `running <-> waitingNetwork`：断网等待与恢复执行（等待期间不重发付费请求）。
  /// - `running -> waitingConfiguration`：执行中发现缺少必要配置或未完成费用告知；
  ///   `waitingConfiguration -> running`：用户补齐配置后继续（D-08、SET-056）。
  /// - `running -> succeeded | partial | failed`：执行结束的三种结果。
  /// - `* -> cancelled`：任意活跃态都可由用户/上层取消。
  ///
  /// 注意：终态（succeeded/partial/failed/cancelled/interrupted）不出现在任何
  /// 键或值里，因此终态不可迁移这一规则由表结构本身保证。
  static const Map<TaskStatus, Set<TaskStatus>>
  allowedTransitions = <TaskStatus, Set<TaskStatus>>{
    TaskStatus.queued: <TaskStatus>{TaskStatus.running, TaskStatus.cancelled},
    TaskStatus.running: <TaskStatus>{
      TaskStatus.waitingNetwork,
      TaskStatus.waitingConfiguration,
      TaskStatus.succeeded,
      TaskStatus.partial,
      TaskStatus.failed,
      TaskStatus.cancelled,
    },
    TaskStatus.waitingNetwork: <TaskStatus>{
      TaskStatus.running,
      TaskStatus.cancelled,
    },
    TaskStatus.waitingConfiguration: <TaskStatus>{
      TaskStatus.running,
      TaskStatus.cancelled,
    },
    // 终态：显式列空集，让“不可迁移”在枚举与文档里都可见。
    TaskStatus.succeeded: <TaskStatus>{},
    TaskStatus.partial: <TaskStatus>{},
    TaskStatus.failed: <TaskStatus>{},
    TaskStatus.cancelled: <TaskStatus>{},
    TaskStatus.interrupted: <TaskStatus>{},
  };

  /// 允许迁移到 [to] 的所有源状态（含终态的空的集合）。
  static Set<TaskStatus> sourcesFor(TaskStatus to) => TaskStatus.values
      .where((TaskStatus from) => isLegal(from: from, to: to))
      .toSet();

  /// 迁移 [from] -> [to] 是否在合法表内；不含 deadline/revision 等附加校验。
  static bool isLegal({required TaskStatus from, required TaskStatus to}) =>
      allowedTransitions[from]?.contains(to) ?? false;

  /// 执行一次迁移并返回新快照。
  ///
  /// 校验顺序（靠前者优先报错，测试依赖这一顺序）：
  /// 1. 乐观并发：[expectedRevision] 与当前快照不一致 -> [StateTransitionFailure.concurrentModification]；
  /// 2. 终态不可迁移 -> [StateTransitionFailure.terminalStateImmutable]；
  /// 3. deadline 不可推后 -> [StateTransitionFailure.deadlineImmutable]；
  /// 4. 非法边 -> [StateTransitionFailure.illegalTransition]。
  ///
  /// [now] 用于记录 startedAt/finishedAt，由调用方注入（配合 Clock 抽象，
  /// 让超时与预算测试可确定性重放）。
  ///
  /// [newDeadline] 只在需要设定初始时限或**提早**时限时传入；传更晚的时刻会被
  /// 拒绝，而不是静默夹取——静默修正会让“deadline 不重置”的保证变得不可观察。
  static Result<TaskSnapshot> apply({
    required TaskSnapshot current,
    required TaskStatus to,
    DateTime? newDeadline,
    DateTime? now,
    int? expectedRevision,
  }) {
    final TaskStatus from = current.status;

    if (expectedRevision != null && expectedRevision != current.revision) {
      return Err<TaskSnapshot>(
        StateTransitionError(
          failure: StateTransitionFailure.concurrentModification,
          from: from,
          to: to,
          taskId: current.taskId,
          detail: '期望 revision=$expectedRevision，实际 ${current.revision}',
        ),
      );
    }

    if (from.isTerminal) {
      return Err<TaskSnapshot>(
        StateTransitionError(
          failure: StateTransitionFailure.terminalStateImmutable,
          from: from,
          to: to,
          taskId: current.taskId,
          detail: '终态任务不可迁移；恢复由新任务承接',
        ),
      );
    }

    final DateTime? currentDeadline = current.deadline;
    if (newDeadline != null &&
        currentDeadline != null &&
        newDeadline.isAfter(currentDeadline)) {
      return Err<TaskSnapshot>(
        StateTransitionError(
          failure: StateTransitionFailure.deadlineImmutable,
          from: from,
          to: to,
          taskId: current.taskId,
          detail:
              'deadline 只能保持不变或提前：'
              '${currentDeadline.toIso8601String()} -> '
              '${newDeadline.toIso8601String()}',
        ),
      );
    }

    if (!isLegal(from: from, to: to)) {
      return Err<TaskSnapshot>(
        StateTransitionError(
          failure: StateTransitionFailure.illegalTransition,
          from: from,
          to: to,
          taskId: current.taskId,
          detail:
              '合法目标：${(allowedTransitions[from] ?? const {}).map((TaskStatus s) => s.name).join(', ')}',
        ),
      );
    }

    final bool enteringRunning = to == TaskStatus.running;
    final bool enteringTerminal = to.isTerminal;
    return Ok<TaskSnapshot>(
      current.copyWith(
        status: to,
        deadline: newDeadline ?? currentDeadline,
        startedAt: enteringRunning
            ? (now ?? current.startedAt)
            : current.startedAt,
        finishedAt: enteringTerminal ? now : current.finishedAt,
        revision: current.revision + 1,
      ),
    );
  }
}
