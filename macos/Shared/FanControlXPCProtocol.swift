import Dispatch
import Foundation

struct FanControlHelperConfiguration {
  static let helperBundleSuffix = ".FanControlHelper"
  static let machServiceSuffix = ".fancontrol.helper"
  static let launchDaemonPlistName = "FanControlHelper.plist"
  static let helperRelativePath = "Contents/Library/LaunchServices/FanControlHelper"

  let appBundleIdentifier: String

  var helperBundleIdentifier: String {
    "\(appBundleIdentifier)\(Self.helperBundleSuffix)"
  }

  var machServiceName: String {
    "\(appBundleIdentifier)\(Self.machServiceSuffix)"
  }

  static func currentAppConfiguration(bundle: Bundle = .main) -> FanControlHelperConfiguration? {
    guard let appBundleIdentifier = appBundleIdentifier(for: bundle) else {
      return nil
    }

    return FanControlHelperConfiguration(appBundleIdentifier: appBundleIdentifier)
  }

  static func appBundleIdentifier(for bundle: Bundle) -> String? {
    guard let bundleIdentifier = bundle.bundleIdentifier, !bundleIdentifier.isEmpty else {
      return nil
    }

    guard bundleIdentifier.hasSuffix(helperBundleSuffix) else {
      return bundleIdentifier
    }

    return String(bundleIdentifier.dropLast(helperBundleSuffix.count))
  }
}

enum CodeSigningRequirementBuilder {
  static func requirement(identifier: String, teamIdentifier: String) -> String {
    "identifier \"\(identifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
  }
}

enum FanControlWriteResultValidator {
  static func validate<E: Error>(
    _ results: [Result<Void, E>],
    unavailableError: @autoclosure () -> E
  ) throws {
    guard !results.isEmpty else {
      throw unavailableError()
    }

    for result in results {
      if case let .failure(error) = result {
        throw error
      }
    }
  }
}

enum AppleSMCFanMode: Int {
  case automatic = 0
  case manual = 1
}

final class ManualFanLeaseController {
  typealias ExpirationHandler = (Int) -> Void

  private let duration: DispatchTimeInterval
  private let queue: DispatchQueue
  private let expirationHandler: ExpirationHandler
  private var timers: [Int: DispatchSourceTimer] = [:]

  init(
    duration: DispatchTimeInterval,
    queue: DispatchQueue = DispatchQueue(label: "ManualFanLeaseController"),
    expirationHandler: @escaping ExpirationHandler
  ) {
    self.duration = duration
    self.queue = queue
    self.expirationHandler = expirationHandler
  }

  func arm(for fanIndex: Int) {
    queue.sync {
      cancelLocked(for: fanIndex)

      let timer = DispatchSource.makeTimerSource(queue: queue)
      timer.schedule(deadline: .now() + duration)
      timer.setEventHandler { [weak self] in
        self?.expireLease(for: fanIndex)
      }
      timers[fanIndex] = timer
      timer.resume()
    }
  }

  func cancel(for fanIndex: Int) {
    queue.sync {
      cancelLocked(for: fanIndex)
    }
  }

  private func expireLease(for fanIndex: Int) {
    cancelLocked(for: fanIndex)
    expirationHandler(fanIndex)
  }

  private func cancelLocked(for fanIndex: Int) {
    guard let timer = timers.removeValue(forKey: fanIndex) else {
      return
    }

    timer.cancel()
  }
}

protocol FanControlControlling: AnyObject {
  func setFanMode(index: Int, mode: AppleSMCFanMode) throws
  func setFanTargetRpm(index: Int, targetRpm: Int) throws
  func applyManualTargetRpm(index: Int, targetRpm: Int) throws
}

@objc protocol FanControlXPCProtocol {
  func setFanMode(
    _ fanIndex: Int,
    modeRawValue: Int,
    withReply reply: @escaping (String?) -> Void
  )

  func setFanTargetRpm(
    _ fanIndex: Int,
    targetRpm: Int,
    withReply reply: @escaping (String?) -> Void
  )

  func applyManualTargetRpm(
    _ fanIndex: Int,
    targetRpm: Int,
    withReply reply: @escaping (String?) -> Void
  )
}
