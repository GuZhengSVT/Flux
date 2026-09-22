// 故障恢复编排与诊断导出的端口（T048；架构 5.3 的恢复段与第 8 节、SET-082）。
//
// 两个能力合在一个文件里，因为它们的**调用时机是同一个**：启动时检查恢复标记 + 用户在设置页
// 导出诊断。分开会让组合根里出现两处几乎相同的「数据目录在哪」的推导，而那个推导一旦漂移，
// 症状是「恢复切到了 A、诊断包里写着 B」。
//
// 两条刻意的设计：
//   1) **编排端口的签名里没有「就地覆盖」**：它只接受「切换到某目录」与「删除某目录」，没有
//      「写入某目录」。因此「切换把正在用的数据目录覆盖掉」在接口上不可表达；
//   2) **诊断导出端口不接受任意文本**：它只接受已经由 core 的白名单构建出的报告文本与一个
//      文件名建议。调用方无法顺手把一段原文塞进导出包。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flux/core/core.dart';

import '../../feeds/application/file_access.dart';

import 'diagnostics_export_service.dart';
import 'restore_orchestrator.dart';

/// 恢复编排的持久化与文件操作端口（由 infrastructure/local 实现）。
abstract interface class RestoreOrchestrationPort {
  /// 读当前的恢复标记；没有（或标记损坏）时返回 null。
  Future<Result<RestoreMarker?>> readMarker();

  /// 写入标记（覆盖）。
  Future<Result<void>> writeMarker(RestoreMarker marker);

  /// 删除标记（幂等：不存在也算成功）。
  Future<Result<void>> clearMarker();

  /// 当前数据目录路径。
  String? get currentDataDirectoryPath;

  /// 判断一个路径是否存在**目录**。
  Future<bool> directoryExists(String path);

  /// 判断 [directory] 下确实有一个**能打开**的数据库（与 T046 的恢复校验同一口径：
  /// 「写完了文件」与「这是一个能用的库」是两件事）。
  Future<bool> databaseUsable(String directory);

  /// 把目录 [from] 搬到 [to]（用于停放旧目录与启用新目录）。
  ///
  /// [to] 已存在时**必须失败**：静默覆盖会让一次切换把两个目录合到一起，而这不可撤销。
  Future<Result<void>> moveDirectory({
    required String from,
    required String to,
  });

  /// 删除一个目录（递归）；不存在视为成功。
  Future<Result<void>> deleteDirectory(String path);

  /// 生成一个**新的停放目录名**（与当前数据目录并列，例如 `Flux.superseded-<token>`）。
  String newParkedDirectoryName(String token);
}

/// 诊断包的内容来源（由 infrastructure 实现）。
abstract interface class DiagnosticsExportSource {
  /// 系统信息（Flutter/OS/版本/架构/语言/主题/数据目录是否存在）。
  Future<Result<DiagnosticsSection>> systemSection();

  /// 存储统计（T047 的分类占用 + 计数）。
  Future<Result<DiagnosticsSection>> storageSection();

  /// 同步状态摘要（能力三态、待同步数、冲突数等；**不含地址与凭据**）。
  Future<Result<DiagnosticsSection>> syncSection();

  /// 已脱敏的日志（内存 + 文件日志合并）。
  Future<Result<DiagnosticsSection>> logSection();
}

/// 恢复编排端口 Provider。
///
/// 默认抛错（与其余端口同一口径）：漏接线必须立刻暴露，而不是退化成一个「什么都不做」的实现——
/// 那会让用户以为恢复已编排好，重启后数据却还是旧的。
final Provider<RestoreOrchestrationPort> restoreOrchestrationPortProvider =
    Provider<RestoreOrchestrationPort>(
      (Ref ref) => throw StateError(
        'restoreOrchestrationPortProvider 未被组合根覆盖：见 lib/app/app_providers.dart',
      ),
    );

/// 诊断导出内容来源 Provider（默认抛错，理由同上）。
final Provider<DiagnosticsExportSource> diagnosticsExportSourceProvider =
    Provider<DiagnosticsExportSource>(
      (Ref ref) => throw StateError(
        'diagnosticsExportSourceProvider 未被组合根覆盖：见 lib/app/app_providers.dart',
      ),
    );

/// 恢复编排用例（由端口组合，因此界面与启动路径共用同一份判定）。
final Provider<RestoreOrchestrator> restoreOrchestratorProvider =
    Provider<RestoreOrchestrator>(
      (Ref ref) => RestoreOrchestrator(
        port: ref.watch(restoreOrchestrationPortProvider),
      ),
    );

/// 诊断导出用例（由内容来源 + 文件端口 + 白名单构建器组成）。
final Provider<DiagnosticsExportService> diagnosticsExportServiceProvider =
    Provider<DiagnosticsExportService>(
      (Ref ref) => DiagnosticsExportService(
        source: ref.watch(diagnosticsExportSourceProvider),
        files: ref.watch(fileAccessProvider),
      ),
    );

/// 启动时的恢复编排结论（由组合根写入；界面读它展示「重启后生效」的状态）。
///
/// 用 Provider 而不是让界面重新读一次标记：结论是**启动那一刻**做的决定（切换可能已经把数据
/// 目录换掉了），重读标记得到的是「现在还有什么待办」，两者不是同一件事；而且重读会让界面在
/// 展示状态时产生副作用（cleaned 残留标记会被清掉）。
final NotifierProvider<RestoreActionController, RestoreOrchestrationState>
restoreActionProvider =
    NotifierProvider<RestoreActionController, RestoreOrchestrationState>(
      RestoreActionController.new,
    );

/// 启动编排结论的持有者。
final class RestoreActionController
    extends Notifier<RestoreOrchestrationState> {
  @override
  RestoreOrchestrationState build() => RestoreOrchestrationState.idle;

  /// 写入启动结论（由组合根在装配时调用一次）。
  void publish(RestoreOrchestrationState next) => state = next;
}
