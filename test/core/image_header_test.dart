// T021：图片格式嗅探与尺寸读取（纯字节解析，不需真实图片）。
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/core/core.dart';

import '../app/fake_article_image_loader.dart';

/// 构造一个只有头部、尺寸任填的 PNG。
Uint8List png(int width, int height) {
  final Uint8List bytes = Uint8List.fromList(kTestPngBytes);
  void write(int offset, int value) {
    bytes[offset] = (value >> 24) & 0xFF;
    bytes[offset + 1] = (value >> 16) & 0xFF;
    bytes[offset + 2] = (value >> 8) & 0xFF;
    bytes[offset + 3] = value & 0xFF;
  }

  write(16, width);
  write(20, height);
  return bytes;
}

/// 最小合法 GIF（逻辑屏幕宽高在 6..9，小端）。
Uint8List gif(int width, int height) => Uint8List.fromList(<int>[
  0x47,
  0x49,
  0x46,
  0x38,
  0x39,
  0x61,
  width & 0xFF,
  (width >> 8) & 0xFF,
  height & 0xFF,
  (height >> 8) & 0xFF,
]);

/// 最小合法 JPEG（SOI + SOF0，含尺寸）。
Uint8List jpeg(int width, int height) => Uint8List.fromList(<int>[
  0xFF,
  0xD8,
  0xFF,
  0xC0,
  0x00,
  0x11,
  0x08,
  (height >> 8) & 0xFF,
  height & 0xFF,
  (width >> 8) & 0xFF,
  width & 0xFF,
  0x03,
  0x01,
  0x11,
  0x00,
  0x02,
  0x11,
  0x01,
  0x03,
  0x11,
  0x01,
]);

/// 最小 WebP（RIFF + VP8X 扩展头）。
Uint8List webpVp8x(int width, int height) {
  final Uint8List bytes = Uint8List(30);
  bytes.setRange(0, 4, <int>[0x52, 0x49, 0x46, 0x46]); // RIFF
  bytes.setRange(8, 12, <int>[0x57, 0x45, 0x42, 0x50]); // WEBP
  bytes.setRange(12, 16, <int>[0x56, 0x50, 0x38, 0x58]); // VP8X
  final int w = width - 1;
  final int h = height - 1;
  bytes[24] = w & 0xFF;
  bytes[25] = (w >> 8) & 0xFF;
  bytes[26] = (w >> 16) & 0xFF;
  bytes[27] = h & 0xFF;
  bytes[28] = (h >> 8) & 0xFF;
  bytes[29] = (h >> 16) & 0xFF;
  return bytes;
}

void main() {
  group('魔数嗅探', () {
    test('识别四种白名单格式', () {
      expect(sniffImageFormat(png(1, 1)), ImageFormat.png);
      expect(sniffImageFormat(gif(1, 1)), ImageFormat.gif);
      expect(sniffImageFormat(jpeg(1, 1)), ImageFormat.jpeg);
      expect(sniffImageFormat(webpVp8x(1, 1)), ImageFormat.webp);
    });

    test('不属于白名单的内容一律返回 null', () {
      expect(sniffImageFormat(<int>[]), isNull);
      expect(sniffImageFormat('<html>'.codeUnits), isNull);
      // SVG 是 XML：即使内容是图片语义，也不在白名单（可携带脚本）。
      expect(sniffImageFormat('<svg/>'.codeUnits), isNull);
      // BMP 同样不在白名单。
      expect(sniffImageFormat(<int>[0x42, 0x4D]), isNull);
    });

    test('GIF 只认 87a/89a 与结尾的 0x61', () {
      expect(
        sniffImageFormat(<int>[0x47, 0x49, 0x46, 0x38, 0x38, 0x61]),
        isNull,
      );
    });

    test('WebP 必须是 RIFF....WEBP 四字节标记都在位', () {
      final Uint8List notWebp = Uint8List(30);
      notWebp.setRange(0, 4, <int>[0x52, 0x49, 0x46, 0x46]);
      expect(sniffImageFormat(notWebp), isNull);
    });
  });

  group('尺寸读取', () {
    test('PNG：读 IHDR 的高宽（大端）', () {
      final ImageDimensions? dims = probeImageDimensions(png(1200, 800));
      expect(dims, isNotNull);
      expect(dims!.width, 1200);
      expect(dims.height, 800);
    });

    test('GIF：逻辑屏幕宽高（小端）', () {
      final ImageDimensions dims = probeImageDimensions(gif(300, 200))!;
      expect(dims.width, 300);
      expect(dims.height, 200);
    });

    test('JPEG：遍历到 SOF0 才能拿到尺寸（前面可能有 APPn 段）', () {
      final ImageDimensions dims = probeImageDimensions(jpeg(640, 480))!;
      expect(dims.width, 640);
      expect(dims.height, 480);
    });

    test('WebP（VP8X）：24 位小端，存的是实际尺寸减一', () {
      final ImageDimensions dims = probeImageDimensions(webpVp8x(100, 50))!;
      expect(dims.width, 100);
      expect(dims.height, 50);
    });

    test('PNG 但 IHDR 标记不在预期位置 → 读不出（不猜尺寸）', () {
      final Uint8List corrupted = png(10, 10);
      corrupted[12] = 0x00; // 破坏 'I'
      expect(probeImageDimensions(corrupted), isNull);
    });

    test('声明 0×0 的图被判为读不出（不是「安全的空图」）', () {
      expect(probeImageDimensions(png(0, 0)), isNull);
    });

    test('截断到只有签名时读不出', () {
      expect(probeImageDimensions(png(10, 10).sublist(0, 12)), isNull);
    });

    test('无法识别的格式返回 null', () {
      expect(probeImageDimensions('<html>'.codeUnits), isNull);
    });
  });

  group('解码上限', () {
    test('像素数超过 50 MP 被标记为超限', () {
      final ImageDimensions huge = probeImageDimensions(png(40000, 40000))!;
      expect(huge.pixels, 1600000000);
      expect(huge.exceedsDecodeCap, isTrue);
    });

    test('常见大图（8K 级别）不超限', () {
      final ImageDimensions big = probeImageDimensions(png(7680, 4320))!;
      expect(big.exceedsDecodeCap, isFalse);
    });
  });

  group('格式到 MIME 的映射', () {
    test('四种格式映射到规范 MIME', () {
      expect(imageFormatMimeType(ImageFormat.png), 'image/png');
      expect(imageFormatMimeType(ImageFormat.jpeg), 'image/jpeg');
      expect(imageFormatMimeType(ImageFormat.gif), 'image/gif');
      expect(imageFormatMimeType(ImageFormat.webp), 'image/webp');
    });
  });

  group('策略（MIME/体积）', () {
    test('白名单只含四种可显示格式', () {
      expect(kAllowedImageMimeTypes.contains('image/png'), isTrue);
      expect(kAllowedImageMimeTypes.contains('image/jpeg'), isTrue);
      expect(kAllowedImageMimeTypes.contains('image/gif'), isTrue);
      expect(kAllowedImageMimeTypes.contains('image/webp'), isTrue);
      expect(kAllowedImageMimeTypes.contains('image/svg+xml'), isFalse);
      expect(kAllowedImageMimeTypes.contains('text/html'), isFalse);
    });

    test('Content-Type 解析去掉参数并小写', () {
      expect(normalizeMimeType('IMAGE/PNG; charset=UTF-8'), 'image/png');
      expect(normalizeMimeType('  image/jpeg  '), 'image/jpeg');
      expect(normalizeMimeType(null), isNull);
      expect(normalizeMimeType(''), isNull);
      expect(normalizeMimeType(';charset=utf-8'), isNull);
    });

    test('未声明长度不因「没长度」被拒（chunked 响应是正常的）', () {
      expect(
        isCacheableImage(mimeType: 'image/png', declaredBytes: null),
        isTrue,
      );
      expect(
        isCacheableImage(
          mimeType: 'image/png',
          declaredBytes: kMaxImageBytes + 1,
        ),
        isFalse,
      );
      expect(
        isCacheableImage(mimeType: 'image/svg+xml', declaredBytes: 10),
        isFalse,
      );
    });

    test('单图上限是 4 MiB（对齐 SET-065 的口径）', () {
      expect(kMaxImageBytes, 4 * 1024 * 1024);
    });
  });
}
