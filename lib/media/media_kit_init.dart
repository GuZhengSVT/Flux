import 'package:media_kit/media_kit.dart';

/// media_kit 初始化入口。
///
/// `main()` 在 `runApp` 之前调用本函数完成 mpv/libmpv 库加载；
/// `EmbeddedVideoPlayer` 内部也会自行调用本函数兜底。
Future<void> ensureMediaKitInitialized() async {
  MediaKit.ensureInitialized();
}
