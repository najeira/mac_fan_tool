import Dispatch
import Foundation

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
    manualLeaseDuration: DispatchTimeInterval = .seconds(15),
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

  func listener(
    _ listener: NSXPCListener,
    shouldAcceptNewConnection newConnection: NSXPCConnection
  ) -> Bool {
    newConnection.exportedInterface = NSXPCInterface(with: FanControlXPCProtocol.self)
    newConnection.exportedObject = self
    newConnection.resume()
    return true
  }

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
