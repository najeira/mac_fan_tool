import Cocoa
import FlutterMacOS

/// Flutter ビューとネイティブのハードウェア API を結び付けるメインウィンドウです。
class MainFlutterWindow: NSWindow {
  private let hardwareBridge = HardwareBridge()

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    HardwareHostApiSetup.setUp(
      binaryMessenger: flutterViewController.engine.binaryMessenger,
      api: hardwareBridge
    )

    super.awakeFromNib()
  }

  override func performClose(_ sender: Any?) {
    if AppDelegate.shared?.interceptMainWindowClose(self) == true {
      return
    }

    super.performClose(sender)
  }
}
