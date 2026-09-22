// 明文备份与恢复的端口与规划（T046；架构 5.3 的备份/恢复段、SET-076）。
//
// 为什么端口住在 features 而不是让用例直接读文件：features 不得 import infrastructure
// （架构 2.2，有回归守卫）。这里定义的是「备份需要外部提供什么」——一个**一致性数据库快照**、
// 一个可选的媒体目录清单、以及写/读文件的能力——由组合根注入实现。
//
// 三条刻意的设计：
//   1) **快照必须是「一次一致性读」而不是文件复制**。复制活动数据库会漏掉 WAL 里已提交但尚未
//      落盘的页（架构 5.3 明确点名）。因此端口只接受「给我一份一致的快照字节」，具体怎么做
//      （VACUUM INTO / backup API）由基础设施决定，用例不猜；
//   2) **凭据不出现在这个端口的签名里**。备份需要的一切都是文件与计数，因此「备份顺手带上了
//      密码」在这条路径上不可表达；
//   3) **恢复到新目录**：端口接受一个**目标目录**，并且不提供「就地覆盖」的入口。恢复的实现只能
//      写到调用方给它的新目录里，切换是另一件事（见 use case 的说明）。
library;

import 'dart:typed_data';

import 'package:flux/core/core.dart';

/// 媒体目录里的一个文件（相对路径 + 内容）。
final class MediaCacheEntry {
  /// 构造条目。
  const MediaCacheEntry({required this.relativePath, required this.bytes});

  /// 相对媒体目录的路径（正斜杠分隔；导出时会加上 `media/` 前缀）。
  final String relativePath;

  /// 文件内容。
  final Uint8List bytes;
}

/// 备份内容读取端口（由 infrastructure/local 实现）。
abstract interface class BackupContentSource {
  /// 取一份**一致性**的数据库快照字节。
  ///
  /// 实现必须使用 SQLite 的备份机制（VACUUM INTO 或 backup API），**不得**直接复制活动
  /// 数据库文件：WAL 模式下已提交的页可能仍在 -wal 里，复制的文件会缺它们（架构 5.3）。
  Future<Result<Uint8List>> snapshotDatabase();

  /// 当前数据库的 schema 版本。
  Future<Result<int>> schemaVersion();

  /// 文章数与订阅数（写进清单，供恢复预览显示）。
  Future<Result<({int articles, int feeds})>> contentCounts();

  /// 读媒体缓存目录里的全部文件（SET-076 的「含媒体」开关打开时才调用）。
  ///
  /// 只读**缓存条目文件**（图片与其元数据），不读临时文件（`.part`）：把半成品打进
  /// 备份会让恢复出来的缓存里出现一批永远解不开的文件。
  Future<Result<List<MediaCacheEntry>>> readMediaCache();
}

/// 恢复目标端口（由 infrastructure/local 实现）。
abstract interface class BackupRestoreTarget {
  /// 在 [directory] 下写入数据库快照与媒体文件。
  ///
  /// [directory] 必须是**一个尚未存在或为空**的新目录：写到已有数据目录上会让「失败不动
  /// 原库」这条承诺失效（写到一半失败时原库已经被部分覆盖）。
  Future<Result<void>> writeRestoredData({
    required String directory,
    required Uint8List databaseBytes,
    required List<MediaCacheEntry> media,
  });

  /// 校验 [directory] 下的恢复结果确实可用（能打开、schema 与清单一致）。
  ///
  /// 这一步不是「顺手检查」：架构 5.3 要求「恢复到干净目录成功」，而「写完了文件」与
  /// 「这是一个能用的库」是两件事——文件写全但库结构损坏时，用户会以为恢复成功并重启，
  /// 而重启后应用报「数据库损坏」。
  Future<Result<void>> verifyRestoredData({
    required String directory,
    required int expectedSchemaVersion,
  });

  /// 基础数据目录（「.../Flux」）。
  String? get dataDirectoryPath;

  /// 媒体缓存目录名（相对数据目录，当前是 `media`）。
  String get mediaDirectoryName;
}
