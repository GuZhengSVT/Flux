import 'package:media_kit/media_kit.dart';

/// media_kit 初始化入口。
///
/// ## 如何接入 main()
///
/// 本文件刻意不修改 `lib/main.dart`，避免与其它任务冲突。
/// 需要内嵌视频播放时，请在 `main()` 中、`runApp(...)` **之前** 调用：
///
/// ```dart
/// import 'media/media_kit_init.dart';
///
/// Future<void> main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   // 初始化 media_kit（mpv/libmpv 库加载），必须在任何 Player 创建之前。
///   await ensureMediaKitInitialized();
///   // ... 其余初始化逻辑
/// }
/// ```
///
/// `EmbeddedVideoPlayer` 内部也会自行调用本函数兜底，
/// 因此即便 main 尚未接入，首次播放时依然能正常工作。
Future<void> ensureMediaKitInitialized() async {
  MediaKit.ensureInitialized();
}
