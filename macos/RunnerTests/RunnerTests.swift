import XCTest
@testable import MacFanTool

private let testEnvironment = ResolvedEnvironment(
  configuration: FanControlHelperConfiguration(appBundleIdentifier: "com.example.macFanTool"),
  helperRequirement: "helper-requirement"
)

private enum TestWriteError: Error, Equatable {
  case unavailable
  case partialFailure
}

private struct NoOpServiceReadinessChecker: FanControlServiceReadinessChecking {
  func ensureReady(environment: ResolvedEnvironment) throws {}
}

final class RunnerTests: XCTestCase {
  func testCodeSigningRequirementBuilderIncludesAnchorAndTeam() {
    XCTAssertEqual(
      CodeSigningRequirementBuilder.requirement(
        identifier: "com.example.macFanTool",
        teamIdentifier: "TEAM123456"
      ),
      """
      identifier "com.example.macFanTool" and anchor apple generic and certificate leaf[subject.OU] = "TEAM123456"
      """
    )
  }

  func testFanControlWriteResultValidatorFailsWhenAnyWriteFails() {
    XCTAssertThrowsError(
      try FanControlWriteResultValidator.validate(
        [.success(()), .failure(TestWriteError.partialFailure)],
        unavailableError: TestWriteError.unavailable
      )
    ) { error in
      XCTAssertEqual(error as? TestWriteError, .partialFailure)
    }
  }

  func testFanControlWriteResultValidatorFailsWhenNoWritePathExists() {
    XCTAssertThrowsError(
      try FanControlWriteResultValidator.validate(
        [] as [Result<Void, TestWriteError>],
        unavailableError: TestWriteError.unavailable
      )
    ) { error in
      XCTAssertEqual(error as? TestWriteError, .unavailable)
    }
  }

  func testPerformCommandFailsWhenConnectionInvalidatesBeforeReply() {
    let remote = FakeFanControlRemote { _, _, _ in }
    let connection = FakeFanControlConnection(remote: remote)
    connection.onResume = { [weak connection] in
      connection?.invalidationHandler?()
    }

    let client = FanControlHelperClient(
      commandTimeout: .seconds(1),
      environmentResolver: { testEnvironment },
      connectionFactory: { _ in connection }
    )

    XCTAssertThrowsError(
      try client.performCommand(environment: testEnvironment) { remote, reply in
        remote.setFanMode(0, modeRawValue: FanModeData.manual.rawValue, withReply: reply)
      }
    ) { error in
      XCTAssertEqual(
        error as? FanControlHelperClientError,
        .connectionFailed("The privileged helper connection was invalidated before replying.")
      )
    }
  }

  func testPerformCommandTimesOutWhenHelperDoesNotReply() {
    let remote = FakeFanControlRemote { _, _, _ in }
    let connection = FakeFanControlConnection(remote: remote)
    let client = FanControlHelperClient(
      commandTimeout: .milliseconds(50),
      environmentResolver: { testEnvironment },
      connectionFactory: { _ in connection }
    )

    XCTAssertThrowsError(
      try client.performCommand(environment: testEnvironment) { remote, reply in
        remote.setFanMode(0, modeRawValue: FanModeData.manual.rawValue, withReply: reply)
      }
    ) { error in
      XCTAssertEqual(
        error as? FanControlHelperClientError,
        .connectionFailed("Timed out while waiting for the privileged helper.")
      )
    }
  }

  func testPerformCommandSucceedsWhenHelperReplies() throws {
    let remote = FakeFanControlRemote { _, _, reply in
      reply(nil)
    }
    let connection = FakeFanControlConnection(remote: remote)
    let client = FanControlHelperClient(
      commandTimeout: .seconds(1),
      environmentResolver: { testEnvironment },
      connectionFactory: { _ in connection }
    )

    XCTAssertNoThrow(
      try client.performCommand(environment: testEnvironment) { remote, reply in
        remote.setFanMode(0, modeRawValue: FanModeData.manual.rawValue, withReply: reply)
      }
    )
    XCTAssertTrue(connection.didInvalidate)
  }

  func testSetFanTargetRpmUsesAtomicHelperCommand() throws {
    var received: (fanIndex: Int, targetRpm: Int)?
    let remote = FakeFanControlRemote(
      setFanModeHandler: { _, _, reply in
        reply("unexpected mode write")
      },
      applyManualTargetRpmHandler: { fanIndex, targetRpm, reply in
        received = (fanIndex, targetRpm)
        reply(nil)
      }
    )
    let connection = FakeFanControlConnection(remote: remote)
    let client = FanControlHelperClient(
      commandTimeout: .seconds(1),
      environmentResolver: { testEnvironment },
      connectionFactory: { _ in connection },
      serviceReadinessChecker: NoOpServiceReadinessChecker()
    )

    XCTAssertNoThrow(try client.setFanTargetRpm(fanId: "fan-1", targetRpm: 2450))
    XCTAssertEqual(received?.fanIndex, 1)
    XCTAssertEqual(received?.targetRpm, 2450)
  }

  func testRenewManualLeaseUsesHelperRenewCommand() throws {
    var renewedFanIndex: Int?
    let remote = FakeFanControlRemote(
      setFanModeHandler: { _, _, reply in
        reply(nil)
      },
      renewManualLeaseHandler: { fanIndex, reply in
        renewedFanIndex = fanIndex
        reply(nil)
      }
    )
    let connection = FakeFanControlConnection(remote: remote)
    let client = FanControlHelperClient(
      commandTimeout: .seconds(1),
      environmentResolver: { testEnvironment },
      connectionFactory: { _ in connection },
      serviceReadinessChecker: NoOpServiceReadinessChecker()
    )

    XCTAssertNoThrow(try client.renewManualLease(fanId: "fan-1"))
    XCTAssertEqual(renewedFanIndex, 1)
  }

  func testAppleSMCFanControllerRejectsOutOfRangeTargetsWithoutWriting() {
    let smc = FakeAppleSMC(
      numericValues: [
        "FNum": 1,
        "F0Ac": 2200,
        "F0Mn": 1200,
        "F0Mx": 4000,
        "F0Tg": 2200,
      ],
      integerValues: [
        "F0Md": 0,
        "FS! ": 0,
      ],
      numericWritableKeys: ["F0Tg"],
      integerWritableKeys: ["F0Md", "FS! "]
    )
    let controller = AppleSMCFanController(
      smc: smc,
      platform: TestFanControlPlatform(isAppleSilicon: true)
    )

    XCTAssertThrowsError(try controller.applyManualTargetRpm(index: 0, targetRpm: 1100)) { error in
      guard let fanError = error as? AppleSMCFanControlError else {
        return XCTFail("Unexpected error: \(error)")
      }
      guard case let .targetOutOfRange(index, requested, minimum, maximum) = fanError else {
        return XCTFail("Unexpected error: \(fanError)")
      }
      XCTAssertEqual(index, 0)
      XCTAssertEqual(requested, 1100)
      XCTAssertEqual(minimum, 1200)
      XCTAssertEqual(maximum, 4000)
    }
    XCTAssertTrue(smc.writeLog.isEmpty)
  }

  func testAppleSMCFanControllerRollsBackModeAndTargetWhenTargetVerificationFails() {
    let smc = FakeAppleSMC(
      numericValues: [
        "FNum": 1,
        "F0Ac": 2200,
        "F0Mn": 1200,
        "F0Mx": 4000,
        "F0Tg": 2200,
      ],
      integerValues: [
        "F0Md": 0,
        "FS! ": 0,
      ],
      numericWritableKeys: ["F0Tg"],
      integerWritableKeys: ["F0Md", "FS! "]
    )
    var targetWrites = 0
    smc.numericWriteBehaviors["F0Tg"] = { value in
      targetWrites += 1
      return targetWrites == 1 ? value + 75 : value
    }
    let controller = AppleSMCFanController(
      smc: smc,
      platform: TestFanControlPlatform(isAppleSilicon: true)
    )

    XCTAssertThrowsError(try controller.applyManualTargetRpm(index: 0, targetRpm: 2450)) { error in
      guard let fanError = error as? AppleSMCFanControlError else {
        return XCTFail("Unexpected error: \(error)")
      }
      guard case let .verificationFailed(message) = fanError else {
        return XCTFail("Unexpected error: \(fanError)")
      }
      XCTAssertTrue(message.contains("F0Tg"))
    }

    XCTAssertEqual(smc.numericValues["F0Tg"], 2200)
    XCTAssertEqual(smc.integerValues["F0Md"], 0)
    XCTAssertEqual(smc.integerValues["FS! "], 0)
  }

  func testAppleSMCFanControllerReportsRollbackFailureWhenRestoreFails() {
    let smc = FakeAppleSMC(
      numericValues: [
        "FNum": 1,
        "F0Ac": 2200,
        "F0Mn": 1200,
        "F0Mx": 4000,
        "F0Tg": 2200,
      ],
      integerValues: [
        "F0Md": 0,
        "FS! ": 0,
      ],
      numericWritableKeys: ["F0Tg"],
      integerWritableKeys: ["F0Md", "FS! "]
    )
    var targetWrites = 0
    smc.numericWriteBehaviors["F0Tg"] = { value in
      targetWrites += 1
      if targetWrites == 1 {
        return value + 50
      }

      throw AppleSMCFanControlError.writeFailed(
        key: "F0Tg",
        description: "rollback refused"
      )
    }
    let controller = AppleSMCFanController(
      smc: smc,
      platform: TestFanControlPlatform(isAppleSilicon: true)
    )

    XCTAssertThrowsError(try controller.applyManualTargetRpm(index: 0, targetRpm: 2450)) { error in
      guard let fanError = error as? AppleSMCFanControlError else {
        return XCTFail("Unexpected error: \(error)")
      }
      guard case let .rollbackFailed(primaryMessage, rollbackMessage) = fanError else {
        return XCTFail("Unexpected error: \(fanError)")
      }
      XCTAssertTrue(primaryMessage.contains("verification failed"))
      XCTAssertTrue(rollbackMessage.contains("rollback refused"))
    }
  }

  func testSetFanModeRejectsNonCanonicalFanIds() {
    let client = FanControlHelperClient()

    for fanId in ["cpu-fan-1", "fan-1-extra", "fan-", "Fan-1"] {
      XCTAssertThrowsError(try client.setFanMode(fanId: fanId, mode: .manual)) { error in
        XCTAssertEqual(error as? FanControlHelperClientError, .invalidFanId(fanId))
      }
    }
  }

  func testManualFanLeaseControllerExpiresArmedLease() {
    let leaseExpired = expectation(description: "manual lease expired")

    let leaseController = ManualFanLeaseController(
      duration: DispatchTimeInterval.milliseconds(50),
      queue: DispatchQueue(label: "RunnerTests.manualLease.expiry")
    ) { fanIndex in
      XCTAssertEqual(fanIndex, 0)
      leaseExpired.fulfill()
    }

    leaseController.arm(for: 0)

    wait(for: [leaseExpired], timeout: 1.0)
  }

  func testManualFanLeaseControllerCancelPreventsExpiry() {
    let unexpectedExpiry = expectation(description: "lease should not expire")
    unexpectedExpiry.isInverted = true
    let leaseWindowElapsed = expectation(description: "lease window elapsed")

    let leaseController = ManualFanLeaseController(
      duration: DispatchTimeInterval.milliseconds(50),
      queue: DispatchQueue(label: "RunnerTests.manualLease.cancel")
    ) { _ in
      unexpectedExpiry.fulfill()
    }

    leaseController.arm(for: 0)
    leaseController.cancel(for: 0)

    DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(150)) {
      leaseWindowElapsed.fulfill()
    }

    wait(for: [unexpectedExpiry, leaseWindowElapsed], timeout: 1.0)
  }

  func testManualFanLeaseControllerRenewExtendsArmedLease() {
    let unexpectedEarlyExpiry = expectation(description: "lease should not expire early")
    unexpectedEarlyExpiry.isInverted = true
    let earlyLeaseWindowElapsed = expectation(description: "early lease window elapsed")
    let renewedLeaseExpired = expectation(description: "renewed lease expired")
    var renewalWindowElapsed = false

    let leaseController = ManualFanLeaseController(
      duration: DispatchTimeInterval.milliseconds(50),
      queue: DispatchQueue(label: "RunnerTests.manualLease.renew")
    ) { _ in
      if renewalWindowElapsed {
        renewedLeaseExpired.fulfill()
      } else {
        unexpectedEarlyExpiry.fulfill()
      }
    }

    leaseController.arm(for: 0)
    DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(25)) {
      XCTAssertTrue(leaseController.renew(for: 0))
    }
    DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(60)) {
      renewalWindowElapsed = true
      earlyLeaseWindowElapsed.fulfill()
    }

    wait(for: [unexpectedEarlyExpiry, earlyLeaseWindowElapsed], timeout: 0.08)
    wait(for: [renewedLeaseExpired], timeout: 1.0)
  }

  func testHardwareSensorBridgeSupportReturnsEmptyForMissingClient() {
    XCTAssertTrue(HardwareSensorBridgeSupport.temperatureValuesForSystemClient(nil).isEmpty)
  }
}

private final class FakeFanControlConnection: FanControlXPCConnection {
  var invalidationHandler: (() -> Void)?
  var interruptionHandler: (() -> Void)?
  var onResume: (() -> Void)?
  var remote: FanControlXPCProtocol?
  private(set) var didInvalidate = false

  init(remote: FanControlXPCProtocol? = nil) {
    self.remote = remote
  }

  func resume() {
    onResume?()
  }

  func invalidate() {
    didInvalidate = true
  }

  func remoteObjectProxy(errorHandler: @escaping (any Error) -> Void) -> FanControlXPCProtocol? {
    remote
  }
}

private final class FakeFanControlRemote: NSObject, FanControlXPCProtocol {
  typealias FanModeHandler = (Int, Int, @escaping (String?) -> Void) -> Void
  typealias ApplyManualTargetHandler = (Int, Int, @escaping (String?) -> Void) -> Void
  typealias RenewManualLeaseHandler = (Int, @escaping (String?) -> Void) -> Void

  private let setFanModeHandler: FanModeHandler
  private let applyManualTargetRpmHandler: ApplyManualTargetHandler
  private let renewManualLeaseHandler: RenewManualLeaseHandler

  init(
    setFanModeHandler: @escaping FanModeHandler,
    applyManualTargetRpmHandler: @escaping ApplyManualTargetHandler = { _, _, reply in reply(nil) },
    renewManualLeaseHandler: @escaping RenewManualLeaseHandler = { _, reply in reply(nil) }
  ) {
    self.setFanModeHandler = setFanModeHandler
    self.applyManualTargetRpmHandler = applyManualTargetRpmHandler
    self.renewManualLeaseHandler = renewManualLeaseHandler
  }

  func setFanMode(
    _ fanIndex: Int,
    modeRawValue: Int,
    withReply reply: @escaping (String?) -> Void
  ) {
    setFanModeHandler(fanIndex, modeRawValue, reply)
  }

  func applyManualTargetRpm(
    _ fanIndex: Int,
    targetRpm: Int,
    withReply reply: @escaping (String?) -> Void
  ) {
    applyManualTargetRpmHandler(fanIndex, targetRpm, reply)
  }

  func renewManualLease(
    _ fanIndex: Int,
    withReply reply: @escaping (String?) -> Void
  ) {
    renewManualLeaseHandler(fanIndex, reply)
  }
}

private struct TestFanControlPlatform: FanControlPlatformChecking {
  let isAppleSilicon: Bool
}

private final class FakeAppleSMC: AppleSMCControlling {
  var numericValues: [String: Double]
  var integerValues: [String: UInt32]
  let numericWritableKeys: Set<String>
  let integerWritableKeys: Set<String>
  var numericWriteBehaviors: [String: (Double) throws -> Double] = [:]
  var integerWriteBehaviors: [String: (UInt32) throws -> UInt32] = [:]
  private(set) var writeLog: [String] = []

  init(
    numericValues: [String: Double],
    integerValues: [String: UInt32],
    numericWritableKeys: Set<String>,
    integerWritableKeys: Set<String>
  ) {
    self.numericValues = numericValues
    self.integerValues = integerValues
    self.numericWritableKeys = numericWritableKeys
    self.integerWritableKeys = integerWritableKeys
  }

  func value(for key: String, allowZero: Bool) -> Double? {
    guard let value = numericValues[key] else {
      return nil
    }

    if !allowZero && value == 0 {
      return nil
    }

    return value
  }

  func integerValue(for key: String, allowZero: Bool) -> UInt32? {
    guard let value = integerValues[key] else {
      return nil
    }

    if !allowZero && value == 0 {
      return nil
    }

    return value
  }

  func canWriteNumeric(for key: String) -> Bool {
    numericWritableKeys.contains(key)
  }

  func canWriteInteger(for key: String) -> Bool {
    integerWritableKeys.contains(key)
  }

  func writeNumeric(_ numericValue: Double, for key: String) throws {
    writeLog.append("numeric:\(key):\(numericValue)")
    let storedValue = try numericWriteBehaviors[key]?(numericValue) ?? numericValue
    numericValues[key] = storedValue
  }

  func writeInteger(_ integerValue: UInt32, for key: String) throws {
    writeLog.append("integer:\(key):\(integerValue)")
    let storedValue = try integerWriteBehaviors[key]?(integerValue) ?? integerValue
    integerValues[key] = storedValue
  }

  func updateInteger(for key: String, transform: (UInt32) -> UInt32) throws {
    guard let currentValue = integerValues[key] else {
      throw AppleSMCFanControlError.smcKeyUnavailable(key)
    }

    try writeInteger(transform(currentValue), for: key)
  }
}
