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
      setFanTargetRpmHandler: { _, _, reply in
        reply("unexpected target write")
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
      connectionFactory: { _ in connection }
    )

    XCTAssertNoThrow(try client.setFanTargetRpm(fanId: "fan-1", targetRpm: 2450))
    XCTAssertEqual(received?.fanIndex, 1)
    XCTAssertEqual(received?.targetRpm, 2450)
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
  typealias FanTargetHandler = (Int, Int, @escaping (String?) -> Void) -> Void
  typealias ApplyManualTargetHandler = (Int, Int, @escaping (String?) -> Void) -> Void

  private let setFanModeHandler: FanModeHandler
  private let setFanTargetRpmHandler: FanTargetHandler
  private let applyManualTargetRpmHandler: ApplyManualTargetHandler

  init(
    setFanModeHandler: @escaping FanModeHandler,
    setFanTargetRpmHandler: @escaping FanTargetHandler = { _, _, reply in reply(nil) },
    applyManualTargetRpmHandler: @escaping ApplyManualTargetHandler = { _, _, reply in reply(nil) }
  ) {
    self.setFanModeHandler = setFanModeHandler
    self.setFanTargetRpmHandler = setFanTargetRpmHandler
    self.applyManualTargetRpmHandler = applyManualTargetRpmHandler
  }

  func setFanMode(
    _ fanIndex: Int,
    modeRawValue: Int,
    withReply reply: @escaping (String?) -> Void
  ) {
    setFanModeHandler(fanIndex, modeRawValue, reply)
  }

  func setFanTargetRpm(
    _ fanIndex: Int,
    targetRpm: Int,
    withReply reply: @escaping (String?) -> Void
  ) {
    setFanTargetRpmHandler(fanIndex, targetRpm, reply)
  }

  func applyManualTargetRpm(
    _ fanIndex: Int,
    targetRpm: Int,
    withReply reply: @escaping (String?) -> Void
  ) {
    applyManualTargetRpmHandler(fanIndex, targetRpm, reply)
  }
}
