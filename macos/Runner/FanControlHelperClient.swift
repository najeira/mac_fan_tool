import Foundation
import Security
import ServiceManagement

final class FanControlHelperClient {
  static let shared = FanControlHelperClient()

  private init() {}

  func canControlFans(isFanControlSupported: Bool) -> Bool {
    guard isFanControlSupported else {
      return false
    }

    switch helperAvailability() {
    case .unavailable:
      return false
    case let .available(_, status):
      switch status {
      case .enabled, .notRegistered:
        return true
      case .requiresApproval, .notFound:
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
        return "macOS could not validate the bundled privileged fan helper in this build."
      case .unknown:
        return "The privileged fan helper reported an unknown registration state."
      }
    }
  }

  func setFanMode(fanId: String, mode: FanModeData) throws {
    let fanIndex = try resolvedFanIndex(from: fanId)
    let environment = try resolvedEnvironment()
    if #available(macOS 13.0, *) {
      try ensureServiceReady(environment: environment)
    }
    try performCommand(environment: environment) { remote, reply in
      remote.setFanMode(fanIndex, modeRawValue: mode.rawValue, withReply: reply)
    }
  }

  func setFanTargetRpm(fanId: String, targetRpm: Int64) throws {
    let fanIndex = try resolvedFanIndex(from: fanId)
    let clampedTarget = max(0, min(Int(targetRpm), Int(Int32.max)))

    let environment = try resolvedEnvironment()
    if #available(macOS 13.0, *) {
      try ensureServiceReady(environment: environment)
    }
    try performCommand(environment: environment) { remote, reply in
      remote.setFanTargetRpm(fanIndex, targetRpm: clampedTarget, withReply: reply)
    }
  }

  private func helperAvailability() -> HelperAvailability {
    do {
      let environment = try resolvedEnvironment()
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
  private func ensureServiceReady(environment: ResolvedEnvironment) throws {
    switch environment.service.status {
    case .enabled:
      return

    case .notRegistered:
      do {
        try environment.service.register()
      } catch {
        let nsError = error as NSError
        if nsError.code != kSMErrorAlreadyRegistered {
          throw FanControlHelperClientError.registrationFailed(
            message: registrationFailureMessage(for: nsError)
          )
        }
      }

      switch environment.service.status {
      case .enabled:
        return
      case .requiresApproval:
        throw FanControlHelperClientError.requiresApproval
      case .notFound:
        throw FanControlHelperClientError.helperMissing
      case .notRegistered:
        throw FanControlHelperClientError.registrationFailed(
          message: "macOS did not keep the privileged helper registered."
        )
      @unknown default:
        throw FanControlHelperClientError.registrationFailed(
          message: "The privileged helper returned an unknown registration state."
        )
      }

    case .requiresApproval:
      throw FanControlHelperClientError.requiresApproval

    case .notFound:
      throw FanControlHelperClientError.helperMissing

    @unknown default:
      throw FanControlHelperClientError.registrationFailed(
        message: "The privileged helper returned an unknown registration state."
      )
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

  private func performCommand(
    environment: ResolvedEnvironment,
    _ work: (FanControlXPCProtocol, @escaping (String?) -> Void) -> Void
  ) throws {
    let connection = NSXPCConnection(
      machServiceName: environment.configuration.machServiceName,
      options: .privileged
    )
    connection.remoteObjectInterface = NSXPCInterface(with: FanControlXPCProtocol.self)
    if #available(macOS 13.0, *) {
      connection.setCodeSigningRequirement(environment.helperRequirement)
    }

    let semaphore = DispatchSemaphore(value: 0)
    let timeout = DispatchTime.now() + .seconds(10)
    var helperErrorMessage: String?
    var connectionError: Error?

    connection.invalidationHandler = {
      semaphore.signal()
    }
    connection.interruptionHandler = {
      semaphore.signal()
    }
    connection.resume()

    guard let remote = connection.synchronousRemoteObjectProxyWithErrorHandler({ error in
      connectionError = error
      semaphore.signal()
    }) as? FanControlXPCProtocol else {
      connection.invalidate()
      throw FanControlHelperClientError.connectionFailed(
        "The privileged helper interface could not be created."
      )
    }

    work(remote) { message in
      helperErrorMessage = message
      semaphore.signal()
    }

    let waitResult = semaphore.wait(timeout: timeout)
    connection.invalidate()

    if waitResult == .timedOut {
      throw FanControlHelperClientError.connectionFailed(
        "Timed out while waiting for the privileged helper."
      )
    }

    if let connectionError {
      throw FanControlHelperClientError.connectionFailed(
        connectionError.localizedDescription
      )
    }

    if let helperErrorMessage {
      throw FanControlHelperClientError.commandFailed(helperErrorMessage)
    }
  }

  private func resolvedFanIndex(from fanId: String) throws -> Int {
    if fanId.hasPrefix("fan-"), let index = Int(fanId.dropFirst(4)) {
      return index
    }

    let digits = fanId.reversed().prefix { $0.isNumber }.reversed()
    if let index = Int(String(digits)) {
      return index
    }

    throw FanControlHelperClientError.invalidFanId(fanId)
  }

  private func registrationFailureMessage(for error: NSError) -> String {
    switch error.code {
    case kSMErrorInvalidSignature:
      return "The app or bundled helper is not signed in a way that ServiceManagement accepts."
    case kSMErrorAuthorizationFailure:
      return "macOS refused the authorization needed to register the privileged helper."
    case kSMErrorToolNotValid, kSMErrorJobPlistNotFound, kSMErrorInvalidPlist:
      return "The bundled privileged helper could not be validated by macOS."
    case kSMErrorLaunchDeniedByUser:
      return FanControlHelperClientError.requiresApproval.message
    default:
      return error.localizedDescription
    }
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
    "identifier \"\(identifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
  }
}

enum FanControlHelperClientError: Error {
  case unsupportedOS
  case invalidFanId(String)
  case configurationInvalid(String)
  case installToApplications
  case helperMissing
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

private enum HelperServiceStatus {
  case enabled
  case notRegistered
  case requiresApproval
  case notFound
  case unknown
}

private struct ResolvedEnvironment {
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
