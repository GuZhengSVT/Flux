// 图片保存适配器（T020）：HTTP 下载 + 系统保存面板。
//
// 两步都必须在基础设施层：
//   1) 下载要 http（features 不得 import package:http，架构 2.2 的守卫会拦）；
//   2) 选保存位置要 file_selector 的系统面板（macOS 上是 NSSavePanel）。
//
// 三条与产品规则对应的边界：
//   - **大小上限**：下载前用 content-length 预检、读流时再计数。一张「图片」请求回来的
//     可能是几百 MB 的文件或一个无限流；没有上限的话，用户点一次保存就能把内存吃干净。
//     真正的 MIME/尺寸/解码限额与缓存属 T021，这里只保证不无上限地把响应读进内存；
//   - **用户取消不是错误**：面板取消返回 Ok(null)，界面不提示（把取消做成失败会让
//     一次误解变成一条红色提示）；
//   - **权限拒绝是类型化失败**：目标路径不可写（只读卷、权限不足）翻译成 StorageError，
//     由界面提示，而不是抛一个平台异常。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;

import 'package:flux/core/core.dart';
import 'package:flux/features/articles/application/article_platform_ports.dart';

/// 单张图片的下载上限。
///
/// 16 MiB：足够任何网页配图，同时挡住「把整部视频当图片保存」这类误操作。可配置化属
/// T021（媒体大小限制），本任务先给一个不无上限的硬边界。
const int kMaxDownloadBytes = 16 * 1024 * 1024;

/// 图片类型过滤（保存面板的默认类型）。
const XTypeGroup imageTypeGroup = XTypeGroup(
  label: 'Image',
  extensions: <String>['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'],
  uniformTypeIdentifiers: <String>['public.image'],
);

/// 下载并按用户选择的位置保存图片。
final class HttpImageSaveService implements ImageSaveService {
  /// 构造适配器。
  const HttpImageSaveService({this.client});

  /// 注入的 HTTP 客户端（测试用 MockClient 替换；生产用默认客户端）。
  final http.Client? client;

  @override
  Future<Result<String?>> saveImage({
    required String url,
    required String suggestedName,
  }) async {
    // 与打开链接同一条理由：不该把一个非 http(s) 地址交给下载器。
    if (!isSafeDocUrl(url)) {
      return Err<String?>(
        StorageError(operation: 'imageSave', detail: '地址协议不被允许'),
      );
    }
    final http.Client? injected = client;
    final http.Client effective = injected ?? http.Client();
    try {
      final Uint8List bytes = await _download(effective, url);
      if (bytes.isEmpty) {
        return Err<String?>(
          StorageError(operation: 'imageSave', detail: '响应为空'),
        );
      }
      // 先让用户选位置**再**写文件：顺序反过来会出现「文件还没落地就提示成功」。
      final FileSaveLocation? location = await getSaveLocation(
        suggestedName: suggestedName,
        acceptedTypeGroups: const <XTypeGroup>[imageTypeGroup],
      );
      if (location == null) {
        // 取消：Ok(null)，不是错误。
        return const Ok<String?>(null);
      }
      final XFile file = XFile.fromData(
        bytes,
        name: suggestedName,
        mimeType: 'application/octet-stream',
      );
      await file.saveTo(location.path);
      return Ok<String?>(location.path);
    } on AppError catch (error) {
      // 下载阶段抛出的类型化失败（大小超限、HTTP 非 2xx）原样返回：它已经带了具体的
      // 原因，被下面的通用分支重新包一层会把原因换成异常的 runtimeType（实测就是这样
      // 变成一句无信息的「StorageError」）。
      return Err<String?>(error);
    } on FileSystemException catch (error, stackTrace) {
      // 权限拒绝 / 目标不可写：**类型化失败并保留原因类别**，界面据此提示。
      return Err<String?>(
        StorageError(
          operation: 'imageSave',
          detail: error.osError?.errorCode == 13 ? 'permission denied' : 'io',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    } on Exception catch (error, stackTrace) {
      return Err<String?>(
        StorageError(
          operation: 'imageSave',
          detail: error.runtimeType.toString(),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    } finally {
      // 只关闭自己建的客户端；注入的客户端由调用方（测试）负责。
      if (injected == null) {
        effective.close();
      }
    }
  }

  /// 下载并做大小上限检查。
  Future<Uint8List> _download(http.Client client, String url) async {
    final http.StreamedResponse response = await client.send(
      http.Request('GET', Uri.parse(url)),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StorageError(
        operation: 'imageSave',
        detail: 'HTTP ${response.statusCode}',
      );
    }
    // 声明长度先预检：这样大文件在读完之前就被拒绝。
    final int? declared = response.contentLength;
    if (declared != null && declared > kMaxDownloadBytes) {
      throw StorageError(operation: 'imageSave', detail: '声明长度超过上限');
    }
    final BytesBuilder builder = BytesBuilder(copy: false);
    await for (final List<int> chunk in response.stream) {
      builder.add(chunk);
      if (builder.length > kMaxDownloadBytes) {
        // 未声明长度但实际超限：中止读取，而不是继续读到内存里再判断。
        throw StorageError(operation: 'imageSave', detail: '实际长度超过上限');
      }
    }
    return builder.takeBytes();
  }
}
