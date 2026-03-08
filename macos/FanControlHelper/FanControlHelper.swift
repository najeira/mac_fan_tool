import Dispatch
import Foundation

/// 特権ヘルパー側で XPC リクエストを受け取り、SMC へのファン制御を書き込むサービスです。
final class FanControlHelperService: NSObject, NSXPCListenerDelegate, FanControlXPCProtocol {
  typealias Logger = (String) -> Void

  private let controller: FanControlControlling?
  private let controllerError: AppleSMCFanControlError?
  private let manualLeaseDuration: DispatchTimeInterval
  private let logger: Logger
  private lazy var manualLeaseController = ManualFanLeaseController(
    duration: manualLeaseDuration,
    expirationHandler: { [weak self] fanIndex in
      self?.expireManualLease(for: fanIndex)
    }
  )

  override convenience init() {
    let resolvedController = Self.resolveController()
    self.init(
      controller: resolvedController.controller,
      controllerError: resolvedController.error
    )
  }

  init(
    controller: FanControlControlling?,
    controllerError: AppleSMCFanControlError?,
    manualLeaseDuration: DispatchTimeInterval = .seconds(90),
    logger: @escaping Logger = { message in
      NSLog("%@", message)
    }
  ) {
    self.controller = controller
    self.controllerError = controllerError
    self.manualLeaseDuration = manualLeaseDuration
    self.logger = logger
    super.init()
  }

  private static func resolveController() -> (
    controller: FanControlControlling?,
    error: AppleSMCFanControlError?
  ) {
    do {
      return (try AppleSMCFanController(), nil)
    } catch let error as AppleSMCFanControlError {
      return (nil, error)
    } catch {
      return (nil, .smcUnavailable(String(describing: error)))
    }
  }

  /// 受信した XPC 接続に公開インターフェースを設定して処理可能にします。
  func listener(
    _ listener: NSXPCListener,
    shouldAcceptNewConnection newConnection: NSXPCConnection
  ) -> Bool {
    newConnection.exportedInterface = NSXPCInterface(with: FanControlXPCProtocol.self)
    newConnection.exportedObject = self
    newConnection.resume()
    return true
  }

  /// 指定したファンの制御モードを自動または手動へ切り替えます。
  func setFanMode(
    _ fanIndex: Int,
    modeRawValue: Int,
    withReply reply: @escaping (String?) -> Void
  ) {
    guard let mode = AppleSMCFanMode(rawValue: modeRawValue) else {
      reply("Unsupported fan mode value: \(modeRawValue).")
      return
    }

    do {
      let controller = try resolvedController()
      try controller.setFanMode(index: fanIndex, mode: mode)
      updateManualLease(for: fanIndex, mode: mode)
      reply(nil)
    } catch let error as AppleSMCFanControlError {
      reply(error.message)
    } catch {
      reply(String(describing: error))
    }
  }

  /// 指定したファンを手動制御に切り替えたうえで目標 RPM をまとめて適用します。
  func applyManualTargetRpm(
    _ fanIndex: Int,
    targetRpm: Int,
    withReply reply: @escaping (String?) -> Void
  ) {
    do {
      let controller = try resolvedController()
      try controller.applyManualTargetRpm(index: fanIndex, targetRpm: targetRpm)
      armManualLease(for: fanIndex)
      reply(nil)
    } catch let error as AppleSMCFanControlError {
      reply(error.message)
    } catch {
      reply(String(describing: error))
    }
  }

  /// 手動ファン制御の期限を延長し、自動復帰を防ぎます。
  func renewManualLease(
    _ fanIndex: Int,
    withReply reply: @escaping (String?) -> Void
  ) {
    guard manualLeaseController.renew(for: fanIndex) else {
      reply("Manual fan control lease is not active for fan \(fanIndex).")
      return
    }

    reply(nil)
  }

  private func resolvedController() throws -> FanControlControlling {
    if let controller {
      return controller
    }

    throw controllerError ?? .smcUnavailable("The fan controller could not be initialized.")
  }

  private func updateManualLease(for fanIndex: Int, mode: AppleSMCFanMode) {
    switch mode {
    case .manual:
      armManualLease(for: fanIndex)
    case .automatic:
      cancelManualLease(for: fanIndex)
    }
  }

  private func armManualLease(for fanIndex: Int) {
    manualLeaseController.arm(for: fanIndex)
  }

  private func cancelManualLease(for fanIndex: Int) {
    manualLeaseController.cancel(for: fanIndex)
  }

  private func expireManualLease(for fanIndex: Int) {
    do {
      let controller = try resolvedController()
      try controller.setFanMode(index: fanIndex, mode: .automatic)
    } catch let error as AppleSMCFanControlError {
      logger("Failed to expire manual fan lease for fan \(fanIndex): \(error.message)")
    } catch {
      logger("Failed to expire manual fan lease for fan \(fanIndex): \(error)")
    }
  }
}
