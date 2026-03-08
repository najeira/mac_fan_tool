import Dispatch
import Foundation

/// アプリ本体と特権ヘルパーで共有するバンドル識別子やサービス名を組み立てます。
struct FanControlHelperConfiguration {
  static let helperBundleSuffix = ".FanControlHelper"
  static let machServiceSuffix = ".fancontrol.helper"
  static let launchDaemonPlistName = "FanControlHelper.plist"
  static let helperRelativePath = "Contents/Library/HelperTools/FanControlHelper"

  let appBundleIdentifier: String

  var helperBundleIdentifier: String {
    "\(appBundleIdentifier)\(Self.helperBundleSuffix)"
  }

  var machServiceName: String {
    "\(appBundleIdentifier)\(Self.machServiceSuffix)"
  }

  /// 現在の実行バンドルからアプリ本体用の設定値を組み立てます。
  static func currentAppConfiguration(bundle: Bundle = .main) -> FanControlHelperConfiguration? {
    guard let appBundleIdentifier = appBundleIdentifier(for: bundle) else {
      return nil
    }

    return FanControlHelperConfiguration(appBundleIdentifier: appBundleIdentifier)
  }

  /// ヘルパー実行時でもアプリ本体のバンドル ID を逆算して返します。
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

/// 指定したバンドル ID とチーム ID からコード署名要件文字列を生成します。
enum CodeSigningRequirementBuilder {
  static func requirement(identifier: String, teamIdentifier: String) -> String {
    "identifier \"\(identifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
  }
}

/// 複数の SMC 書き込み結果を検証し、失敗があれば最初のエラーを返します。
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

/// AppleSMC が受け付けるファン制御モードを表します。
enum AppleSMCFanMode: Int {
  case automatic = 0
  case manual = 1
}

/// 手動ファン制御の有効期限をファン単位で管理するタイマーです。
final class ManualFanLeaseController {
  typealias ExpirationHandler = (Int) -> Void

  private let duration: DispatchTimeInterval
  private let queue: DispatchQueue
  private let expirationHandler: ExpirationHandler
  private var timers: [Int: DispatchSourceTimer] = [:]

  /// リース継続時間と満了時のコールバックを受け取ってタイマー管理を初期化します。
  init(
    duration: DispatchTimeInterval,
    queue: DispatchQueue = DispatchQueue(label: "ManualFanLeaseController"),
    expirationHandler: @escaping ExpirationHandler
  ) {
    self.duration = duration
    self.queue = queue
    self.expirationHandler = expirationHandler
  }

  /// 指定したファンの期限タイマーを開始または再設定します。
  func arm(for fanIndex: Int) {
    queue.sync {
      scheduleLocked(for: fanIndex)
    }
  }

  /// 既存の期限タイマーを延長し、未管理のファンなら失敗を返します。
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

  /// 指定したファンの期限タイマーを停止します。
  func cancel(for fanIndex: Int) {
    queue.sync {
      cancelLocked(for: fanIndex)
    }
  }

  /// リース満了時にタイマーを破棄して期限切れハンドラを呼び出します。
  private func expireLease(for fanIndex: Int) {
    cancelLocked(for: fanIndex)
    expirationHandler(fanIndex)
  }

  /// 管理中のタイマーがあれば停止して辞書から取り除きます。
  private func cancelLocked(for fanIndex: Int) {
    guard let timer = timers.removeValue(forKey: fanIndex) else {
      return
    }

    timer.cancel()
  }

  /// 指定ファン向けに単発の期限タイマーを新規作成します。
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

/// AppleSMC キーの読み書きに必要な最小 API を抽象化します。
protocol AppleSMCControlling: AnyObject {
  /// 指定キーの数値を読み取ります。
  func value(for key: String, allowZero: Bool) -> Double?
  /// 指定キーの整数値を読み取ります。
  func integerValue(for key: String, allowZero: Bool) -> UInt32?
  /// 指定キーが数値書き込み可能かを返します。
  func canWriteNumeric(for key: String) -> Bool
  /// 指定キーが整数書き込み可能かを返します。
  func canWriteInteger(for key: String) -> Bool
  /// 指定キーへ数値を書き込みます。
  func writeNumeric(_ numericValue: Double, for key: String) throws
  /// 指定キーへ整数を書き込みます。
  func writeInteger(_ integerValue: UInt32, for key: String) throws
  /// 指定キーの整数値を読み取って変換し、結果を書き戻します。
  func updateInteger(for key: String, transform: (UInt32) -> UInt32) throws
}

/// ファン制御を行えるハードウェア条件を判定するための抽象化です。
protocol FanControlPlatformChecking {
  var isAppleSilicon: Bool { get }
}

/// ファン制御処理でユーザー向けに返す失敗理由をまとめたエラーです。
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

/// Apple Silicon の AppleSMC を通じてファンモードと目標 RPM を安全に更新します。
final class AppleSMCFanController: FanControlControlling {
  private enum TargetWriteVerification {
    static let maxWriteAttempts = 3
    static let readbackPollCount = 5
    static let readbackPollInterval: TimeInterval = 0.1
  }

  private let smc: AppleSMCControlling
  private let platform: FanControlPlatformChecking
  private let sleep: (TimeInterval) -> Void

  /// SMC 抽象化とプラットフォーム判定を注入してテスト可能な制御器を構築します。
  init(
    smc: AppleSMCControlling,
    platform: FanControlPlatformChecking,
    sleep: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
  ) {
    self.smc = smc
    self.platform = platform
    self.sleep = sleep
  }

  /// 指定ファンのモードを自動または手動へ変更します。
  func setFanMode(index: Int, mode: AppleSMCFanMode) throws {
    try validateWritableFan(index)
    let snapshot = try captureModeSnapshot(for: index)
    try performFanWrite {
      try writeMode(mode, using: snapshot.capabilities)
    } rollback: {
      try restoreModeSnapshot(snapshot)
    }
  }

  /// 指定ファンの目標 RPM を現在のモードのまま更新します。
  func setFanTargetRpm(index: Int, targetRpm: Int) throws {
    try validateWritableFanTarget(index: index, targetRpm: targetRpm)
    let snapshot = try captureTargetSnapshot(for: index)
    try performFanWrite {
      try writeTarget(targetRpm, for: index)
    } rollback: {
      try restoreTargetSnapshot(snapshot)
    }
  }

  /// 指定ファンを手動モードへ切り替えつつ目標 RPM を一括適用します。
  func applyManualTargetRpm(index: Int, targetRpm: Int) throws {
    try validateWritableFanTarget(index: index, targetRpm: targetRpm)
    let modeSnapshot = try captureModeSnapshot(for: index)
    let targetSnapshot = try captureTargetSnapshot(for: index)
    do {
      try performFanWrite {
        try writeMode(.manual, using: modeSnapshot.capabilities)
        try writeTarget(targetRpm, for: index)
      } rollback: {
        try restoreTargetSnapshot(targetSnapshot)
        try restoreModeSnapshot(modeSnapshot)
      }
    } catch let error as AppleSMCFanControlError {
      guard shouldFallbackToLegacyTargetWrite(after: error) else {
        throw error
      }

      // Some Macs accept the target write but reject or lag the combined
      // manual+target transition. Preserve the pre-88a163 behavior as a fallback.
      try setFanTargetRpm(index: index, targetRpm: targetRpm)
    }
  }

  /// Apple Silicon 上で制御可能なファンかを事前検証します。
  private func validateWritableFan(_ index: Int) throws {
    guard platform.isAppleSilicon else {
      throw AppleSMCFanControlError.unsupportedPlatform
    }

    try validateFanIndex(index)
  }

  /// 指定ファンへの書き込み前に存在確認と目標 RPM の範囲検証をまとめて行います。
  private func validateWritableFanTarget(index: Int, targetRpm: Int) throws {
    try validateWritableFan(index)
    let bounds = try fanBounds(for: index)
    try validateTarget(targetRpm, bounds: bounds, index: index)
  }

  /// 指定インデックスが存在するファン番号かどうかを確認します。
  private func validateFanIndex(_ index: Int) throws {
    let fanCount = readFanCount()
    guard fanCount > 0 else {
      throw AppleSMCFanControlError.noFansAvailable
    }

    guard index >= 0, index < fanCount else {
      throw AppleSMCFanControlError.fanNotFound(index)
    }
  }

  /// SMC から現在のファン数を読み取り、整数へ正規化します。
  private func readFanCount() -> Int {
    guard let rawFanCount = smc.value(for: "FNum", allowZero: true) else {
      return 0
    }

    return max(0, Int(rawFanCount.rounded(.towardZero)))
  }

  /// 指定ファンの最小・最大 RPM を読み取り、安全な書き込み範囲を返します。
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

  /// 要求された RPM が読み取った安全範囲内かを確認します。
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

  /// atomic manual apply が verification で落ちたときだけ legacy target-only 経路を試します。
  private func shouldFallbackToLegacyTargetWrite(after error: AppleSMCFanControlError) -> Bool {
    if case .verificationFailed = error {
      return true
    }

    return false
  }

  /// ファン書き込み処理を実行し、失敗時は呼び出し元が渡したロールバックを試行します。
  private func performFanWrite(
    write: () throws -> Void,
    rollback: () throws -> Void
  ) throws {
    do {
      try write()
    } catch let error as AppleSMCFanControlError {
      try rollbackThenThrow(error, rollback: rollback)
    }
  }

  /// モード変更前の SMC 値と書き込み経路をまとめて退避します。
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

  /// 目標 RPM 変更前のターゲット値を退避します。
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

  /// 利用可能な SMC 書き込み経路を使ってファンモードを書き込み、直後に検証します。
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

  /// 退避しておいたモード関連キーを元の値へ戻します。
  private func restoreModeSnapshot(_ snapshot: FanModeSnapshot) throws {
    if snapshot.capabilities.writesModeKey {
      guard let modeKeyValue = snapshot.modeKeyValue else {
        throw AppleSMCFanControlError.stateSnapshotUnavailable(snapshot.capabilities.modeKey)
      }
      try smc.writeInteger(modeKeyValue, for: snapshot.capabilities.modeKey)
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

  /// モード変更後の SMC 値を読み戻し、意図した状態か確認します。
  private func verifyMode(
    _ mode: AppleSMCFanMode,
    using capabilities: FanModeWriteCapabilities
  ) throws {
    let expectsManual = mode == .manual
    let actualModeValue =
      capabilities.writesModeKey
      ? try readIntegerKey(capabilities.modeKey, allowZero: true)
      : nil
    let actualForceMask =
      capabilities.writesForceMask
      ? try readIntegerKey(capabilities.forceKey, allowZero: true)
      : nil
    if let actualForceMask {
      let forceMaskIndicatesManual = (actualForceMask & capabilities.maskBit) != 0
      guard forceMaskIndicatesManual == expectsManual else {
        let modeDescription = actualModeValue.map(String.init) ?? "n/a"
        throw AppleSMCFanControlError.verificationFailed(
          "expected fan \(capabilities.index) to indicate \(mode), but read back \(capabilities.modeKey)=\(modeDescription), \(capabilities.forceKey)=\(actualForceMask)"
        )
      }
      return
    }

    guard actualModeValue != nil else {
      throw AppleSMCFanControlError.modeControlUnavailable(capabilities.index)
    }

    // F0Md alone is not a reliable, immediate source of truth on all Macs.
    // When FS! is unavailable, treat the mode-key readback as advisory and let
    // target verification catch the cases where control did not actually stick.
  }

  /// 目標 RPM キーへ値を書き込み、読み戻しで結果を確認します。
  private func writeTarget(_ targetRpm: Int, for index: Int) throws {
    let targetKey = "F\(index)Tg"
    guard smc.canWriteNumeric(for: targetKey) else {
      throw AppleSMCFanControlError.targetControlUnavailable(index)
    }

    try writeAndVerifyTarget(targetRpm, for: targetKey)
  }

  /// 退避しておいた目標 RPM を元の値へ戻します。
  private func restoreTargetSnapshot(_ snapshot: FanTargetSnapshot) throws {
    try writeAndVerifyTarget(snapshot.value, for: snapshot.key)
  }

  /// 目標 RPM 書き込みはモード切替直後だと反映が遅れることがあるため、短時間だけ再確認します。
  private func writeAndVerifyTarget(_ expectedTargetRpm: Int, for key: String) throws {
    var lastActualTargetRpm: Int?

    for attempt in 0..<TargetWriteVerification.maxWriteAttempts {
      try smc.writeNumeric(Double(expectedTargetRpm), for: key)
      if let actualTargetRpm = try waitForTargetReadback(expectedTargetRpm, for: key) {
        lastActualTargetRpm = actualTargetRpm
      } else {
        return
      }

      if attempt + 1 < TargetWriteVerification.maxWriteAttempts {
        sleep(TargetWriteVerification.readbackPollInterval)
      }
    }

    throw AppleSMCFanControlError.verificationFailed(
      "expected \(key) to read back \(expectedTargetRpm) RPM, but got \(lastActualTargetRpm ?? 0) RPM"
    )
  }

  /// 一定時間ポーリングし、目標 RPM の読み戻しが追いつくか確認します。
  private func waitForTargetReadback(_ expectedTargetRpm: Int, for key: String) throws -> Int? {
    var lastActualTargetRpm: Int?

    for pollIndex in 0..<TargetWriteVerification.readbackPollCount {
      guard let actualValue = smc.value(for: key, allowZero: true) else {
        throw AppleSMCFanControlError.stateSnapshotUnavailable(key)
      }

      let actualTargetRpm = Int(actualValue.rounded())
      if actualTargetRpm == expectedTargetRpm {
        return nil
      }

      lastActualTargetRpm = actualTargetRpm

      let shouldContinuePolling = pollIndex + 1 < TargetWriteVerification.readbackPollCount
      if shouldContinuePolling {
        sleep(TargetWriteVerification.readbackPollInterval)
      }
    }

    return lastActualTargetRpm
  }

  /// 整数キーを必須値として読み取り、欠損時は状態取得失敗を返します。
  private func readIntegerKey(_ key: String, allowZero: Bool) throws -> UInt32 {
    guard let value = smc.integerValue(for: key, allowZero: allowZero) else {
      throw AppleSMCFanControlError.stateSnapshotUnavailable(key)
    }

    return value
  }

  /// 整数キーの読み戻し値が期待値と一致するかを共通化して検証します。
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

  /// 失敗時にロールバックを試み、結果に応じて適切なエラーへまとめ直します。
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

/// ヘルパーサービスが実装すべきファン制御操作です。
protocol FanControlControlling: AnyObject {
  /// ファンモードを書き換えます。
  func setFanMode(index: Int, mode: AppleSMCFanMode) throws
  /// 手動モードと目標 RPM をまとめて適用します。
  func applyManualTargetRpm(index: Int, targetRpm: Int) throws
}

/// アプリ本体から特権ヘルパーを呼び出すための XPC インターフェースです。
@objc protocol FanControlXPCProtocol {
  /// 指定ファンのモードを変更します。
  func setFanMode(
    _ fanIndex: Int,
    modeRawValue: Int,
    withReply reply: @escaping (String?) -> Void
  )

  /// 指定ファンへ手動目標 RPM を適用します。
  func applyManualTargetRpm(
    _ fanIndex: Int,
    targetRpm: Int,
    withReply reply: @escaping (String?) -> Void
  )

  /// 指定ファンの手動制御リースを延長します。
  func renewManualLease(
    _ fanIndex: Int,
    withReply reply: @escaping (String?) -> Void
  )
}
