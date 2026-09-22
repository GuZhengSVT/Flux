// 文件读写端口（T015）。
//
// 为什么需要这一层：导入要打开文件、导出要保存文件，而这两件事依赖 file_selector
// （平台通道）。features 层不得 import infrastructure（架构 2.2，测试会拦截），
// 因此这里定义最小端口，由 infrastructure 适配；测试注入内存实现即可。
//
// 端口只做「选文件并读文本」与「选位置并写文本」，**不暴露路径以外的任何平台
// 能力**：页面对文件系统的全部需求就是这两件事，收窄接口可以避免后续顺手拿它
// 做别的事（例如扫描目录）。
library;

import 'package:flux/core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 用户选中的一个文件。
class PickedFile {
  /// 构造选中文件。
  const PickedFile({
    required this.path,
    required this.content,
    this.bytes = const <int>[],
  });

  /// 文件路径（仅用于显示与诊断，不写进数据库）。
  final String path;

  /// 文件文本内容。
  final String content;

  /// 文件原始字节（T046 的备份包是二进制）。
  ///
  /// 与 [content] 并列而不是只留一个：OPML 是文本，用文本读更省事也更可断言；而 ZIP 用
  /// 文本读会**破坏内容**（非法 UTF-8 序列会被替换字符改写），因此二进制入口必须存在，
  /// 且两者不能互相冒充。
  final List<int> bytes;
}

/// 文件读写端口。
abstract interface class FileAccessPort {
  /// 让用户选一个 OPML 文件并读回文本；用户取消时返回 `Ok(null)`。
  ///
  /// 「取消」不是错误，因此用 null 而不是诊断性错误：把取消做成错误会让调用方
  /// 不得不为一条正常路径写错误处理分支。
  Future<Result<PickedFile?>> pickOpmlToRead();

  /// 让用户选保存位置并写文本；用户取消时返回 `Ok(null)`；返回值为最终路径。
  Future<Result<String?>> saveOpml(String suggestedName, String content);

  /// 让用户选一个**二进制**文件并读回字节（T046 的备份包）；取消时返回 `Ok(null)`。
  Future<Result<PickedFile?>> pickArchiveToRead();

  /// 让用户选保存位置并写**字节**（T046 的备份包）；取消时返回 `Ok(null)`；返回最终路径。
  Future<Result<String?>> saveBytes(
    String suggestedName,
    List<int> bytes, {
    required String mimeType,
    required List<String> extensions,
  });
}

/// 文件端口（由组合根注入平台实现）。
final Provider<FileAccessPort> fileAccessProvider = Provider<FileAccessPort>(
  (Ref ref) => throw StateError(
    'fileAccessProvider 未被组合根覆盖：见 lib/app/app_bootstrap.dart',
  ),
);
