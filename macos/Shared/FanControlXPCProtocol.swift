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
      scheduleLocked(for: fanIndex)
    }
  }

  @discardableResult
  func renew(for fanIndex: Int) -> Bool {
    queue.sync {
      guard timers[fanIndex] != nil else {
        return false
      }

      scheduleLocked(for: fanIndex)
      return true
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

  private func scheduleLocked(for fanIndex: Int) {
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

protocol AppleSMCControlling: AnyObject {
  func value(for key: String, allowZero: Bool) -> Double?
  func integerValue(for key: String, allowZero: Bool) -> UInt32?
  func canWriteNumeric(for key: String) -> Bool
  func canWriteInteger(for key: String) -> Bool
  func writeNumeric(_ numericValue: Double, for key: String) throws
  func writeInteger(_ integerValue: UInt32, for key: String) throws
  func updateInteger(for key: String, transform: (UInt32) -> UInt32) throws
}

protocol FanControlPlatformChecking {
  var isAppleSilicon: Bool { get }
}

enum AppleSMCFanControlError: Error {
  case unsupportedPlatform
  case smcUnavailable(String)
  case noFansAvailable
  case fanNotFound(Int)
  case incompleteTelemetry(Int)
  case modeControlUnavailable(Int)
  case targetControlUnavailable(Int)
  case smcKeyUnavailable(String)
  case stateSnapshotUnavailable(String)
  case invalidDataSize(key: String, expected: Int, actual: Int)
  case unsupportedDataType(key: String, dataType: String)
  case valueOutOfRange(key: String, dataType: String, value: Double)
  case targetOutOfRange(index: Int, requested: Int, minimum: Int, maximum: Int)
  case verificationFailed(String)
  case rollbackFailed(primaryMessage: String, rollbackMessage: String)
  case writeFailed(key: String, description: String)

  var message: String {
    switch self {
    case .unsupportedPlatform:
      return "Fan control helper supports Apple Silicon only."
    case let .smcUnavailable(message):
      return message
    case .noFansAvailable:
      return "No controllable fans were reported by AppleSMC."
    case let .fanNotFound(index):
      return "Fan \(index) is not available on this Mac."
    case let .incompleteTelemetry(index):
      return "Fan telemetry is incomplete for fan \(index)."
    case let .modeControlUnavailable(index):
      return "Manual fan mode is not exposed for fan \(index) on this Mac."
    case let .targetControlUnavailable(index):
      return "Target RPM writes are not exposed for fan \(index) on this Mac."
    case let .smcKeyUnavailable(key):
      return "AppleSMC key \(key) is not available on this Mac."
    case let .stateSnapshotUnavailable(key):
      return "AppleSMC key \(key) could not be read for rollback or verification."
    case let .invalidDataSize(key, expected, actual):
      return "AppleSMC key \(key) expected \(expected) bytes, but got \(actual)."
    case let .unsupportedDataType(key, dataType):
      return "AppleSMC key \(key) uses unsupported type \(dataType)."
    case let .valueOutOfRange(key, dataType, value):
      return "Value \(value) is out of range for AppleSMC key \(key) (\(dataType))."
    case let .targetOutOfRange(index, requested, minimum, maximum):
      return "Fan \(index) target \(requested) RPM is outside the safe range \(minimum)-\(maximum) RPM."
    case let .verificationFailed(message):
      return "AppleSMC write verification failed: \(message)"
    case let .rollbackFailed(primaryMessage, rollbackMessage):
      return "\(primaryMessage) Rollback also failed: \(rollbackMessage)"
    case let .writeFailed(key, description):
      return "AppleSMC write to \(key) failed: \(description)."
    }
  }
}

private struct FanModeWriteCapabilities {
  let index: Int
  let modeKey: String
  let forceKey: String
  let maskBit: UInt32
  let writesModeKey: Bool
  let writesForceMask: Bool
}

private struct FanModeSnapshot {
  let capabilities: FanModeWriteCapabilities
  let modeKeyValue: UInt32?
  let forceMaskValue: UInt32?
}

private struct FanTargetSnapshot {
  let key: String
  let value: Int
}

final class AppleSMCFanController: FanControlControlling {
  private let smc: AppleSMCControlling
  private let platform: FanControlPlatformChecking

  init(smc: AppleSMCControlling, platform: FanControlPlatformChecking) {
    self.smc = smc
    self.platform = platform
  }

  func setFanMode(index: Int, mode: AppleSMCFanMode) throws {
    try validateWritableFan(index)
    let snapshot = try captureModeSnapshot(for: index)

    do {
      try writeMode(mode, using: snapshot.capabilities)
    } catch let error as AppleSMCFanControlError {
      try rollbackThenThrow(error) {
        try restoreModeSnapshot(snapshot)
      }
    }
  }

  func setFanTargetRpm(index: Int, targetRpm: Int) throws {
    try validateWritableFan(index)

    let bounds = try fanBounds(for: index)
    try validateTarget(targetRpm, bounds: bounds, index: index)
    let snapshot = try captureTargetSnapshot(for: index)

    do {
      try writeTarget(targetRpm, for: index)
    } catch let error as AppleSMCFanControlError {
      try rollbackThenThrow(error) {
        try restoreTargetSnapshot(snapshot)
      }
    }
  }

  func applyManualTargetRpm(index: Int, targetRpm: Int) throws {
    try validateWritableFan(index)

    let bounds = try fanBounds(for: index)
    try validateTarget(targetRpm, bounds: bounds, index: index)
    let modeSnapshot = try captureModeSnapshot(for: index)
    let targetSnapshot = try captureTargetSnapshot(for: index)

    do {
      try writeMode(.manual, using: modeSnapshot.capabilities)
      try writeTarget(targetRpm, for: index)
    } catch let error as AppleSMCFanControlError {
      try rollbackThenThrow(error) {
        try restoreTargetSnapshot(targetSnapshot)
        try restoreModeSnapshot(modeSnapshot)
      }
    }
  }

  private func validateWritableFan(_ index: Int) throws {
    guard platform.isAppleSilicon else {
      throw AppleSMCFanControlError.unsupportedPlatform
    }

    try validateFanIndex(index)
  }

  private func validateFanIndex(_ index: Int) throws {
    let fanCount = readFanCount()
    guard fanCount > 0 else {
      throw AppleSMCFanControlError.noFansAvailable
    }

    guard index >= 0, index < fanCount else {
      throw AppleSMCFanControlError.fanNotFound(index)
    }
  }

  private func readFanCount() -> Int {
    guard let rawFanCount = smc.value(for: "FNum", allowZero: true) else {
      return 0
    }

    return max(0, Int(rawFanCount.rounded(.towardZero)))
  }

  private func fanBounds(for index: Int) throws -> (minimumRpm: Int, maximumRpm: Int) {
    guard let current = smc.value(for: "F\(index)Ac", allowZero: false) else {
      throw AppleSMCFanControlError.incompleteTelemetry(index)
    }

    let minimum = Int((smc.value(for: "F\(index)Mn", allowZero: false) ?? current).rounded())
    let maximum = Int((smc.value(for: "F\(index)Mx", allowZero: false) ?? current).rounded())

    return (
      minimumRpm: min(minimum, maximum),
      maximumRpm: max(minimum, maximum)
    )
  }

  private func validateTarget(
    _ targetRpm: Int,
    bounds: (minimumRpm: Int, maximumRpm: Int),
    index: Int
  ) throws {
    guard targetRpm >= bounds.minimumRpm, targetRpm <= bounds.maximumRpm else {
      throw AppleSMCFanControlError.targetOutOfRange(
        index: index,
        requested: targetRpm,
        minimum: bounds.minimumRpm,
        maximum: bounds.maximumRpm
      )
    }
  }

  private func captureModeSnapshot(for index: Int) throws -> FanModeSnapshot {
    let capabilities = FanModeWriteCapabilities(
      index: index,
      modeKey: "F\(index)Md",
      forceKey: "FS! ",
      maskBit: UInt32(1) << UInt32(index),
      writesModeKey: smc.canWriteInteger(for: "F\(index)Md"),
      writesForceMask: smc.canWriteInteger(for: "FS! ")
    )

    guard capabilities.writesModeKey || capabilities.writesForceMask else {
      throw AppleSMCFanControlError.modeControlUnavailable(index)
    }

    let modeKeyValue =
      capabilities.writesModeKey
      ? try readIntegerKey(capabilities.modeKey, allowZero: true)
      : nil
    let forceMaskValue =
      capabilities.writesForceMask
      ? try readIntegerKey(capabilities.forceKey, allowZero: true)
      : nil

    return FanModeSnapshot(
      capabilities: capabilities,
      modeKeyValue: modeKeyValue,
      forceMaskValue: forceMaskValue
    )
  }

  private func captureTargetSnapshot(for index: Int) throws -> FanTargetSnapshot {
    let targetKey = "F\(index)Tg"
    guard smc.canWriteNumeric(for: targetKey) else {
      throw AppleSMCFanControlError.targetControlUnavailable(index)
    }

    guard let value = smc.value(for: targetKey, allowZero: true) else {
      throw AppleSMCFanControlError.stateSnapshotUnavailable(targetKey)
    }

    return FanTargetSnapshot(key: targetKey, value: Int(value.rounded()))
  }

  private func writeMode(
    _ mode: AppleSMCFanMode,
    using capabilities: FanModeWriteCapabilities
  ) throws {
    let modeValue: UInt32 = mode == .manual ? 1 : 0
    var results: [Result<Void, AppleSMCFanControlError>] = []

    if capabilities.writesModeKey {
      do {
        try smc.writeInteger(modeValue, for: capabilities.modeKey)
        results.append(.success(()))
      } catch let error as AppleSMCFanControlError {
        results.append(.failure(error))
      }
    }

    if capabilities.writesForceMask {
      do {
        try smc.updateInteger(for: capabilities.forceKey) { currentValue in
          mode == .manual
            ? (currentValue | capabilities.maskBit)
            : (currentValue & ~capabilities.maskBit)
        }
        results.append(.success(()))
      } catch let error as AppleSMCFanControlError {
        results.append(.failure(error))
      }
    }

    try FanControlWriteResultValidator.validate(
      results,
      unavailableError: AppleSMCFanControlError.modeControlUnavailable(capabilities.index)
    )
    try verifyMode(mode, using: capabilities)
  }

  private func restoreModeSnapshot(_ snapshot: FanModeSnapshot) throws {
    if snapshot.capabilities.writesModeKey {
      guard let modeKeyValue = snapshot.modeKeyValue else {
        throw AppleSMCFanControlError.stateSnapshotUnavailable(snapshot.capabilities.modeKey)
      }
      try smc.writeInteger(modeKeyValue, for: snapshot.capabilities.modeKey)
      try verifyIntegerValue(
        modeKeyValue,
        for: snapshot.capabilities.modeKey,
        failureDescription:
          "expected \(snapshot.capabilities.modeKey) to restore to \(modeKeyValue)"
      )
    }

    if snapshot.capabilities.writesForceMask {
      guard let forceMaskValue = snapshot.forceMaskValue else {
        throw AppleSMCFanControlError.stateSnapshotUnavailable(snapshot.capabilities.forceKey)
      }
      try smc.writeInteger(forceMaskValue, for: snapshot.capabilities.forceKey)
      try verifyIntegerValue(
        forceMaskValue,
        for: snapshot.capabilities.forceKey,
        failureDescription:
          "expected \(snapshot.capabilities.forceKey) to restore to \(forceMaskValue)"
      )
    }
  }

  private func verifyMode(
    _ mode: AppleSMCFanMode,
    using capabilities: FanModeWriteCapabilities
  ) throws {
    let expectsManual = mode == .manual

    if capabilities.writesModeKey {
      let actualModeValue = try readIntegerKey(capabilities.modeKey, allowZero: true)
      guard (actualModeValue > 0) == expectsManual else {
        throw AppleSMCFanControlError.verificationFailed(
          "expected \(capabilities.modeKey) to indicate \(mode), but read back \(actualModeValue)"
        )
      }
    }

    if capabilities.writesForceMask {
      let actualForceMask = try readIntegerKey(capabilities.forceKey, allowZero: true)
      let isManual = (actualForceMask & capabilities.maskBit) != 0
      guard isManual == expectsManual else {
        let expectedState = expectsManual ? "set" : "cleared"
        throw AppleSMCFanControlError.verificationFailed(
          "expected \(capabilities.forceKey) bit \(capabilities.index) to be \(expectedState), but read back \(actualForceMask)"
        )
      }
    }
  }

  private func writeTarget(_ targetRpm: Int, for index: Int) throws {
    let targetKey = "F\(index)Tg"
    guard smc.canWriteNumeric(for: targetKey) else {
      throw AppleSMCFanControlError.targetControlUnavailable(index)
    }

    try smc.writeNumeric(Double(targetRpm), for: targetKey)
    try verifyTarget(targetRpm, for: targetKey)
  }

  private func restoreTargetSnapshot(_ snapshot: FanTargetSnapshot) throws {
    try smc.writeNumeric(Double(snapshot.value), for: snapshot.key)
    try verifyTarget(snapshot.value, for: snapshot.key)
  }

  private func verifyTarget(_ expectedTargetRpm: Int, for key: String) throws {
    guard let actualValue = smc.value(for: key, allowZero: true) else {
      throw AppleSMCFanControlError.stateSnapshotUnavailable(key)
    }

    let actualTargetRpm = Int(actualValue.rounded())
    guard actualTargetRpm == expectedTargetRpm else {
      throw AppleSMCFanControlError.verificationFailed(
        "expected \(key) to read back \(expectedTargetRpm) RPM, but got \(actualTargetRpm) RPM"
      )
    }
  }

  private func readIntegerKey(_ key: String, allowZero: Bool) throws -> UInt32 {
    guard let value = smc.integerValue(for: key, allowZero: allowZero) else {
      throw AppleSMCFanControlError.stateSnapshotUnavailable(key)
    }

    return value
  }

  private func verifyIntegerValue(
    _ expected: UInt32,
    for key: String,
    failureDescription: String
  ) throws {
    let actual = try readIntegerKey(key, allowZero: true)
    guard actual == expected else {
      throw AppleSMCFanControlError.verificationFailed(
        "\(failureDescription), but read back \(actual)"
      )
    }
  }

  private func rollbackThenThrow(
    _ primaryError: AppleSMCFanControlError,
    rollback: () throws -> Void
  ) throws {
    do {
      try rollback()
    } catch let rollbackError as AppleSMCFanControlError {
      throw AppleSMCFanControlError.rollbackFailed(
        primaryMessage: primaryError.message,
        rollbackMessage: rollbackError.message
      )
    } catch {
      throw AppleSMCFanControlError.rollbackFailed(
        primaryMessage: primaryError.message,
        rollbackMessage: String(describing: error)
      )
    }

    throw primaryError
  }
}

protocol FanControlControlling: AnyObject {
  func setFanMode(index: Int, mode: AppleSMCFanMode) throws
  func applyManualTargetRpm(index: Int, targetRpm: Int) throws
}

@objc protocol FanControlXPCProtocol {
  func setFanMode(
    _ fanIndex: Int,
    modeRawValue: Int,
    withReply reply: @escaping (String?) -> Void
  )

  func applyManualTargetRpm(
    _ fanIndex: Int,
    targetRpm: Int,
    withReply reply: @escaping (String?) -> Void
  )

  func renewManualLease(
    _ fanIndex: Int,
    withReply reply: @escaping (String?) -> Void
  )
}
