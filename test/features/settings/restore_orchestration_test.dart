// T048：恢复编排的用例层验收（架构 5.3 的恢复段）。
//
// 用**真实临时目录与真实数据库**，不用替身：这条路径的价值在于「目录真的被搬对了吗、失败之后
// 当前数据目录真的还在吗」，用替身断言「调用了改名方法」等于什么都没验。
//
// 状态机
//   pendingRestart ──（启动）──► switched ──（确认）──► cleaned（标记被清）
// 与三种失败分支（恢复目录不在 / 库打不开 / 切换失败回退）逐条覆盖。
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:flux/core/core.dart';
import 'package:flux/features/settings/application/restore_orchestrator.dart';
import 'package:flux/features/settings/application/maintenance_ports.dart';
import 'package:flux/infrastructure/local/database.dart';
import 'package:flux/infrastructure/local/restore_orchestration_store.dart';

/// 固定时钟（标记里的时刻可确定地断言）。
final class _FixedClock implements Clock {
  _FixedClock(this._now);

  final DateTime _now;

  @override
  DateTime now() => _now;

  @override
  Duration monotonic() => Duration.zero;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory root; // 父目录：数据目录与恢复目录都建在它下面
  late String dataDir; // 当前数据目录
  late String restoredDir; // 恢复出来的目录
  final DateTime now = DateTime.utc(2026, 9, 22, 12);

  setUp(() async {
    root = Directory.systemTemp.createTempSync('flux_t048_');
    dataDir = p.join(root.path, 'Flux');
    restoredDir = p.join(root.path, 'Flux-restored-1');
    await Directory(dataDir).create(recursive: true);
  });

  tearDown(() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  /// 在一个目录下建一个**真实可用**的库，并写入一条订阅。
  Future<void> seedDatabase(
    String directory, {
    required String feedName,
  }) async {
    final Directory dir = Directory(directory);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    final AppDatabase db = AppDatabase.openFile(
      File(p.join(directory, fluxDatabaseFileName)),
    );
    await db.customSelect('SELECT 1').get();
    await db
        .into(db.feeds)
        .insert(
          FeedsCompanion.insert(
            syncId: 'feed-$feedName',
            normalizedUrl: 'https://a.example/$feedName.xml',
            name: feedName,
          ),
        );
    await db.close();
  }

  /// 读某个目录的库里的订阅名（用于断言「换到了哪一份数据」）。
  Future<List<String>> feedNames(String directory) async {
    final AppDatabase db = AppDatabase.openFile(
      File(p.join(directory, fluxDatabaseFileName)),
    );
    await db.customSelect('SELECT 1').get();
    final List<String> names = (await db.select(db.feeds).get())
        .map((Feed f) => f.name)
        .toList();
    await db.close();
    return names;
  }

  RestoreOrchestrator orchestrator() => RestoreOrchestrator(
    port: FileRestoreOrchestrationStore(dataDirectoryPath: dataDir),
    clock: _FixedClock(now),
  );

  /// 标记文件的路径（数据目录的父目录下）。
  String markerPath() => p.join(root.path, RestoreMarker.fileName);

  group('状态机：pendingRestart → switched → cleaned', () {
    test('启动时切换：数据目录指向恢复内容，旧目录被停放到并列位置', () async {
      await seedDatabase(dataDir, feedName: '旧数据');
      await seedDatabase(restoredDir, feedName: '恢复数据');
      final RestoreOrchestrator service = orchestrator();
      // T046 的恢复成功路径写下标记。
      final Result<void> marked = await service.markPendingRestart(
        restoredDirectory: restoredDir,
        schemaVersion: 17,
      );
      expect(marked.isOk, isTrue);
      expect(File(markerPath()).existsSync(), isTrue);
      expect(File(markerPath()).readAsStringSync(), contains('pendingRestart'));

      // 重启：启动编排。
      final Result<RestoreAction> action = await service.runOnStartup();
      expect(action.unwrap(), RestoreAction.switchToRestored);

      // 当前数据目录现在装的是恢复出来的那一份数据。
      expect(await feedNames(dataDir), <String>['恢复数据']);
      // 恢复目录本身已经不在（它被改名成了数据目录）。
      expect(Directory(restoredDir).existsSync(), isFalse);
      // 标记进入 switched，并记下停放目录。
      final RestoreOrchestrationState state = (await service.readState())
          .unwrap();
      expect(state.phase, RestorePhase.switched);
      expect(state.supersededDirectory, isNotNull);
      expect(state.needsCleanupConfirmation, isTrue);
      // 旧数据确实还在停放位置（没有被删掉）。
      final String parked = state.supersededDirectory!;
      expect(Directory(parked).existsSync(), isTrue);
      expect(await feedNames(parked), <String>['旧数据']);

      // 用户确认后清理：旧目录被删，标记被清（阶段 cleaned 之后不留标记）。
      final Result<String?> cleaned = await service.completeCleanup();
      expect(cleaned.unwrap(), parked);
      expect(Directory(parked).existsSync(), isFalse);
      expect(File(markerPath()).existsSync(), isFalse);
      // 当前数据仍然是恢复出来的那一份。
      expect(await feedNames(dataDir), <String>['恢复数据']);
      expect((await service.readState()).unwrap().phase, isNull);
    });

    test('已切换的阶段再启动**不会**再切一次（不搬动正在使用的目录）', () async {
      await seedDatabase(dataDir, feedName: '旧数据');
      await seedDatabase(restoredDir, feedName: '恢复数据');
      final RestoreOrchestrator service = orchestrator();
      await service.markPendingRestart(restoredDirectory: restoredDir);
      await service.runOnStartup();
      final RestoreOrchestrationState afterFirst = (await service.readState())
          .unwrap();

      // 再启动一次（用户重启了但还没确认清理）。
      final Result<RestoreAction> second = await service.runOnStartup();
      expect(second.unwrap(), RestoreAction.awaitCleanupConfirmation);

      // 状态与数据都原样。
      final RestoreOrchestrationState afterSecond = (await service.readState())
          .unwrap();
      expect(afterSecond.phase, afterFirst.phase);
      expect(afterSecond.supersededDirectory, afterFirst.supersededDirectory);
      expect(await feedNames(dataDir), <String>['恢复数据']);
      expect(
        Directory(afterFirst.supersededDirectory!).existsSync(),
        isTrue,
        reason: '旧目录仍在（未确认清理之前不能删）',
      );
    });
  });

  group('失败分支：当前数据目录必须保持可用', () {
    test('恢复目录不存在：丢弃标记并报告，当前数据一行不动', () async {
      await seedDatabase(dataDir, feedName: '当前数据');
      final RestoreOrchestrator service = orchestrator();
      await service.markPendingRestart(
        restoredDirectory: p.join(root.path, 'Flux-gone'),
      );

      final Result<RestoreAction> action = await service.runOnStartup();
      expect(action.unwrap(), RestoreAction.dropMarkerAndReport);
      // 标记被丢弃（留着会让每次启动重复报告一个无法完成的任务）。
      expect(File(markerPath()).existsSync(), isFalse);
      // 当前数据完好。
      expect(await feedNames(dataDir), <String>['当前数据']);
    });

    test('恢复目录存在但库不可用（损坏）：丢弃标记，当前数据不动', () async {
      await seedDatabase(dataDir, feedName: '当前数据');
      await Directory(restoredDir).create(recursive: true);
      // 写一个不是 SQLite 的文件。
      await File(p.join(restoredDir, fluxDatabaseFileName))
          .writeAsString('this is not a database');
      final RestoreOrchestrator service = orchestrator();
      await service.markPendingRestart(restoredDirectory: restoredDir);

      final Result<RestoreAction> action = await service.runOnStartup();
      expect(action.unwrap(), RestoreAction.dropMarkerAndReport);
      expect(File(markerPath()).existsSync(), isFalse);
      expect(await feedNames(dataDir), <String>['当前数据']);
    });

    test('切换失败自动回退：当前数据目录仍是切换前的那一份', () async {
      await seedDatabase(dataDir, feedName: '当前数据');
      await seedDatabase(restoredDir, feedName: '恢复数据');
      // 制造「启用新目录」这一步必然失败：用一个已经存在同名目标的停放目录不行，因此这里
      // 直接用一个会失败的端口——目标目录在「停放」之后被别的东西占住。
      //
      // 为什么不在真实文件系统上制造失败：让 rename 失败需要平台级的锁/权限构造，而那种构造
      // 在不同机器上行为不同（不可复现）。这里用**受控端口**表达同一个事实：第 2 步失败时
      // 编排必须把第 1 步搬走的目录搬回来。真实文件系统的搬移本身由上面的成功用例覆盖。
      final _FailingActivatePort port = _FailingActivatePort(dataDir);
      final RestoreOrchestrator service = RestoreOrchestrator(
        port: port,
        clock: _FixedClock(now),
      );
      await service.markPendingRestart(restoredDirectory: restoredDir);
      // 让 port 也从文件系统读标记：这里直接写一个标记文件给它。
      await File(markerPath()).writeAsString(
        RestoreMarker(
          phase: RestorePhase.pendingRestart,
          restoredDirectory: restoredDir,
          restoredAt: now,
        ).encode(),
      );

      final Result<RestoreAction> action = await service.runOnStartup();
      expect(action.isOk, isTrue, reason: '失败被回退吸收，不作为启动错误抛出');
      expect(action.unwrap(), RestoreAction.switchToRestored);
      // **回退发生**：数据目录被搬回来并仍在原处，装的是切换前的数据。
      expect(port.moves.length, 3, reason: '停放 → 启用（失败）→ 回退');
      expect(Directory(dataDir).existsSync(), isTrue);
      expect(await feedNames(dataDir), <String>['当前数据']);
      // 标记保持 pendingRestart：下次启动可重试。
      final RestoreMarker? marker = RestoreMarker.decode(
        File(markerPath()).readAsStringSync(),
      );
      expect(marker?.phase, RestorePhase.pendingRestart);
    });

    test('回退本身失败：明确报错（不静默停在停放位置）', () async {
      await seedDatabase(dataDir, feedName: '当前数据');
      await seedDatabase(restoredDir, feedName: '恢复数据');
      final _FailingBothPort port = _FailingBothPort(dataDir);
      final RestoreOrchestrator service = RestoreOrchestrator(
        port: port,
        clock: _FixedClock(now),
      );
      await File(markerPath()).writeAsString(
        RestoreMarker(
          phase: RestorePhase.pendingRestart,
          restoredDirectory: restoredDir,
          restoredAt: now,
        ).encode(),
      );

      final Result<RestoreAction> action = await service.runOnStartup();
      expect(action.isErr, isTrue, reason: '回退失败必须报错——数据目录停在停放位置时静默会让用户以为数据没了');
      expect(action.errorOrNull!.kind, 'storage');
      // 标记保留（用户还能看到状态并人工处理）。
      expect(File(markerPath()).existsSync(), isTrue);
      // 这正是「必须报错」的那种结局：数据目录停在停放位置，原路径上已经没有数据。
      // 静默的话用户下次启动会看到「什么都没有」而不知道去哪里找——因此这里如实断言它。
      expect(Directory(dataDir).existsSync(), isFalse);
      final List<String> parkedDirs = Directory(root.path)
          .listSync()
          .whereType<Directory>()
          .map((Directory d) => p.basename(d.path))
          .where((String name) => name.contains('superseded'))
          .toList(growable: false);
      expect(parkedDirs, hasLength(1), reason: '数据在停放目录里（人工处理时有明确去处）');
      expect(await feedNames(p.join(root.path, parkedDirs.single)), <String>[
        '当前数据',
      ], reason: '停放目录里的数据完好，用户可以据此找回');
    });

    test('没有标记时什么都不做（大多数启动的情形）', () async {
      await seedDatabase(dataDir, feedName: '当前数据');
      final RestoreOrchestrator service = orchestrator();
      expect(
        (await service.runOnStartup()).unwrap(),
        RestoreAction.nothingToDo,
      );
      expect(await feedNames(dataDir), <String>['当前数据']);
    });

    test('损坏的标记按「没有恢复任务」处理（不猜、不切）', () async {
      await seedDatabase(dataDir, feedName: '当前数据');
      await File(markerPath()).writeAsString('{ not json');
      final RestoreOrchestrator service = orchestrator();
      expect((await service.readState()).unwrap().phase, isNull);
      expect(
        (await service.runOnStartup()).unwrap(),
        RestoreAction.nothingToDo,
      );
      expect(await feedNames(dataDir), <String>['当前数据']);
    });
  });

  group('放弃与清理的边界', () {
    test('放弃只清标记，**不删**恢复出来的目录', () async {
      await seedDatabase(dataDir, feedName: '当前数据');
      await seedDatabase(restoredDir, feedName: '恢复数据');
      final RestoreOrchestrator service = orchestrator();
      await service.markPendingRestart(restoredDirectory: restoredDir);

      expect((await service.abandon()).isOk, isTrue);
      expect(File(markerPath()).existsSync(), isFalse);
      // 恢复目录（一份完整可用的数据）仍在：删它是破坏性动作，由用户自己在文件系统里做。
      expect(Directory(restoredDir).existsSync(), isTrue);
      expect(await feedNames(restoredDir), <String>['恢复数据']);
      expect(await feedNames(dataDir), <String>['当前数据']);
    });

    test('不在 switched 阶段时清理是空操作（Ok(null)，不是失败）', () async {
      final RestoreOrchestrator service = orchestrator();
      expect((await service.completeCleanup()).unwrap(), isNull);
      await seedDatabase(restoredDir, feedName: '恢复数据');
      await service.markPendingRestart(restoredDirectory: restoredDir);
      // pendingRestart 阶段没有「被顶替的目录」这个概念。
      expect((await service.completeCleanup()).unwrap(), isNull);
      expect(Directory(restoredDir).existsSync(), isTrue);
      expect(Directory(dataDir).existsSync(), isTrue);
    });

    test('搬移的目标已存在时拒绝（不合并两个目录）', () async {
      await seedDatabase(dataDir, feedName: '当前数据');
      final String occupied = p.join(root.path, 'Flux-occupied');
      await Directory(occupied).create(recursive: true);
      final FileRestoreOrchestrationStore store = FileRestoreOrchestrationStore(
        dataDirectoryPath: dataDir,
      );
      final Result<void> moved = await store.moveDirectory(
        from: dataDir,
        to: occupied,
      );
      expect(moved.isErr, isTrue, reason: '静默合并不可撤销');
      // 两个目录都还在原处（没被合并、旧目录也没被搬走）。
      expect(Directory(dataDir).existsSync(), isTrue);
      expect(await feedNames(dataDir), <String>['当前数据']);
    });
  });
}

/// 让「启用新目录」这一步失败、其余正常的端口（用于验证回退）。
final class _FailingActivatePort implements RestoreOrchestrationPort {
  _FailingActivatePort(this.dataDirectoryPath);

  /// 当前数据目录（本替身用它判断「哪一步是启用/回退」）。
  final String dataDirectoryPath;

  @override
  String? get currentDataDirectoryPath => dataDirectoryPath;

  /// 发生过的搬移（from → to），用于断言「停放 → 启用 → 回退」三步。
  final List<(String, String)> moves = <(String, String)>[];

  @override
  Future<Result<RestoreMarker?>> readMarker() async {
    final File file = File(
      p.join(p.dirname(dataDirectoryPath), RestoreMarker.fileName),
    );
    if (!file.existsSync()) {
      return const Ok<RestoreMarker?>(null);
    }
    return Ok<RestoreMarker?>(RestoreMarker.decode(await file.readAsString()));
  }

  @override
  Future<Result<void>> writeMarker(RestoreMarker marker) async {
    await File(p.join(p.dirname(dataDirectoryPath), RestoreMarker.fileName))
        .writeAsString(marker.encode(), flush: true);
    return okUnit();
  }

  @override
  Future<Result<void>> clearMarker() async {
    final File file = File(
      p.join(p.dirname(dataDirectoryPath), RestoreMarker.fileName),
    );
    if (file.existsSync()) {
      await file.delete();
    }
    return okUnit();
  }

  @override
  Future<bool> directoryExists(String path) async =>
      Directory(path).existsSync();

  @override
  Future<bool> databaseUsable(String directory) async => true;

  @override
  Future<Result<void>> deleteDirectory(String path) async => okUnit();

  @override
  String newParkedDirectoryName(String token) =>
      p.join(p.dirname(dataDirectoryPath), 'Flux.superseded-$token');

  @override
  Future<Result<void>> moveDirectory({
    required String from,
    required String to,
  }) async {
    moves.add((from, to));
    // 第 2 步（启用恢复目录，即 from 是恢复目录）刻意失败。
    if (from.contains('restored')) {
      return Err<void>(
        StorageError(operation: 'restore.moveDirectory', detail: '模拟启用失败'),
      );
    }
    Directory(from).renameSync(to);
    return okUnit();
  }
}

/// 让启用与回退都失败的端口（用于验证「回退失败必须报错」）。
///
/// 目标判定按**去向**：启用（恢复目录 → 数据目录）与回退（停放目录 → 数据目录）都以数据目录
/// 为去向，因此「去向是数据目录就失败」刚好只打这两步，而停放（数据目录 → 停放目录）成功。
/// 若按来源判定（例如「来自恢复目录就失败」），回退就会被误判成成功，用例也就验不到这条分支。
final class _FailingBothPort implements RestoreOrchestrationPort {
  _FailingBothPort(this.dataDirectoryPath);

  /// 当前数据目录（本替身用它判断「哪一步是启用/回退」）。
  final String dataDirectoryPath;

  @override
  String? get currentDataDirectoryPath => dataDirectoryPath;

  @override
  Future<Result<RestoreMarker?>> readMarker() async {
    final File file = File(
      p.join(p.dirname(dataDirectoryPath), RestoreMarker.fileName),
    );
    if (!file.existsSync()) {
      return const Ok<RestoreMarker?>(null);
    }
    return Ok<RestoreMarker?>(RestoreMarker.decode(await file.readAsString()));
  }

  @override
  Future<Result<void>> writeMarker(RestoreMarker marker) async => okUnit();

  @override
  Future<Result<void>> clearMarker() async => okUnit();

  @override
  Future<bool> directoryExists(String path) async =>
      Directory(path).existsSync();

  @override
  Future<bool> databaseUsable(String directory) async => true;

  @override
  Future<Result<void>> deleteDirectory(String path) async => okUnit();

  @override
  String newParkedDirectoryName(String token) =>
      p.join(p.dirname(dataDirectoryPath), 'Flux.superseded-$token');

  @override
  Future<Result<void>> moveDirectory({
    required String from,
    required String to,
  }) async {
    if (to == dataDirectoryPath) {
      return Err<void>(
        StorageError(operation: 'restore.moveDirectory', detail: '模拟搬移失败'),
      );
    }
    // 其余情形真的搬（停放这一步因此是真实的文件操作）。
    final Directory source = Directory(from);
    if (source.existsSync()) {
      await source.rename(to);
    }
    return okUnit();
  }
}
