import Cocoa
import FlutterMacOS

/// Flutter ビューとネイティブのハードウェア API を結び付けるメインウィンドウです。
class MainFlutterWindow: NSWindow {
  private let hardwareBridge = HardwareBridge()

  /// Flutter ビューを埋め込み、生成済みプラグインとネイティブ API ブリッジを登録します。
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

  /// 閉じる操作をアプリデリゲートへ委譲し、常駐動作時は非表示だけに切り替えます。
  override func performClose(_ sender: Any?) {
    if AppDelegate.shared?.interceptMainWindowClose(self) == true {
      return
    }

    super.performClose(sender)
  }
}
