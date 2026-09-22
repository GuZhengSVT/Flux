// 诊断导出包的**纯规则**（T048；SET-082、架构第 8 节「日志/截图/分享/备份不得泄露凭据」）。
//
// 这个文件的职责是把「一个诊断包里允许出现什么」写成可断言的结构，而不是靠实现记得别写：
//   * 四类内容各有一张**字段白名单**（系统信息 / 存储统计 / 同步状态摘要 / 日志文本）；
//   * 「不含原文、不含 prompt、不含秘密」不是一句承诺，而是**逐字段可枚举的封闭集合**——
//     一个不在白名单里的字段根本进不了包；
//   * 导出文本在**拼装之后**再跑一遍脱敏并断言（写入时已脱敏不等于拼装后仍干净）。
library;

import '../error/secret_redaction.dart';

/// 诊断包的一个小节。
final class DiagnosticsSection {
  /// 构造小节。
  const DiagnosticsSection({required this.title, required this.fields});

  /// 小节标题（稳定的机器可读名，不是本地化文案——诊断包要能被非本机环境解析）。
  final String title;

  /// 字段（有序：键 → 已脱敏的文本值）。
  final List<DiagnosticsField> fields;
}

/// 诊断包的一个字段。
final class DiagnosticsField {
  /// 构造字段。
  const DiagnosticsField({required this.name, required this.value});

  /// 字段名。
  final String name;

  /// 字段值（文本；写入前会被脱敏）。
  final String value;
}

/// 诊断包的**字段白名单**。
///
/// 逐条列出而不是「有哪些就写哪些」：后者的形状让「顺手加一个 body 字段」在类型上成立，
/// 而它的后果是把用户原文写进一个发给别人的文件里。白名单把「包里有原文」变成不可能。
abstract final class DiagnosticsAllowlist {
  /// 系统信息小节的字段。
  static const List<String> system = <String>[
    'appVersion',
    'buildMode',
    'osName',
    'osVersion',
    'dartVersion',
    'cpuArchitecture',
    'locale',
    'themeMode',
    'dataDirectoryPresent',
  ];

  /// 存储统计小节的字段。
  static const List<String> storage = <String>[
    'databaseBytes',
    'mediaBytes',
    'mediaEntries',
    'articleBodyBytes',
    'articleBodyCount',
    'newsSummaryBytes',
    'newsSummaryCount',
    'aiCacheBytes',
    'aiCacheEntries',
    'failedDraftCount',
    'mediaLimitBytes',
    'feedCount',
    'articleCount',
    'measuredAt',
  ];

  /// 同步状态摘要小节的字段。
  ///
  /// **没有**服务器地址、用户名与远端目录：它们合起来足以说明「谁在用哪个服务」，而诊断包的
  /// 用途是排查协议行为（能力三态、待同步数、冲突数），不需要目的地。
  static const List<String> sync = <String>[
    'configured',
    'enabled',
    'capability',
    'lastSyncedAt',
    'pendingChangeCount',
    'conflictCount',
    'pendingRemoteDeletionCount',
    'baseVersionPresent',
    'degraded',
  ];

  /// 日志小节只有一条「日志文本」字段（内容自身已是脱敏后的行）。
  static const List<String> log = <String>['logText', 'logEntryCount'];

  /// 全部允许的字段名（用于「包里有白名单之外的东西」的断言）。
  static List<String> get all => <String>[
    ...system,
    ...storage,
    ...sync,
    ...log,
  ];
}

/// 构建诊断包。
///
/// [sections] 里出现的每个字段名都会被检查是否在白名单内；**不在白名单里的字段直接丢掉**
/// （而不是报错或写进去）。丢掉而不是报错，是因为导出是对一个可能已经不完整的系统做检查
/// （数据库不可用、日志文件读不到），让一次「多余字段」把整个导出变成失败，反而会阻碍排查。
final class DiagnosticsReportBuilder {
  /// 构造构建器。
  const DiagnosticsReportBuilder();

  /// 组装报告文本。
  ///
  /// 每一步的值都经过 [SecretRedaction.redact]（与写入日志时同一套策略），最后**整篇再跑一遍**：
  /// 拼装会把来自不同位置的片段接在一起，一次整体重扫能覆盖「单看每一段都干净、连起来却形成了
  /// 一个 `token=<值>` 形状」这种情况。
  String build({
    required DiagnosticsSection system,
    required DiagnosticsSection storage,
    required DiagnosticsSection sync,
    required DiagnosticsSection log,
  }) {
    final StringBuffer buffer = StringBuffer();
    buffer.writeln('flux-diagnostics v1');
    for (final DiagnosticsSection section in <DiagnosticsSection>[
      system,
      storage,
      sync,
      log,
    ]) {
      buffer.writeln('');
      buffer.writeln('[${section.title}]');
      final Set<String> allowed = _allowedFor(section.title);
      for (final DiagnosticsField field in section.fields) {
        if (!allowed.contains(field.name)) {
          // 白名单之外的字段不进包（见构建器说明）。
          continue;
        }
        final String value = SecretRedaction.redact(field.value);
        // 单行化：值里的换行会让一个字段伪造出多行，污染解析与人工阅读（与诊断日志同一口径）。
        final String singleLine = value.replaceAll(RegExp(r'[\r\n]+'), ' ');
        buffer.writeln('${field.name}=$singleLine');
      }
    }
    // 整篇重扫一次（见方法说明）。
    return SecretRedaction.redact(buffer.toString());
  }

  static Set<String> _allowedFor(String title) => switch (title) {
    'system' => DiagnosticsAllowlist.system.toSet(),
    'storage' => DiagnosticsAllowlist.storage.toSet(),
    'sync' => DiagnosticsAllowlist.sync.toSet(),
    'log' => DiagnosticsAllowlist.log.toSet(),
    _ => const <String>{},
  };
}

/// 一次诊断导出的结论。
final class DiagnosticsExportResult {
  /// 构造结论。
  const DiagnosticsExportResult({
    required this.path,
    required this.byteCount,
    required this.fieldCount,
    this.logEntryCount = 0,
  });

  /// 用户选定的保存路径。
  final String path;

  /// 文本字节数。
  final int byteCount;

  /// 字段数（白名单过滤之后的实际条数）。
  final int fieldCount;

  /// 包含的日志行数。
  final int logEntryCount;
}
