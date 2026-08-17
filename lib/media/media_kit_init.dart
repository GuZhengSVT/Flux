import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

/// media_kit 初始化入口。
///
/// `main()` 在 `runApp` 之前调用本函数完成 mpv/libmpv 库加载；
/// `EmbeddedVideoPlayer` 内部也会自行调用本函数兜底。
///
/// 初始化失败不应阻塞应用启动：视频功能不可用时，应用其余部分仍应可用。
Future<void> ensureMediaKitInitialized() async {
  try {
    MediaKit.ensureInitialized();
  } catch (e) {
    debugPrint('Flux: media_kit initialization failed: $e');
  }
}
