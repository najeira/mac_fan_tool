import Dispatch
import Foundation
import Security

let configuration = FanControlHelperConfiguration.currentAppConfiguration()
let listener = NSXPCListener(
  machServiceName: configuration?.machServiceName ?? "invalid.fancontrol.helper"
)
let delegate = FanControlHelperService()

if #available(macOS 13.0, *), let configuration {
  do {
    let signature = try currentProcessSignature()
    guard let teamIdentifier = signature.teamIdentifier else {
      throw HelperStartupError.missingTeamIdentifier
    }

    listener.setConnectionCodeSigningRequirement(
      CodeSigningRequirementBuilder.requirement(
        identifier: configuration.appBundleIdentifier,
        teamIdentifier: teamIdentifier
      )
    )
  } catch {
    fputs(
      "Failed to configure helper client requirement: \(error)\n",
      stderr
    )
    exit(EXIT_FAILURE)
  }
}

listener.delegate = delegate
listener.resume()
dispatchMain()

private enum HelperStartupError: LocalizedError {
  case missingTeamIdentifier

  var errorDescription: String? {
    switch self {
    case .missingTeamIdentifier:
      return "The helper signature does not include a team identifier."
    }
  }
}

private struct CodeSignatureDetails {
  let teamIdentifier: String?
}

private func currentProcessSignature() throws -> CodeSignatureDetails {
  var dynamicCode: SecCode?
  let status = SecCodeCopySelf([], &dynamicCode)
  guard status == errSecSuccess, let dynamicCode else {
    throw HelperStartupError.missingTeamIdentifier
  }

  var staticCode: SecStaticCode?
  let staticStatus = SecCodeCopyStaticCode(dynamicCode, [], &staticCode)
  guard staticStatus == errSecSuccess, let staticCode else {
    throw HelperStartupError.missingTeamIdentifier
  }

  var information: CFDictionary?
  let infoStatus = SecCodeCopySigningInformation(
    staticCode,
    SecCSFlags(rawValue: kSecCSSigningInformation),
    &information
  )
  guard infoStatus == errSecSuccess,
        let information = information as NSDictionary? else {
    throw HelperStartupError.missingTeamIdentifier
  }

  return CodeSignatureDetails(
    teamIdentifier: information[kSecCodeInfoTeamIdentifier as String] as? String
  )
}
