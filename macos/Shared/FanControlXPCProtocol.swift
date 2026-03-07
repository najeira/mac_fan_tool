import Foundation

struct FanControlHelperConfiguration {
  static let helperBundleSuffix = ".FanControlHelper"
  static let machServiceSuffix = ".fancontrol.helper"
  static let launchDaemonPlistName = "FanControlHelper.plist"
  static let helperExecutableName = "FanControlHelper"

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
