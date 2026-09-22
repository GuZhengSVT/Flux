// T048：恢复编排的**纯规则**（架构 5.3 的恢复段）。
//
// 判定只看四个事实，因此可以逐条钉住最危险的几种组合：切换过的不许再切、恢复目录不可用时
// 必须放弃标记并保持当前数据目录不变、恢复目录就是当前目录时不搬。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';

void main() {
  final DateTime at = DateTime.utc(2026, 9, 22, 12);

  RestoreMarker marker({
    RestorePhase phase = RestorePhase.pendingRestart,
    String restoredDirectory = '/Users/x/Flux-restored-1',
    String? supersededDirectory,
  }) => RestoreMarker(
    phase: phase,
    restoredDirectory: restoredDirectory,
    restoredAt: at,
    supersededDirectory: supersededDirectory,
  );

  group('标记编解码', () {
    test('往返无损（含可空字段）', () {
      final RestoreMarker original = RestoreMarker(
        phase: RestorePhase.switched,
        restoredDirectory: '/Users/x/Flux-restored-1',
        restoredAt: at,
        supersededDirectory: '/Users/x/Flux.superseded-9',
        schemaVersion: 17,
      );
      final RestoreMarker? decoded = RestoreMarker.decode(original.encode());
      expect(decoded, isNotNull);
      expect(decoded!.phase, RestorePhase.switched);
      expect(decoded.restoredDirectory, original.restoredDirectory);
      expect(decoded.supersededDirectory, original.supersededDirectory);
      expect(decoded.restoredAt, at);
      expect(decoded.schemaVersion, 17);
    });

    test('编码确定性：同一内容编出同一串字节（可逐字比对）', () {
      expect(marker().encode(), marker().encode());
    });

    test('结构问题一律返回 null，不凑一份默认标记', () {
      // 一个凑出来的标记会让应用把数据目录切到不存在的位置（最坏是「启动后什么都看不到」）。
      expect(RestoreMarker.decode('{'), isNull);
      expect(RestoreMarker.decode('[]'), isNull);
      expect(RestoreMarker.decode('{}'), isNull);
      expect(
        RestoreMarker.decode(
          '{"phase":"unknownPhase","restoredDirectory":"/x","restoredAt":"2026-09-22T12:00:00.000Z"}',
        ),
        isNull,
        reason: '不认识的阶段说明这是一个更新版本写的标记，不能按任何已知阶段处理',
      );
      expect(
        RestoreMarker.decode(
          '{"phase":"pendingRestart","restoredDirectory":"","restoredAt":"2026-09-22T12:00:00.000Z"}',
        ),
        isNull,
        reason: '空路径不是「切换到空目录」',
      );
      expect(
        RestoreMarker.decode(
          '{"phase":"pendingRestart","restoredDirectory":"/x","restoredAt":"not-a-date"}',
        ),
        isNull,
      );
    });
  });

  group('启动判定（decideRestoreAction）', () {
    test('没有标记：什么都不做', () {
      expect(
        decideRestoreAction(
          marker: null,
          currentDataDirectory: '/Users/x/Flux',
          restoredDirectoryExists: true,
          restoredDatabaseUsable: true,
        ),
        RestoreAction.nothingToDo,
      );
    });

    test('pendingRestart + 恢复目录可用：切换', () {
      expect(
        decideRestoreAction(
          marker: marker(),
          currentDataDirectory: '/Users/x/Flux',
          restoredDirectoryExists: true,
          restoredDatabaseUsable: true,
        ),
        RestoreAction.switchToRestored,
      );
    });

    test('pendingRestart 但恢复目录不存在 / 库打不开：丢弃标记并报告', () {
      expect(
        decideRestoreAction(
          marker: marker(),
          currentDataDirectory: '/Users/x/Flux',
          restoredDirectoryExists: false,
          restoredDatabaseUsable: false,
        ),
        RestoreAction.dropMarkerAndReport,
      );
      expect(
        decideRestoreAction(
          marker: marker(),
          currentDataDirectory: '/Users/x/Flux',
          restoredDirectoryExists: true,
          restoredDatabaseUsable: false,
        ),
        RestoreAction.dropMarkerAndReport,
        reason: '目录在但库不可用同样必须放弃（切换之后才发现它坏了，旧目录已被顶替）',
      );
    });

    test('switched：**绝不**再切一次，只等清理确认', () {
      expect(
        decideRestoreAction(
          marker: marker(
            phase: RestorePhase.switched,
            supersededDirectory: '/Users/x/Flux.superseded-1',
          ),
          currentDataDirectory: '/Users/x/Flux',
          restoredDirectoryExists: true,
          restoredDatabaseUsable: true,
        ),
        RestoreAction.awaitCleanupConfirmation,
        reason: '再切一次会把当前正在用的目录搬到别处',
      );
    });

    test('cleaned 残留标记：按无事可做处理（调用方顺手清掉）', () {
      expect(
        decideRestoreAction(
          marker: marker(phase: RestorePhase.cleaned),
          currentDataDirectory: '/Users/x/Flux',
          restoredDirectoryExists: true,
          restoredDatabaseUsable: true,
        ),
        RestoreAction.nothingToDo,
      );
    });

    test('恢复目录就是当前数据目录：不搬（相等判定按规范化路径）', () {
      expect(
        decideRestoreAction(
          marker: marker(restoredDirectory: '/Users/x/Flux/'),
          currentDataDirectory: '/Users/x/Flux',
          restoredDirectoryExists: true,
          restoredDatabaseUsable: true,
        ),
        RestoreAction.nothingToDo,
        reason: '末尾分隔符不同时仍是同一个位置',
      );
    });
  });

  group('编排状态', () {
    test('idle 不暗示任何待办', () {
      expect(RestoreOrchestrationState.idle.phase, isNull);
      expect(RestoreOrchestrationState.idle.pendingRestart, isFalse);
      expect(RestoreOrchestrationState.idle.needsCleanupConfirmation, isFalse);
    });

    test('switched + 有停放目录才算「待清理确认」', () {
      const RestoreOrchestrationState switched = RestoreOrchestrationState(
        phase: RestorePhase.switched,
        restoredDirectory: '/x/Flux',
        supersededDirectory: '/x/Flux.superseded-1',
      );
      expect(switched.needsCleanupConfirmation, isTrue);
      expect(switched.pendingRestart, isFalse);
      expect(
        const RestoreOrchestrationState(phase: RestorePhase.switched)
            .needsCleanupConfirmation,
        isFalse,
        reason: '没有停放目录就没有可删的东西，不该给用户一个「删除」按钮',
      );
    });
  });
}
