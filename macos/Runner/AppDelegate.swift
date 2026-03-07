import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  static var shared: AppDelegate? {
    NSApp.delegate as? AppDelegate
  }

  private let hardwareBridge = HardwareBridge()
  private var statusItem: NSStatusItem?
  private var isQuitting = false
  private var hasRestoredFanModes = false

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    configureStatusItem()
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag {
      showMainWindow()
    }
    return true
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    isQuitting = true
    restoreFansToAutomaticIfNeeded()
    return .terminateNow
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  @discardableResult
  func interceptMainWindowClose(_ window: NSWindow) -> Bool {
    guard !isQuitting else {
      return false
    }

    hideMainWindow(window)
    return true
  }

  @objc private func showMainWindowFromStatusItem(_ sender: Any?) {
    showMainWindow()
  }

  @objc private func quitFromStatusItem(_ sender: Any?) {
    NSApp.terminate(sender)
  }

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

  private func hideMainWindow(_ window: NSWindow) {
    window.orderOut(nil)
  }

  private var mainWindow: NSWindow? {
    NSApp.windows.first(where: { $0 is MainFlutterWindow }) ??
      NSApp.mainWindow ??
      NSApp.windows.first
  }

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
