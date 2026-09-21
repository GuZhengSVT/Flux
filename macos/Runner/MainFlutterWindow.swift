import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    // 关闭本窗口的「状态恢复」。
    //
    // 实测：本方法里调用 setContentSize 后，窗口确实先变成 1200×800，但约 1.5 秒后
    // 又被 macOS 的窗口恢复机制改回 nib 里的 800×600（诊断日志记录了这个过程）。
    // 原因是 nib 里窗口带 restorable 属性，系统会在启动后异步用存档覆盖 frame。
    // 关掉它，代码设置的默认尺寸才是真正生效的那个。
    self.isRestorable = false

    // 默认窗口尺寸（T011）：阅读器在宽窗下才有意义（架构第 7 节：>=1100 三栏）。
    // 取 1200×800 —— 内容区扣掉侧边导航后仍 >=1100，三栏布局可用；在
    // 1920×1080 屏幕上也不会被系统挤到屏幕外。这只是默认值，用户可自由缩放。
    self.setContentSize(NSSize(width: 1200, height: 800))
    self.center()

    // 最小尺寸（架构第 7 节「桌面最小窗初值 720×560」）。
    // 用 contentMinSize 而不是 minSize：后者含标题栏高度，会让 560 实际对应更小
    // 的内容区，与架构按**内容逻辑尺寸**描述断点的口径不一致。
    //
    // 已知影响：内容区最小 720 意味着**桌面窗口不允许出现 <600 的宽度**，
    // 因此单栏布局在 macOS 上无法通过缩放窗口到达。这与架构「<600 单栏」并不
    // 矛盾——那条描述的是内容如何分栏，而不是要求桌面窗口必须能缩到 600 以下；
    // 手机目标仍会走单栏分支，桌面侧由组件测试与 golden 覆盖该分支。
    self.contentMinSize = NSSize(width: 720, height: 560)
  }
}
