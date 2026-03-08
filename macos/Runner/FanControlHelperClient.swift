import Foundation
import Security
import ServiceManagement

final class FanControlHelperClient {
  static let shared = FanControlHelperClient()

  typealias EnvironmentResolver = () throws -> ResolvedEnvironment
  typealias ConnectionFactory = (ResolvedEnvironment) -> FanControlXPCConnection

  private let commandTimeout: DispatchTimeInterval
  private let environmentResolver: EnvironmentResolver?
  private let connectionFactory: ConnectionFactory?
  private let serviceReadinessChecker: FanControlServiceReadinessChecking

  init(
    commandTimeout: DispatchTimeInterval = .seconds(10),
    environmentResolver: EnvironmentResolver? = nil,
    connectionFactory: ConnectionFactory? = nil,
    serviceReadinessChecker: FanControlServiceReadinessChecking = SMAppServiceReadinessChecker()
  ) {
    self.commandTimeout = commandTimeout
    self.environmentResolver = environmentResolver
    self.connectionFactory = connectionFactory
    self.serviceReadinessChecker = serviceReadinessChecker
  }

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

  func setFanMode(fanId: String, mode: FanModeData) throws {
    let fanIndex = try resolvedFanIndex(from: fanId)
    let environment = try commandEnvironment()
    try performCommand(environment: environment) { remote, reply in
      remote.setFanMode(fanIndex, modeRawValue: mode.rawValue, withReply: reply)
    }
  }

  func setFanTargetRpm(fanId: String, targetRpm: Int64) throws {
    let fanIndex = try resolvedFanIndex(from: fanId)
    let requestedTarget = Int(targetRpm)

    let environment = try commandEnvironment()
    try performCommand(environment: environment) { remote, reply in
      remote.applyManualTargetRpm(fanIndex, targetRpm: requestedTarget, withReply: reply)
    }
  }

  func renewManualLease(fanId: String) throws {
    let fanIndex = try resolvedFanIndex(from: fanId)
    let environment = try commandEnvironment()
    try performCommand(environment: environment) { remote, reply in
      remote.renewManualLease(fanIndex, withReply: reply)
    }
  }

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

  private func commandEnvironment() throws -> ResolvedEnvironment {
    let environment = try currentEnvironment()
    try serviceReadinessChecker.ensureReady(environment: environment)
    return environment
  }

  private func currentEnvironment() throws -> ResolvedEnvironment {
    if let environmentResolver {
      return try environmentResolver()
    }

    return try resolvedEnvironment()
  }

  private func makeConnection(for environment: ResolvedEnvironment) -> FanControlXPCConnection {
    if let connectionFactory {
      return connectionFactory(environment)
    }

    return FanControlNSXPCConnection(environment: environment)
  }

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

    return ResolvedEnvironment(
      configuration: configuration,
      helperRequirement: codeSigningRequirement(
        identifier: configuration.helperBundleIdentifier,
        teamIdentifier: helperTeamIdentifier
      )
    )
  }

  private func helperExecutableURL(for bundleURL: URL) -> URL {
    bundleURL.appendingPathComponent(FanControlHelperConfiguration.helperRelativePath)
  }

  private func launchDaemonPlistURL(for bundleURL: URL) -> URL {
    bundleURL
      .appendingPathComponent("Contents/Library/LaunchDaemons", isDirectory: true)
      .appendingPathComponent(FanControlHelperConfiguration.launchDaemonPlistName)
  }

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

  private func currentProcessSignature() throws -> CodeSignatureDetails {
    var dynamicCode: SecCode?
    let status = SecCodeCopySelf([], &dynamicCode)
    guard status == errSecSuccess, let dynamicCode else {
      throw FanControlHelperClientError.signedBuildRequired(
        "macOS could not read the app signature."
      )
    }

    var staticCode: SecStaticCode?
    let staticStatus = SecCodeCopyStaticCode(dynamicCode, [], &staticCode)
    guard staticStatus == errSecSuccess, let staticCode else {
      throw FanControlHelperClientError.signedBuildRequired(
        "macOS could not inspect the app signature."
      )
    }

    return try signatureDetails(for: staticCode)
  }

  private func signatureDetails(forExecutableAt url: URL) throws -> CodeSignatureDetails {
    var staticCode: SecStaticCode?
    let status = SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode)
    guard status == errSecSuccess, let staticCode else {
      throw FanControlHelperClientError.signedBuildRequired(
        "macOS could not inspect the bundled helper signature."
      )
    }

    return try signatureDetails(for: staticCode)
  }

  private func signatureDetails(for staticCode: SecStaticCode) throws -> CodeSignatureDetails {
    var information: CFDictionary?
    let status = SecCodeCopySigningInformation(
      staticCode,
      SecCSFlags(rawValue: kSecCSSigningInformation),
      &information
    )
    guard status == errSecSuccess, let information else {
      throw FanControlHelperClientError.signedBuildRequired(
        "macOS could not inspect the code signature."
      )
    }

    return CodeSignatureDetails(dictionary: information as NSDictionary)
  }

  private func codeSigningRequirement(identifier: String, teamIdentifier: String) -> String {
    CodeSigningRequirementBuilder.requirement(
      identifier: identifier,
      teamIdentifier: teamIdentifier
    )
  }
}

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

protocol FanControlServiceReadinessChecking {
  func ensureReady(environment: ResolvedEnvironment) throws
}

private struct SMAppServiceReadinessChecker: FanControlServiceReadinessChecking {
  func ensureReady(environment: ResolvedEnvironment) throws {
    guard #available(macOS 13.0, *) else {
      return
    }

    try ensureServiceReady(environment: environment)
  }

  @available(macOS 13.0, *)
  private func ensureServiceReady(environment: ResolvedEnvironment) throws {
    switch environment.service.status {
    case .enabled:
      return

    case .notRegistered, .notFound:
      try registerService(environment: environment, allowReset: true)
      try ensureRegisteredStatus(environment: environment)

    case .requiresApproval:
      throw FanControlHelperClientError.requiresApproval

    @unknown default:
      throw FanControlHelperClientError.registrationFailed(
        message: "The privileged helper returned an unknown registration state."
      )
    }
  }

  @available(macOS 13.0, *)
  private func registerService(
    environment: ResolvedEnvironment,
    allowReset: Bool
  ) throws {
    do {
      try environment.service.register()
    } catch {
      let nsError = error as NSError

      if allowReset && shouldResetRegistration(status: environment.service.status, error: nsError) {
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

    if allowReset && environment.service.status == .notFound {
      try resetRegistration(environment: environment)
      try registerService(environment: environment, allowReset: false)
    }
  }

  @available(macOS 13.0, *)
  private func resetRegistration(environment: ResolvedEnvironment) throws {
    do {
      try environment.service.unregister()
    } catch {
      let nsError = error as NSError
      if nsError.code != kSMErrorJobNotFound {
        throw FanControlHelperClientError.registrationFailed(
          message: registrationFailureMessage(for: nsError)
        )
      }
    }
  }

  @available(macOS 13.0, *)
  private func ensureRegisteredStatus(environment: ResolvedEnvironment) throws {
    switch environment.service.status {
    case .enabled:
      return
    case .requiresApproval:
      throw FanControlHelperClientError.requiresApproval
    case .notFound:
      throw FanControlHelperClientError.helperUnavailable
    case .notRegistered:
      throw FanControlHelperClientError.registrationFailed(
        message: "macOS did not keep the privileged helper registered."
      )
    @unknown default:
      throw FanControlHelperClientError.registrationFailed(
        message: "The privileged helper returned an unknown registration state."
      )
    }
  }

  @available(macOS 13.0, *)
  private func shouldResetRegistration(
    status: SMAppService.Status,
    error: NSError
  ) -> Bool {
    if status == .notFound {
      return true
    }

    switch error.code {
    case kSMErrorAlreadyRegistered,
      kSMErrorJobPlistNotFound,
      kSMErrorInvalidPlist,
      kSMErrorToolNotValid,
      kSMErrorInvalidSignature:
      return true
    default:
      return false
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

private enum HelperServiceStatus {
  case enabled
  case notRegistered
  case requiresApproval
  case notFound
  case unknown
}

struct ResolvedEnvironment {
  let configuration: FanControlHelperConfiguration
  let helperRequirement: String

  @available(macOS 13.0, *)
  var service: SMAppService {
    SMAppService.daemon(plistName: FanControlHelperConfiguration.launchDaemonPlistName)
  }
}

private struct CodeSignatureDetails {
  let identifier: String?
  let teamIdentifier: String?

  init(dictionary: NSDictionary) {
    identifier = dictionary[kSecCodeInfoIdentifier as String] as? String
    teamIdentifier = dictionary[kSecCodeInfoTeamIdentifier as String] as? String
  }
}

protocol FanControlXPCConnection: AnyObject {
  var invalidationHandler: (() -> Void)? { get set }
  var interruptionHandler: (() -> Void)? { get set }

  func resume()
  func invalidate()
  func remoteObjectProxy(errorHandler: @escaping (Error) -> Void) -> FanControlXPCProtocol?
}

private final class FanControlNSXPCConnection: FanControlXPCConnection {
  private let connection: NSXPCConnection

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

  func resume() {
    connection.resume()
  }

  func invalidate() {
    connection.invalidate()
  }

  func remoteObjectProxy(errorHandler: @escaping (Error) -> Void) -> FanControlXPCProtocol? {
    connection.remoteObjectProxyWithErrorHandler(errorHandler) as? FanControlXPCProtocol
  }
}

private final class XPCCommandAwaiter {
  private let lock = NSLock()
  private let semaphore = DispatchSemaphore(value: 0)
  private var result: Result<Void, FanControlHelperClientError>?

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
