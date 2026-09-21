import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// Keychain 通道（T010）。持有强引用，确保通道在应用生命周期内一直有效。
  private var keychainPlugin: KeychainPlugin?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    // 在 GeneratedPluginRegistrant 之外单独注册本工程自有的原生通道。
    // 使用 mainFlutterWindow 的 ViewController 作为 messenger，与 Flutter 侧
    // MethodChannel 的默认绑定一致。
    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      keychainPlugin = KeychainPlugin(messenger: controller.engine.binaryMessenger)
    }
    super.applicationDidFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
