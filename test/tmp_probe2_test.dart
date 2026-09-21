import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// 1x1 PNG。
final Uint8List kPng = Uint8List.fromList(<int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

void main() {
  test('probe decode + descriptor', () async {
    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
      kPng,
    );
    final ui.ImageDescriptor desc = await ui.ImageDescriptor.encoded(buffer);
    // ignore: avoid_print
    print('DIMS ${desc.width}x${desc.height}');
    final ui.Codec codec = await desc.instantiateCodec(
      targetWidth: 1000,
      targetHeight: 1000,
    );
    final ui.FrameInfo frame = await codec.getNextFrame();
    // ignore: avoid_print
    print('DECODED ${frame.image.width}x${frame.image.height}');
    frame.image.dispose();
    codec.dispose();
    desc.dispose();
    buffer.dispose();

    // 伪造一个声明超大尺寸的 PNG 头。
    final Uint8List huge = Uint8List.fromList(kPng);
    huge[16] = 0x00;
    huge[17] = 0x11;
    huge[18] = 0x00;
    huge[19] = 0x11;
    try {
      final ui.ImmutableBuffer b2 = await ui.ImmutableBuffer.fromUint8List(
        huge,
      );
      final ui.ImageDescriptor d2 = await ui.ImageDescriptor.encoded(b2);
      // ignore: avoid_print
      print('HUGE DIMS ${d2.width}x${d2.height}');
      d2.dispose();
      b2.dispose();
    } on Exception catch (e) {
      // ignore: avoid_print
      print('HUGE ERROR ${e.runtimeType}');
    }
  });
}
