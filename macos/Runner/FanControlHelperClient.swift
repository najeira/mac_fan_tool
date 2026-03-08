import CryptoKit
import Foundation
import ServiceManagement

/// アプリ本体から特権ヘルパーの登録、接続、コマンド実行を仲介するクライアントです。
final class FanControlHelperClient {
  static let shared = FanControlHelperClient()

  typealias EnvironmentResolver = () throws -> ResolvedEnvironment
  typealias ConnectionFactory = (ResolvedEnvironment) -> FanControlXPCConnection

  private let commandTimeout: DispatchTimeInterval
  private let environmentResolver: EnvironmentResolver?
  private let connectionFactory: ConnectionFactory?
  private let serviceReadinessChecker: FanControlServiceReadinessChecking
  private let serviceRecovery: FanControlServiceRecovering

  init(
    commandTimeout: DispatchTimeInterval = .seconds(10),
    environmentResolver: EnvironmentResolver? = nil,
    connectionFactory: ConnectionFactory? = nil,
    serviceReadinessChecker: FanControlServiceReadinessChecking = SMAppServiceReadinessChecker(),
    serviceRecovery: FanControlServiceRecovering = SMAppServiceRecovery()
  ) {
    self.commandTimeout = commandTimeout
    self.environmentResolver = environmentResolver
    self.connectionFactory = connectionFactory
    self.serviceReadinessChecker = serviceReadinessChecker
    self.serviceRecovery = serviceRecovery
  }

  /// 現在の環境でファン制御 UI を有効化してよいかを判定します。
  func canControlFans(isFanControlSupported: Bool) -> Bool {
    guard isFanControlSupported else {
      return false
    }

    switch helperAvailability() {
    case .unavailable:
      return false
    case let .available(_, status):
      switch status {
      case .enabled, .notRegistered, .notFound:
        return true
      case .requiresApproval:
        return false
      case .unknown:
        return false
      }
    }
  }

  /// ヘルパーの登録状態に応じて UI 表示用の補足メッセージを返します。
  func statusNote(isFanControlSupported: Bool) -> String? {
    guard isFanControlSupported else {
      return nil
    }

    switch helperAvailability() {
    case let .unavailable(error):
      return error.message
    case let .available(_, status):
      switch status {
      case .enabled:
        return nil
      case .notRegistered:
        return "Fan writes use a bundled privileged helper. The first fan command will ask macOS to register it."
      case .requiresApproval:
        return "Approve the privileged fan helper in System Settings > General > Login Items before applying manual RPM."
      case .notFound:
        return "macOS could not validate the bundled privileged fan helper. The next fan command will try to refresh its registration."
      case .unknown:
        return "The privileged fan helper reported an unknown registration state."
      }
    }
  }

  /// ファン ID をヘルパー用のインデックスへ変換してモード変更を依頼します。
  func setFanMode(fanId: String, mode: FanModeData) throws {
    try performFanCommand(fanId: fanId) { remote, reply, fanIndex in
      remote.setFanMode(fanIndex, modeRawValue: mode.rawValue, withReply: reply)
    }
  }

  /// ファン ID をヘルパー用のインデックスへ変換して目標 RPM を設定します。
  func setFanTargetRpm(fanId: String, targetRpm: Int64) throws {
    let requestedTarget = Int(targetRpm)
    try performFanCommand(fanId: fanId) { remote, reply, fanIndex in
      remote.applyManualTargetRpm(fanIndex, targetRpm: requestedTarget, withReply: reply)
    }
  }

  /// 手動ファン制御リースの期限延長をヘルパーへ依頼します。
  func renewManualLease(fanId: String) throws {
    try performFanCommand(fanId: fanId) { remote, reply, fanIndex in
      remote.renewManualLease(fanIndex, withReply: reply)
    }
  }

  /// 現在の環境と登録状態からヘルパー利用可否を評価します。
  private func helperAvailability() -> HelperAvailability {
    do {
      let environment = try currentEnvironment()
      if #available(macOS 13.0, *) {
        return .available(environment, serviceStatus(from: environment.service.status))
      }

      return .unavailable(.unsupportedOS)
    } catch let error as FanControlHelperClientError {
      return .unavailable(error)
    } catch {
      return .unavailable(.configurationInvalid(String(describing: error)))
    }
  }

  /// ServiceManagement の状態値をアプリ内の簡略化した状態へ変換します。
  @available(macOS 13.0, *)
  private func serviceStatus(from status: SMAppService.Status) -> HelperServiceStatus {
    switch status {
    case .enabled:
      return .enabled
    case .notRegistered:
      return .notRegistered
    case .requiresApproval:
      return .requiresApproval
    case .notFound:
      return .notFound
    @unknown default:
      return .unknown
    }
  }

  /// XPC 接続を 1 回開いてコマンドを実行し、同期的に応答を待ちます。
  func performCommand(
    environment: ResolvedEnvironment,
    _ work: (FanControlXPCProtocol, @escaping (String?) -> Void) -> Void
  ) throws {
    let connection = makeConnection(for: environment)
    let awaiter = XPCCommandAwaiter()
    let timeout = DispatchTime.now() + commandTimeout

    connection.invalidationHandler = {
      awaiter.complete(
        .failure(
          .connectionFailed(
            "The privileged helper connection was invalidated before replying."
          )
        )
      )
    }
    connection.interruptionHandler = {
      awaiter.complete(
        .failure(
          .connectionFailed(
            "The privileged helper connection was interrupted before replying."
          )
        )
      )
    }
    connection.resume()
    defer {
      connection.invalidate()
    }

    guard let remote = connection.remoteObjectProxy(errorHandler: { error in
      awaiter.complete(.failure(.connectionFailed(error.localizedDescription)))
    }) else {
      throw FanControlHelperClientError.connectionFailed(
        "The privileged helper interface could not be created."
      )
    }

    work(remote) { message in
      if let message {
        awaiter.complete(.failure(.commandFailed(message)))
      } else {
        awaiter.complete(.success(()))
      }
    }

    try awaiter.wait(timeout: timeout)
  }

  /// コマンド実行前にサービス登録状態を確認済みの環境を返します。
  private func commandEnvironment() throws -> ResolvedEnvironment {
    let environment = try currentEnvironment()
    try serviceReadinessChecker.ensureReady(environment: environment)
    return environment
  }

  /// 差し替え用リゾルバがあればそれを使い、なければ本番環境を解決します。
  private func currentEnvironment() throws -> ResolvedEnvironment {
    if let environmentResolver {
      return try environmentResolver()
    }

    return try resolvedEnvironment()
  }

  /// ファン ID の解決と環境準備をまとめて行い、ヘルパー呼び出しへ引き渡します。
  private func performFanCommand(
    fanId: String,
    command: (FanControlXPCProtocol, @escaping (String?) -> Void, Int) -> Void
  ) throws {
    let fanIndex = try resolvedFanIndex(from: fanId)
    let environment = try commandEnvironment()
    do {
      try performCommand(environment: environment) { remote, reply in
        command(remote, reply, fanIndex)
      }
    } catch let error as FanControlHelperClientError {
      guard try serviceRecovery.recover(environment: environment, after: error) else {
        throw error
      }

      try performCommand(environment: environment) { remote, reply in
        command(remote, reply, fanIndex)
      }
    }
  }

  /// 差し替え用ファクトリがあればそれを使って XPC 接続を生成します。
  private func makeConnection(for environment: ResolvedEnvironment) -> FanControlXPCConnection {
    if let connectionFactory {
      return connectionFactory(environment)
    }

    return FanControlNSXPCConnection(environment: environment)
  }

  /// `fan-N` 形式の識別子からヘルパー用の整数インデックスを取り出します。
  private func resolvedFanIndex(from fanId: String) throws -> Int {
    let prefix = "fan-"
    guard fanId.hasPrefix(prefix) else {
      throw FanControlHelperClientError.invalidFanId(fanId)
    }

    let suffix = fanId.dropFirst(prefix.count)
    guard !suffix.isEmpty,
          suffix.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }),
          let index = Int(String(suffix)) else {
      throw FanControlHelperClientError.invalidFanId(fanId)
    }

    return index
  }

  /// バンドル配置、署名、ヘルパー同梱状態を検証して実行環境を構築します。
  private func resolvedEnvironment() throws -> ResolvedEnvironment {
    guard #available(macOS 13.0, *) else {
      throw FanControlHelperClientError.unsupportedOS
    }

    guard let configuration = FanControlHelperConfiguration.currentAppConfiguration() else {
      throw FanControlHelperClientError.configurationInvalid(
        "The app bundle identifier is unavailable."
      )
    }

    let bundleURL = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
    guard isInstalledInApplications(bundleURL: bundleURL) else {
      throw FanControlHelperClientError.installToApplications
    }

    let helperExecutableURL = helperExecutableURL(for: bundleURL)
    guard FileManager.default.fileExists(atPath: helperExecutableURL.path) else {
      throw FanControlHelperClientError.helperMissing
    }

    let launchDaemonPlistURL = launchDaemonPlistURL(for: bundleURL)
    guard FileManager.default.fileExists(atPath: launchDaemonPlistURL.path) else {
      throw FanControlHelperClientError.helperMissing
    }

    let appSignature = try currentProcessSignature()
    guard let appSignatureIdentifier = appSignature.identifier else {
      throw FanControlHelperClientError.signedBuildRequired(
        "Set the same Development Team for the Runner and FanControlHelper targets, then rebuild."
      )
    }

    guard appSignatureIdentifier == configuration.appBundleIdentifier else {
      throw FanControlHelperClientError.signedBuildRequired(
        "The app signature identifier does not match \(configuration.appBundleIdentifier)."
      )
    }

    guard let appTeamIdentifier = appSignature.teamIdentifier else {
      throw FanControlHelperClientError.signedBuildRequired(
        "Set the same Development Team for the Runner and FanControlHelper targets, then rebuild."
      )
    }

    let helperSignature = try signatureDetails(forExecutableAt: helperExecutableURL)
    guard let helperSignatureIdentifier = helperSignature.identifier else {
      throw FanControlHelperClientError.signedBuildRequired(
        "The bundled helper is not signed with the selected development team."
      )
    }

    guard helperSignatureIdentifier == configuration.helperBundleIdentifier else {
      throw FanControlHelperClientError.signedBuildRequired(
        "The bundled helper signature identifier does not match \(configuration.helperBundleIdentifier)."
      )
    }

    guard let helperTeamIdentifier = helperSignature.teamIdentifier else {
      throw FanControlHelperClientError.signedBuildRequired(
        "The bundled helper is not signed with the selected development team."
      )
    }

    guard helperTeamIdentifier == appTeamIdentifier else {
      throw FanControlHelperClientError.signedBuildRequired(
        "The app and bundled helper are signed by different teams."
      )
    }

    let helperFingerprint: String
    do {
      helperFingerprint = try bundledHelperFingerprint(
        forExecutableAt: helperExecutableURL,
        signature: helperSignature
      )
    } catch {
      throw FanControlHelperClientError.configurationInvalid(
        "macOS could not hash the bundled privileged helper."
      )
    }

    return ResolvedEnvironment(
      configuration: configuration,
      helperFingerprint: helperFingerprint,
      helperRequirement: codeSigningRequirement(
        identifier: configuration.helperBundleIdentifier,
        teamIdentifier: helperTeamIdentifier
      )
    )
  }

  /// アプリ同梱の特権ヘルパー実行ファイルの配置先 URL を返します。
  private func helperExecutableURL(for bundleURL: URL) -> URL {
    bundleURL.appendingPathComponent(FanControlHelperConfiguration.helperRelativePath)
  }

  /// アプリ同梱の LaunchDaemon plist の配置先 URL を返します。
  private func launchDaemonPlistURL(for bundleURL: URL) -> URL {
    bundleURL
      .appendingPathComponent("Contents/Library/LaunchDaemons", isDirectory: true)
      .appendingPathComponent(FanControlHelperConfiguration.launchDaemonPlistName)
  }

  /// アプリが `/Applications` 配下にインストールされているかを確認します。
  private func isInstalledInApplications(bundleURL: URL) -> Bool {
    let applicationDirectories =
      FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask)
      + FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask)

    let bundlePath = bundleURL.path

    return applicationDirectories.contains { directoryURL in
      let applicationsPath =
        directoryURL.resolvingSymlinksInPath().standardizedFileURL.path
      return bundlePath == applicationsPath || bundlePath.hasPrefix(applicationsPath + "/")
    }
  }

  /// 実行中アプリ自身のコード署名情報を取得します。
  private func currentProcessSignature() throws -> CodeSignatureDetails {
    do {
      return try CodeSignatureReader.currentProcessDetails()
    } catch CodeSignatureReaderError.currentCodeUnavailable {
      throw FanControlHelperClientError.signedBuildRequired(
        "macOS could not read the app signature."
      )
    } catch CodeSignatureReaderError.currentStaticCodeUnavailable {
      throw FanControlHelperClientError.signedBuildRequired(
        "macOS could not inspect the app signature."
      )
    } catch {
      throw FanControlHelperClientError.signedBuildRequired(
        "macOS could not inspect the code signature."
      )
    }
  }

  /// 指定した実行ファイル URL からコード署名情報を取得します。
  private func signatureDetails(forExecutableAt url: URL) throws -> CodeSignatureDetails {
    do {
      return try CodeSignatureReader.details(forExecutableAt: url)
    } catch CodeSignatureReaderError.executableStaticCodeUnavailable {
      throw FanControlHelperClientError.signedBuildRequired(
        "macOS could not inspect the bundled helper signature."
      )
    } catch {
      throw FanControlHelperClientError.signedBuildRequired(
        "macOS could not inspect the code signature."
      )
    }
  }

  /// 同梱 helper の内容が変わったことを検知するため、署名情報と実バイナリから fingerprint を作ります。
  private func bundledHelperFingerprint(
    forExecutableAt url: URL,
    signature: CodeSignatureDetails
  ) throws -> String {
    let executableData = try Data(contentsOf: url, options: .mappedIfSafe)
    let digest = SHA256.hash(data: executableData)
    let digestHex = digest.map { String(format: "%02x", $0) }.joined()
    return [
      signature.identifier ?? "unknown-identifier",
      signature.teamIdentifier ?? "unknown-team",
      digestHex,
    ].joined(separator: "|")
  }

  /// ヘルパー接続時に使うコード署名要件文字列を生成します。
  private func codeSigningRequirement(identifier: String, teamIdentifier: String) -> String {
    CodeSigningRequirementBuilder.requirement(
      identifier: identifier,
      teamIdentifier: teamIdentifier
    )
  }
}

/// ヘルパークライアントが UI やブリッジへ返す失敗理由です。
enum FanControlHelperClientError: Error, Equatable {
  case unsupportedOS
  case invalidFanId(String)
  case configurationInvalid(String)
  case installToApplications
  case helperMissing
  case helperUnavailable
  case signedBuildRequired(String)
  case requiresApproval
  case registrationFailed(message: String)
  case connectionFailed(String)
  case commandFailed(String)

  var message: String {
    switch self {
    case .unsupportedOS:
      return "Privileged helper based fan control requires macOS 13 or later."
    case let .invalidFanId(fanId):
      return "Unsupported fan identifier: \(fanId)."
    case let .configurationInvalid(message):
      return "Privileged helper configuration is invalid: \(message)"
    case .installToApplications:
      return "Install the signed app in /Applications before using fan control."
    case .helperMissing:
      return "The bundled privileged fan helper is missing from this build."
    case .helperUnavailable:
      return "macOS could not validate or register the bundled privileged fan helper."
    case let .signedBuildRequired(message):
      return "Fan control requires a signed build: \(message)"
    case .requiresApproval:
      return "Approve the privileged fan helper in System Settings > General > Login Items, then try again."
    case let .registrationFailed(message):
      return "Privileged helper registration failed: \(message)"
    case let .connectionFailed(message):
      return "Connecting to the privileged helper failed: \(message)"
    case let .commandFailed(message):
      return message
    }
  }
}

private enum HelperAvailability {
  case unavailable(FanControlHelperClientError)
  case available(ResolvedEnvironment, HelperServiceStatus)
}

/// 特権ヘルパーがコマンドを受け付けられる状態かを確認する抽象化です。
protocol FanControlServiceReadinessChecking {
  /// 必要に応じて登録や承認状態を確認し、実行可能でなければエラーにします。
  func ensureReady(environment: ResolvedEnvironment) throws
}

/// 接続失敗後に既存の helper 登録を再作成し、再試行可否を返す抽象化です。
protocol FanControlServiceRecovering {
  /// 復旧処理を行い、呼び出し元が 1 回だけ再試行してよいかを返します。
  func recover(environment: ResolvedEnvironment, after error: FanControlHelperClientError) throws
    -> Bool
}

private struct SMAppServiceReadinessChecker: FanControlServiceReadinessChecking {
  private let fingerprintStore: HelperRegistrationFingerprintStoring

  init(
    fingerprintStore: HelperRegistrationFingerprintStoring = UserDefaultsHelperRegistrationFingerprintStore()
  ) {
    self.fingerprintStore = fingerprintStore
  }

  /// ServiceManagement の登録・承認状態を検査し、必要なら登録処理を進めます。
  func ensureReady(environment: ResolvedEnvironment) throws {
    guard #available(macOS 13.0, *) else {
      return
    }

    try ensureServiceReady(environment: environment)
  }

  /// 状態ごとに登録、承認待ち、失敗を振り分けます。
  @available(macOS 13.0, *)
  private func ensureServiceReady(environment: ResolvedEnvironment) throws {
    let service = environment.service
    let status = settledServiceStatus(for: service)

    if status == .enabled && shouldRefreshRegistration(environment: environment) {
      try refreshRegistration(environment: environment)
      recordRegisteredFingerprint(environment)
      return
    }

    switch status {
    case .enabled:
      recordRegisteredFingerprint(environment)
      return

    case .notRegistered, .notFound:
      try registerService(environment: environment, allowReset: true)
      try ensureRegisteredStatus(environment: environment, allowReset: true)
      recordRegisteredFingerprint(environment)

    case .requiresApproval:
      throw FanControlHelperClientError.requiresApproval

    @unknown default:
      throw FanControlHelperClientError.registrationFailed(
        message: "The privileged helper returned an unknown registration state."
      )
    }
  }

  /// app bundle 内 helper が更新されていれば、登録済み helper も入れ替えます。
  @available(macOS 13.0, *)
  private func shouldRefreshRegistration(environment: ResolvedEnvironment) -> Bool {
    fingerprintStore.fingerprint(for: environment.configuration.appBundleIdentifier)
      != environment.helperFingerprint
  }

  /// 登録済み helper fingerprint を保存し、次回起動時に stale 判定できるようにします。
  @available(macOS 13.0, *)
  private func recordRegisteredFingerprint(_ environment: ResolvedEnvironment) {
    fingerprintStore.setFingerprint(
      environment.helperFingerprint,
      for: environment.configuration.appBundleIdentifier
    )
  }

  /// 必要に応じて登録リセットを挟みつつ、特権ヘルパーを登録します。
  @available(macOS 13.0, *)
  private func registerService(
    environment: ResolvedEnvironment,
    allowReset: Bool
  ) throws {
    do {
      try environment.service.register()
    } catch {
      let nsError = error as NSError

      if allowReset && shouldResetRegistration(error: nsError) {
        try resetRegistration(environment: environment)
        try registerService(environment: environment, allowReset: false)
        return
      }

      if nsError.code != kSMErrorAlreadyRegistered {
        throw FanControlHelperClientError.registrationFailed(
          message: registrationFailureMessage(for: nsError)
        )
      }
    }
  }

  /// 既存の特権ヘルパー登録を解除し、壊れた状態を掃除します。
  @available(macOS 13.0, *)
  private func resetRegistration(environment: ResolvedEnvironment) throws {
    do {
      try unregisterServiceAndWait(environment.service)
    } catch {
      let nsError = error as NSError
      if nsError.code != kSMErrorJobNotFound {
        throw FanControlHelperClientError.registrationFailed(
          message: registrationFailureMessage(for: nsError)
        )
      }
    }
  }

  /// 同梱 helper が更新されている場合に、登録済み helper を強制的に差し替えます。
  @available(macOS 13.0, *)
  private func refreshRegistration(environment: ResolvedEnvironment) throws {
    try resetRegistration(environment: environment)
    try registerService(environment: environment, allowReset: false)
    try ensureRegisteredStatus(environment: environment, allowReset: false)
  }

  /// 登録直後の状態が実際に利用可能かを再確認します。
  @available(macOS 13.0, *)
  private func ensureRegisteredStatus(
    environment: ResolvedEnvironment,
    allowReset: Bool
  ) throws {
    let service = environment.service

    switch settledServiceStatus(for: service) {
    case .enabled:
      return
    case .requiresApproval:
      throw FanControlHelperClientError.requiresApproval
    case .notFound:
      if allowReset {
        try resetRegistration(environment: environment)
        try registerService(environment: environment, allowReset: false)
        try ensureRegisteredStatus(environment: environment, allowReset: false)
        return
      }
      throw FanControlHelperClientError.helperUnavailable
    case .notRegistered:
      if allowReset {
        try resetRegistration(environment: environment)
        try registerService(environment: environment, allowReset: false)
        try ensureRegisteredStatus(environment: environment, allowReset: false)
        return
      }
      throw FanControlHelperClientError.registrationFailed(
        message: "macOS did not keep the privileged helper registered."
      )
    @unknown default:
      throw FanControlHelperClientError.registrationFailed(
        message: "The privileged helper returned an unknown registration state."
      )
    }
  }

  /// 登録情報のリセットを試すべきエラーかどうかを判定します。
  @available(macOS 13.0, *)
  private func shouldResetRegistration(
    error: NSError
  ) -> Bool {
    switch error.code {
    case kSMErrorJobPlistNotFound,
      kSMErrorInvalidPlist,
      kSMErrorToolNotValid,
      kSMErrorInvalidSignature:
      return true
    default:
      return false
    }
  }

  /// ServiceManagement の `NSError` をユーザー向けメッセージへ変換します。
  private func registrationFailureMessage(for error: NSError) -> String {
    switch error.code {
    case kSMErrorInvalidSignature:
      return "The app or bundled helper is not signed in a way that ServiceManagement accepts."
    case kSMErrorAuthorizationFailure:
      return "macOS refused the authorization needed to register the privileged helper."
    case kSMErrorToolNotValid, kSMErrorJobPlistNotFound, kSMErrorInvalidPlist:
      return "The bundled privileged helper could not be validated by macOS."
    case kSMErrorJobNotFound:
      return "macOS could not find the helper registration after refreshing it."
    case kSMErrorLaunchDeniedByUser:
      return FanControlHelperClientError.requiresApproval.message
    default:
      return error.localizedDescription
    }
  }
}

private struct SMAppServiceRecovery: FanControlServiceRecovering {
  func recover(environment: ResolvedEnvironment, after error: FanControlHelperClientError) throws
    -> Bool {
    guard case .connectionFailed = error else {
      return false
    }

    guard #available(macOS 13.0, *) else {
      return false
    }

    let service = environment.service
    let settledStatus = settledServiceStatus(for: service)

    switch settledStatus {
    case .enabled:
      return true
    case .requiresApproval:
      throw FanControlHelperClientError.requiresApproval
    case .notRegistered, .notFound:
      break
    @unknown default:
      throw FanControlHelperClientError.registrationFailed(
        message: "The privileged helper returned an unknown registration state."
      )
    }

    do {
      try unregisterServiceAndWait(service)
    } catch {
      let nsError = error as NSError
      if nsError.code != kSMErrorJobNotFound {
        throw FanControlHelperClientError.registrationFailed(
          message: registrationFailureMessage(for: nsError)
        )
      }
    }

    do {
      try service.register()
    } catch {
      throw FanControlHelperClientError.registrationFailed(
        message: registrationFailureMessage(for: error as NSError)
      )
    }

    switch settledServiceStatus(for: service) {
    case .enabled:
      return true
    case .requiresApproval:
      throw FanControlHelperClientError.requiresApproval
    case .notFound:
      throw FanControlHelperClientError.helperUnavailable
    case .notRegistered:
      throw FanControlHelperClientError.registrationFailed(
        message: "macOS did not keep the privileged helper registered after reconnecting it."
      )
    @unknown default:
      throw FanControlHelperClientError.registrationFailed(
        message: "The privileged helper returned an unknown registration state."
      )
    }
  }

  private func registrationFailureMessage(for error: NSError) -> String {
    switch error.code {
    case kSMErrorInvalidSignature:
      return "The app or bundled helper is not signed in a way that ServiceManagement accepts."
    case kSMErrorAuthorizationFailure:
      return "macOS refused the authorization needed to register the privileged helper."
    case kSMErrorToolNotValid, kSMErrorJobPlistNotFound, kSMErrorInvalidPlist:
      return "The bundled privileged helper could not be validated by macOS."
    case kSMErrorJobNotFound:
      return "macOS could not find the helper registration after refreshing it."
    case kSMErrorLaunchDeniedByUser:
      return FanControlHelperClientError.requiresApproval.message
    default:
      return error.localizedDescription
    }
  }
}

@available(macOS 13.0, *)
private func unregisterServiceAndWait(
  _ service: SMAppService,
  timeout: DispatchTimeInterval = .seconds(5)
) throws {
  let semaphore = DispatchSemaphore(value: 0)
  var completionError: NSError?

  service.unregister { error in
    completionError = error as NSError?
    semaphore.signal()
  }

  if semaphore.wait(timeout: .now() + timeout) == .timedOut {
    throw NSError(
      domain: NSOSStatusErrorDomain,
      code: kSMErrorServiceUnavailable,
      userInfo: [
        NSLocalizedDescriptionKey:
          "Timed out while waiting for the privileged helper to unregister.",
      ]
    )
  }

  if let completionError {
    throw completionError
  }
}

@available(macOS 13.0, *)
private func settledServiceStatus(
  for service: SMAppService,
  maxPolls: Int = 20,
  pollInterval: TimeInterval = 0.1
) -> SMAppService.Status {
  var status = service.status

  for _ in 0..<maxPolls {
    switch status {
    case .enabled, .requiresApproval:
      return status
    case .notRegistered, .notFound:
      Thread.sleep(forTimeInterval: pollInterval)
      status = service.status
    @unknown default:
      return status
    }
  }

  return status
}

private enum HelperServiceStatus {
  case enabled
  case notRegistered
  case requiresApproval
  case notFound
  case unknown
}

/// 特権ヘルパー接続に必要な設定と署名要件を束ねた実行環境です。
struct ResolvedEnvironment {
  let configuration: FanControlHelperConfiguration
  let helperFingerprint: String
  let helperRequirement: String

  @available(macOS 13.0, *)
  var service: SMAppService {
    SMAppService.daemon(plistName: FanControlHelperConfiguration.launchDaemonPlistName)
  }
}

private protocol HelperRegistrationFingerprintStoring {
  func fingerprint(for appBundleIdentifier: String) -> String?
  func setFingerprint(_ fingerprint: String, for appBundleIdentifier: String)
}

private struct UserDefaultsHelperRegistrationFingerprintStore:
  HelperRegistrationFingerprintStoring
{
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func fingerprint(for appBundleIdentifier: String) -> String? {
    defaults.string(forKey: storageKey(for: appBundleIdentifier))
  }

  func setFingerprint(_ fingerprint: String, for appBundleIdentifier: String) {
    defaults.set(fingerprint, forKey: storageKey(for: appBundleIdentifier))
  }

  private func storageKey(for appBundleIdentifier: String) -> String {
    "FanControlHelperClient.registeredHelperFingerprint.\(appBundleIdentifier)"
  }
}

/// NSXPCConnection を差し替え可能にするための軽量インターフェースです。
protocol FanControlXPCConnection: AnyObject {
  var invalidationHandler: (() -> Void)? { get set }
  var interruptionHandler: (() -> Void)? { get set }

  /// XPC 接続を開始します。
  func resume()
  /// XPC 接続を破棄します。
  func invalidate()
  /// エラーハンドラ付きでリモートプロキシを取得します。
  func remoteObjectProxy(errorHandler: @escaping (Error) -> Void) -> FanControlXPCProtocol?
}

/// 特権ヘルパーへの NSXPCConnection を生成する本番実装です。
private final class FanControlNSXPCConnection: FanControlXPCConnection {
  private let connection: NSXPCConnection

  /// 特権ヘルパー向けの `NSXPCConnection` を構築し、必要なら署名要件も設定します。
  init(environment: ResolvedEnvironment) {
    connection = NSXPCConnection(
      machServiceName: environment.configuration.machServiceName,
      options: .privileged
    )
    connection.remoteObjectInterface = NSXPCInterface(with: FanControlXPCProtocol.self)
    if #available(macOS 13.0, *) {
      connection.setCodeSigningRequirement(environment.helperRequirement)
    }
  }

  var invalidationHandler: (() -> Void)? {
    get { connection.invalidationHandler }
    set { connection.invalidationHandler = newValue }
  }

  var interruptionHandler: (() -> Void)? {
    get { connection.interruptionHandler }
    set { connection.interruptionHandler = newValue }
  }

  /// XPC 接続を有効化して通信を開始します。
  func resume() {
    connection.resume()
  }

  /// 使用後の XPC 接続を閉じます。
  func invalidate() {
    connection.invalidate()
  }

  /// ヘルパーの XPC プロキシを取得します。
  func remoteObjectProxy(errorHandler: @escaping (Error) -> Void) -> FanControlXPCProtocol? {
    connection.remoteObjectProxyWithErrorHandler(errorHandler) as? FanControlXPCProtocol
  }
}

/// 非同期の XPC 応答を同期的に待ち合わせるためのユーティリティです。
private final class XPCCommandAwaiter {
  private let lock = NSLock()
  private let semaphore = DispatchSemaphore(value: 0)
  private var result: Result<Void, FanControlHelperClientError>?

  /// 最初に受け取った結果だけを確定させて待機中の処理へ通知します。
  func complete(_ result: Result<Void, FanControlHelperClientError>) {
    lock.lock()
    defer {
      lock.unlock()
    }

    guard self.result == nil else {
      return
    }

    self.result = result
    semaphore.signal()
  }

  /// タイムアウトまで応答を待ち、完了結果に応じて成功または失敗を返します。
  func wait(timeout: DispatchTime) throws {
    if semaphore.wait(timeout: timeout) == .timedOut {
      throw FanControlHelperClientError.connectionFailed(
        "Timed out while waiting for the privileged helper."
      )
    }

    lock.lock()
    defer {
      lock.unlock()
    }

    guard let result else {
      throw FanControlHelperClientError.connectionFailed(
        "The privileged helper finished without returning a result."
      )
    }

    switch result {
    case .success:
      return
    case let .failure(error):
      throw error
    }
  }
}
