// 媒体缓存策略（T021；架构 4.2「图片按需缓存、预留尺寸、失败不阻塞文章」与
// SET-080「媒体缓存上限 512 MiB，允许 128–4096」）。
//
// 为什么策略（纯函数）与缓存实现（文件 I/O）分开：这些规则是**可断言的规则**，
// 不是实现细节。「默认 4 MiB 上限」「MIME 白名单」「LRU 上限取 SET-080 的值并夹紧
// 到 128–4096」都应该能用纯 Dart 逐条断言，而把它们埋在文件读写里就只能靠一个
// 临时目录 + 真实 I/O 去验证，测试慢且脆弱。
//
// 三件事在这里定义：
//   1) 允许的图片 MIME（白名单，不是黑名单——黑名单总会漏掉新的可执行类型）；
//   2) 单图字节上限（对齐 SET-065 的 4 MiB，但独立成常量：图像分析的上传上限与
//      阅读时缓存的图片上限是两件事，将来可能分开调）；
//   3) 缓存上限的夹紧（把 SET-080 的 MiB 值翻译成字节，并夹到文档给的 128–4096）。
library;

import 'dart:typed_data';

import 'image_header.dart';

/// 允许缓存的图片 MIME 类型（架构 4.2 的受控 MIME）。
///
/// 白名单只列阅读器真能显示的格式。刻意**不**包含：
///   - image/svg+xml：SVG 可携带脚本与外部引用，渲染它等于把一段可执行的 XML 交给
///     渲染管线。本项目自绘 SVG 图标走的是内置资源（T012），从不渲染远端 SVG；
///   - image/bmp / image/tiff：阅读场景里几乎不出现，且部分解码器对畸形 BMP 的处理
///     历史上出过问题；体积也通常是 JPEG/WebP 的数倍；
///   - image/avif：Flutter 的图片解码依赖平台能力，macOS 支持情况随版本变化，不在
///     首发白名单里（被拒绝会显示占位与失败说明，而不是一张坏图）。
const Set<String> kAllowedImageMimeTypes = <String>{
  'image/jpeg',
  'image/jpg',
  'image/png',
  'image/gif',
  'image/webp',
};

/// 单张图片的字节上限：4 MiB。
///
/// 文档口径是 SET-065 的「单图上传上限 4 MiB」。这里独立成常量并在注释里说明关系，
/// 而不是直接读 SET-065：那张设置控制的是「送往视觉模型前的上传大小」，与「阅读时
/// 允许缓存多大的图」是两个不同的约束，共用一个值只是当下的巧合。将来若把缓存上限
/// 调大而上传上限不变，两处不会互相牵扯。
const int kMaxImageBytes = 4 * 1024 * 1024;

/// 缓存大小的下限与上限（SET-080：512 MiB，允许 128–4096）。
const int kMinCacheMiB = 128;
const int kMaxCacheMiB = 4096;

/// 把字节长度格式化为人类可读的 MiB 描述。
///
/// 放在 core 而不是 infrastructure（它原先在 image_cache_service.dart）：占用统计要显示在设置页
/// （features 层），而 features 不得 import infrastructure（架构 2.2 的守卫会拦）。格式化是纯
/// 展示逻辑，没有实现细节，core 是正确的归属。
///
/// 小于 0.1 MiB 时显示 0.1 MiB 而不是 0.0：一个「0.0 MiB」的条目看起来像「没有占用」，而它其实
/// 有几百 KB（例如几十张缩略图的元数据）。四舍五入到 0 会把一次真实的清理显示成「什么都没做」。
String describeBytes(int bytes) {
  final double mib = bytes / (1024 * 1024);
  if (bytes > 0 && mib < 0.1) {
    return '< 0.1 MiB';
  }
  return '${mib.toStringAsFixed(1)} MiB';
}

/// SET-080 的默认值（MiB）。
const int kDefaultCacheMiB = 512;

/// 把 SET-080 的 MiB 值夹紧到文档允许的区间。
///
/// 越界值不报错而是夹紧：设置值来自用户/旧版本/手工改动，一个 99999 MiB 的缓存上限
/// 不该让图片缓存整个失效。夹紧的后果是「上限被拉回允许区间」，这是可解释的，而读不
/// 到上限时抛错的后果是「一张图都显示不出来」。
int clampCacheMiB(int rawMiB) => rawMiB.clamp(kMinCacheMiB, kMaxCacheMiB);

/// 把 MiB 上限翻译成字节。
int cacheLimitBytes(int rawMiB) => clampCacheMiB(rawMiB) * 1024 * 1024;

/// 从 Content-Type 头里解析 MIME 类型（去掉参数、转小写）。
///
/// 返回 null 表示「没有可用的类型声明」。调用方**不得**在 null 时猜类型：一张
/// 没有 Content-Type 的响应可能是任何东西，按扩展名猜等于信任远端提供的文件名
/// （架构 5.1 明确不以外部名称直接拼路径/决定行为）。
String? normalizeMimeType(String? contentType) {
  if (contentType == null) {
    return null;
  }
  final String trimmed = contentType.trim().toLowerCase();
  if (trimmed.isEmpty) {
    return null;
  }
  final int semicolon = trimmed.indexOf(';');
  final String base =
      (semicolon == -1 ? trimmed : trimmed.substring(0, semicolon)).trim();
  return base.isEmpty ? null : base;
}

/// 该 MIME 是否在允许缓存的图片白名单里。
bool isAllowedImageMime(String? mimeType) {
  final String? normalized = normalizeMimeType(mimeType);
  return normalized != null && kAllowedImageMimeTypes.contains(normalized);
}

/// 一张图是否可缓存（MIME 与体积都通过）。
///
/// [declaredBytes] 为 null 表示响应没有声明长度——那种情况**不**在这里拒绝，而是由
/// 流式读取的计数上限兜住（见 infrastructure 的下载管线）。在这里因为「没声明长度」
/// 就拒绝，会把一批正常的分块响应（chunked）全部拒掉。
bool isCacheableImage({
  required String? mimeType,
  required int? declaredBytes,
}) {
  if (!isAllowedImageMime(mimeType)) {
    return false;
  }
  if (declaredBytes != null && declaredBytes > kMaxImageBytes) {
    return false;
  }
  return true;
}

/// 一张已经过校验、可交给渲染管线的图片。
///
/// 放在 core 而不是 infrastructure：它是**校验完成的产物**，界面（features 层）
/// 必须能读到它，而 features 不得 import infrastructure（架构 2.2 的守卫会拦）。
/// 与 [ImageDimensions] 分开：那个是「从头部读出的声明尺寸」，这个带着真正要渲染的
/// 字节，两者的来源与可信度都不同。
final class LoadedImage {
  /// 构造已加载图片。
  const LoadedImage({
    required this.bytes,
    required this.mimeType,
    required this.width,
    required this.height,
  });

  /// 图片字节（MIME/体积/魔数都已校验）。
  final Uint8List bytes;

  /// MIME。
  final String mimeType;

  /// 宽（像素）。
  final int width;

  /// 高（像素）。
  final int height;

  /// 该图的完整尺寸（用于「解码不超原图」的换算）。
  ImageDimensions get dimensions => ImageDimensions(width, height);
}

/// 一次媒体下载是否被允许（SET-013 计费网络守卫）。
///
/// 为什么做成接口而不是在加载器里直接读设置：加载器住在 infrastructure，而设置与
/// 网络状况的读取是 features 的端口（settingsStoreProvider /
/// networkConditionsProvider）。让加载器直接依赖它们会把依赖方向倒过来。
abstract interface class MediaDownloadPolicy {
  /// 当前是否允许下载媒体（图片）。
  ///
  /// 返回 false 表示「现在不该发这次请求」（例如 SET-013 关闭且当前是计费网络）。
  /// 缓存**命中**不受它限制：读本机文件不是网络行为（架构 4.1 的离线可读）。
  Future<bool> allowsImageDownload();
}

/// 总是允许下载的策略（测试与「无计费判定能力」的场合）。
///
/// 与 [PermissiveNetworkConditions] 同一条理由：回答「允许」不等于「确认不受限」，
/// 它只表示没有证据表明受限，而守卫的方向永远是放行。
final class AllowAllMediaDownloads implements MediaDownloadPolicy {
  /// 构造放行策略。
  const AllowAllMediaDownloads();

  @override
  Future<bool> allowsImageDownload() async => true;
}
