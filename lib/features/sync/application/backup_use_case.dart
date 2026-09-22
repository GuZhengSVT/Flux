// 明文备份导出与安全恢复（T046；架构 5.3 的备份/恢复段、SET-076）。
//
// 两条流程各自的承诺：
//
// **导出**：一致性快照（VACUUM INTO，不是复制活动库）→ ZIP（快照 + 版本清单 + 每文件 SHA-256
// + 可选媒体）→ 排除凭据。三件事都在这个用例里定，因此「包里有密码」不可能由某一条分支悄悄
// 发生：进入包的条目只有快照、清单与媒体缓存，而快照本身**不含任何凭据列**（Keychain 只在系统
// 钥匙串里，SET-071 与 SET-027 的秘密从不落库）。
//
// **恢复**：选文件 → 校验（路径/白名单/清单/schema/大小/哈希，**全部先于任何写操作**）→ 恢复到
// **新目录**（不动原库）→ 校验新库可用 → 交给调用方切换。任何一步失败都返回分类错误且原库不受
// 影响；「失败不动原库」是结构性的：本用例没有任何写到原数据目录的语句。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flux/core/core.dart';
import 'package:flux/core/app_metadata.dart';

import '../../feeds/application/file_access.dart';
import 'backup_ports.dart';

/// 一次导出的结果。
final class BackupExportResult {
  /// 构造结果。
  const BackupExportResult({
    required this.path,
    required this.bytes,
    required this.entryCount,
    required this.includeMedia,
    required this.mediaEntryCount,
  });

  /// 用户选定的保存路径。
  final String path;

  /// 包的总字节数（界面显示「导出了多大一份」）。
  final int bytes;

  /// 包内条目数（含清单）。
  final int entryCount;

  /// 是否含媒体。
  final bool includeMedia;

  /// 媒体条目数（不含媒体时为 0）。
  final int mediaEntryCount;
}

/// 一次预检的结论：给用户看的预览 + **当时读到的字节**。
///
/// 为什么必须把字节一起带出来：用户确认的依据是预览里那份「备份时间/版本/文章数」，而恢复
/// 必须用**同一份字节**。若恢复时重新读一遍文件，用户在这两次点击之间把文件换掉（或文件被
/// 别的程序改写）时，被恢复的就是一份他从未看过的东西。
final class BackupInspection {
  /// 构造预检结论。
  const BackupInspection({required this.preview, required this.archiveBytes});

  /// 给用户看的预览。
  final BackupRestorePreview preview;

  /// 预检时读到的包字节。
  final Uint8List archiveBytes;
}

/// 一次恢复的结论。
final class BackupRestoreResult {
  /// 构造结论。
  const BackupRestoreResult({required this.directory, required this.preview});

  /// 恢复出来的**新数据目录**（调用方据此切换）。
  final String directory;

  /// 预检结论（界面在切换前再次确认时展示）。
  final BackupRestorePreview preview;
}

/// 备份导出与恢复用例。
final class BackupUseCase {
  /// 构造用例。
  const BackupUseCase({
    required this.content,
    required this.restoreTarget,
    required this.files,
    required this.currentSchemaVersion,
    this.diagnostics = const NoopDiagnosticSink(),
    this.clock = const SystemClock(),
  });

  /// 备份内容来源（一致性快照、计数、媒体缓存）。
  final BackupContentSource content;

  /// 恢复目标（写新目录并校验）。
  final BackupRestoreTarget restoreTarget;

  /// 文件选择与保存（复用 T015 的端口：用户经系统面板明确授权的那两个动作）。
  final FileAccessPort files;

  /// 当前应用的 schema 版本（由组合根从打开的数据库读出）。
  ///
  /// 由外部传入而不是在这里写一个常量：schema 版本只有一处定义（AppDatabase.schemaVersion），
  /// 在备份校验里再抄一个数字，迟早在某次迁移后只剩一处被更新——而那时的症状是
  /// 「较新的备份被当成可以恢复」，进而写出一份当前应用读不了的库。
  final int currentSchemaVersion;

  /// 诊断记录（只记数量与类别，不记正文与路径）。
  final DiagnosticSink diagnostics;

  /// 时钟（写清单里的导出时刻；**不参与任何判定**）。
  final Clock clock;

  // -------------------------------------------------------------------------
  // 导出
  // -------------------------------------------------------------------------

  /// 导出明文备份；用户取消保存时返回 `Ok(null)`。
  ///
  /// [includeMedia] 来自 SET-076（默认不含媒体）：媒体是缓存，体积通常是数据库的数倍，
  /// 而它可以从源重新下载——把它默认打进包里会让「导出一次备份」变成一件要等很久的事。
  Future<Result<BackupExportResult?>> export({
    required bool includeMedia,
    required String suggestedName,
  }) async {
    // 1) 一致性快照（**先于**问用户保存位置：快照可能失败，而让用户先选完文件再报错
    //    会让他以为自己选错了地方）。
    final Result<Uint8List> snapshot = await content.snapshotDatabase();
    if (snapshot.isErr) {
      return Err<BackupExportResult?>(snapshot.errorOrNull!);
    }
    final Result<int> schema = await content.schemaVersion();
    if (schema.isErr) {
      return Err<BackupExportResult?>(schema.errorOrNull!);
    }
    final Result<({int articles, int feeds})> counts = await content
        .contentCounts();
    if (counts.isErr) {
      return Err<BackupExportResult?>(counts.errorOrNull!);
    }

    final List<BackupArchiveEntry> entries = <BackupArchiveEntry>[
      BackupArchiveEntry(
        name: backupDatabaseEntryName,
        bytes: snapshot.unwrap(),
      ),
    ];
    if (includeMedia) {
      final Result<List<MediaCacheEntry>> media = await content
          .readMediaCache();
      if (media.isErr) {
        return Err<BackupExportResult?>(media.errorOrNull!);
      }
      for (final MediaCacheEntry cache in media.unwrap()) {
        entries.add(
          BackupArchiveEntry(
            name: '$backupMediaEntryPrefix${cache.relativePath}',
            bytes: cache.bytes,
          ),
        );
      }
    }

    // 2) 清单：每个条目一条记录（大小 + SHA-256），并带上恢复预览需要的元数据。
    final BackupManifest manifest = BackupManifest(
      formatVersion: backupFormatVersion,
      schemaVersion: schema.unwrap(),
      appVersion: fluxAppVersion,
      createdAt: clock.now().toUtc(),
      includeMedia: includeMedia,
      entries: backupEntryRecordsOf(entries),
      articleCount: counts.unwrap().articles,
      feedCount: counts.unwrap().feeds,
    );
    final List<BackupArchiveEntry> withManifest = <BackupArchiveEntry>[
      BackupArchiveEntry(
        name: backupManifestFileName,
        bytes: Uint8List.fromList(utf8.encode(manifest.encode())),
      ),
      ...entries,
    ];

    // 3) 打进 ZIP 并交给用户选位置。
    final Uint8List archive = zipEncode(<ZipEntry>[
      for (final BackupArchiveEntry entry in withManifest)
        ZipEntry(name: entry.name, bytes: entry.bytes),
    ]);
    final Result<String?> saved = await files.saveBytes(
      suggestedName,
      archive,
      mimeType: 'application/zip',
      extensions: const <String>['zip'],
    );
    if (saved.isErr) {
      return Err<BackupExportResult?>(saved.errorOrNull!);
    }
    final String? path = saved.valueOrNull;
    if (path == null) {
      // 用户取消：不是错误。
      return const Ok<BackupExportResult?>(null);
    }
    final int mediaEntryCount = entries
        .where(
          (BackupArchiveEntry e) => e.name.startsWith(backupMediaEntryPrefix),
        )
        .length;
    diagnostics.info(
      '导出明文备份：${withManifest.length} 个条目，媒体 ${includeMedia ? mediaEntryCount : 0} 个',
      tag: 'backup.export',
    );
    return Ok<BackupExportResult?>(
      BackupExportResult(
        path: path,
        bytes: archive.length,
        entryCount: withManifest.length,
        includeMedia: includeMedia,
        mediaEntryCount: mediaEntryCount,
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 恢复
  // -------------------------------------------------------------------------

  /// 选一个备份文件并做**只读**预检；用户取消时返回 `Ok(null)`。
  ///
  /// 预检不写任何东西（连临时目录都不建）：界面要能先告诉用户「这份包是什么时候的、
  /// 里面有几百篇文章」，而他此刻还没决定要不要恢复。
  Future<Result<BackupInspection?>> inspectBackup() async {
    final Result<PickedFile?> picked = await files.pickArchiveToRead();
    if (picked.isErr) {
      return Err<BackupInspection?>(picked.errorOrNull!);
    }
    final PickedFile? file = picked.valueOrNull;
    if (file == null) {
      return const Ok<BackupInspection?>(null);
    }
    final Uint8List bytes = Uint8List.fromList(file.bytes);
    final Result<BackupRestorePreview> inspected = inspectArchiveBytes(bytes);
    if (inspected.isErr) {
      // 预检失败：连一次写入都还没发生，因此不存在「原库被破坏」的可能。
      return Err<BackupInspection?>(inspected.errorOrNull!);
    }
    return Ok<BackupInspection?>(
      BackupInspection(preview: inspected.unwrap(), archiveBytes: bytes),
    );
  }

  /// 用一个**已经预检过**的包执行恢复：写新目录 → 校验新库 → 返回新目录。
  ///
  /// [preview] 必须来自 [inspectBackup]（或同一次解析）：恢复路径**不**重新解一遍包，
  /// 否则「用户看到的那份预览」与「实际恢复的那份包」可能是两个不同的文件（用户在两次
  /// 点击之间把文件换掉了），而他确认的依据是前者的内容。
  Future<Result<BackupRestoreResult>> restore({
    required BackupRestorePreview preview,
    required Uint8List archiveBytes,
    required String targetDirectory,
    bool includeMedia = true,
    void Function(double progress)? onProgress,
  }) async {
    final Result<BackupValidation> validated = validateArchiveBytes(
      archiveBytes,
    );
    if (validated.isErr) {
      return Err<BackupRestoreResult>(validated.errorOrNull!);
    }
    final BackupValidation validation = validated.unwrap();
    if (!validation.isOk) {
      return Err<BackupRestoreResult>(_validationError(validation));
    }
    onProgress?.call(0.3);

    // 只写**已校验过**的内容；不含媒体时把媒体条目丢掉（SET-076 的开关对恢复同样有效：
    // 一个只想拿回订阅与状态的人不该被迫写几个 GB 的图片缓存）。
    final List<MediaCacheEntry> media = <MediaCacheEntry>[];
    if (includeMedia && validation.mediaEntryCount > 0) {
      final List<ZipDecodedEntry> decoded = _decodeOrThrow(archiveBytes);
      for (final ZipDecodedEntry entry in decoded) {
        if (!entry.name.startsWith(backupMediaEntryPrefix)) {
          continue;
        }
        media.add(
          MediaCacheEntry(
            relativePath: entry.name.substring(backupMediaEntryPrefix.length),
            bytes: entry.bytes,
          ),
        );
      }
    }

    final Result<void> written = await restoreTarget.writeRestoredData(
      directory: targetDirectory,
      databaseBytes: validation.databaseBytes,
      media: media,
    );
    if (written.isErr) {
      return Err<BackupRestoreResult>(written.errorOrNull!);
    }
    onProgress?.call(0.8);

    // 写入完成 ≠ 恢复成功：必须能真的打开它（与清单声明的 schema 一致）。
    final Result<void> verified = await restoreTarget.verifyRestoredData(
      directory: targetDirectory,
      expectedSchemaVersion: validation.manifest!.schemaVersion,
    );
    if (verified.isErr) {
      return Err<BackupRestoreResult>(verified.errorOrNull!);
    }
    onProgress?.call(1);
    diagnostics.info(
      '恢复到新目录：${validation.manifest!.articleCount} 篇文章、${media.length} 个媒体文件',
      tag: 'backup.restore',
    );
    return Ok<BackupRestoreResult>(
      BackupRestoreResult(directory: targetDirectory, preview: preview),
    );
  }

  /// 只读预检（供界面在选完文件后立刻展示备份时间/版本/文章数）。
  Result<BackupRestorePreview> inspectArchiveBytes(Uint8List archiveBytes) {
    final Result<BackupValidation> validated = validateArchiveBytes(
      archiveBytes,
    );
    if (validated.isErr) {
      return Err<BackupRestorePreview>(validated.errorOrNull!);
    }
    final BackupValidation validation = validated.unwrap();
    if (!validation.isOk) {
      return Err<BackupRestorePreview>(_validationError(validation));
    }
    return Ok<BackupRestorePreview>(
      BackupRestorePreview(
        manifest: validation.manifest!,
        archiveBytes: archiveBytes.length,
        entryCount: validation.mediaEntryCount + 2,
      ),
    );
  }

  /// 校验包字节：解 ZIP → 逐项校验。
  Result<BackupValidation> validateArchiveBytes(Uint8List archiveBytes) {
    final List<ZipDecodedEntry>? decoded = zipDecode(archiveBytes);
    if (decoded == null) {
      return Err<BackupValidation>(
        _backupError(BackupFailureKind.corruptArchive),
      );
    }
    final BackupValidation validation = validateBackupArchive(
      <BackupArchiveEntry>[
        for (final ZipDecodedEntry entry in decoded)
          BackupArchiveEntry(name: entry.name, bytes: entry.bytes),
      ],
      currentSchemaVersion: currentSchemaVersion,
    );
    if (!validation.isOk) {
      return Err<BackupValidation>(_validationError(validation));
    }
    return Ok<BackupValidation>(validation);
  }

  /// 把一次校验失败翻译成类型化错误（带**稳定类别名**，供界面分类展示）。
  static AppError _validationError(BackupValidation validation) =>
      _backupError(validation.failureKind!, entry: validation.failingEntry);

  static AppError _backupError(BackupFailureKind kind, {String? entry}) =>
      ValidationError(field: 'backupRestore', reason: kind.name, value: entry);

  /// 解包（已校验过时会成功；否则抛类型化错误由调用方兜住）。
  static List<ZipDecodedEntry> _decodeOrThrow(Uint8List bytes) {
    final List<ZipDecodedEntry>? decoded = zipDecode(bytes);
    if (decoded == null) {
      throw _backupError(BackupFailureKind.corruptArchive);
    }
    return decoded;
  }
}
