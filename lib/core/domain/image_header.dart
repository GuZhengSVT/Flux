// 图片字节嗅探与尺寸读取（T021；架构 4.2「解码前字节校验」与第 8 节图像安全）。
//
// 为什么要在**解码之前**做这两件事，而不是把字节交给解码器让它自己判断：
//   1) **声明与内容不符**是最常见的攻击面。响应头说 image/png、字节其实是 SVG 或
//      一段可执行内容，如果直接解码就等于信任远端的自我声明。这里按魔数嗅探真实
//      格式，与声明的 MIME 不一致就拒绝；
//   2) **解码炸弹**（一张几十 KB 的 PNG 解出几十亿像素）只有在解码时才发生，那时
//      内存已经被吃掉了。四个白名单格式的头部都带尺寸字段，读出来先按像素数拒绝，
//      比事后补救有效得多。
//
// 本文件是**纯函数 + 纯字节解析**：不依赖 Flutter、不依赖平台解码器，因此每个分支
// 都能用固定字节数组断言（构造一个畸形头部不需要真的生成一张畸形图片）。
library;

/// 嗅探出的图片格式。
enum ImageFormat { png, jpeg, gif, webp }

/// 格式对应的规范 MIME。
String imageFormatMimeType(ImageFormat format) => switch (format) {
  ImageFormat.png => 'image/png',
  ImageFormat.jpeg => 'image/jpeg',
  ImageFormat.gif => 'image/gif',
  ImageFormat.webp => 'image/webp',
};

/// 单张图片允许解码出的最大像素数：50 MP。
///
/// 50 MP 高于任何相机与常见网页配图（一张 8K 图约 33 MP），因此正常图片不会碰到
/// 这个上限；而它足以拦住「4 MiB 的 PNG 解出 10 亿像素」这类炸弹——10 亿像素按
/// 4 字节/像素是 4 GB，在拒绝之前就把内存吃光了。
const int kMaxDecodedPixels = 50 * 1000 * 1000;

/// 图片的像素尺寸。
final class ImageDimensions {
  /// 构造尺寸。
  const ImageDimensions(this.width, this.height);

  /// 宽（像素）。
  final int width;

  /// 高（像素）。
  final int height;

  /// 总像素数。
  int get pixels => width * height;

  /// 是否超过解码像素上限。
  bool get exceedsDecodeCap => pixels > kMaxDecodedPixels;
}

/// 按魔数嗅探格式；无法识别时返回 null。
///
/// 只认白名单里的四种：一个识别不出来的字节流**不能**按声明放行，因为下一步就是
/// 把它交给解码器。
ImageFormat? sniffImageFormat(List<int> bytes) {
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0D &&
      bytes[5] == 0x0A &&
      bytes[6] == 0x1A &&
      bytes[7] == 0x0A) {
    return ImageFormat.png;
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return ImageFormat.jpeg;
  }
  if (bytes.length >= 6 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x38 &&
      (bytes[4] == 0x37 || bytes[4] == 0x39) &&
      bytes[5] == 0x61) {
    return ImageFormat.gif;
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return ImageFormat.webp;
  }
  return null;
}

/// 读取图片尺寸（不解码像素）；无法解析或格式不支持时返回 null。
///
/// 返回 null 与「尺寸是 0×0」是两件不同的事：前者表示读不出来（调用方必须拒绝），
/// 后者是一个真实的空图声明。这里宁可在读不出时返回 null，也不猜一个安全值——
/// 猜出来的尺寸会让「是否超限」这个判断失去意义。
ImageDimensions? probeImageDimensions(List<int> bytes) {
  final ImageFormat? format = sniffImageFormat(bytes);
  return switch (format) {
    ImageFormat.png => _probePng(bytes),
    ImageFormat.gif => _probeGif(bytes),
    ImageFormat.webp => _probeWebp(bytes),
    ImageFormat.jpeg => _probeJpeg(bytes),
    null => null,
  };
}

/// PNG：IHDR 紧跟 8 字节签名 + 4 字节长度 + 4 字节类型，随后是宽高各 4 字节大端。
ImageDimensions? _probePng(List<int> bytes) {
  const int widthOffset = 16;
  const int heightOffset = 20;
  if (bytes.length < heightOffset + 4) {
    return null;
  }
  // IHDR 必须紧随签名：类型字段的 ASCII 是 "IHDR"。
  if (bytes[12] != 0x49 ||
      bytes[13] != 0x48 ||
      bytes[14] != 0x44 ||
      bytes[15] != 0x52) {
    return null;
  }
  final int width = _readUint32Be(bytes, widthOffset);
  final int height = _readUint32Be(bytes, heightOffset);
  if (width <= 0 || height <= 0) {
    return null;
  }
  return ImageDimensions(width, height);
}

/// GIF：签名后 6 字节为逻辑屏幕宽高，各 2 字节小端。
ImageDimensions? _probeGif(List<int> bytes) {
  if (bytes.length < 10) {
    return null;
  }
  final int width = bytes[6] | (bytes[7] << 8);
  final int height = bytes[8] | (bytes[9] << 8);
  if (width <= 0 || height <= 0) {
    return null;
  }
  return ImageDimensions(width, height);
}

/// WebP：RIFF 容器，三种子格式的尺寸位置各不相同。
///
///   - VP8 （有损）：帧头里有一个 3 字节小端宽高（取低 14 位）；
///   - VP8L（无损）：1 字节签名 0x2F 后跟位打包的 14 位宽高；
///   - VP8X（扩展）：24 位小端宽高各减一。
ImageDimensions? _probeWebp(List<int> bytes) {
  if (bytes.length < 30) {
    return null;
  }
  final String chunk = String.fromCharCodes(bytes.sublist(12, 16));
  switch (chunk) {
    case 'VP8 ':
      // 帧头：0x9D 0x01 0x2A 之后是 3 字节小端（宽高各 14 位）。
      if (bytes.length < 30 ||
          bytes[23] != 0x9D ||
          bytes[24] != 0x01 ||
          bytes[25] != 0x2A) {
        return null;
      }
      final int width = (bytes[26] | (bytes[27] << 8)) & 0x3FFF;
      final int height = (bytes[28] | (bytes[29] << 8)) & 0x3FFF;
      if (width <= 0 || height <= 0) {
        return null;
      }
      return ImageDimensions(width, height);
    case 'VP8L':
      if (bytes.length < 25 || bytes[20] != 0x2F) {
        return null;
      }
      // 14 位宽、14 位高，位打包在一起。
      final int bits =
          bytes[21] | (bytes[22] << 8) | (bytes[23] << 16) | (bytes[24] << 24);
      final int width = (bits & 0x3FFF) + 1;
      final int height = ((bits >> 14) & 0x3FFF) + 1;
      return ImageDimensions(width, height);
    case 'VP8X':
      if (bytes.length < 30) {
        return null;
      }
      // 24 位小端，存储的是「实际尺寸 - 1」。
      final int width = (bytes[24] | (bytes[25] << 8) | (bytes[26] << 16)) + 1;
      final int height = (bytes[27] | (bytes[28] << 8) | (bytes[29] << 16)) + 1;
      return ImageDimensions(width, height);
    default:
      return null;
  }
}

/// JPEG：遍历段，找 SOFn（0xC0–0xCF，跳过 C4/C8/CC）取高宽。
///
/// 需要遍历而不是取固定偏移：SOF 之前可能有任意数量的 APPn/注释段（EXIF 缩略图、
/// ICC profile 都很常见），固定偏移一定会读错。
ImageDimensions? _probeJpeg(List<int> bytes) {
  int offset = 2; // 跳过 SOI
  while (offset + 3 < bytes.length) {
    if (bytes[offset] != 0xFF) {
      return null; // 段边界不对：不猜，直接放弃
    }
    int marker = bytes[offset + 1];
    // 填充字节 0xFF 可以重复出现。
    while (marker == 0xFF && offset + 2 < bytes.length) {
      offset++;
      marker = bytes[offset + 1];
    }
    offset += 2;
    // 无长度字段的标记：SOI/EOI/RSTn/TEM。
    if (marker == 0xD8 ||
        marker == 0xD9 ||
        (marker >= 0xD0 && marker <= 0xD7) ||
        marker == 0x01) {
      continue;
    }
    if (offset + 1 >= bytes.length) {
      return null;
    }
    final int length = (bytes[offset] << 8) | bytes[offset + 1];
    if (length < 2 || offset + length > bytes.length) {
      return null;
    }
    final bool isSof =
        marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC;
    if (isSof) {
      if (offset + 7 > bytes.length) {
        return null;
      }
      final int height = (bytes[offset + 3] << 8) | bytes[offset + 4];
      final int width = (bytes[offset + 5] << 8) | bytes[offset + 6];
      if (width <= 0 || height <= 0) {
        return null;
      }
      return ImageDimensions(width, height);
    }
    offset += length;
  }
  return null;
}

/// 大端 32 位无符号读取。
int _readUint32Be(List<int> bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];
