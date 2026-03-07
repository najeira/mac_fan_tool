import Foundation

final class FanControlHelperService: NSObject, NSXPCListenerDelegate, FanControlXPCProtocol {
  private let controller: AppleSMCFanController?
  private let controllerError: AppleSMCFanControlError?

  override init() {
    do {
      controller = try AppleSMCFanController()
      controllerError = nil
    } catch let error as AppleSMCFanControlError {
      controller = nil
      controllerError = error
    } catch {
      controller = nil
      controllerError = .smcUnavailable(String(describing: error))
    }
    super.init()
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
      reply(nil)
    } catch let error as AppleSMCFanControlError {
      reply(error.message)
    } catch {
      reply(String(describing: error))
    }
  }

  func setFanTargetRpm(
    _ fanIndex: Int,
    targetRpm: Int,
    withReply reply: @escaping (String?) -> Void
  ) {
    do {
      let controller = try resolvedController()
      try controller.setFanTargetRpm(index: fanIndex, targetRpm: targetRpm)
      reply(nil)
    } catch let error as AppleSMCFanControlError {
      reply(error.message)
    } catch {
      reply(String(describing: error))
    }
  }

  private func resolvedController() throws -> AppleSMCFanController {
    if let controller {
      return controller
    }

    throw controllerError ?? .smcUnavailable("The fan controller could not be initialized.")
  }
}
