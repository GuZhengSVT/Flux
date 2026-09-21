import Cocoa
import FlutterMacOS

/// Flux 的 macOS 系统分享通道（T020）。
///
/// 只做一件事：把 Dart 侧的「分享一段文本」映射到 AppKit 的 NSSharingServicePicker。
/// 不引入其他插件，也不碰数据库或文件——架构第 2.1 节把「文件/分享」列为允许的平台桥接
/// 范围，而分享面板本身就是这个范围的一部分。
///
/// 为什么用 NSSharingServicePicker 而不是自己写服务列表：
///   系统分享面板会给出用户**已安装**的分享目标（邮件、信息、备忘录、第三方应用），并
///   遵循系统偏好设置。自建列表既拿不到完整集合，也违背「用系统接口」的意图。
///
/// 一个 AppKit 的实际约束：picker 必须挂在某个视图上才能弹出。这里用主窗口的 contentView
/// ——分享面板是模态的用户交互，出现在主窗口上是符合预期的位置。取不到视图时返回 false，
/// 由 Dart 侧回退为复制（架构 4.2），而不是什么都不做。
final class SharePlugin {
  /// 通道名，必须与 Dart 侧 fluxShareChannelName 一致。
  static let channelName = "io.github.guzhengsvt.flux/share"

  /// 通道句柄；注册后由 Flutter 持有。
  private let channel: FlutterMethodChannel

  /// 持有当前的 picker。
  ///
  /// **必须**持有：NSSharingServicePicker 在超出作用域后会被释放，而弹出动画还在进行，
  /// 结果就是点了分享什么都没发生（这类「偶发不弹」几乎都源于此）。
  private var activePicker: NSSharingServicePicker?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: SharePlugin.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isAvailable":
      // 只要能在主窗口上找到一个视图就认为可用：真正的「有没有可分享的目标」由系统在
      // 弹出面板时决定（可能一个都没有），那时 Dart 侧按「用户取消」处理。
      result(hostView() != nil)
    case "shareText":
      guard let text = call.arguments as? String, !text.isEmpty else {
        result(FlutterError(code: "badArguments", message: "expected non-empty string", details: nil))
        return
      }
      guard let view = hostView() else {
        result(false)
        return
      }
      let picker = NSSharingServicePicker(items: [text])
      activePicker = picker
      // 以视图中心附近的矩形作为弹出锚点：picker 需要一个 source rect 才能定位面板。
      let anchor = NSRect(
        x: view.bounds.midX - 1,
        y: view.bounds.midY - 1,
        width: 2,
        height: 2
      )
      picker.show(relativeTo: anchor, of: view, preferredEdge: .minY)
      // 返回 true 的语义是「面板已弹出」：用户是否真的选了某个目标，AppKit 不会回调告诉
      // 我们（没有 delegate 的 picker 不报告结果），因此这里不谎报「分享成功与否」。
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// 用来挂 picker 的视图（主窗口的 contentView）。
  private func hostView() -> NSView? {
    NSApplication.shared.mainWindow?.contentView
      ?? NSApplication.shared.windows.first?.contentView
  }
}
