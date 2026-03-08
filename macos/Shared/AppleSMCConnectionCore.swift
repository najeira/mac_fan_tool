import Darwin
import Foundation
import IOKit

typealias FourCharCode = UInt32

enum SMCDataType: String {
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

enum SMCCommand: UInt8 {
  case kernelIndex = 2
  case readBytes = 5
  case writeBytes = 6
  case readKeyInfo = 9
}

struct SMCKeyData {
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

struct SMCValue {
  init(key: String) {
    self.key = key
  }

  let key: String
  var dataSize: UInt32 = 0
  var dataType = ""
  var bytes = [UInt8](repeating: 0, count: 32)
}

/// AppleSMC 接続の確立段階で起きる失敗理由を表します。
enum AppleSMCConnectionOpenError: Error {
  case lookupFailed(result: kern_return_t)
  case serviceNotFound
  case openFailed(result: kern_return_t)

  var message: String {
    switch self {
    case let .lookupFailed(result):
      let description = String(cString: mach_error_string(result), encoding: .ascii) ?? "unknown error"
      return "AppleSMC lookup failed: \(description)."
    case .serviceNotFound:
      return "AppleSMC service was not found."
    case let .openFailed(result):
      let description = String(cString: mach_error_string(result), encoding: .ascii) ?? "unknown error"
      return "AppleSMC open failed: \(description)."
    }
  }
}

/// AppleSMC の生データを整数へ変換するときの失敗理由を表します。
enum AppleSMCValueDecodingError: Error {
  case invalidDataSize(key: String, expected: Int, actual: Int)
  case unsupportedDataType(key: String, dataType: String)
}

/// AppleSMC の接続確立、読み取り、デコードを共通化する基盤クラスです。
class AppleSMCConnectionCore {
  private let lock = NSLock()
  private var connection: io_connect_t = 0
  private let ioMainPort: mach_port_t

  /// AppleSMC サービスを探索して IOKit 接続を開きます。
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
      throw AppleSMCConnectionOpenError.lookupFailed(result: matchingResult)
    }

    let device = IOIteratorNext(iterator)
    IOObjectRelease(iterator)

    guard device != 0 else {
      throw AppleSMCConnectionOpenError.serviceNotFound
    }

    defer {
      IOObjectRelease(device)
    }

    let openResult = IOServiceOpen(device, mach_task_self_, 0, &connection)
    guard openResult == kIOReturnSuccess else {
      throw AppleSMCConnectionOpenError.openFailed(result: openResult)
    }
  }

  deinit {
    if connection != 0 {
      IOServiceClose(connection)
    }
  }

  /// 指定キーを数値として読み取り、必要ならゼロ値を除外します。
  func value(for key: String, allowZero: Bool = false) -> Double? {
    readOptionalValue(for: key, allowZero: allowZero) { value in
      decode(value: value)
    }
  }

  /// 指定キーを整数として読み取り、必要ならゼロ値を除外します。
  func integerValue(for key: String, allowZero: Bool = false) -> UInt32? {
    try? readOptionalValue(for: key, allowZero: allowZero) { value in
      try decodeInteger(value: value)
    }
  }

  /// 指定キーが数値型として書き込み可能かを返します。
  func canWriteNumeric(for key: String) -> Bool {
    readOptionalValue(for: key) { value in
      supportsNumericEncoding(value: value)
    } ?? false
  }

  /// 指定キーが整数型として書き込み可能かを返します。
  func canWriteInteger(for key: String) -> Bool {
    readOptionalValue(for: key) { value in
      supportsIntegerEncoding(value: value)
    } ?? false
  }

  /// 指定キーの生の SMC 値を読み取ります。
  func readValue(for key: String) -> SMCValue? {
    var value = SMCValue(key: key)
    let result = read(&value)
    guard result == kIOReturnSuccess else {
      return nil
    }
    return value
  }

  /// まずキー情報を取得し、その後で実データ本体を読み込んで `SMCValue` を埋めます。
  func read(_ value: inout SMCValue) -> kern_return_t {
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

  /// `IOConnectCallStructMethod` を呼び出して AppleSMC へコマンドを送信します。
  func call(
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

  /// 取得した値がすべてゼロバイトかどうかを判定します。
  func isZero(_ value: SMCValue) -> Bool {
    value.bytes.prefix(Int(value.dataSize)).allSatisfy { $0 == 0 }
  }

  /// AppleSMC へのアクセスを排他制御しながら任意の処理を実行します。
  func withLock<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock()
    defer {
      lock.unlock()
    }

    return try body()
  }

  /// 任意キーを読み取り、変換クロージャへ渡して必要な型へ整形します。
  func readOptionalValue<T>(
    for key: String,
    allowZero: Bool = true,
    _ transform: (SMCValue) throws -> T?
  ) rethrows -> T? {
    try withLock {
      guard let value = readValue(for: key), allowZero || !isZero(value) else {
        return nil
      }

      return try transform(value)
    }
  }

  /// 任意キーを必須値として読み取り、欠損時は呼び出し元指定のエラーを返します。
  func withRequiredValue<T>(
    for key: String,
    error: @autoclosure () -> Error,
    _ body: (SMCValue) throws -> T
  ) throws -> T {
    try withLock {
      guard let value = readValue(for: key) else {
        throw error()
      }

      return try body(value)
    }
  }

  /// 生の SMC 値を整数型へデコードします。
  func decodeInteger(value: SMCValue) throws -> UInt32 {
    switch value.dataType {
    case SMCDataType.ui8.rawValue:
      guard value.dataSize == 1 else {
        throw AppleSMCValueDecodingError.invalidDataSize(
          key: value.key,
          expected: 1,
          actual: Int(value.dataSize)
        )
      }
      return UInt32(value.bytes[0])

    case SMCDataType.ui16.rawValue:
      guard value.dataSize == 2 else {
        throw AppleSMCValueDecodingError.invalidDataSize(
          key: value.key,
          expected: 2,
          actual: Int(value.dataSize)
        )
      }
      return UInt32(UInt16(bytes: (value.bytes[0], value.bytes[1])))

    case SMCDataType.ui32.rawValue:
      guard value.dataSize == 4 else {
        throw AppleSMCValueDecodingError.invalidDataSize(
          key: value.key,
          expected: 4,
          actual: Int(value.dataSize)
        )
      }
      return UInt32(bytes: (value.bytes[0], value.bytes[1], value.bytes[2], value.bytes[3]))

    default:
      throw AppleSMCValueDecodingError.unsupportedDataType(
        key: value.key,
        dataType: value.dataType
      )
    }
  }

  /// 指定 SMC 値が数値エンコードによる書き込みに対応しているかを判定します。
  func supportsNumericEncoding(value: SMCValue) -> Bool {
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

  /// 指定 SMC 値が整数エンコードによる書き込みに対応しているかを判定します。
  func supportsIntegerEncoding(value: SMCValue) -> Bool {
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

  /// 生の SMC 値を型ごとの係数に従って `Double` へ変換します。
  func decode(value: SMCValue) -> Double? {
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

extension FourCharCode {
  /// 4文字の SMC キー文字列を FourCharCode へ変換します。
  init(from string: String) {
    precondition(string.count == 4)
    self = string.utf8.reduce(0) { partialResult, codeUnit in
      (partialResult << 8) | UInt32(codeUnit)
    }
  }
}

extension UInt32 {
  /// 4バイトのビッグエンディアン表現から `UInt32` を復元します。
  init(bytes: (UInt8, UInt8, UInt8, UInt8)) {
    self = UInt32(bytes.0) << 24 |
      UInt32(bytes.1) << 16 |
      UInt32(bytes.2) << 8 |
      UInt32(bytes.3)
  }

  /// `UInt32` を 4 文字の SMC 型・キー文字列へ変換します。
  var fourCharString: String {
    String(UnicodeScalar((self >> 24) & 0xff)!) +
      String(UnicodeScalar((self >> 16) & 0xff)!) +
      String(UnicodeScalar((self >> 8) & 0xff)!) +
      String(UnicodeScalar(self & 0xff)!)
  }
}

extension UInt16 {
  /// 2バイトのビッグエンディアン表現から `UInt16` を復元します。
  init(bytes: (UInt8, UInt8)) {
    self = UInt16(bytes.0) << 8 | UInt16(bytes.1)
  }
}

extension Int {
  /// AppleSMC の `fpe2` 固定小数形式を整数へ変換します。
  init(fpe2 bytes: (UInt8, UInt8)) {
    self = (Int(bytes.0) << 6) + (Int(bytes.1) >> 2)
  }
}

extension Float {
  /// 先頭 4 バイトを `Float` のメモリ表現として読み取ります。
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
