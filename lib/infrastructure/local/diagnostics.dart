// 脱敏诊断日志（T010，SET-082；架构第 8 节）。
//
// 目标：出问题时有可排查的记录，同时**保证日志与导出里不含凭据、不含正文与
// prompt**。这两件事会冲突——日志越详细越好查，越详细越可能夹带秘密——因此
// 设计上用「多层脱敏」而不是「靠调用方自觉」：
//
//   第 1 层：复用 lib/core/error/secret_redaction.dart 的既有策略
//           （Bearer、sk-/ghp_/AKIA 等前缀、URL query 敏感参数、userinfo、name=value）；
//   第 2 层：本文件的兜底正则，专门覆盖第 1 层可能漏掉的长随机串与更多参数名：
//           - `sk-[A-Za-z0-9]{16,}`（更长或带连字符变体的密钥）；
//           - `Bearer <token>`（大小写不敏感、长度更宽）；
//           - URL query 中的 token/key/password 参数值。
//   第 3 层：导出时**再跑一遍**两层脱敏并断言。为什么导出要再来一次：
//           导出内容可能来自拼接结果（例如把条目重新组装），只信任「写入时已脱敏」
//           就等于假设中间没人拼接原文；重跑一次是廉价且可测的保险。
//
// 保留策略（SET-082 默认值）：error 级别、7 天、总量上限 10 MiB；超限删最旧。
// 内存用 ring buffer（有界，不随运行时长无限增长）；文件为可选 sink。
library;

import 'dart:io';

import 'package:flux/core/core.dart';

/// 诊断日志级别。
///
/// 级别越高越少：error < warning < info 指“允许记录的**最低**级别”，
/// 即设成 warning 时 error 与 warning 都记录，info 被丢弃。
enum DiagnosticLevel {
  /// 错误（SET-082 默认级别）。
  error,

  /// 警告。
  warning,

  /// 信息。
  info,
}

/// 诊断日志的兜底脱敏。
///
/// 这一层与 core 的 [SecretRedaction] 有意分开：core 的策略更保守（宁可多遮），
/// 面对的是异常消息；这里面对的是任意日志文本，需要额外覆盖更长/变形的前缀与
/// 更多参数名。两层都跑，取并集。
abstract final class DiagnosticRedaction {
  /// 兜底正则：`sk-` 开头、长度 ≥ 16 的密钥（core 只要求 6 位且允许连字符变体，
  /// 这里补一条更宽的以覆盖带连字符或更长的主流行密钥形态）。
  static final RegExp _longSkKey = RegExp(r'sk-[A-Za-z0-9]{16,}');

  /// 兜底正则：`Bearer <token>`，大小写不敏感，token 长度 ≥ 8。
  static final RegExp _bearer = RegExp(
    r'bearer\s+[A-Za-z0-9._~+/=\-]{8,}',
    caseSensitive: false,
  );

  /// 兜底正则：URL query 里的 token/key/password 参数。
  ///
  /// 命中后只把**值**替换为占位符，保留参数名与其余 query，便于定位是哪个参数
  /// 出了问题，同时不留下可用的凭据。
  static final RegExp _querySecret = RegExp(
    // 值取到引号/尖括号/空白/下一个 & 之前：不要在 URL 里越过参数边界，
    // 否则会把后续参数一起吃掉（那会让日志更难读，虽然不会更不安全）。
    '([?&](?:token|access_token|api_key|apikey|key|password|passwd|pwd|secret|sig|auth)=)'
    '([^&\\s"\'<>]+)',
    caseSensitive: false,
  );

  /// 对单条日志消息做兜底脱敏。
  ///
  /// 先跑 core 策略，再跑本层，保证两层顺序稳定、结果可复现。
  static String sanitize(String? message) {
    final String base = SecretRedaction.redact(message);
    String output = base.replaceAllMapped(_bearer, (_) => 'Bearer $masked');
    output = output.replaceAllMapped(_longSkKey, (_) => masked);
    output = output.replaceAllMapped(
      _querySecret,
      (Match match) => '${match[1]}$masked',
    );
    return output;
  }

  /// 脱敏占位符，与 core 保持一致，便于搜索与断言。
  static const String masked = SecretRedaction.masked;
}

/// 一条诊断记录。
final class DiagnosticEntry {
  /// 构造一条已脱敏的记录。
  const DiagnosticEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.tag,
  });

  /// 记录时刻（UTC）。
  final DateTime timestamp;

  /// 级别。
  final DiagnosticLevel level;

  /// 已脱敏的消息。
  final String message;

  /// 可选分类标签（例如 `keychain`、`database`），便于筛读。
  final String? tag;

  /// 单行表示：ISO 时间 + 级别 + 标签 + 消息（行内不换行，避免注入伪造条目）。
  String toLine() {
    final String levelName = level.name;
    final String tagPart = tag == null || tag!.isEmpty ? '-' : tag!;
    // 把消息里的换行替换掉：否则一条日志能伪造出多行，污染解析与人工阅读。
    final String singleLine = message.replaceAll(RegExp(r'[\r\n]+'), ' ');
    return '${timestamp.toIso8601String()}\t$levelName\t$tagPart\t$singleLine';
  }
}

/// 诊断日志服务：级别过滤 + 有界内存 + 可选文件 + 两层脱敏 + 保留策略。
final class DiagnosticLog {
  /// 构造诊断日志。
  ///
  /// 默认值即 SET-082 的文档口径：error / 7 天 / 10 MiB，可直接用于生产装配。
  DiagnosticLog({
    this.level = DiagnosticLevel.error,
    this.retentionDays = 7,
    this.maxTotalBytes = 10 * 1024 * 1024,
    this.maxEntries = 5000,
    this.clock = const SystemClock(),
    this.fileSink,
  });

  /// 允许记录的**最低**级别（SET-082）。
  DiagnosticLevel level;

  /// 保留天数（SET-082：7 天）；超期条目在写入/导出前被裁剪。
  int retentionDays;

  /// 总量上限（SET-082：10 MiB）；超限时删最旧的内存条目。
  int maxTotalBytes;

  /// 内存中最多保留的条数（有界，防止长跑进程内存无上限增长）。 */
  final int maxEntries;

  /// 时间来源；测试注入 [FakeClock] 以确定性地验证保留策略。 */
  final Clock clock;

  /// 可选的文件 sink；为空时只保留内存日志。 */
  final DiagnosticFileSink? fileSink;

  /// 内存 ring buffer。用 Queue 语义（尾部追加、头部淘汰）保证有界。
  final List<DiagnosticEntry> _entries = <DiagnosticEntry>[];

  /// 被级别过滤丢弃的条数（用于确认过滤真的生效，而不是“看起来没日志”）。
  int suppressedByLevel = 0;

  /// 因超限/超期被裁剪的条数。
  int trimmedCount = 0;

  /// 当前内存中的记录（按时间升序）。
  List<DiagnosticEntry> get entries =>
      List<DiagnosticEntry>.unmodifiable(_entries);

  /// 记录的语义级别是否允许写入。
  bool allows(DiagnosticLevel candidate) => candidate.index <= level.index;

  /// 记录一条日志；返回是否被写入（被级别过滤时返回 false）。
  ///
  /// [message] 与 [tag] 都会经过脱敏：调用方不必保证输入已经安全。
  bool record(DiagnosticLevel logLevel, String message, {String? tag}) {
    if (!allows(logLevel)) {
      suppressedByLevel++;
      return false;
    }
    final DiagnosticEntry entry = DiagnosticEntry(
      timestamp: clock.now().toUtc(),
      level: logLevel,
      message: DiagnosticRedaction.sanitize(message),
      tag: tag == null ? null : DiagnosticRedaction.sanitize(tag),
    );
    _entries.add(entry);
    fileSink?.append(entry);
    _enforceLimits();
    return true;
  }

  /// 记录错误级日志。
  bool error(String message, {String? tag}) =>
      record(DiagnosticLevel.error, message, tag: tag);

  /// 记录警告级日志。
  bool warning(String message, {String? tag}) =>
      record(DiagnosticLevel.warning, message, tag: tag);

  /// 记录信息级日志。
  bool info(String message, {String? tag}) =>
      record(DiagnosticLevel.info, message, tag: tag);

  /// 按级别筛出记录（不改变底层缓冲）。
  List<DiagnosticEntry> entriesAt(DiagnosticLevel at) => _entries
      .where((DiagnosticEntry e) => e.level == at)
      .toList(growable: false);

  /// 清空内存记录（不影响文件 sink）。
  void clear() {
    _entries.clear();
  }

  /// 导出日志文本。
  ///
  /// **导出前对每条记录再跑一遍脱敏**：即使写入时已脱敏，重跑也能覆盖
  /// “导出侧拼接/重排后引入原文”的情况；这是可测试的廉价保险。
  String export() {
    pruneExpired();
    final List<DiagnosticEntry> snapshot = List<DiagnosticEntry>.of(_entries);
    final StringBuffer buffer = StringBuffer();
    for (final DiagnosticEntry entry in snapshot) {
      final DiagnosticEntry sanitized = DiagnosticEntry(
        timestamp: entry.timestamp,
        level: entry.level,
        message: DiagnosticRedaction.sanitize(entry.message),
        tag: entry.tag == null ? null : DiagnosticRedaction.sanitize(entry.tag),
      );
      buffer.writeln(sanitized.toLine());
    }
    return buffer.toString();
  }

  /// 按保留天数裁剪超期记录；返回被删条数。
  int pruneExpired() {
    if (retentionDays <= 0) {
      return 0;
    }
    final DateTime cutoff = clock.now().toUtc().subtract(
      Duration(days: retentionDays),
    );
    final int before = _entries.length;
    _entries.removeWhere((DiagnosticEntry e) => e.timestamp.isBefore(cutoff));
    final int removed = before - _entries.length;
    trimmedCount += removed;
    return removed;
  }

  /// 当前内存记录的总字节数（按行表示估算，与文件口径一致）。
  int get currentBytes => _entries.fold<int>(
    0,
    (int sum, DiagnosticEntry e) => sum + e.toLine().length,
  );

  /// 强制裁剪：先按保留天数，再按条数与字节上限，超限删最旧。
  void _enforceLimits() {
    pruneExpired();
    while (_entries.length > maxEntries) {
      _entries.removeAt(0);
      trimmedCount++;
    }
    while (currentBytes > maxTotalBytes && _entries.length > 1) {
      _entries.removeAt(0);
      trimmedCount++;
    }
  }
}

/// 诊断日志的可选文件 sink。
///
/// 为什么单独抽一个类型：文件写入在 T010 不是必需能力（内存日志已满足“有记录可
/// 导出”），但 SET-082 的「保留天数/总量上限」在文件上才有真正的长期意义。
/// 把它做成可注入的接口，单元测试能用临时目录验证裁剪，生产可按需开启。
abstract interface class DiagnosticFileSink {
  /// 追加一条记录。
  void append(DiagnosticEntry entry);

  /// 读取文件中的全部行（用于测试与导出）。
  List<String> readLines();
}

/// 基于 [File] 的日志 sink：按行追加，超期/超限时重写文件。
final class FileDiagnosticSink implements DiagnosticFileSink {
  /// 绑定一个日志文件与保留策略。
  FileDiagnosticSink({
    required this.file,
    this.retentionDays = 7,
    this.maxTotalBytes = 10 * 1024 * 1024,
    this.clock = const SystemClock(),
  });

  /// 目标日志文件；父目录需已存在（由装配层保证）。
  final File file;

  /// 保留天数（SET-082）。
  final int retentionDays;

  /// 总量上限（SET-082：10 MiB）。
  final int maxTotalBytes;

  /// 时间来源；用于保留天数裁剪，测试可注入假时钟。
  final Clock clock;

  @override
  void append(DiagnosticEntry entry) {
    final List<String> lines = _readExisting();
    lines.add(entry.toLine());
    _rewrite(lines);
  }

  @override
  List<String> readLines() => _readExisting();

  /// 读取现有行；文件不存在时视为空（首次运行是正常状态）。
  List<String> _readExisting() {
    if (!file.existsSync()) {
      return <String>[];
    }
    return file
        .readAsStringSync()
        .split('\n')
        .where((String line) => line.trim().isNotEmpty)
        .toList();
  }

  /// 按保留天数与总量上限裁剪后重写。
  void _rewrite(List<String> lines) {
    List<String> kept = lines;

    // 1) 按时间戳裁剪超期行。解析失败的行（外部写入/损坏）保守保留，
    //    但在下面的字节裁剪里仍可能被淘汰。
    if (retentionDays > 0) {
      final DateTime cutoff = clock.now().toUtc().subtract(
        Duration(days: retentionDays),
      );
      kept = kept.where((String line) {
        final DateTime? at = _parseTimestamp(line);
        if (at == null) {
          return true;
        }
        return !at.isBefore(cutoff);
      }).toList();
    }

    // 2) 按总字节上限从**最旧**开始淘汰。
    int total = kept.fold<int>(0, (int sum, String l) => sum + l.length + 1);
    int start = 0;
    while (total > maxTotalBytes && start < kept.length - 1) {
      total -= kept[start].length + 1;
      start++;
    }
    kept = kept.sublist(start);

    file.writeAsStringSync(
      kept.isEmpty ? '' : '${kept.join('\n')}\n',
      flush: true,
    );
  }

  /// 从行首的 ISO-8601 时间戳解析时刻；失败返回 null。
  DateTime? _parseTimestamp(String line) {
    final int tab = line.indexOf('\t');
    final String head = tab < 0 ? line : line.substring(0, tab);
    return DateTime.tryParse(head)?.toUtc();
  }
}
