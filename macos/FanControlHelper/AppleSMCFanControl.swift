import Darwin
import Foundation
import IOKit

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
  case writeBytes = 6
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

private enum Sysctl {
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
      throw AppleSMCFanControlError.smcUnavailable(
        "AppleSMC lookup failed: \(String(cString: mach_error_string(matchingResult), encoding: .ascii) ?? "unknown error")."
      )
    }

    let device = IOIteratorNext(iterator)
    IOObjectRelease(iterator)

    guard device != 0 else {
      throw AppleSMCFanControlError.smcUnavailable("AppleSMC service was not found.")
    }

    defer {
      IOObjectRelease(device)
    }

    let openResult = IOServiceOpen(device, mach_task_self_, 0, &connection)
    guard openResult == kIOReturnSuccess else {
      throw AppleSMCFanControlError.smcUnavailable(
        "AppleSMC open failed: \(String(cString: mach_error_string(openResult), encoding: .ascii) ?? "unknown error")."
      )
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

  func integerValue(for key: String, allowZero: Bool = false) -> UInt32? {
    lock.lock()
    defer {
      lock.unlock()
    }

    guard let value = readValue(for: key) else {
      return nil
    }

    if !allowZero && isZero(value) {
      return nil
    }

    return try? decodeInteger(value: value)
  }

  func canWriteNumeric(for key: String) -> Bool {
    lock.lock()
    defer {
      lock.unlock()
    }

    guard let value = readValue(for: key) else {
      return false
    }

    return supportsNumericEncoding(value: value)
  }

  func canWriteInteger(for key: String) -> Bool {
    lock.lock()
    defer {
      lock.unlock()
    }

    guard let value = readValue(for: key) else {
      return false
    }

    return supportsIntegerEncoding(value: value)
  }

  func writeNumeric(_ numericValue: Double, for key: String) throws {
    lock.lock()
    defer {
      lock.unlock()
    }

    guard let value = readValue(for: key) else {
      throw AppleSMCFanControlError.smcKeyUnavailable(key)
    }

    let bytes = try encodeNumeric(numericValue, using: value)
    try writeLocked(bytes, using: value)
  }

  func writeInteger(_ integerValue: UInt32, for key: String) throws {
    lock.lock()
    defer {
      lock.unlock()
    }

    guard let value = readValue(for: key) else {
      throw AppleSMCFanControlError.smcKeyUnavailable(key)
    }

    let bytes = try encodeInteger(integerValue, using: value)
    try writeLocked(bytes, using: value)
  }

  func updateInteger(for key: String, transform: (UInt32) -> UInt32) throws {
    lock.lock()
    defer {
      lock.unlock()
    }

    guard let value = readValue(for: key) else {
      throw AppleSMCFanControlError.smcKeyUnavailable(key)
    }

    let current = try decodeInteger(value: value)
    let next = transform(current)
    let bytes = try encodeInteger(next, using: value)
    try writeLocked(bytes, using: value)
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
    value.dataType = String(
      bytes: [
        UInt8((output.keyInfo.dataType >> 24) & 0xff),
        UInt8((output.keyInfo.dataType >> 16) & 0xff),
        UInt8((output.keyInfo.dataType >> 8) & 0xff),
        UInt8(output.keyInfo.dataType & 0xff),
      ],
      encoding: .ascii
    ) ?? ""

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

  private func isZero(_ value: SMCValue) -> Bool {
    value.bytes.prefix(Int(value.dataSize)).allSatisfy { $0 == 0 }
  }

  private func writeLocked(_ bytes: [UInt8], using value: SMCValue) throws {
    let dataSize = Int(value.dataSize)
    guard dataSize > 0, dataSize <= 32 else {
      throw AppleSMCFanControlError.invalidDataSize(
        key: value.key,
        expected: dataSize,
        actual: bytes.count
      )
    }

    guard bytes.count == dataSize else {
      throw AppleSMCFanControlError.invalidDataSize(
        key: value.key,
        expected: dataSize,
        actual: bytes.count
      )
    }

    var input = SMCKeyData()
    var output = SMCKeyData()
    var paddedBytes = [UInt8](repeating: 0, count: 32)

    input.key = FourCharCode(from: value.key)
    input.data8 = SMCCommand.writeBytes.rawValue
    input.keyInfo.dataSize = IOByteCount32(value.dataSize)
    if value.dataType.count == 4 {
      input.keyInfo.dataType = FourCharCode(from: value.dataType)
    }

    paddedBytes.replaceSubrange(0..<bytes.count, with: bytes)
    withUnsafeMutableBytes(of: &input.bytes) { rawBuffer in
      rawBuffer.copyBytes(from: paddedBytes)
    }

    let result = call(
      index: SMCCommand.kernelIndex.rawValue,
      input: &input,
      output: &output
    )
    guard result == kIOReturnSuccess else {
      throw AppleSMCFanControlError.writeFailed(
        key: value.key,
        description: String(cString: mach_error_string(result), encoding: .ascii) ?? "unknown error"
      )
    }
  }

  private func decodeInteger(value: SMCValue) throws -> UInt32 {
    switch value.dataType {
    case SMCDataType.ui8.rawValue:
      guard value.dataSize == 1 else {
        throw AppleSMCFanControlError.invalidDataSize(
          key: value.key,
          expected: 1,
          actual: Int(value.dataSize)
        )
      }
      return UInt32(value.bytes[0])

    case SMCDataType.ui16.rawValue:
      guard value.dataSize == 2 else {
        throw AppleSMCFanControlError.invalidDataSize(
          key: value.key,
          expected: 2,
          actual: Int(value.dataSize)
        )
      }
      return UInt32(UInt16(bytes: (value.bytes[0], value.bytes[1])))

    case SMCDataType.ui32.rawValue:
      guard value.dataSize == 4 else {
        throw AppleSMCFanControlError.invalidDataSize(
          key: value.key,
          expected: 4,
          actual: Int(value.dataSize)
        )
      }
      return UInt32(bytes: (value.bytes[0], value.bytes[1], value.bytes[2], value.bytes[3]))

    default:
      throw AppleSMCFanControlError.unsupportedDataType(
        key: value.key,
        dataType: value.dataType
      )
    }
  }

  private func encodeNumeric(_ numericValue: Double, using value: SMCValue) throws -> [UInt8] {
    switch value.dataType {
    case SMCDataType.ui8.rawValue:
      return try encodeInteger(
        checkedInteger(for: value, numericValue: numericValue, max: Double(UInt8.max)),
        using: value
      )

    case SMCDataType.ui16.rawValue:
      return try encodeInteger(
        checkedInteger(for: value, numericValue: numericValue, max: Double(UInt16.max)),
        using: value
      )

    case SMCDataType.ui32.rawValue:
      return try encodeInteger(
        checkedInteger(for: value, numericValue: numericValue, max: Double(UInt32.max)),
        using: value
      )

    case SMCDataType.flt.rawValue:
      guard value.dataSize == 4 else {
        throw AppleSMCFanControlError.invalidDataSize(
          key: value.key,
          expected: 4,
          actual: Int(value.dataSize)
        )
      }

      var floatValue = Float(numericValue)
      guard floatValue.isFinite else {
        throw AppleSMCFanControlError.valueOutOfRange(
          key: value.key,
          dataType: value.dataType,
          value: numericValue
        )
      }

      return withUnsafeBytes(of: &floatValue) { rawBuffer in
        Array(rawBuffer)
      }

    case SMCDataType.fpe2.rawValue:
      guard value.dataSize == 2 else {
        throw AppleSMCFanControlError.invalidDataSize(
          key: value.key,
          expected: 2,
          actual: Int(value.dataSize)
        )
      }

      let integerValue = try checkedInteger(
        for: value,
        numericValue: numericValue,
        max: Double(UInt16.max >> 2)
      )
      let encoded = UInt16(integerValue) << 2
      return [
        UInt8((encoded >> 8) & 0xff),
        UInt8(encoded & 0xff),
      ]

    default:
      throw AppleSMCFanControlError.unsupportedDataType(
        key: value.key,
        dataType: value.dataType
      )
    }
  }

  private func encodeInteger(_ integerValue: UInt32, using value: SMCValue) throws -> [UInt8] {
    switch value.dataType {
    case SMCDataType.ui8.rawValue:
      guard value.dataSize == 1 else {
        throw AppleSMCFanControlError.invalidDataSize(
          key: value.key,
          expected: 1,
          actual: Int(value.dataSize)
        )
      }
      guard integerValue <= UInt32(UInt8.max) else {
        throw AppleSMCFanControlError.valueOutOfRange(
          key: value.key,
          dataType: value.dataType,
          value: Double(integerValue)
        )
      }
      return [UInt8(integerValue)]

    case SMCDataType.ui16.rawValue:
      guard value.dataSize == 2 else {
        throw AppleSMCFanControlError.invalidDataSize(
          key: value.key,
          expected: 2,
          actual: Int(value.dataSize)
        )
      }
      guard integerValue <= UInt32(UInt16.max) else {
        throw AppleSMCFanControlError.valueOutOfRange(
          key: value.key,
          dataType: value.dataType,
          value: Double(integerValue)
        )
      }
      let encoded = UInt16(integerValue)
      return [
        UInt8((encoded >> 8) & 0xff),
        UInt8(encoded & 0xff),
      ]

    case SMCDataType.ui32.rawValue:
      guard value.dataSize == 4 else {
        throw AppleSMCFanControlError.invalidDataSize(
          key: value.key,
          expected: 4,
          actual: Int(value.dataSize)
        )
      }
      return [
        UInt8((integerValue >> 24) & 0xff),
        UInt8((integerValue >> 16) & 0xff),
        UInt8((integerValue >> 8) & 0xff),
        UInt8(integerValue & 0xff),
      ]

    default:
      throw AppleSMCFanControlError.unsupportedDataType(
        key: value.key,
        dataType: value.dataType
      )
    }
  }

  private func checkedInteger(
    for value: SMCValue,
    numericValue: Double,
    max: Double
  ) throws -> UInt32 {
    guard numericValue.isFinite else {
      throw AppleSMCFanControlError.valueOutOfRange(
        key: value.key,
        dataType: value.dataType,
        value: numericValue
      )
    }

    let roundedValue = numericValue.rounded()
    guard roundedValue >= 0, roundedValue <= max else {
      throw AppleSMCFanControlError.valueOutOfRange(
        key: value.key,
        dataType: value.dataType,
        value: numericValue
      )
    }

    return UInt32(roundedValue)
  }

  private func supportsNumericEncoding(value: SMCValue) -> Bool {
    switch value.dataType {
    case SMCDataType.ui8.rawValue:
      return value.dataSize == 1
    case SMCDataType.ui16.rawValue:
      return value.dataSize == 2
    case SMCDataType.ui32.rawValue:
      return value.dataSize == 4
    case SMCDataType.flt.rawValue:
      return value.dataSize == 4
    case SMCDataType.fpe2.rawValue:
      return value.dataSize == 2
    default:
      return false
    }
  }

  private func supportsIntegerEncoding(value: SMCValue) -> Bool {
    switch value.dataType {
    case SMCDataType.ui8.rawValue:
      return value.dataSize == 1
    case SMCDataType.ui16.rawValue:
      return value.dataSize == 2
    case SMCDataType.ui32.rawValue:
      return value.dataSize == 4
    default:
      return false
    }
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

enum AppleSMCFanMode: Int {
  case automatic = 0
  case manual = 1
}

enum AppleSMCFanControlError: Error {
  case unsupportedPlatform
  case smcUnavailable(String)
  case noFansAvailable
  case fanNotFound(Int)
  case incompleteTelemetry(Int)
  case modeControlUnavailable(Int)
  case targetControlUnavailable(Int)
  case smcKeyUnavailable(String)
  case invalidDataSize(key: String, expected: Int, actual: Int)
  case unsupportedDataType(key: String, dataType: String)
  case valueOutOfRange(key: String, dataType: String, value: Double)
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
    case let .invalidDataSize(key, expected, actual):
      return "AppleSMC key \(key) expected \(expected) bytes, but got \(actual)."
    case let .unsupportedDataType(key, dataType):
      return "AppleSMC key \(key) uses unsupported type \(dataType)."
    case let .valueOutOfRange(key, dataType, value):
      return "Value \(value) is out of range for AppleSMC key \(key) (\(dataType))."
    case let .writeFailed(key, description):
      return "AppleSMC write to \(key) failed: \(description)."
    }
  }
}

final class AppleSMCFanController {
  private let smc: AppleSMCConnection

  init() throws {
    self.smc = try AppleSMCConnection()
  }

  func setFanMode(index: Int, mode: AppleSMCFanMode) throws {
    guard Sysctl.isAppleSilicon else {
      throw AppleSMCFanControlError.unsupportedPlatform
    }

    try validateFanIndex(index)

    let modeValue: UInt32 = mode == .manual ? 1 : 0
    let maskBit = UInt32(1) << UInt32(index)

    var results: [Result<Void, AppleSMCFanControlError>] = []
    let modeKey = "F\(index)Md"

    if smc.canWriteInteger(for: modeKey) {
      do {
        try smc.writeInteger(modeValue, for: modeKey)
        results.append(.success(()))
      } catch let error as AppleSMCFanControlError {
        results.append(.failure(error))
      }
    }

    let forceKey = "FS! "
    if smc.canWriteInteger(for: forceKey) {
      do {
        try smc.updateInteger(for: forceKey) { currentValue in
          mode == .manual ? (currentValue | maskBit) : (currentValue & ~maskBit)
        }
        results.append(.success(()))
      } catch let error as AppleSMCFanControlError {
        results.append(.failure(error))
      }
    }

    try FanControlWriteResultValidator.validate(
      results,
      unavailableError: AppleSMCFanControlError.modeControlUnavailable(index)
    )
  }

  func setFanTargetRpm(index: Int, targetRpm: Int) throws {
    guard Sysctl.isAppleSilicon else {
      throw AppleSMCFanControlError.unsupportedPlatform
    }

    try validateFanIndex(index)
    let bounds = try fanBounds(for: index)
    let clampedTarget = max(bounds.minimumRpm, min(targetRpm, bounds.maximumRpm))
    let targetKey = "F\(index)Tg"

    guard smc.canWriteNumeric(for: targetKey) else {
      throw AppleSMCFanControlError.targetControlUnavailable(index)
    }

    try smc.writeNumeric(Double(clampedTarget), for: targetKey)
  }

  private func validateFanIndex(_ index: Int) throws {
    let fanCount = readFanCount()
    guard fanCount > 0 else {
      throw AppleSMCFanControlError.noFansAvailable
    }

    guard index >= 0, index < fanCount else {
      throw AppleSMCFanControlError.fanNotFound(index)
    }
  }

  private func readFanCount() -> Int {
    guard let rawFanCount = smc.value(for: "FNum", allowZero: true) else {
      return 0
    }

    return max(0, Int(rawFanCount.rounded(.towardZero)))
  }

  private func fanBounds(for index: Int) throws -> (minimumRpm: Int, maximumRpm: Int) {
    guard let current = smc.value(for: "F\(index)Ac") else {
      throw AppleSMCFanControlError.incompleteTelemetry(index)
    }

    let minimum = Int((smc.value(for: "F\(index)Mn") ?? current).rounded())
    let maximum = Int((smc.value(for: "F\(index)Mx") ?? current).rounded())

    return (
      minimumRpm: min(minimum, maximum),
      maximumRpm: max(minimum, maximum)
    )
  }
}
