import Cocoa
import FlutterMacOS

@main
/// メインウィンドウとメニューバー常駐の振る舞いを管理する macOS アプリデリゲートです。
class AppDelegate: FlutterAppDelegate {
  static var shared: AppDelegate? {
    NSApp.delegate as? AppDelegate
  }

  private let hardwareBridge = HardwareBridge()
  private var statusItem: NSStatusItem?
  private var isQuitting = false
  private var hasRestoredFanModes = false

  /// アプリ起動後にステータスバー項目を初期化し、常駐 UI を使える状態にします。
  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    configureStatusItem()
  }

  /// ウィンドウを閉じてもアプリ本体は終了させず、メニューバー常駐を継続します。
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  /// Dock などから再オープンされたときに、非表示だったメインウィンドウを再表示します。
  override func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag {
      showMainWindow()
    }
    return true
  }

  /// 終了直前に手動制御中のファンを自動制御へ戻してから終了処理を続行します。
  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    isQuitting = true
    restoreFansToAutomaticIfNeeded()
    return .terminateNow
  }

  /// macOS の安全な状態復元に対応していることを通知します。
  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// メインウィンドウを閉じる代わりに非表示へ切り替え、常駐動作を維持します。
  @discardableResult
  func interceptMainWindowClose(_ window: NSWindow) -> Bool {
    guard !isQuitting else {
      return false
    }

    hideMainWindow(window)
    return true
  }

  /// ステータスバー項目からメインウィンドウを前面に戻します。
  @objc private func showMainWindowFromStatusItem(_ sender: Any?) {
    showMainWindow()
  }

  /// ステータスバー項目からアプリ終了を要求します。
  @objc private func quitFromStatusItem(_ sender: Any?) {
    NSApp.terminate(sender)
  }

  /// メインウィンドウを復元してアプリを前面化します。
  private func showMainWindow() {
    guard let window = mainWindow else {
      return
    }

    if window.isMiniaturized {
      window.deminiaturize(nil)
    }

    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  /// メインウィンドウを閉じずに非表示にします。
  private func hideMainWindow(_ window: NSWindow) {
    window.orderOut(nil)
  }

  private var mainWindow: NSWindow? {
    NSApp.windows.first(where: { $0 is MainFlutterWindow }) ??
      NSApp.mainWindow ??
      NSApp.windows.first
  }

  /// メニューバー常駐用のステータス項目とメニューを構築します。
  private func configureStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    item.button?.toolTip = "Mac Fan Tool"

    if let image = statusItemImage() {
      item.button?.image = image
    } else {
      item.button?.title = "Fan"
    }

    let menu = NSMenu()
    menu.addItem(
      NSMenuItem(
        title: "Open Dashboard",
        action: #selector(showMainWindowFromStatusItem(_:)),
        keyEquivalent: ""
      )
    )
    menu.addItem(.separator())
    menu.addItem(
      NSMenuItem(
        title: "Quit",
        action: #selector(quitFromStatusItem(_:)),
        keyEquivalent: ""
      )
    )

    for item in menu.items {
      item.target = self
    }

    item.menu = menu
    statusItem = item
  }

  /// ステータスバーで使うアイコンをシンボル画像またはアプリアイコンから生成します。
  private func statusItemImage() -> NSImage? {
    if #available(macOS 11.0, *) {
      let image = NSImage(
        systemSymbolName: "fanblades",
        accessibilityDescription: "Mac Fan Tool"
      )
      image?.isTemplate = true
      return image
    }

    guard let image = NSApp.applicationIconImage.copy() as? NSImage else {
      return nil
    }

    image.size = NSSize(width: 18, height: 18)
    return image
  }

  /// 終了時の多重実行を防ぎつつ、手動制御中の全ファンを自動制御へ戻します。
  private func restoreFansToAutomaticIfNeeded() {
    guard !hasRestoredFanModes else {
      return
    }
    hasRestoredFanModes = true

    do {
      let snapshot = try hardwareBridge.getSnapshot()
      let manualFans = (snapshot.fans ?? [])
        .compactMap { $0 }
        .filter { $0.mode == .manual }

      for fan in manualFans {
        guard let fanId = fan.id else {
          continue
        }

        do {
          try hardwareBridge.setFanMode(fanId: fanId, mode: .automatic)
        } catch {
          NSLog("Failed to restore %@ to automatic on quit: %@", fanId, String(describing: error))
        }
      }
    } catch {
      NSLog("Failed to read fan state during quit: %@", String(describing: error))
    }
  }
}
