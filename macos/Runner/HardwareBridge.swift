import Cocoa
import Darwin
import Foundation
import IOKit
import IOKit.hidsystem

private typealias FourCharCode = UInt32

private enum SMCDataType: String {
  case ui8 = "ui8 "
  case ui16 = "ui16"
  case ui32 = "ui32"
  case sp1e = "sp1e"
  case sp3c = "sp3c"
  case sp4b = "sp4b"
  case sp5a = "sp5a"
  case spa5 = "spa5"
  case sp69 = "sp69"
  case sp78 = "sp78"
  case sp87 = "sp87"
  case sp96 = "sp96"
  case spb4 = "spb4"
  case spf0 = "spf0"
  case flt = "flt "
  case fpe2 = "fpe2"
}

private enum SMCCommand: UInt8 {
  case kernelIndex = 2
  case readBytes = 5
  case readIndex = 8
  case readKeyInfo = 9
}

private struct SMCKeyData {
  typealias Bytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
  )

  struct Version {
    var major: CUnsignedChar = 0
    var minor: CUnsignedChar = 0
    var build: CUnsignedChar = 0
    var reserved: CUnsignedChar = 0
    var release: CUnsignedShort = 0
  }

  struct PowerLimit {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
  }

  struct KeyInfo {
    var dataSize: IOByteCount32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
  }

  var key: UInt32 = 0
  var version = Version()
  var powerLimit = PowerLimit()
  var keyInfo = KeyInfo()
  var padding: UInt16 = 0
  var result: UInt8 = 0
  var status: UInt8 = 0
  var data8: UInt8 = 0
  var data32: UInt32 = 0
  var bytes: Bytes = (
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  )
}

private struct SMCValue {
  init(key: String) {
    self.key = key
  }

  let key: String
  var dataSize: UInt32 = 0
  var dataType = ""
  var bytes = [UInt8](repeating: 0, count: 32)
}

private struct SensorDescriptor {
  let key: String
  let name: String
  let kind: SensorKindData
}

private enum AppleSiliconModel {
  case m1
  case m1Pro
  case m1Max
  case m1Ultra
  case m2
  case m2Pro
  case m2Max
  case m2Ultra
  case m3
  case m3Pro
  case m3Max
  case m3Ultra
  case m4
  case m4Pro
  case m4Max
  case m4Ultra
  case unknown

  static func detect(from brand: String) -> AppleSiliconModel {
    let normalized = brand.uppercased()

    if normalized.contains("M4 ULTRA") {
      return .m4Ultra
    }
    if normalized.contains("M4 MAX") {
      return .m4Max
    }
    if normalized.contains("M4 PRO") {
      return .m4Pro
    }
    if normalized.contains("M4") {
      return .m4
    }
    if normalized.contains("M3 ULTRA") {
      return .m3Ultra
    }
    if normalized.contains("M3 MAX") {
      return .m3Max
    }
    if normalized.contains("M3 PRO") {
      return .m3Pro
    }
    if normalized.contains("M3") {
      return .m3
    }
    if normalized.contains("M2 ULTRA") {
      return .m2Ultra
    }
    if normalized.contains("M2 MAX") {
      return .m2Max
    }
    if normalized.contains("M2 PRO") {
      return .m2Pro
    }
    if normalized.contains("M2") {
      return .m2
    }
    if normalized.contains("M1 ULTRA") {
      return .m1Ultra
    }
    if normalized.contains("M1 MAX") {
      return .m1Max
    }
    if normalized.contains("M1 PRO") {
      return .m1Pro
    }
    if normalized.contains("M1") {
      return .m1
    }
    return .unknown
  }

  var generation: AppleSiliconGeneration {
    switch self {
    case .m1, .m1Pro, .m1Max, .m1Ultra:
      return .m1
    case .m2, .m2Pro, .m2Max, .m2Ultra:
      return .m2
    case .m3, .m3Pro, .m3Max, .m3Ultra:
      return .m3
    case .m4, .m4Pro, .m4Max, .m4Ultra:
      return .m4
    case .unknown:
      return .unknown
    }
  }
}

private enum AppleSiliconGeneration {
  case m1
  case m2
  case m3
  case m4
  case unknown
}

private enum Sysctl {
  static func string(_ name: String) -> String? {
    var size: size_t = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0 else {
      return nil
    }

    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
      return nil
    }

    return String(cString: buffer)
  }

  static func int32(_ name: String) -> Int32? {
    var value: Int32 = 0
    var size = MemoryLayout<Int32>.size
    guard sysctlbyname(name, &value, &size, nil, 0) == 0 else {
      return nil
    }
    return value
  }

  static var isAppleSilicon: Bool {
    int32("hw.optional.arm64") == 1
  }
}

private extension FourCharCode {
  init(from string: String) {
    precondition(string.count == 4)
    self = string.utf8.reduce(0) { partialResult, codeUnit in
      (partialResult << 8) | UInt32(codeUnit)
    }
  }
}

private extension UInt32 {
  init(bytes: (UInt8, UInt8, UInt8, UInt8)) {
    self = UInt32(bytes.0) << 24 |
      UInt32(bytes.1) << 16 |
      UInt32(bytes.2) << 8 |
      UInt32(bytes.3)
  }

  var fourCharString: String {
    String(UnicodeScalar((self >> 24) & 0xff)!) +
      String(UnicodeScalar((self >> 16) & 0xff)!) +
      String(UnicodeScalar((self >> 8) & 0xff)!) +
      String(UnicodeScalar(self & 0xff)!)
  }
}

private extension UInt16 {
  init(bytes: (UInt8, UInt8)) {
    self = UInt16(bytes.0) << 8 | UInt16(bytes.1)
  }
}

private extension Int {
  init(fpe2 bytes: (UInt8, UInt8)) {
    self = (Int(bytes.0) << 6) + (Int(bytes.1) >> 2)
  }
}

private extension Float {
  init?(smcBytes: [UInt8]) {
    guard smcBytes.count >= 4 else {
      return nil
    }

    var value: Float = 0
    withUnsafeMutableBytes(of: &value) { buffer in
      buffer.copyBytes(from: smcBytes.prefix(4))
    }
    self = value
  }
}

private final class AppleSMCConnection {
  private let lock = NSLock()
  private var connection: io_connect_t = 0
  private let ioMainPort: mach_port_t

  init() throws {
    if #available(macOS 12.0, *) {
      ioMainPort = kIOMainPortDefault
    } else {
      ioMainPort = kIOMasterPortDefault
    }

    var iterator: io_iterator_t = 0
    let matchingDictionary = IOServiceMatching("AppleSMC")
    let matchingResult = IOServiceGetMatchingServices(
      ioMainPort,
      matchingDictionary,
      &iterator
    )

    guard matchingResult == kIOReturnSuccess else {
      throw SMCConnectionError.openFailed(result: matchingResult)
    }

    let device = IOIteratorNext(iterator)
    IOObjectRelease(iterator)

    guard device != 0 else {
      throw SMCConnectionError.serviceNotFound
    }

    defer {
      IOObjectRelease(device)
    }

    let openResult = IOServiceOpen(device, mach_task_self_, 0, &connection)
    guard openResult == kIOReturnSuccess else {
      throw SMCConnectionError.openFailed(result: openResult)
    }
  }

  deinit {
    if connection != 0 {
      IOServiceClose(connection)
    }
  }

  func value(for key: String, allowZero: Bool = false) -> Double? {
    lock.lock()
    defer {
      lock.unlock()
    }

    guard let value = readValue(for: key) else {
      return nil
    }

    if !allowZero && value.bytes.prefix(Int(value.dataSize)).allSatisfy({ $0 == 0 }) {
      return nil
    }

    return decode(value: value)
  }

  private func readValue(for key: String) -> SMCValue? {
    var value = SMCValue(key: key)
    let result = read(&value)
    guard result == kIOReturnSuccess else {
      return nil
    }
    return value
  }

  private func read(_ value: inout SMCValue) -> kern_return_t {
    var input = SMCKeyData()
    var output = SMCKeyData()

    input.key = FourCharCode(from: value.key)
    input.data8 = SMCCommand.readKeyInfo.rawValue

    let infoResult = call(
      index: SMCCommand.kernelIndex.rawValue,
      input: &input,
      output: &output
    )
    guard infoResult == kIOReturnSuccess else {
      return infoResult
    }

    value.dataSize = UInt32(output.keyInfo.dataSize)
    value.dataType = output.keyInfo.dataType.fourCharString

    input.keyInfo.dataSize = output.keyInfo.dataSize
    input.data8 = SMCCommand.readBytes.rawValue

    let readResult = call(
      index: SMCCommand.kernelIndex.rawValue,
      input: &input,
      output: &output
    )
    guard readResult == kIOReturnSuccess else {
      return readResult
    }

    let bytes = withUnsafeBytes(of: output.bytes) { rawBuffer in
      Array(rawBuffer)
    }
    let dataSize = min(bytes.count, Int(value.dataSize))
    value.bytes.replaceSubrange(0..<dataSize, with: bytes.prefix(dataSize))
    return kIOReturnSuccess
  }

  private func call(
    index: UInt8,
    input: inout SMCKeyData,
    output: inout SMCKeyData
  ) -> kern_return_t {
    let inputSize = MemoryLayout<SMCKeyData>.stride
    var outputSize = MemoryLayout<SMCKeyData>.stride

    return IOConnectCallStructMethod(
      connection,
      UInt32(index),
      &input,
      inputSize,
      &output,
      &outputSize
    )
  }

  private func decode(value: SMCValue) -> Double? {
    switch value.dataType {
    case SMCDataType.ui8.rawValue:
      return Double(value.bytes[0])

    case SMCDataType.ui16.rawValue:
      return Double(UInt16(bytes: (value.bytes[0], value.bytes[1])))

    case SMCDataType.ui32.rawValue:
      return Double(UInt32(bytes: (value.bytes[0], value.bytes[1], value.bytes[2], value.bytes[3])))

    case SMCDataType.sp1e.rawValue:
      return Double(UInt16(value.bytes[0]) * 256 + UInt16(value.bytes[1])) / 16_384

    case SMCDataType.sp3c.rawValue:
      return Double(UInt16(value.bytes[0]) * 256 + UInt16(value.bytes[1])) / 4_096

    case SMCDataType.sp4b.rawValue:
      return Double(UInt16(value.bytes[0]) * 256 + UInt16(value.bytes[1])) / 2_048

    case SMCDataType.sp5a.rawValue:
      return Double(UInt16(value.bytes[0]) * 256 + UInt16(value.bytes[1])) / 1_024

    case SMCDataType.sp69.rawValue:
      return Double(UInt16(value.bytes[0]) * 256 + UInt16(value.bytes[1])) / 512

    case SMCDataType.sp78.rawValue:
      return Double(Int(value.bytes[0]) * 256 + Int(value.bytes[1])) / 256

    case SMCDataType.sp87.rawValue:
      return Double(Int(value.bytes[0]) * 256 + Int(value.bytes[1])) / 128

    case SMCDataType.sp96.rawValue:
      return Double(Int(value.bytes[0]) * 256 + Int(value.bytes[1])) / 64

    case SMCDataType.spa5.rawValue:
      return Double(UInt16(value.bytes[0]) * 256 + UInt16(value.bytes[1])) / 32

    case SMCDataType.spb4.rawValue:
      return Double(Int(value.bytes[0]) * 256 + Int(value.bytes[1])) / 16

    case SMCDataType.spf0.rawValue:
      return Double(Int(value.bytes[0]) * 256 + Int(value.bytes[1]))

    case SMCDataType.flt.rawValue:
      return Float(smcBytes: value.bytes).map(Double.init)

    case SMCDataType.fpe2.rawValue:
      return Double(Int(fpe2: (value.bytes[0], value.bytes[1])))

    default:
      return nil
    }
  }
}

private enum SMCConnectionError: Error {
  case serviceNotFound
  case openFailed(result: kern_return_t)

  var message: String {
    switch self {
    case .serviceNotFound:
      return "AppleSMC service was not found."
    case let .openFailed(result):
      let description = String(cString: mach_error_string(result), encoding: .ascii) ?? "unknown error"
      return "AppleSMC open failed: \(description)."
    }
  }
}

private final class AppleSiliconHardwareMonitor {
  private let chipBrand: String
  private let chipModel: AppleSiliconModel
  private let smc: AppleSMCConnection?
  private let startupNote: String?

  init() {
    chipBrand = Sysctl.string("machdep.cpu.brand_string") ?? "Apple Silicon"
    chipModel = AppleSiliconModel.detect(from: chipBrand)

    guard Sysctl.isAppleSilicon else {
      smc = nil
      startupNote = "Intel Macs are not supported by this build."
      return
    }

    do {
      smc = try AppleSMCConnection()
      startupNote = nil
    } catch let error as SMCConnectionError {
      smc = nil
      startupNote = "\(error.message) Direct-distribution builds must run without App Sandbox to access AppleSMC."
    } catch {
      smc = nil
      startupNote = "AppleSMC initialization failed: \(error)"
    }
  }

  func capabilities() -> HardwareCapabilitiesData {
    guard Sysctl.isAppleSilicon else {
      return HardwareCapabilitiesData(
        supportsRawSensors: false,
        supportsFanControl: false,
        hasFans: false,
        backend: "unsupported-intel",
        note: startupNote
      )
    }

    guard smc != nil else {
      return HardwareCapabilitiesData(
        supportsRawSensors: false,
        supportsFanControl: false,
        hasFans: false,
        backend: "apple-smc-unavailable",
        note: startupNote
      )
    }

    let sensors = readSensors()
    let fans = readFans()
    let backend = sensors.contains(where: { $0.id?.hasPrefix("hid-") == true })
      ? "apple-smc-hid"
      : "apple-smc"

    return HardwareCapabilitiesData(
      supportsRawSensors: !sensors.isEmpty,
      supportsFanControl: false,
      hasFans: !fans.isEmpty,
      backend: backend,
      note: sensors.isEmpty ? missingSensorNote() : nil
    )
  }

  func snapshot(thermalState: ThermalStateData) -> HardwareSnapshotData {
    guard Sysctl.isAppleSilicon else {
      return HardwareSnapshotData(
        capturedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
        thermalState: thermalState,
        sensors: [],
        fans: [],
        note: startupNote
      )
    }

    guard smc != nil else {
      return HardwareSnapshotData(
        capturedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
        thermalState: thermalState,
        sensors: [],
        fans: [],
        note: startupNote
      )
    }

    let sensors = readSensors()
    let fans = readFans()

    return HardwareSnapshotData(
      capturedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
      thermalState: thermalState,
      sensors: sensors,
      fans: fans,
      note: sensors.isEmpty ? missingSensorNote() : nil
    )
  }

  private func readSensors() -> [SensorReadingData] {
    guard smc != nil else {
      return []
    }

    var readings: [SensorReadingData] = []

    if chipModel == .m4Pro {
      readings.append(contentsOf: readM4ProCpuThermals())
      readings.append(contentsOf: readKnownSmcSensors(Self.m4ProGpuSensors))
      readings.append(contentsOf: readKnownSmcSensors(Self.m4ProSupplementalSensors))
      readings.append(contentsOf: readKnownHidSensors(promotePmuTdieToCpu: false))
    } else {
      readings.append(contentsOf: readKnownSmcSensors(sensorCatalog))
      readings.append(contentsOf: readKnownHidSensors(promotePmuTdieToCpu: false))
    }

    return deduplicated(readings)
  }

  private func readKnownSmcSensors(_ descriptors: [SensorDescriptor]) -> [SensorReadingData] {
    guard let smc else {
      return []
    }

    var readings: [SensorReadingData] = []
    var seenKeys = Set<String>()

    for descriptor in descriptors {
      guard !seenKeys.contains(descriptor.key) else {
        continue
      }
      guard let value = smc.value(for: descriptor.key), isReasonableTemperature(value) else {
        continue
      }

      seenKeys.insert(descriptor.key)
      readings.append(
        SensorReadingData(
          id: descriptor.key,
          name: descriptor.name,
          unit: "C",
          value: value,
          kind: descriptor.kind
        )
      )
    }

    return readings
  }

  private func readM4ProCpuThermals() -> [SensorReadingData] {
    let hidValues = hidTemperatureValues()
    let cpuSensors = hidValues
      .filter { $0.key.hasPrefix("PMU tdie") }
      .compactMap { key, value -> SensorReadingData? in
        guard isReasonableTemperature(value),
              let index = trailingInteger(in: key) else {
          return nil
        }

        return SensorReadingData(
          id: "hid-\(key)",
          name: "CPU thermal \(index)",
          unit: "C",
          value: value,
          kind: .cpu
        )
      }
      .sorted { ($0.id ?? "") < ($1.id ?? "") }

    if !cpuSensors.isEmpty {
      return cpuSensors
    }

    return readKnownSmcSensors(Self.m4CpuFallbackSensors)
  }

  private func readKnownHidSensors(promotePmuTdieToCpu: Bool) -> [SensorReadingData] {
    let temperatures = hidTemperatureValues()

    return temperatures.compactMap { key, value in
      sensorFromHid(key: key, value: value, promotePmuTdieToCpu: promotePmuTdieToCpu)
    }
  }

  private func hidTemperatureValues() -> [String: Double] {
    guard let sensors = AppleSiliconTemperatureSensors(0xff00, 0x0005, kIOHIDEventTypeTemperature) else {
      return [:]
    }

    return sensors.reduce(into: [String: Double]()) { partialResult, item in
      partialResult[item.key] = item.value.doubleValue
    }
  }

  private func sensorFromHid(
    key: String,
    value: Double,
    promotePmuTdieToCpu: Bool
  ) -> SensorReadingData? {
    guard isReasonableTemperature(value) else {
      return nil
    }

    if promotePmuTdieToCpu, key.hasPrefix("PMU tdie"), let index = trailingInteger(in: key) {
      return SensorReadingData(
        id: "hid-\(key)",
        name: "CPU thermal \(index)",
        unit: "C",
        value: value,
        kind: .cpu
      )
    }

    if key.hasPrefix("GPU MTR Temp Sensor"), let index = trailingInteger(in: key) {
      return SensorReadingData(
        id: "hid-\(key)",
        name: "GPU cluster \(index + 1)",
        unit: "C",
        value: value,
        kind: .gpu
      )
    }

    if key.hasPrefix("pACC MTR Temp Sensor"), let index = trailingInteger(in: key) {
      return SensorReadingData(
        id: "hid-\(key)",
        name: "CPU performance thermal \(index + 1)",
        unit: "C",
        value: value,
        kind: .cpu
      )
    }

    if key.hasPrefix("eACC MTR Temp Sensor"), let index = trailingInteger(in: key) {
      return SensorReadingData(
        id: "hid-\(key)",
        name: "CPU efficiency thermal \(index + 1)",
        unit: "C",
        value: value,
        kind: .cpu
      )
    }

    if key.hasPrefix("PMGR SOC Die Temp Sensor"), let index = trailingInteger(in: key) {
      return SensorReadingData(
        id: "hid-\(key)",
        name: "Power manager die \(index + 1)",
        unit: "C",
        value: value,
        kind: .other
      )
    }

    if key.hasPrefix("PMU tdev"), let index = trailingInteger(in: key) {
      return SensorReadingData(
        id: "hid-\(key)",
        name: "Power manager dev \(index)",
        unit: "C",
        value: value,
        kind: .other
      )
    }

    if key.hasPrefix("PMU tdie"), let index = trailingInteger(in: key) {
      return SensorReadingData(
        id: "hid-\(key)",
        name: "Power manager die \(index)",
        unit: "C",
        value: value,
        kind: .other
      )
    }

    if key.hasPrefix("NAND CH"), let channel = channelNumber(in: key) {
      return SensorReadingData(
        id: "hid-\(key)",
        name: "SSD / NAND channel \(channel + 1)",
        unit: "C",
        value: value,
        kind: .other
      )
    }

    if key == "gas gauge battery" {
      return SensorReadingData(
        id: "hid-\(key)",
        name: "Battery",
        unit: "C",
        value: value,
        kind: .other
      )
    }

    if key == "PMU tcal" {
      return SensorReadingData(
        id: "hid-\(key)",
        name: "Power manager calibration",
        unit: "C",
        value: value,
        kind: .other
      )
    }

    return nil
  }

  private func deduplicated(_ readings: [SensorReadingData]) -> [SensorReadingData] {
    var seen = Set<String>()
    var result: [SensorReadingData] = []

    for reading in readings {
      guard let id = reading.id, !seen.contains(id) else {
        continue
      }
      seen.insert(id)
      result.append(reading)
    }

    return result.sorted {
      ($0.kind?.rawValue ?? 99, $0.name ?? "", $0.id ?? "") <
      ($1.kind?.rawValue ?? 99, $1.name ?? "", $1.id ?? "")
    }
  }

  private func readFans() -> [FanReadingData] {
    guard let smc else {
      return []
    }

    guard let rawFanCount = smc.value(for: "FNum", allowZero: true) else {
      return []
    }

    let fanCount = max(0, Int(rawFanCount.rounded(.towardZero)))
    guard fanCount > 0 else {
      return []
    }

    var fans: [FanReadingData] = []

    for index in 0..<fanCount {
      let current = smc.value(for: "F\(index)Ac")
      let minimum = smc.value(for: "F\(index)Mn")
      let maximum = smc.value(for: "F\(index)Mx")
      let target = smc.value(for: "F\(index)Tg", allowZero: true)
      let modeValue = smc.value(for: "F\(index)Md", allowZero: true) ?? 0

      guard let current else {
        continue
      }

      let minimumRpm = Int((minimum ?? current).rounded())
      let maximumRpm = Int((maximum ?? current).rounded())
      let currentRpm = Int(current.rounded())
      let targetRpm = target.map { Int($0.rounded()) }

      fans.append(
        FanReadingData(
          id: "fan-\(index)",
          name: fanCount == 1 ? "System fan" : "Fan \(index + 1)",
          currentRpm: Int64(currentRpm),
          minimumRpm: Int64(minimumRpm),
          maximumRpm: Int64(maximumRpm),
          targetRpm: targetRpm.map(Int64.init),
          mode: modeValue > 0 ? .manual : .automatic
        )
      )
    }

    return fans
  }

  private func isReasonableTemperature(_ value: Double) -> Bool {
    value.isFinite && value > 0 && value < 140
  }

  private func trailingInteger(in text: String) -> Int? {
    let suffix = text.reversed().prefix { $0.isNumber }.reversed()
    guard !suffix.isEmpty else {
      return nil
    }
    return Int(String(suffix))
  }

  private func channelNumber(in text: String) -> Int? {
    guard let chRange = text.range(of: "CH"),
          let tempRange = text.range(of: " temp") else {
      return nil
    }

    let value = text[chRange.upperBound..<tempRange.lowerBound]
    return Int(value)
  }

  private func missingSensorNote() -> String? {
    switch chipModel.generation {
    case .unknown:
      return "AppleSMC opened successfully, but this chip generation (\(chipBrand)) is not mapped yet."
    case .m1, .m2, .m3, .m4:
      return "AppleSMC opened successfully, but none of the mapped temperature keys matched \(chipBrand)."
    }
  }

  private var sensorCatalog: [SensorDescriptor] {
    switch chipModel.generation {
    case .m1:
      return Self.m1Sensors + Self.appleSiliconCommonSensors
    case .m2:
      return Self.m2Sensors + Self.appleSiliconCommonSensors
    case .m3:
      return Self.m3Sensors + Self.appleSiliconCommonSensors
    case .m4:
      return Self.m4Sensors + Self.appleSiliconCommonSensors + Self.m4SupplementalSensors
    case .unknown:
      return Self.appleSiliconCommonSensors
    }
  }

  private static let appleSiliconCommonSensors: [SensorDescriptor] = [
    SensorDescriptor(key: "TaLP", name: "Airflow left", kind: .ambient),
    SensorDescriptor(key: "TaRF", name: "Airflow right", kind: .ambient),
    SensorDescriptor(key: "TB1T", name: "Battery 1", kind: .other),
    SensorDescriptor(key: "TB2T", name: "Battery 2", kind: .other),
    SensorDescriptor(key: "TW0P", name: "Airport", kind: .other),
  ]

  private static let m1Sensors: [SensorDescriptor] = [
    SensorDescriptor(key: "Tp09", name: "CPU efficiency core 1", kind: .cpu),
    SensorDescriptor(key: "Tp0T", name: "CPU efficiency core 2", kind: .cpu),
    SensorDescriptor(key: "Tp01", name: "CPU performance core 1", kind: .cpu),
    SensorDescriptor(key: "Tp05", name: "CPU performance core 2", kind: .cpu),
    SensorDescriptor(key: "Tp0D", name: "CPU performance core 3", kind: .cpu),
    SensorDescriptor(key: "Tp0H", name: "CPU performance core 4", kind: .cpu),
    SensorDescriptor(key: "Tp0L", name: "CPU performance core 5", kind: .cpu),
    SensorDescriptor(key: "Tp0P", name: "CPU performance core 6", kind: .cpu),
    SensorDescriptor(key: "Tp0X", name: "CPU performance core 7", kind: .cpu),
    SensorDescriptor(key: "Tp0b", name: "CPU performance core 8", kind: .cpu),
    SensorDescriptor(key: "Tg05", name: "GPU 1", kind: .gpu),
    SensorDescriptor(key: "Tg0D", name: "GPU 2", kind: .gpu),
    SensorDescriptor(key: "Tg0L", name: "GPU 3", kind: .gpu),
    SensorDescriptor(key: "Tg0T", name: "GPU 4", kind: .gpu),
    SensorDescriptor(key: "Tm02", name: "Memory 1", kind: .memory),
    SensorDescriptor(key: "Tm06", name: "Memory 2", kind: .memory),
    SensorDescriptor(key: "Tm08", name: "Memory 3", kind: .memory),
    SensorDescriptor(key: "Tm09", name: "Memory 4", kind: .memory),
  ]

  private static let m2Sensors: [SensorDescriptor] = [
    SensorDescriptor(key: "Tp1h", name: "CPU efficiency core 1", kind: .cpu),
    SensorDescriptor(key: "Tp1t", name: "CPU efficiency core 2", kind: .cpu),
    SensorDescriptor(key: "Tp1p", name: "CPU efficiency core 3", kind: .cpu),
    SensorDescriptor(key: "Tp1l", name: "CPU efficiency core 4", kind: .cpu),
    SensorDescriptor(key: "Tp01", name: "CPU performance core 1", kind: .cpu),
    SensorDescriptor(key: "Tp05", name: "CPU performance core 2", kind: .cpu),
    SensorDescriptor(key: "Tp09", name: "CPU performance core 3", kind: .cpu),
    SensorDescriptor(key: "Tp0D", name: "CPU performance core 4", kind: .cpu),
    SensorDescriptor(key: "Tp0X", name: "CPU performance core 5", kind: .cpu),
    SensorDescriptor(key: "Tp0b", name: "CPU performance core 6", kind: .cpu),
    SensorDescriptor(key: "Tp0f", name: "CPU performance core 7", kind: .cpu),
    SensorDescriptor(key: "Tp0j", name: "CPU performance core 8", kind: .cpu),
    SensorDescriptor(key: "Tg0f", name: "GPU 1", kind: .gpu),
    SensorDescriptor(key: "Tg0j", name: "GPU 2", kind: .gpu),
  ]

  private static let m3Sensors: [SensorDescriptor] = [
    SensorDescriptor(key: "Te05", name: "CPU efficiency core 1", kind: .cpu),
    SensorDescriptor(key: "Te0L", name: "CPU efficiency core 2", kind: .cpu),
    SensorDescriptor(key: "Te0P", name: "CPU efficiency core 3", kind: .cpu),
    SensorDescriptor(key: "Te0S", name: "CPU efficiency core 4", kind: .cpu),
    SensorDescriptor(key: "Tf04", name: "CPU performance core 1", kind: .cpu),
    SensorDescriptor(key: "Tf09", name: "CPU performance core 2", kind: .cpu),
    SensorDescriptor(key: "Tf0A", name: "CPU performance core 3", kind: .cpu),
    SensorDescriptor(key: "Tf0B", name: "CPU performance core 4", kind: .cpu),
    SensorDescriptor(key: "Tf0D", name: "CPU performance core 5", kind: .cpu),
    SensorDescriptor(key: "Tf0E", name: "CPU performance core 6", kind: .cpu),
    SensorDescriptor(key: "Tf44", name: "CPU performance core 7", kind: .cpu),
    SensorDescriptor(key: "Tf49", name: "CPU performance core 8", kind: .cpu),
    SensorDescriptor(key: "Tf4A", name: "CPU performance core 9", kind: .cpu),
    SensorDescriptor(key: "Tf4B", name: "CPU performance core 10", kind: .cpu),
    SensorDescriptor(key: "Tf4D", name: "CPU performance core 11", kind: .cpu),
    SensorDescriptor(key: "Tf4E", name: "CPU performance core 12", kind: .cpu),
    SensorDescriptor(key: "Tf14", name: "GPU 1", kind: .gpu),
    SensorDescriptor(key: "Tf18", name: "GPU 2", kind: .gpu),
    SensorDescriptor(key: "Tf19", name: "GPU 3", kind: .gpu),
    SensorDescriptor(key: "Tf1A", name: "GPU 4", kind: .gpu),
    SensorDescriptor(key: "Tf24", name: "GPU 5", kind: .gpu),
    SensorDescriptor(key: "Tf28", name: "GPU 6", kind: .gpu),
    SensorDescriptor(key: "Tf29", name: "GPU 7", kind: .gpu),
    SensorDescriptor(key: "Tf2A", name: "GPU 8", kind: .gpu),
  ]

  private static let m4Sensors: [SensorDescriptor] = [
    SensorDescriptor(key: "Te05", name: "CPU efficiency core 1", kind: .cpu),
    SensorDescriptor(key: "Te0S", name: "CPU efficiency core 2", kind: .cpu),
    SensorDescriptor(key: "Te09", name: "CPU efficiency core 3", kind: .cpu),
    SensorDescriptor(key: "Te0H", name: "CPU efficiency core 4", kind: .cpu),
    SensorDescriptor(key: "Tp01", name: "CPU performance core 1", kind: .cpu),
    SensorDescriptor(key: "Tp05", name: "CPU performance core 2", kind: .cpu),
    SensorDescriptor(key: "Tp09", name: "CPU performance core 3", kind: .cpu),
    SensorDescriptor(key: "Tp0D", name: "CPU performance core 4", kind: .cpu),
    SensorDescriptor(key: "Tp0V", name: "CPU performance core 5", kind: .cpu),
    SensorDescriptor(key: "Tp0Y", name: "CPU performance core 6", kind: .cpu),
    SensorDescriptor(key: "Tp0b", name: "CPU performance core 7", kind: .cpu),
    SensorDescriptor(key: "Tp0e", name: "CPU performance core 8", kind: .cpu),
    SensorDescriptor(key: "Tg0G", name: "GPU 1", kind: .gpu),
    SensorDescriptor(key: "Tg0H", name: "GPU 2", kind: .gpu),
    SensorDescriptor(key: "Tg1U", name: "GPU 3", kind: .gpu),
    SensorDescriptor(key: "Tg1k", name: "GPU 4", kind: .gpu),
    SensorDescriptor(key: "Tg0K", name: "GPU 5", kind: .gpu),
    SensorDescriptor(key: "Tg0L", name: "GPU 6", kind: .gpu),
    SensorDescriptor(key: "Tg0d", name: "GPU 7", kind: .gpu),
    SensorDescriptor(key: "Tg0e", name: "GPU 8", kind: .gpu),
    SensorDescriptor(key: "Tg0j", name: "GPU 9", kind: .gpu),
    SensorDescriptor(key: "Tg0k", name: "GPU 10", kind: .gpu),
    SensorDescriptor(key: "Tm0p", name: "Memory proximity 1", kind: .memory),
    SensorDescriptor(key: "Tm1p", name: "Memory proximity 2", kind: .memory),
    SensorDescriptor(key: "Tm2p", name: "Memory proximity 3", kind: .memory),
  ]

  private static let m4SupplementalSensors: [SensorDescriptor] = [
    SensorDescriptor(key: "TH0x", name: "SSD / NAND", kind: .other),
    SensorDescriptor(key: "TPMP", name: "Power manager", kind: .other),
    SensorDescriptor(key: "TPSD", name: "Power supply die", kind: .other),
    SensorDescriptor(key: "TPSP", name: "Power supply", kind: .other),
  ]

  private static let m4CpuFallbackSensors: [SensorDescriptor] = [
    SensorDescriptor(key: "Tp01", name: "CPU thermal 1", kind: .cpu),
    SensorDescriptor(key: "Tp05", name: "CPU thermal 2", kind: .cpu),
    SensorDescriptor(key: "Tp09", name: "CPU thermal 3", kind: .cpu),
    SensorDescriptor(key: "Tp0D", name: "CPU thermal 4", kind: .cpu),
    SensorDescriptor(key: "Tp0H", name: "CPU thermal 5", kind: .cpu),
    SensorDescriptor(key: "Tp0L", name: "CPU thermal 6", kind: .cpu),
    SensorDescriptor(key: "Tp0P", name: "CPU thermal 7", kind: .cpu),
    SensorDescriptor(key: "Tp0T", name: "CPU thermal 8", kind: .cpu),
    SensorDescriptor(key: "Tp0X", name: "CPU thermal 9", kind: .cpu),
    SensorDescriptor(key: "Tp0b", name: "CPU thermal 10", kind: .cpu),
    SensorDescriptor(key: "Tp0e", name: "CPU thermal 11", kind: .cpu),
    SensorDescriptor(key: "Tp0i", name: "CPU thermal 12", kind: .cpu),
    SensorDescriptor(key: "Tp0m", name: "CPU thermal 13", kind: .cpu),
    SensorDescriptor(key: "Tp0q", name: "CPU thermal 14", kind: .cpu),
  ]

  private static let m4ProSupplementalSensors: [SensorDescriptor] = [
    SensorDescriptor(key: "Tm0p", name: "Memory proximity 1", kind: .memory),
    SensorDescriptor(key: "Tm1p", name: "Memory proximity 2", kind: .memory),
    SensorDescriptor(key: "Tm2p", name: "Memory proximity 3", kind: .memory),
    SensorDescriptor(key: "TH0x", name: "SSD / NAND", kind: .other),
    SensorDescriptor(key: "TH0a", name: "SSD / NAND A", kind: .other),
    SensorDescriptor(key: "TH0b", name: "SSD / NAND B", kind: .other),
    SensorDescriptor(key: "TH0p", name: "SSD controller", kind: .other),
    SensorDescriptor(key: "TPMP", name: "Power manager", kind: .other),
    SensorDescriptor(key: "TPCP", name: "CPU package", kind: .cpu),
    SensorDescriptor(key: "TPSD", name: "Power supply die", kind: .other),
    SensorDescriptor(key: "TPSP", name: "Power supply", kind: .other),
    SensorDescriptor(key: "TW0P", name: "Airport", kind: .other),
  ]

  private static let m4ProGpuSensors: [SensorDescriptor] = [
    SensorDescriptor(key: "Tg04", name: "GPU thermal 1", kind: .gpu),
    SensorDescriptor(key: "Tg05", name: "GPU thermal 2", kind: .gpu),
    SensorDescriptor(key: "Tg0K", name: "GPU thermal 3", kind: .gpu),
    SensorDescriptor(key: "Tg0L", name: "GPU thermal 4", kind: .gpu),
    SensorDescriptor(key: "Tg0R", name: "GPU thermal 5", kind: .gpu),
    SensorDescriptor(key: "Tg0S", name: "GPU thermal 6", kind: .gpu),
    SensorDescriptor(key: "Tg0X", name: "GPU thermal 7", kind: .gpu),
    SensorDescriptor(key: "Tg0Y", name: "GPU thermal 8", kind: .gpu),
    SensorDescriptor(key: "Tg0d", name: "GPU thermal 9", kind: .gpu),
    SensorDescriptor(key: "Tg0e", name: "GPU thermal 10", kind: .gpu),
    SensorDescriptor(key: "Tg0j", name: "GPU thermal 11", kind: .gpu),
    SensorDescriptor(key: "Tg0k", name: "GPU thermal 12", kind: .gpu),
    SensorDescriptor(key: "Tg0y", name: "GPU thermal 13", kind: .gpu),
    SensorDescriptor(key: "Tg0z", name: "GPU thermal 14", kind: .gpu),
    SensorDescriptor(key: "Tg1E", name: "GPU thermal 15", kind: .gpu),
    SensorDescriptor(key: "Tg1F", name: "GPU thermal 16", kind: .gpu),
    SensorDescriptor(key: "Tg1U", name: "GPU thermal 17", kind: .gpu),
    SensorDescriptor(key: "Tg1V", name: "GPU thermal 18", kind: .gpu),
    SensorDescriptor(key: "Tg1k", name: "GPU thermal 19", kind: .gpu),
    SensorDescriptor(key: "Tg1l", name: "GPU thermal 20", kind: .gpu),
  ]
}

final class HardwareBridge: HardwareHostApi {
  private let monitor = AppleSiliconHardwareMonitor()

  func getCapabilities() throws -> HardwareCapabilitiesData {
    monitor.capabilities()
  }

  func getSnapshot() throws -> HardwareSnapshotData {
    monitor.snapshot(thermalState: mapThermalState(ProcessInfo.processInfo.thermalState))
  }

  func setFanMode(fanId: String, mode: FanModeData) throws {
    throw PigeonError(
      code: "unimplemented",
      message: "Fan writes are disabled. AppleSMC fan telemetry is wired, but manual control has not been enabled yet.",
      details: "\(fanId):\(mode)"
    )
  }

  func setFanTargetRpm(fanId: String, targetRpm: Int64) throws {
    throw PigeonError(
      code: "unimplemented",
      message: "Fan writes are disabled. AppleSMC fan telemetry is wired, but manual control has not been enabled yet.",
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
