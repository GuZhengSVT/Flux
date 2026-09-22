// 明文备份的**纯规则**（T046；架构 5.3「清理、备份和统计」的备份与恢复段、SET-076）。
//
// 架构原话：「明文 ZIP 备份包含一致性数据快照、版本清单、校验和、可选媒体，排除凭据；提示
// 「包含个人订阅/正文，任何持有者均可读取」。OPML 不是完整备份。使用 SQLite 备份机制而非复制
// 活动数据库并遗漏 WAL。」「恢复默认到新数据目录，先校验 schema、大小、路径、哈希，失败不动原库；
// 正式切换前再次确认。旧版本不能写较新 schema。压缩包拒绝绝对路径和路径穿越。」
//
// 这个文件是本任务里**最该被逐条断言**的部分，因此它不碰文件系统、不碰 ZIP 编解码、不碰网络：
//   * 「路径穿越被拒」「schema 更新时拒恢复」「哈希不符即失败」都是纯函数判定；
//   * 包内**允许出现哪些条目**是一张显式清单（[backupEntryAllowed]），因此「凭据进了包」这件事
//     在规则层就不可表达，而不是靠实现记得别写；
//   * 版本清单（[BackupManifest]）的编解码是确定性的（键排序、无缩进抖动），因此「同一份内容
//     编出同一串字节」这条性质可以被单独钉住。
library;

import 'dart:convert';
import 'dart:typed_data';

import '../digest/sha256.dart';

/// 一个包内条目（纯数据：名字 + 未压缩内容）。
///
/// 放在 core 而不是 infrastructure：校验规则（名字是否安全、是否在白名单内、大小与哈希是否
/// 相符）与编解码实现是两件事，前者必须能被纯 Dart 用例逐条钉住。
final class BackupArchiveEntry {
  /// 构造条目。
  const BackupArchiveEntry({required this.name, required this.bytes});

  /// 包内条目名。
  final String name;

  /// 未压缩内容。
  final Uint8List bytes;
}

/// 一次包校验的结论。
final class BackupValidation {
  const BackupValidation._({
    required this.manifest,
    required this.databaseEntry,
    required this.mediaEntryCount,
    required this.failureKind,
    required this.failingEntry,
  });

  /// 校验通过。
  factory BackupValidation.ok({
    required BackupManifest manifest,
    required BackupArchiveEntry databaseEntry,
    required int mediaEntryCount,
  }) => BackupValidation._(
    manifest: manifest,
    databaseEntry: databaseEntry,
    mediaEntryCount: mediaEntryCount,
    failureKind: null,
    failingEntry: null,
  );

  /// 校验失败。
  factory BackupValidation.failed(
    BackupFailureKind kind, {
    String? failingEntry,
  }) => BackupValidation._(
    manifest: null,
    databaseEntry: null,
    mediaEntryCount: 0,
    failureKind: kind,
    failingEntry: failingEntry,
  );

  /// 包内清单；失败时为 null。
  final BackupManifest? manifest;

  /// 数据库快照条目；失败时为 null。
  final BackupArchiveEntry? databaseEntry;

  /// 媒体条目数。
  final int mediaEntryCount;

  /// 失败类别；成功时为 null。
  final BackupFailureKind? failureKind;

  /// 失败的条目名（尽量给出：用户要能看出是哪一个文件有问题）。
  final String? failingEntry;

  /// 是否通过。
  bool get isOk => failureKind == null;

  /// 数据库快照的字节。
  Uint8List get databaseBytes => databaseEntry!.bytes;
}

/// 校验一个已解开的包（架构 5.3「先校验 schema、大小、路径、哈希」）。
///
/// 顺序有意义，且每一道都**先于任何写操作**：
///   1) 每个条目名安全（绝对路径/路径穿越/反斜杠）——这是安全边界，必须在最前面；
///   2) 每个条目名在白名单内——不在白名单的包不属于本应用；
///   3) 清单存在且读得懂（结构 + 更高的包结构版本）；
///   4) 备份的 schema 不高于当前应用（旧版本不能写较新 schema）；
///   5) 数据库快照存在；
///   6) 每个条目的大小与 SHA-256 与清单一致。
///
/// 清单自身不在清单里（自指会让校验需要一个外部的信任根），因此它的完整性由
/// 「读得懂 + 结构自洽 + 包结构版本匹配」保证；这一点在实现里是显式的，而不是一个被忘掉的
/// 缺口。
BackupValidation validateBackupArchive(
  List<BackupArchiveEntry> entries, {
  required int currentSchemaVersion,
}) {
  // 1) 名字安全。
  for (final BackupArchiveEntry entry in entries) {
    if (!isSafeBackupEntryName(entry.name)) {
      return BackupValidation.failed(
        BackupFailureKind.unsafeEntryPath,
        failingEntry: entry.name,
      );
    }
  }
  // 2) 白名单。
  for (final BackupArchiveEntry entry in entries) {
    if (!backupEntryAllowed(entry.name)) {
      return BackupValidation.failed(
        BackupFailureKind.disallowedEntry,
        failingEntry: entry.name,
      );
    }
  }
  // 3) 清单。
  final BackupArchiveEntry? manifestEntry = entries
      .where((BackupArchiveEntry e) => e.name == backupManifestFileName)
      .firstOrNull;
  if (manifestEntry == null) {
    return BackupValidation.failed(BackupFailureKind.manifestMissing);
  }
  BackupManifest? manifest;
  try {
    manifest = BackupManifest.decode(utf8.decode(manifestEntry.bytes));
  } on FormatException {
    manifest = null;
  }
  if (manifest == null) {
    return BackupValidation.failed(BackupFailureKind.manifestUnreadable);
  }
  // 4) schema 兼容。
  if (!backupSchemaIsRestorable(
    backupSchemaVersion: manifest.schemaVersion,
    currentSchemaVersion: currentSchemaVersion,
  )) {
    return BackupValidation.failed(BackupFailureKind.schemaTooNew);
  }
  // 5) 数据库快照。
  final BackupArchiveEntry? database = entries
      .where((BackupArchiveEntry e) => e.name == backupDatabaseEntryName)
      .firstOrNull;
  if (database == null) {
    return BackupValidation.failed(BackupFailureKind.databaseEntryMissing);
  }
  // 6) 大小与哈希。
  final Map<String, BackupEntryRecord> expected = <String, BackupEntryRecord>{
    for (final BackupEntryRecord record in manifest.entries)
      record.name: record,
  };
  for (final BackupEntryRecord record in manifest.entries) {
    final BackupArchiveEntry? actual = entries
        .where((BackupArchiveEntry e) => e.name == record.name)
        .firstOrNull;
    if (actual == null) {
      // 清单声明的条目在包里不存在：包被截断或改过。
      return BackupValidation.failed(
        BackupFailureKind.databaseEntryMissing,
        failingEntry: record.name,
      );
    }
    if (actual.bytes.length != record.size) {
      return BackupValidation.failed(
        BackupFailureKind.sizeMismatch,
        failingEntry: record.name,
      );
    }
    if (sha256Hex(actual.bytes) != record.sha256) {
      return BackupValidation.failed(
        BackupFailureKind.hashMismatch,
        failingEntry: record.name,
      );
    }
  }
  // 包里出现了清单没声明的条目（除清单自身）：同样按「被改过」拒绝——放行会让
  // 一个被塞进额外文件的包通过校验。
  for (final BackupArchiveEntry entry in entries) {
    if (entry.name == backupManifestFileName) {
      continue;
    }
    if (!expected.containsKey(entry.name)) {
      return BackupValidation.failed(
        BackupFailureKind.disallowedEntry,
        failingEntry: entry.name,
      );
    }
  }

  return BackupValidation.ok(
    manifest: manifest,
    databaseEntry: database,
    mediaEntryCount: entries
        .where(
          (BackupArchiveEntry e) => e.name.startsWith(backupMediaEntryPrefix),
        )
        .length,
  );
}

/// 生成一份包的条目记录（导出侧用：把已确定的条目变成清单里的记录）。
List<BackupEntryRecord> backupEntryRecordsOf(
  Iterable<BackupArchiveEntry> entries,
) => <BackupEntryRecord>[
  for (final BackupArchiveEntry entry in entries)
    BackupEntryRecord(
      name: entry.name,
      size: entry.bytes.length,
      sha256: sha256Hex(entry.bytes),
    ),
];

/// 备份格式版本（与 SET 编号无关：它描述的是**包结构**）。
///
/// 每改一次包结构就必须提升它：读不懂的包必须被**明确拒绝**，而不是按旧形状尽力解读——
/// 尽力解读的后果是「恢复了一半、剩下的字段被默认值填掉」，而用户以为恢复成功了。
const int backupFormatVersion = 1;

/// 版本清单的文件名。
const String backupManifestFileName = 'manifest.json';

/// 数据库快照在包内的文件名。
///
/// 用与运行时同一个文件名（flux.sqlite）：恢复时它就是「要放回数据目录的那一个文件」，
/// 换一个名字会让恢复实现多一层「源名 → 目标名」的映射，而两层映射最容易出的错是漏写。
const String backupDatabaseEntryName = 'flux.sqlite';

/// 媒体目录在包内的前缀（SET-076 的「是否含媒体」）。
const String backupMediaEntryPrefix = 'media/';

/// 包内允许出现的条目：**数据库快照、版本清单、以及媒体目录下的文件**。
///
/// 这是一张**白名单**而不是黑名单。黑名单的问题在于它必须穷举所有秘密的形态（Keychain 引用、
/// 令牌、密码、模型 Key……），漏掉一种就等于把它写进了包；而白名单只需要回答「这是什么」，
/// 答不上来的东西**根本进不了包**。
bool backupEntryAllowed(String entryName) {
  if (entryName == backupManifestFileName) {
    return true;
  }
  if (entryName == backupDatabaseEntryName) {
    return true;
  }
  if (entryName.startsWith(backupMediaEntryPrefix)) {
    // 媒体条目自身仍要过路径检查：`media/../../etc/passwd` 以正确的前缀开头，
    // 但它的目标在包外。
    return isSafeBackupEntryName(entryName) &&
        entryName.length > backupMediaEntryPrefix.length;
  }
  return false;
}

/// 条目名是否**安全**（架构 5.3 的「压缩包拒绝绝对路径和路径穿越」）。
///
/// 拒绝四类（每一类都有真实的攻击/事故形态）：
///   1) 绝对路径（`/etc/passwd`、`C:\\Users\\...`）——恢复时会写到包外的绝对位置；
///   2) 任何一段是 `..` ——`media/../../x` 会跳出数据目录；
///   3) 反斜杠作为分隔符——同一串在 Windows 上是路径分隔符，在 POSIX 上是文件名的一部分，
///      放行会让「检查时看见一个名字、解开时得到另一个路径」；
///   4) 空名或只有空白、以及空段（`a//b`）——空段在各平台的归一化行为不一致。
bool isSafeBackupEntryName(String name) {
  if (name.isEmpty || name.trim().isEmpty) {
    return false;
  }
  if (name.contains('\\')) {
    return false;
  }
  if (name.startsWith('/')) {
    return false;
  }
  // Windows 盘符（`C:`），以及 UNC 风格的前缀。
  if (RegExp(r'^[A-Za-z]:').hasMatch(name)) {
    return false;
  }
  for (final String segment in name.split('/')) {
    // 空段（a//b、末尾斜杠）与 . / .. 一律拒绝：包内只写**具体文件**，而空段的归一化
    // 行为在各平台不一致（同一个名字可能解出两个不同路径）。
    if (segment.isEmpty || segment == '.' || segment == '..') {
      return false;
    }
  }
  return true;
}

/// 备份的 schema 版本能否被当前应用恢复（架构 5.3「旧版本不能写较新 schema」）。
bool backupSchemaIsRestorable({
  required int backupSchemaVersion,
  required int currentSchemaVersion,
}) => backupSchemaVersion <= currentSchemaVersion;

/// 一个包内条目在版本清单里的记录（大小 + 内容摘要）。
final class BackupEntryRecord {
  /// 构造记录。
  const BackupEntryRecord({
    required this.name,
    required this.size,
    required this.sha256,
  });

  /// 包内条目名。
  final String name;

  /// 未压缩字节数。
  final int size;

  /// 内容的 SHA-256（十六进制小写）。
  final String sha256;

  /// 规范编码。
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'size': size,
    'sha256': sha256,
  };

  /// 从清单解析；形状不对时返回 null（不用默认值凑一个条目）。
  static BackupEntryRecord? fromJson(Object? raw) {
    if (raw is! Map<String, Object?>) {
      return null;
    }
    final Object? name = raw['name'];
    final Object? size = raw['size'];
    final Object? hash = raw['sha256'];
    if (name is! String || size is! int || hash is! String) {
      return null;
    }
    if (size < 0 || hash.isEmpty) {
      return null;
    }
    return BackupEntryRecord(name: name, size: size, sha256: hash);
  }
}

/// 备份包的版本清单。
///
/// 为什么清单必须**独立于 ZIP 目录**再算一遍哈希：ZIP 的 CRC 只能发现传输损坏（它是 32 位、
/// 且某些工具会重算），而我们要回答的是「这个文件是不是导出时的那一份」。SHA-256 写在清单里，
/// 恢复时逐个比对，才是「哈希校验」这条验收的可执行形式。
final class BackupManifest {
  /// 构造清单。
  const BackupManifest({
    required this.formatVersion,
    required this.schemaVersion,
    required this.appVersion,
    required this.createdAt,
    required this.includeMedia,
    required this.entries,
    required this.articleCount,
    required this.feedCount,
  });

  /// 包结构版本。
  final int formatVersion;

  /// 导出时数据库的 schema 版本（恢复前的兼容性判据）。
  final int schemaVersion;

  /// 导出时的应用版本（仅展示与诊断）。
  final String appVersion;

  /// 导出时刻（UTC；仅展示，不参与任何判定）。
  final DateTime createdAt;

  /// 是否包含媒体目录（SET-076）。
  final bool includeMedia;

  /// 每个条目的记录（**按名字排序**，使编码确定）。
  final List<BackupEntryRecord> entries;

  /// 文章数与订阅数（恢复预览要显示「备份时间/版本/文章数」）。
  final int articleCount;

  /// 订阅数。
  final int feedCount;

  /// 规范编码（键排序、缩进固定，因此同内容同字节）。
  String encode() {
    final List<BackupEntryRecord> sorted = <BackupEntryRecord>[...entries]
      ..sort(
        (BackupEntryRecord a, BackupEntryRecord b) => a.name.compareTo(b.name),
      );
    return const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'formatVersion': formatVersion,
      'schemaVersion': schemaVersion,
      'appVersion': appVersion,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'includeMedia': includeMedia,
      'articleCount': articleCount,
      'feedCount': feedCount,
      'entries': <Object?>[
        for (final BackupEntryRecord entry in sorted) entry.toJson(),
      ],
    });
  }

  /// 解析清单。
  ///
  /// 任何结构问题（缺字段、类型不对、**更高的包结构版本**、条目名不安全）都返回 null：
  /// 调用方据此给出「这个包读不懂」而不是用默认值凑一份清单——后者会让恢复在半途失败，
  /// 而失败之前可能已经清掉了目标目录里的东西。
  static BackupManifest? decode(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    final Object? formatVersion = decoded['formatVersion'];
    final Object? schemaVersion = decoded['schemaVersion'];
    final Object? appVersion = decoded['appVersion'];
    final Object? createdAt = decoded['createdAt'];
    final Object? includeMedia = decoded['includeMedia'];
    final Object? articleCount = decoded['articleCount'];
    final Object? feedCount = decoded['feedCount'];
    final Object? rawEntries = decoded['entries'];
    if (formatVersion is! int ||
        schemaVersion is! int ||
        appVersion is! String ||
        createdAt is! String ||
        includeMedia is! bool ||
        articleCount is! int ||
        feedCount is! int ||
        rawEntries is! List<Object?>) {
      return null;
    }
    if (formatVersion != backupFormatVersion) {
      return null;
    }
    final DateTime? created = DateTime.tryParse(createdAt);
    if (created == null) {
      return null;
    }
    final List<BackupEntryRecord> entries = <BackupEntryRecord>[];
    for (final Object? raw in rawEntries) {
      final BackupEntryRecord? entry = BackupEntryRecord.fromJson(raw);
      if (entry == null) {
        return null;
      }
      if (!backupEntryAllowed(entry.name)) {
        // 清单里出现白名单之外的条目 = 这个包不属于本应用（或被改过）。
        return null;
      }
      entries.add(entry);
    }
    return BackupManifest(
      formatVersion: formatVersion,
      schemaVersion: schemaVersion,
      appVersion: appVersion,
      createdAt: created.toUtc(),
      includeMedia: includeMedia,
      entries: entries,
      articleCount: articleCount,
      feedCount: feedCount,
    );
  }
}

/// 恢复失败的原因类别（**稳定英文标识**：进诊断与状态，不进界面文案）。
///
/// 为什么必须分类而不是一句「恢复失败」：这些失败的**处置方式不同**——路
/// 径穿越是安全事件（包不可信），schema 较新是「请升级应用」，哈希不符是包损坏
/// （重新导出一份即可），而磁盘不足要用户腾空间。合成一句话会让用户无从下手。
enum BackupFailureKind {
  /// 用户取消（不是错误）。
  cancelled,

  /// 压缩包无法解析（截断、不是 ZIP、CRC 不符）。
  corruptArchive,

  /// 缺少版本清单。
  manifestMissing,

  /// 清单读不懂（结构问题或更高的包结构版本）。
  manifestUnreadable,

  /// 条目名不安全（绝对路径/路径穿越/反斜杠）。
  unsafeEntryPath,

  /// 出现白名单之外的条目。
  disallowedEntry,

  /// 缺数据库快照。
  databaseEntryMissing,

  /// 条目大小与清单不符。
  sizeMismatch,

  /// 条目哈希与清单不符。
  hashMismatch,

  /// 备份的 schema 比当前应用更新（旧版本不能写较新 schema）。
  schemaTooNew,

  /// 校验通过但写入新目录失败（磁盘不足、权限）。
  writeFailed,

  /// 校验通过但恢复出来的库打不开（结构损坏或迁移失败）。
  restoredDatabaseUnusable,

  /// 切换失败（重命名失败）；**原库必须仍在原位**。
  switchFailed,
}

/// 恢复失败的原因是否是「包不可信」（安全类）。
bool isBackupSecurityFailure(BackupFailureKind kind) =>
    kind == BackupFailureKind.unsafeEntryPath ||
    kind == BackupFailureKind.disallowedEntry;

/// 一次恢复的**预检结论**（用户第二次确认前要看到的那份信息）。
final class BackupRestorePreview {
  /// 构造预检结论。
  const BackupRestorePreview({
    required this.manifest,
    required this.archiveBytes,
    required this.entryCount,
  });

  /// 包内清单。
  final BackupManifest manifest;

  /// 压缩包总字节数。
  final int archiveBytes;

  /// 包内条目数（含清单自身）。
  final int entryCount;

  /// 备份时间（本地时区展示由界面负责）。
  DateTime get createdAt => manifest.createdAt;

  /// 备份的 schema 版本。
  int get schemaVersion => manifest.schemaVersion;

  /// 备份里的文章数与订阅数。
  int get articleCount => manifest.articleCount;

  /// 订阅数。
  int get feedCount => manifest.feedCount;

  /// 是否含媒体。
  bool get includeMedia => manifest.includeMedia;
}
