// 任务状态机测试（T007 验收核心）。
//
// 覆盖手册对 T007 的明确要求：
//   1) 全对组合枚举：合法迁移通过、非法迁移返回类型化错误；
//   2) deadline 不重置：任何迁移都不允许把 deadline 推后；
//   3) terminal 态不可再迁移；
//   4) cancelled 从每个活跃态可达。

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';

// DateTime 没有 const 构造，因此这里用 final 常量而不是 const。
final DateTime _t0 = DateTime.utc(2026, 9, 21, 12);

TaskSnapshot _snapshot(
  TaskStatus status, {
  String taskId = 'task-1',
  DateTime? deadline,
  int revision = 0,
}) => TaskSnapshot(
  taskId: taskId,
  status: status,
  deadline: deadline,
  revision: revision,
);

/// 与 TaskTransition 表独立维护的“期望规则”，用于交叉验证实现未偏离设计。
const Map<TaskStatus, Set<TaskStatus>> _expectedLegal =
    <TaskStatus, Set<TaskStatus>>{
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
      TaskStatus.succeeded: <TaskStatus>{},
      TaskStatus.partial: <TaskStatus>{},
      TaskStatus.failed: <TaskStatus>{},
      TaskStatus.cancelled: <TaskStatus>{},
      TaskStatus.interrupted: <TaskStatus>{},
    };

void main() {
  group('合法迁移表', () {
    test('规则表与设计文档一致（防止实现悄悄放宽）', () {
      expect(TaskTransition.allowedTransitions, _expectedLegal);
    });

    test('规则表覆盖全部 TaskStatus，没有遗漏键', () {
      for (final TaskStatus status in TaskStatus.values) {
        expect(
          TaskTransition.allowedTransitions.containsKey(status),
          isTrue,
          reason: '${status.name} 缺少迁移规则条目',
        );
      }
      expect(
        TaskTransition.allowedTransitions.length,
        TaskStatus.values.length,
      );
    });

    test('枚举全对组合：合法/非法与 isLegal 完全一致', () {
      for (final TaskStatus from in TaskStatus.values) {
        for (final TaskStatus to in TaskStatus.values) {
          final bool expected = _expectedLegal[from]!.contains(to);
          expect(
            TaskTransition.isLegal(from: from, to: to),
            expected,
            reason: '$from -> $to 期望 legal=$expected',
          );
        }
      }
    });

    test('枚举全对组合：合法迁移返回 Ok 且推进 revision', () {
      for (final TaskStatus from in TaskStatus.values) {
        for (final TaskStatus to in _expectedLegal[from]!) {
          final Result<TaskSnapshot> result = TaskTransition.apply(
            current: _snapshot(from, revision: 3),
            to: to,
            now: _t0,
          );
          expect(result.isOk, isTrue, reason: '$from -> $to 应被接受');
          final TaskSnapshot next = result.unwrap();
          expect(next.status, to);
          expect(next.revision, 4, reason: 'revision 应单调 +1');
        }
      }
    });

    test('枚举全对组合：非法迁移返回类型化错误且不改动原快照', () {
      for (final TaskStatus from in TaskStatus.values) {
        for (final TaskStatus to in TaskStatus.values) {
          if (_expectedLegal[from]!.contains(to)) {
            continue;
          }
          final TaskSnapshot before = _snapshot(from, revision: 7);
          final Result<TaskSnapshot> result = TaskTransition.apply(
            current: before,
            to: to,
            now: _t0,
          );
          expect(result.isErr, isTrue, reason: '$from -> $to 应被拒绝');
          final AppError error = result.errorOrNull!;
          expect(error, isA<StateTransitionError>());
          // 终态拒绝与非法边是不同的失败原因，分别断言。
          final StateTransitionError typed = error as StateTransitionError;
          expect(
            typed.failure,
            from.isTerminal
                ? StateTransitionFailure.terminalStateImmutable
                : StateTransitionFailure.illegalTransition,
            reason: '$from -> $to 失败原因不符',
          );
          expect(before.status, from, reason: '原快照不得被修改');
          expect(before.revision, 7);
        }
      }
    });

    test('apply 是纯函数：成功路径不修改传入的快照', () {
      final TaskSnapshot before = _snapshot(TaskStatus.queued);
      final TaskSnapshot after = TaskTransition.apply(
        current: before,
        to: TaskStatus.running,
        now: _t0,
      ).unwrap();
      expect(before.status, TaskStatus.queued);
      expect(before.startedAt, isNull);
      expect(after, isNot(same(before)));
      expect(after.startedAt, _t0);
    });
  });

  group('deadline 不重置', () {
    final DateTime deadline = _t0.add(const Duration(minutes: 10));

    test('把 deadline 推后一律被拒绝（全部活跃源态）', () {
      for (final TaskStatus from in TaskStatus.values.where(
        (TaskStatus s) => !s.isTerminal,
      )) {
        final Result<TaskSnapshot> result = TaskTransition.apply(
          current: _snapshot(from, deadline: deadline),
          to: TaskStatus.cancelled,
          newDeadline: deadline.add(const Duration(seconds: 1)),
          now: _t0,
        );
        expect(result.isErr, isTrue, reason: '$from 推后 deadline 必须失败');
        final AppError error = result.errorOrNull!;
        expect(error, isA<StateTransitionError>());
        expect(
          (error as StateTransitionError).failure,
          StateTransitionFailure.deadlineImmutable,
        );
      }
    });

    test('deadline 相等是允许的（不视为重置）', () {
      final Result<TaskSnapshot> result = TaskTransition.apply(
        current: _snapshot(TaskStatus.queued, deadline: deadline),
        to: TaskStatus.running,
        newDeadline: deadline,
        now: _t0,
      );
      expect(result.isOk, isTrue);
      expect(result.unwrap().deadline, deadline);
    });

    test('deadline 提前是允许的（收紧时限）', () {
      final DateTime earlier = deadline.subtract(const Duration(minutes: 2));
      final Result<TaskSnapshot> result = TaskTransition.apply(
        current: _snapshot(TaskStatus.running, deadline: deadline),
        to: TaskStatus.running,
        newDeadline: earlier,
        now: _t0,
      );
      // running -> running 不在表内，因此这里预期非法边；deadline 规则本身用
      // 下面这条 queued -> running 的迁移单独验证。
      expect(result.isErr, isTrue);

      final Result<TaskSnapshot> tightening = TaskTransition.apply(
        current: _snapshot(TaskStatus.queued, deadline: deadline),
        to: TaskStatus.running,
        newDeadline: earlier,
        now: _t0,
      );
      expect(tightening.isOk, isTrue);
      expect(tightening.unwrap().deadline, earlier);
    });

    test('创建时设定初始 deadline，此后不传 newDeadline 即保持原值', () {
      TaskSnapshot snapshot = TaskSnapshot.pending(
        taskId: 'task-d',
        deadline: deadline,
      );
      snapshot = TaskTransition.apply(
        current: snapshot,
        to: TaskStatus.running,
        now: _t0,
      ).unwrap();
      snapshot = TaskTransition.apply(
        current: snapshot,
        to: TaskStatus.waitingNetwork,
        now: _t0,
      ).unwrap();
      snapshot = TaskTransition.apply(
        current: snapshot,
        to: TaskStatus.running,
        now: _t0,
      ).unwrap();
      expect(snapshot.deadline, deadline, reason: '反复等待/恢复也不得顺延');
      expect(snapshot.revision, 3);
    });

    test('无 deadline 时允许首次设定', () {
      final Result<TaskSnapshot> result = TaskTransition.apply(
        current: _snapshot(TaskStatus.queued),
        to: TaskStatus.running,
        newDeadline: deadline,
        now: _t0,
      );
      expect(result.isOk, isTrue);
      expect(result.unwrap().deadline, deadline);
    });
  });

  group('终态不可迁移', () {
    final List<TaskStatus> terminals = <TaskStatus>[
      TaskStatus.succeeded,
      TaskStatus.partial,
      TaskStatus.failed,
      TaskStatus.cancelled,
      TaskStatus.interrupted,
    ];

    test('五个终态都标记为 isTerminal', () {
      for (final TaskStatus status in terminals) {
        expect(status.isTerminal, isTrue, reason: '${status.name} 应为终态');
        expect(status.isActive, isFalse);
      }
      expect(terminals.length, TaskStatus.values.length - 4);
    });

    test('终态到任意状态都被拒绝，包括自身', () {
      for (final TaskStatus from in terminals) {
        for (final TaskStatus to in TaskStatus.values) {
          final Result<TaskSnapshot> result = TaskTransition.apply(
            current: _snapshot(from),
            to: to,
            now: _t0,
          );
          expect(result.isErr, isTrue, reason: '$from -> $to 必须失败');
          expect(
            (result.errorOrNull! as StateTransitionError).failure,
            StateTransitionFailure.terminalStateImmutable,
          );
        }
      }
    });

    test('interrupted 是恢复入口，但旧任务保持 interrupted 不自行迁移', () {
      // 恢复由新任务承接：新任务从 queued 重新开始，deadline 重新计算。
      final Result<TaskSnapshot> revive = TaskTransition.apply(
        current: _snapshot(TaskStatus.interrupted),
        to: TaskStatus.running,
        now: _t0,
      );
      expect(revive.isErr, isTrue);

      final TaskSnapshot fresh = TaskSnapshot.pending(taskId: 'task-1-retry');
      final TaskSnapshot started = TaskTransition.apply(
        current: fresh,
        to: TaskStatus.running,
        now: _t0,
      ).unwrap();
      expect(started.taskId, 'task-1-retry');
      expect(started.status, TaskStatus.running);
    });
  });

  group('cancelled 从每个活跃态可达', () {
    test('四个活跃态均可取消，且终态为 cancelled', () {
      final List<TaskStatus> actives = TaskStatus.values
          .where((TaskStatus s) => s.isActive)
          .toList(growable: false);
      expect(actives.length, 4, reason: '活跃态应为 queued/running/两个 waiting');

      for (final TaskStatus from in actives) {
        final Result<TaskSnapshot> result = TaskTransition.apply(
          current: _snapshot(from),
          to: TaskStatus.cancelled,
          now: _t0,
        );
        expect(result.isOk, isTrue, reason: '$from 应可取消');
        final TaskSnapshot next = result.unwrap();
        expect(next.status, TaskStatus.cancelled);
        expect(next.finishedAt, _t0, reason: '取消应记录结束时刻');
        expect(next.isCancellable, isFalse);
      }
    });

    test('sourcesFor(cancelled) 正好是四个活跃态', () {
      expect(TaskTransition.sourcesFor(TaskStatus.cancelled), <TaskStatus>{
        TaskStatus.queued,
        TaskStatus.running,
        TaskStatus.waitingConfiguration,
        TaskStatus.waitingNetwork,
      });
    });
  });

  group('等待态语义', () {
    test('waitingConfiguration 与 waitingNetwork 都要求“正在等待”', () {
      expect(TaskStatus.waitingConfiguration.isWaiting, isTrue);
      expect(TaskStatus.waitingNetwork.isWaiting, isTrue);
      expect(TaskStatus.running.isWaiting, isFalse);
      expect(TaskStatus.queued.isWaiting, isFalse);
    });

    test('running -> waitingConfiguration -> running 是完整往返', () {
      TaskSnapshot snapshot = TaskTransition.apply(
        current: _snapshot(TaskStatus.queued),
        to: TaskStatus.running,
        now: _t0,
      ).unwrap();
      snapshot = TaskTransition.apply(
        current: snapshot,
        to: TaskStatus.waitingConfiguration,
        now: _t0,
      ).unwrap();
      expect(snapshot.status, TaskStatus.waitingConfiguration);
      snapshot = TaskTransition.apply(
        current: snapshot,
        to: TaskStatus.running,
        now: _t0,
      ).unwrap();
      expect(snapshot.status, TaskStatus.running);
      expect(snapshot.isTerminal, isFalse);
    });

    test('running -> waitingNetwork -> running -> succeeded 是完整往返', () {
      TaskSnapshot snapshot = TaskTransition.apply(
        current: _snapshot(TaskStatus.queued),
        to: TaskStatus.running,
        now: _t0,
      ).unwrap();
      snapshot = TaskTransition.apply(
        current: snapshot,
        to: TaskStatus.waitingNetwork,
        now: _t0,
      ).unwrap();
      snapshot = TaskTransition.apply(
        current: snapshot,
        to: TaskStatus.running,
        now: _t0,
      ).unwrap();
      snapshot = TaskTransition.apply(
        current: snapshot,
        to: TaskStatus.succeeded,
        now: _t0,
      ).unwrap();
      expect(snapshot.status, TaskStatus.succeeded);
      expect(snapshot.isCompleted, isTrue);
    });

    test('waitingNetwork 不能直接到 succeeded（必须先回到 running）', () {
      final Result<TaskSnapshot> result = TaskTransition.apply(
        current: _snapshot(TaskStatus.waitingNetwork),
        to: TaskStatus.succeeded,
        now: _t0,
      );
      expect(result.isErr, isTrue);
      expect(
        (result.errorOrNull! as StateTransitionError).failure,
        StateTransitionFailure.illegalTransition,
      );
    });
  });

  group('并发控制', () {
    test('revision 不匹配返回 concurrentModification', () {
      final Result<TaskSnapshot> result = TaskTransition.apply(
        current: _snapshot(TaskStatus.queued, revision: 5),
        to: TaskStatus.running,
        now: _t0,
        expectedRevision: 4,
      );
      expect(result.isErr, isTrue);
      final StateTransitionError error =
          result.errorOrNull! as StateTransitionError;
      expect(error.failure, StateTransitionFailure.concurrentModification);
      expect(error.message, contains('revision'));
    });

    test('revision 匹配时正常迁移', () {
      final Result<TaskSnapshot> result = TaskTransition.apply(
        current: _snapshot(TaskStatus.queued, revision: 5),
        to: TaskStatus.running,
        now: _t0,
        expectedRevision: 5,
      );
      expect(result.isOk, isTrue);
      expect(result.unwrap().revision, 6);
    });

    test('并发冲突优先于规则错误报出，便于上层刷新后重试', () {
      // queued -> succeeded 本身非法，但 revision 过期时先报并发冲突。
      final Result<TaskSnapshot> result = TaskTransition.apply(
        current: _snapshot(TaskStatus.queued, revision: 9),
        to: TaskStatus.succeeded,
        now: _t0,
        expectedRevision: 1,
      );
      expect(
        (result.errorOrNull! as StateTransitionError).failure,
        StateTransitionFailure.concurrentModification,
      );
    });

    test('错误消息携带 taskId，便于把日志对到具体任务', () {
      final Result<TaskSnapshot> result = TaskTransition.apply(
        current: _snapshot(TaskStatus.queued, taskId: 'task-xyz'),
        to: TaskStatus.succeeded,
        now: _t0,
      );
      expect(result.errorOrNull!.message, contains('task-xyz'));
    });
  });

  group('快照时间语义', () {
    test('deadline 判断是“达到即超时”，不是“必须超过”', () {
      final TaskSnapshot snapshot = _snapshot(
        TaskStatus.running,
        deadline: _t0,
      );
      expect(snapshot.isDeadlineExceededAt(_t0), isTrue);
      expect(
        snapshot.isDeadlineExceededAt(_t0.subtract(const Duration(seconds: 1))),
        isFalse,
      );
      expect(snapshot.remainingAt(_t0), Duration.zero);
      expect(
        snapshot.remainingAt(_t0.subtract(const Duration(seconds: 30))),
        const Duration(seconds: 30),
      );
    });

    test('无 deadline 时既不算超时也没有剩余时间', () {
      final TaskSnapshot snapshot = _snapshot(TaskStatus.running);
      expect(snapshot.isDeadlineExceededAt(_t0), isFalse);
      expect(snapshot.remainingAt(_t0), isNull);
    });
  });
}
