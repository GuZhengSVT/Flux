// 文件读写适配器（T015）：把 file_selector 接到 FileAccessPort。
//
// 隔离在这里的理由与 T013 的 HTTP 适配器相同：features 层不得 import 平台包。
//
// 关于 macOS 沙盒：file_selector 通过系统面板（NSOpenPanel/NSSavePanel）返回用户
// 明确授权的文件，应用因此可以读写它，无需额外的沙盒豁免。反过来，**不能**用
// 它去访问用户没有选中的路径——那正是这个端口只暴露「选一个文件」两个动作的原因。
//
// 读文件失败（权限、编码、磁盘）统一翻译为 StorageError；解码用宽松模式并把 BOM
// 交给 Dart 的 utf8 处理（file_selector 返回的 XFile 已按平台解码为 String）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import 'package:flux/core/core.dart';
import 'package:flux/features/feeds/application/file_access.dart';

/// OPML 文件类型过滤（按扩展名与 MIME）。
const XTypeGroup opmlTypeGroup = XTypeGroup(
  label: 'OPML',
  extensions: <String>['opml', 'xml'],
  mimeTypes: <String>['text/x-opml', 'application/xml', 'text/xml'],
  uniformTypeIdentifiers: <String>['public.xml'],
);

/// 备份包的类型过滤（T046）。
///
/// 只按扩展名与 MIME 过滤，**不**限制 uniformTypeIdentifiers：ZIP 在各平台上的 UTI 不一致
/// （macOS 的 public.zip-archive 之外还有若干归档 UTI），把过滤器收得太紧会让「自己刚导出的
/// 那个包」在面板里变成不可选——而用户会以为是文件坏了。
const XTypeGroup zipTypeGroup = XTypeGroup(
  label: 'ZIP',
  extensions: <String>['zip'],
  mimeTypes: <String>['application/zip', 'application/x-zip-compressed'],
);

/// 用系统文件面板实现文件读写。
final class FileSelectorAccess implements FileAccessPort {
  /// 构造适配器。
  const FileSelectorAccess();

  @override
  Future<Result<PickedFile?>> pickOpmlToRead() async {
    try {
      final XFile? file = await openFile(
        acceptedTypeGroups: const <XTypeGroup>[opmlTypeGroup],
      );
      if (file == null) {
        return const Ok<PickedFile?>(null);
      }
      final String content = await file.readAsString();
      return Ok<PickedFile?>(PickedFile(path: file.path, content: content));
    } on Exception catch (error, stackTrace) {
      return Err<PickedFile?>(
        StorageError(
          operation: 'opml.pickToRead',
          // 只保留异常类型：平台异常文本可能含完整路径与用户目录结构。
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<String?>> saveOpml(String suggestedName, String content) async {
    try {
      final FileSaveLocation? location = await getSaveLocation(
        suggestedName: suggestedName,
        acceptedTypeGroups: const <XTypeGroup>[opmlTypeGroup],
      );
      if (location == null) {
        return const Ok<String?>(null);
      }
      final XFile file = XFile.fromData(
        Uint8List.fromList(utf8.encode(content)),
        mimeType: 'text/x-opml',
        name: suggestedName,
      );
      await file.saveTo(location.path);
      return Ok<String?>(location.path);
    } on Exception catch (error, stackTrace) {
      return Err<String?>(
        StorageError(
          operation: 'opml.save',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<PickedFile?>> pickArchiveToRead() async {
    try {
      final XFile? file = await openFile(
        acceptedTypeGroups: const <XTypeGroup>[zipTypeGroup],
      );
      if (file == null) {
        return const Ok<PickedFile?>(null);
      }
      // 用 readAsBytes 而不是 readAsString：ZIP 里常有非法 UTF-8 序列，文本读会被替换字符
      // 改写，于是「校验哈希」必然失败——而失败原因是工具读坏了自己的文件。
      final Uint8List bytes = await file.readAsBytes();
      return Ok<PickedFile?>(
        PickedFile(path: file.path, content: '', bytes: bytes),
      );
    } on Exception catch (error, stackTrace) {
      return Err<PickedFile?>(
        StorageError(
          operation: 'backup.pickToRead',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<String?>> saveBytes(
    String suggestedName,
    List<int> bytes, {
    required String mimeType,
    required List<String> extensions,
  }) async {
    try {
      final FileSaveLocation? location = await getSaveLocation(
        suggestedName: suggestedName,
        acceptedTypeGroups: <XTypeGroup>[
          XTypeGroup(
            label: 'ZIP',
            extensions: extensions,
            mimeTypes: <String>[mimeType],
          ),
        ],
      );
      if (location == null) {
        return const Ok<String?>(null);
      }
      final XFile file = XFile.fromData(
        Uint8List.fromList(bytes),
        mimeType: mimeType,
        name: suggestedName,
      );
      await file.saveTo(location.path);
      return Ok<String?>(location.path);
    } on Exception catch (error, stackTrace) {
      return Err<String?>(
        StorageError(
          operation: 'backup.save',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}
