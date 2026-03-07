import Cocoa
import Foundation

final class HardwareBridge: HardwareHostApi {
  func getCapabilities() throws -> HardwareCapabilitiesData {
    return HardwareCapabilitiesData(
      supportsRawSensors: false,
      supportsFanControl: false,
      hasFans: false,
      backend: "swift-placeholder",
      note: "Pigeon and Swift are wired, but the SMC/HID backend has not been implemented yet."
    )
  }

  func getSnapshot() throws -> HardwareSnapshotData {
    return HardwareSnapshotData(
      capturedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
      thermalState: mapThermalState(ProcessInfo.processInfo.thermalState),
      sensors: [],
      fans: [],
      note: "The placeholder bridge currently surfaces thermal pressure only. Wire SMC/HID sampling next."
    )
  }

  func setFanMode(fanId: String, mode: FanModeData) throws {
    throw PigeonError(
      code: "unimplemented",
      message: "Fan control is not wired yet.",
      details: fanId
    )
  }

  func setFanTargetRpm(fanId: String, targetRpm: Int64) throws {
    throw PigeonError(
      code: "unimplemented",
      message: "Fan control is not wired yet.",
      details: "\(fanId):\(targetRpm)"
    )
  }

  private func mapThermalState(_ state: ProcessInfo.ThermalState) -> ThermalStateData {
    switch state {
    case .nominal:
      return .nominal
    case .fair:
      return .fair
    case .serious:
      return .serious
    case .critical:
      return .critical
    @unknown default:
      return .unknown
    }
  }
}
