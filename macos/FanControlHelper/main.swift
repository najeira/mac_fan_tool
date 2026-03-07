import Dispatch
import Foundation

let configuration = FanControlHelperConfiguration.currentAppConfiguration()
let listener = NSXPCListener(
  machServiceName: configuration?.machServiceName ?? "invalid.fancontrol.helper"
)
let delegate = FanControlHelperService()

if #available(macOS 13.0, *), let configuration {
  listener.setConnectionCodeSigningRequirement(
    "identifier \"\(configuration.appBundleIdentifier)\""
  )
}

listener.delegate = delegate
listener.resume()
dispatchMain()
