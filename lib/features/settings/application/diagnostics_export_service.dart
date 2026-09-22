// 诊断导出用例（T048；SET-082、架构第 8 节）。
//
// 这个用例只做三件事：取四节内容 → 交给 core 的白名单构建器拼装 → 保存到用户选的文件。
// 它**不做**任何「挑选字段」的判断——那件事由 [DiagnosticsReportBuilder] 与
// [DiagnosticsAllowlist] 承担，因此「导出包里出现原文或 prompt」在这条路径上不可表达。
//
// 保存路径复用 T015/T046 的 [FileAccessPort]（用户经系统面板明确授权的那一个动作），不新增
// 文件系统入口：诊断包不该成为一条能任意写盘的新通道。
library;

import 'dart:convert';

import 'package:flux/core/core.dart';

import '../../feeds/application/file_access.dart';
import 'maintenance_ports.dart';

/// 诊断导出用例。
final class DiagnosticsExportService {
  /// 构造用例。
  const DiagnosticsExportService({
    required this.source,
    required this.files,
    this.builder = const DiagnosticsReportBuilder(),
    this.diagnostics = const NoopDiagnosticSink(),
    this.clock = const SystemClock(),
  });

  /// 内容来源（四节）。
  final DiagnosticsExportSource source;

  /// 文件保存端口（用户选定位置）。
  final FileAccessPort files;

  /// 报告构建器（白名单 + 脱敏）。
  final DiagnosticsReportBuilder builder;

  /// 诊断记录（只记条数与结果，不记内容）。
  final DiagnosticSink diagnostics;

  /// 时钟（文件名里的日期）。
  final Clock clock;

  /// 组装诊断报告文本（**不写文件**；预览与测试都用它）。
  Future<Result<String>> buildReport() async {
    final Result<DiagnosticsSection> system = await source.systemSection();
    if (system.isErr) {
      return Err<String>(system.errorOrNull!);
    }
    final Result<DiagnosticsSection> storage = await source.storageSection();
    if (storage.isErr) {
      return Err<String>(storage.errorOrNull!);
    }
    final Result<DiagnosticsSection> sync = await source.syncSection();
    if (sync.isErr) {
      return Err<String>(sync.errorOrNull!);
    }
    final Result<DiagnosticsSection> log = await source.logSection();
    if (log.isErr) {
      return Err<String>(log.errorOrNull!);
    }
    return Ok<String>(
      builder.build(
        system: system.unwrap(),
        storage: storage.unwrap(),
        sync: sync.unwrap(),
        log: log.unwrap(),
      ),
    );
  }

  /// 导出诊断包到用户选定的文件；用户取消时返回 `Ok(null)`。
  ///
  /// 文件名只带日期，不带设备名或用户名：文件名会被同步到别处、出现在邮件标题里，而它不该成为
  /// 第二条说明「这是谁的机器」的线索（设备名本身在系统信息小节里，用户已经确认过要导出）。
  Future<Result<DiagnosticsExportResult?>> export() async {
    final Result<String> report = await buildReport();
    if (report.isErr) {
      return Err<DiagnosticsExportResult?>(report.errorOrNull!);
    }
    final String text = report.unwrap();
    final List<int> bytes = utf8.encode(text);
    final String date = clock.now().toUtc().toIso8601String().split('T').first;
    final Result<String?> saved = await files.saveBytes(
      'flux-diagnostics-$date.txt',
      bytes,
      mimeType: 'text/plain',
      extensions: const <String>['txt'],
    );
    if (saved.isErr) {
      return Err<DiagnosticsExportResult?>(saved.errorOrNull!);
    }
    final String? path = saved.valueOrNull;
    if (path == null) {
      // 用户取消：不是错误（与备份导出一致）。
      return const Ok<DiagnosticsExportResult?>(null);
    }
    final int fieldCount = text
        .split('\n')
        .where((String line) => line.contains('=') && !line.startsWith('['))
        .length;
    final int logEntryCount = text
        .split('\n')
        .where(
          (String line) =>
              line.contains('\tERROR\t') ||
              line.contains('\tINFO\t') ||
              line.contains('\tWARN'),
        )
        .length;
    diagnostics.info(
      '导出诊断包：$fieldCount 个字段、$logEntryCount 条日志、${bytes.length} 字节',
      tag: 'diagnostics.export',
    );
    return Ok<DiagnosticsExportResult?>(
      DiagnosticsExportResult(
        path: path,
        byteCount: bytes.length,
        fieldCount: fieldCount,
        logEntryCount: logEntryCount,
      ),
    );
  }
}
