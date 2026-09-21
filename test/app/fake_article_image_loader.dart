// 测试用的图片加载替身（T021）。
//
// 存在的理由：图片位现在是真实控件（走缓存管线），而绝大多数用例关心的是卡片布局、
// 阅读器排版或 golden，不是网络。若不注入替身，每个用例都会真的去解析
// cdn.example.com 并发起请求——在离线 CI 上会挂到超时，在有网的机器上则测试速度与
// 结果都取决于外部服务。
//
// 两个替身：
//   - [OfflineArticleImageLoader]：一律失败（默认注入）。这是**诚实**的替身——图片位
//     在两个实现下的失败分支是产品行为的一部分（占位 + 重试），而「假装加载成功」会
//     让用例看不到那条分支；
//   - [FixedArticleImageLoader]：返回固定字节，用于验证「加载成功」的路径。
library;

import 'dart:typed_data';

import 'package:flux/core/core.dart';
import 'package:flux/features/articles/application/article_image_ports.dart';

/// 一律失败的加载器（不联网）。
///
/// 刻意**不可 const 构造**：图片 Provider 的缓存键含加载器身份，而 ImageCache 是
/// 全局的。共用同一个实例会让不同用例在同一个键上互相复用残留条目。
final class OfflineArticleImageLoader implements ArticleImageLoader {
  @override
  Future<Result<LoadedImage>> load(String url) async =>
      Err<LoadedImage>(NetworkError(uri: url, reason: '测试替身：不发起网络请求'));

  @override
  Future<Result<int>> saveToPath({
    required String url,
    required String targetPath,
  }) async =>
      Err<int>(StorageError(operation: 'testImageSave', detail: '测试替身：不写文件'));

  @override
  Future<void> applyCacheLimitMiB(int limitMiB) async {}
}

/// 返回固定字节的加载器（用于验证成功路径）。
final class FixedArticleImageLoader implements ArticleImageLoader {
  /// 构造替身。
  FixedArticleImageLoader({
    required this.bytes,
    this.width = 1,
    this.height = 1,
  });

  /// 要返回的字节。
  final Uint8List bytes;

  /// 声明宽。
  final int width;

  /// 声明高。
  final int height;

  /// 被请求过的地址（用例据此断言「确实只请求了一次」）。
  final List<String> requested = <String>[];

  /// 套用过的上限（用例据此断言 SET-080 真的生效）。
  final List<int> appliedLimits = <int>[];

  @override
  Future<Result<LoadedImage>> load(String url) async {
    requested.add(url);
    return Ok<LoadedImage>(
      LoadedImage(
        bytes: bytes,
        mimeType: 'image/png',
        width: width,
        height: height,
      ),
    );
  }

  @override
  Future<Result<int>> saveToPath({
    required String url,
    required String targetPath,
  }) async => Ok<int>(bytes.length);

  @override
  Future<void> applyCacheLimitMiB(int limitMiB) async {
    appliedLimits.add(limitMiB);
  }
}

/// 一张 1×1 的合法 PNG（魔数与 IHDR 都正确，可被嗅探与解码）。
final Uint8List kTestPngBytes = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);
