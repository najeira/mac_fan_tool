import Darwin
import Foundation
import IOKit

private enum Sysctl {
  /// `sysctlbyname` を使って指定キーの `Int32` 値を取得します。
  static func int32(_ name: String) -> Int32? {
    var value: Int32 = 0
    var size = MemoryLayout<Int32>.size
    guard sysctlbyname(name, &value, &size, nil, 0) == 0 else {
      return nil
    }
    return value
  }

  /// 実行環境が Apple Silicon かどうかを判定します。
  static var isAppleSilicon: Bool {
    int32("hw.optional.arm64") == 1
  }
}

/// AppleSMC への接続を管理し、キーの読み書きを直列化して行う低レベルラッパーです。
private final class AppleSMCConnection: AppleSMCConnectionCore, AppleSMCControlling {
  override init() throws {
    do {
      try super.init()
    } catch let error as AppleSMCConnectionOpenError {
      throw AppleSMCFanControlError.smcUnavailable(error.message)
    }
  }

  /// 指定した SMC キーへ数値を書き込みます。
  func writeNumeric(_ numericValue: Double, for key: String) throws {
    try withRequiredValue(for: key, error: AppleSMCFanControlError.smcKeyUnavailable(key)) { value in
      let bytes = try encodeNumeric(numericValue, using: value)
      try writeLocked(bytes, using: value)
    }
  }

  /// 指定した SMC キーへ整数値を書き込みます。
  func writeInteger(_ integerValue: UInt32, for key: String) throws {
    try withRequiredValue(for: key, error: AppleSMCFanControlError.smcKeyUnavailable(key)) { value in
      let bytes = try encodeInteger(integerValue, using: value)
      try writeLocked(bytes, using: value)
    }
  }

  /// 現在の整数値を読み取って変換し、その結果を書き戻します。
  func updateInteger(for key: String, transform: (UInt32) -> UInt32) throws {
    try withRequiredValue(for: key, error: AppleSMCFanControlError.smcKeyUnavailable(key)) { value in
      let current = try decodeWritableInteger(value)
      let next = transform(current)
      let bytes = try encodeInteger(next, using: value)
      try writeLocked(bytes, using: value)
    }
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

  /// 書き戻し可能な整数キーをデコードし、ヘルパー用エラーへ正規化します。
  private func decodeWritableInteger(_ value: SMCValue) throws -> UInt32 {
    do {
      return try decodeInteger(value: value)
    } catch let error as AppleSMCValueDecodingError {
      throw mapDecodeError(error)
    }
  }

  /// SMC キーの型に合わせて数値を書き込み用バイト列へ変換します。
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

  /// SMC キーの整数型に合わせて `UInt32` を書き込み用バイト列へ変換します。
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

  /// SMC 値デコード失敗をファン制御向けの公開エラーへ写像します。
  private func mapDecodeError(_ error: AppleSMCValueDecodingError) -> AppleSMCFanControlError {
    switch error {
    case let .invalidDataSize(key, expected, actual):
      return .invalidDataSize(key: key, expected: expected, actual: actual)
    case let .unsupportedDataType(key, dataType):
      return .unsupportedDataType(key: key, dataType: dataType)
    }
  }
}

private struct SystemFanControlPlatform: FanControlPlatformChecking {
  let isAppleSilicon: Bool = Sysctl.isAppleSilicon
}

extension AppleSMCFanController {
  /// 実機の AppleSMC 接続を使う既定のファンコントローラを生成します。
  convenience init() throws {
    try self.init(
      smc: AppleSMCConnection(),
      platform: SystemFanControlPlatform()
    )
  }
}
