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
}
