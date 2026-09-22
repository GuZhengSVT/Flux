// 恢复编排的持久化与文件操作实现（T048；端口在 features/settings/application/maintenance_ports.dart）。
//
// 三条实现纪律：
//
//   1) **标记写在数据目录的父目录**（[RestoreMarker.fileName]）。写在数据目录内部会让「数据目录
//      被改名」这一步顺带把标记也搬走，而它恰恰要在搬移过程中一直可见；
//   2) **搬移的目标已存在时必须失败**（不静默合并）。`Directory.rename` 在目标存在且为空时会
//      成功、非空时会失败，两种行为都不可依赖——因此这里先显式判断目标是否存在，再执行改名。
//      静默成功会让一次切换把两个目录的内容混到一起，而这不可撤销；
//   3) **数据库可用性用真的打开一次来判定**（`openAppDatabase`），而不是看文件在不在。
//      「有一个 flux.sqlite 文件」与「这是一个能用的库」是两件事，而切换之后才发现它坏了，
//      旧目录已经被顶替。
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:flux/core/core.dart';
import 'package:flux/features/settings/application/maintenance_ports.dart';

import 'database.dart';

/// 恢复编排端口实现。
final class FileRestoreOrchestrationStore implements RestoreOrchestrationPort {
  /// 绑定当前数据目录。
  ///
  /// [dataDirectoryPath] 为 null 表示数据目录不可解析（启动降级）：此时所有动作都如实失败/返回
  /// 「做不了」，而不是猜一个路径。
  /// [diagnostics] 可空：标记损坏这件事必须留痕（否则「我的恢复为什么没生效」没有任何线索），
  /// 但存储层不该强迫调用方提供一个日志端口（与 T030 的同类实现一致）。
  const FileRestoreOrchestrationStore({
    required this.dataDirectoryPath,
    this.diagnostics,
  });

  /// 当前运行时数据目录（`.../Flux`）。
  final String? dataDirectoryPath;

  /// 诊断端口（报告损坏的标记）。
  final DiagnosticSink? diagnostics;

  @override
  String? get currentDataDirectoryPath => dataDirectoryPath;

  /// 标记文件（数据目录的父目录下）。
  File? get _markerFile {
    final String? base = dataDirectoryPath;
    if (base == null) {
      return null;
    }
    return File(p.join(p.dirname(base), RestoreMarker.fileName));
  }

  @override
  Future<Result<RestoreMarker?>> readMarker() async {
    final File? file = _markerFile;
    if (file == null || !file.existsSync()) {
      return const Ok<RestoreMarker?>(null);
    }
    try {
      final RestoreMarker? marker = RestoreMarker.decode(
        await file.readAsString(),
      );
      if (marker == null) {
        // 损坏的标记按「没有恢复任务」处理（RestoreMarker.decode 的说明），但**留一条诊断**：
        // 静默丢弃会让「我的恢复为什么没生效」完全没有线索。
        diagnostics?.warning('恢复标记无法解析，按「没有待编排的恢复」处理', tag: 'restore');
      }
      return Ok<RestoreMarker?>(marker);
    } on Exception catch (error, stackTrace) {
      return Err<RestoreMarker?>(
        StorageError(
          operation: 'restore.readMarker',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<void>> writeMarker(RestoreMarker marker) async {
    final File? file = _markerFile;
    if (file == null) {
      return Err<void>(
        StorageError(operation: 'restore.writeMarker', detail: '数据目录不可用'),
      );
    }
    try {
      // 先写临时文件再 rename：进程在写一半时被杀掉会留下一个半截的标记，而它会被下次启动读成
      // 「损坏」并被丢弃（恢复意图静默消失）。rename 在同一文件系统上是原子的。
      final File tmp = File('${file.path}.part');
      await tmp.writeAsString(marker.encode(), flush: true);
      await tmp.rename(file.path);
      return okUnit();
    } on Exception catch (error, stackTrace) {
      return Err<void>(
        StorageError(
          operation: 'restore.writeMarker',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<void>> clearMarker() async {
    final File? file = _markerFile;
    if (file == null) {
      return okUnit();
    }
    try {
      if (file.existsSync()) {
        await file.delete();
      }
      return okUnit();
    } on Exception catch (error, stackTrace) {
      return Err<void>(
        StorageError(
          operation: 'restore.clearMarker',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<bool> directoryExists(String path) async =>
      Directory(path).existsSync();

  @override
  Future<bool> databaseUsable(String directory) async {
    final File file = File(p.join(directory, fluxDatabaseFileName));
    if (!file.existsSync()) {
      return false;
    }
    final Result<AppDatabase> opened = await openAppDatabase(file);
    if (opened.isErr) {
      return false;
    }
    // 打开成功后立刻关闭：这个连接只是用来确认它可读，长期持有会让后续的目录改名失败
    // （Windows 会锁住、macOS 上也留下未合并的 WAL）。
    try {
      await opened.unwrap().close();
    } on Exception {
      // 关闭失败不影响「它确实能打开」这个结论。
    }
    return true;
  }

  @override
  Future<Result<void>> moveDirectory({
    required String from,
    required String to,
  }) async {
    try {
      final Directory source = Directory(from);
      if (!source.existsSync()) {
        return Err<void>(
          StorageError(
            operation: 'restore.moveDirectory',
            detail: '源目录不存在',
            isMissing: true,
          ),
        );
      }
      if (Directory(to).existsSync() || File(to).existsSync()) {
        // 目标已存在：**不合并、不覆盖**（见文件顶部第 2 条）。
        return Err<void>(
          StorageError(
            operation: 'restore.moveDirectory',
            detail: '目标已存在，拒绝覆盖',
          ),
        );
      }
      await source.rename(to);
      return okUnit();
    } on Exception catch (error, stackTrace) {
      return Err<void>(
        StorageError(
          operation: 'restore.moveDirectory',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<void>> deleteDirectory(String path) async {
    try {
      final Directory dir = Directory(path);
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
      }
      return okUnit();
    } on Exception catch (error, stackTrace) {
      return Err<void>(
        StorageError(
          operation: 'restore.deleteDirectory',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  String newParkedDirectoryName(String token) {
    final String? base = dataDirectoryPath;
    if (base == null) {
      // 没有数据目录时不该走到这里（调用方只在切换路径上用它）；抛错而不是猜一个路径，
      // 因为猜错意味着把一个目录搬到别处。
      throw StateError('数据目录不可用：无法规划停放目录');
    }
    return p.join(p.dirname(base), '${p.basename(base)}.superseded-$token');
  }
}
