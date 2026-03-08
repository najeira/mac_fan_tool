import Cocoa
import Darwin
import Foundation
import IOKit.hidsystem

/// Objective-C ブリッジ経由の温度センサー読み取り結果を Swift で扱いやすい形へ変換します。
enum HardwareSensorBridgeSupport {
  /// IOHID クライアントから取得した温度センサー値をセンサー名ごとの辞書へ整形します。
  static func temperatureValuesForSystemClient(
    _ systemClient: IOHIDEventSystemClient?,
    type: Int32 = kIOHIDEventTypeTemperature
  ) -> [String: Double] {
    let sensors = AppleSiliconTemperatureSensorsFromSystemClient(systemClient, type) ?? [:]
    return sensors.mapValues { $0.doubleValue }
  }
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

  /// CPU ブランド文字列から Apple Silicon 世代と派生モデルを推定します。
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

  /// モデルを大まかな世代へ寄せてセンサーカタログ選択に使います。
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
  /// `sysctlbyname` から文字列値を取得します。
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

  /// `sysctlbyname` から `Int32` 値を取得します。
  static func int32(_ name: String) -> Int32? {
    var value: Int32 = 0
    var size = MemoryLayout<Int32>.size
    guard sysctlbyname(name, &value, &size, nil, 0) == 0 else {
      return nil
    }
    return value
  }

  /// 実行中プロセスが Apple Silicon 上かどうかを判定します。
  static var isAppleSilicon: Bool {
    int32("hw.optional.arm64") == 1
  }
}

/// Runner 側で AppleSMC の値を参照し、センサー情報やファン情報を取得する接続です。
private final class AppleSMCConnection: AppleSMCConnectionCore {
  override init() throws {
    do {
      try super.init()
    } catch let error as AppleSMCConnectionOpenError {
      switch error {
      case .serviceNotFound:
        throw SMCConnectionError.serviceNotFound
      case let .lookupFailed(result), let .openFailed(result):
        throw SMCConnectionError.openFailed(result: result)
      }
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

/// Apple Silicon のセンサー情報とファン情報を収集し、UI 向けのデータへ整形します。
private final class AppleSiliconHardwareMonitor {
  private enum CpuThermalStrategy {
    case smcOnly
    case preferPmuTdieThenSmcFallback
  }

  private let chipBrand: String
  private let chipModel: AppleSiliconModel
  private let smc: AppleSMCConnection?
  private let startupNote: String?

  /// チップ種別を判定し、AppleSMC 接続可否と起動時メッセージを初期化します。
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

  /// 利用可能なセンサーとファン制御機能からアプリの能力情報を組み立てます。
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
    let fanCount = readFanCount()
    let fans = readFans()
    let backend = sensors.contains(where: { $0.id?.hasPrefix("hid-") == true })
      ? "apple-smc-hid"
      : "apple-smc"

    let smcFanControlSupported = !fans.isEmpty && supportsFanControl(fanCount: fanCount)
    let fanControlSupported = FanControlHelperClient.shared.canControlFans(
      isFanControlSupported: smcFanControlSupported
    )
    let helperNote = FanControlHelperClient.shared.statusNote(
      isFanControlSupported: smcFanControlSupported
    )

    return HardwareCapabilitiesData(
      supportsRawSensors: !sensors.isEmpty,
      supportsFanControl: fanControlSupported,
      hasFans: !fans.isEmpty,
      backend: backend,
      note: combinedNote(
        sensors.isEmpty ? missingSensorNote() : nil,
        helperNote
      )
    )
  }

  /// 現在の熱状態、センサー値、ファン状態を 1 つのスナップショットとして返します。
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

  /// 指定ファンのモード変更を特権ヘルパーへ委譲します。
  func setFanMode(fanId: String, mode: FanModeData) throws {
    try FanControlHelperClient.shared.setFanMode(fanId: fanId, mode: mode)
  }

  /// 指定ファンの目標 RPM 変更を特権ヘルパーへ委譲します。
  func setFanTargetRpm(fanId: String, targetRpm: Int64) throws {
    try FanControlHelperClient.shared.setFanTargetRpm(
      fanId: fanId,
      targetRpm: targetRpm
    )
  }

  /// 手動ファン制御リースの更新を特権ヘルパーへ委譲します。
  func renewManualFanLease(fanId: String) throws {
    try FanControlHelperClient.shared.renewManualLease(fanId: fanId)
  }

  /// SMC と HID の両方からセンサーを集めて 1 つの配列へ統合します。
  private func readSensors() -> [SensorReadingData] {
    guard smc != nil else {
      return []
    }

    let hidValues = hidTemperatureValues()
    var readings: [SensorReadingData] = []
    readings.append(contentsOf: readCpuThermals(from: hidValues))
    readings.append(contentsOf: readKnownSmcSensors(gpuSensorCatalog))
    readings.append(contentsOf: readKnownSmcSensors(supplementalSmcSensorCatalog))
    readings.append(contentsOf: readSupplementalHidSensors(from: hidValues))
    return deduplicated(readings)
  }

  /// 既知の SMC センサーキー一覧を走査して妥当な温度だけを返します。
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

  /// モデル別の戦略に従って CPU 温度センサーの取得元を切り替えます。
  private func readCpuThermals(from hidValues: [String: Double]) -> [SensorReadingData] {
    switch cpuThermalStrategy {
    case .smcOnly:
      return readKnownSmcSensors(cpuFallbackSmcSensorCatalog)
    case .preferPmuTdieThenSmcFallback:
      let cpuSensors = readPmuTdieCpuThermals(from: hidValues)
      if !cpuSensors.isEmpty {
        return cpuSensors
      }
      return readKnownSmcSensors(cpuFallbackSmcSensorCatalog)
    }
  }

  /// `PMU tdie` 系の HID センサーを CPU 温度センサーへ変換します。
  private func readPmuTdieCpuThermals(from hidValues: [String: Double]) -> [SensorReadingData] {
    hidValues
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
  }

  /// 補助的な HID 温度センサーを UI 表示用の型へ写像します。
  private func readSupplementalHidSensors(from hidValues: [String: Double]) -> [SensorReadingData] {
    hidValues.compactMap { key, value in
      supplementalHidSensor(key: key, value: value)
    }
  }

  /// IOHID イベントシステムから Apple Silicon の温度値辞書を取得します。
  private func hidTemperatureValues() -> [String: Double] {
    guard let sensors = AppleSiliconTemperatureSensors(0xff00, 0x0005, kIOHIDEventTypeTemperature) else {
      return [:]
    }

    return sensors.reduce(into: [String: Double]()) { partialResult, item in
      partialResult[item.key] = item.value.doubleValue
    }
  }

  /// HID センサー名ごとの命名規則に従って表示名と種別を付与します。
  private func supplementalHidSensor(key: String, value: Double) -> SensorReadingData? {
    guard isReasonableTemperature(value) else {
      return nil
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

  /// センサー ID の重複を除去し、表示順が安定するようソートします。
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

  /// AppleSMC から各ファンの回転数、範囲、モードを読み取って整形します。
  private func readFans() -> [FanReadingData] {
    guard let smc else {
      return []
    }

    let fanCount = readFanCount()
    guard fanCount > 0 else {
      return []
    }

    var fans: [FanReadingData] = []
    let forcedFanMask = smc.integerValue(for: "FS! ", allowZero: true)

    for index in 0..<fanCount {
      let current = smc.value(for: "F\(index)Ac")
      let minimum = smc.value(for: "F\(index)Mn")
      let maximum = smc.value(for: "F\(index)Mx")
      let target = smc.value(for: "F\(index)Tg", allowZero: true)
      let modeValue = smc.value(for: "F\(index)Md", allowZero: true)

      guard let current else {
        continue
      }

      let minimumRpm = Int((minimum ?? current).rounded())
      let maximumRpm = Int((maximum ?? current).rounded())
      let currentRpm = Int(current.rounded())
      let targetRpm = target.map { Int($0.rounded()) }
      let manualOverrideEnabled =
        forcedFanMask.map { ($0 & (UInt32(1) << UInt32(index))) != 0 } ?? false
      let isManual = modeValue.map { $0 > 0 } ?? manualOverrideEnabled

      fans.append(
        FanReadingData(
          id: "fan-\(index)",
          name: fanCount == 1 ? "System fan" : "Fan \(index + 1)",
          currentRpm: Int64(currentRpm),
          minimumRpm: Int64(minimumRpm),
          maximumRpm: Int64(maximumRpm),
          targetRpm: targetRpm.map(Int64.init),
          mode: isManual ? .manual : .automatic
        )
      )
    }

    return fans
  }

  /// AppleSMC の `FNum` を読み取り、利用可能なファン数を返します。
  private func readFanCount() -> Int {
    guard let smc,
          let rawFanCount = smc.value(for: "FNum", allowZero: true) else {
      return 0
    }

    return max(0, Int(rawFanCount.rounded(.towardZero)))
  }

  /// 全ファンで目標 RPM とモード変更の書き込みが可能かを判定します。
  private func supportsFanControl(fanCount: Int) -> Bool {
    guard let smc, fanCount > 0 else {
      return false
    }

    for index in 0..<fanCount {
      guard smc.canWriteNumeric(for: "F\(index)Tg") else {
        return false
      }

      let canWriteMode =
        smc.canWriteInteger(for: "F\(index)Md") ||
        smc.canWriteInteger(for: "FS! ")
      guard canWriteMode else {
        return false
      }
    }

    return true
  }

  /// 補足メッセージを空要素抜きで結合し、UI 表示用の 1 つの文にします。
  private func combinedNote(_ parts: String?...) -> String? {
    let filteredParts: [String] = parts.compactMap { part -> String? in
      guard let part, !part.isEmpty else {
        return nil
      }
      return part
    }

    guard !filteredParts.isEmpty else {
      return nil
    }

    return filteredParts.joined(separator: "\n")
  }

  /// 温度として扱うには不自然な値を除外します。
  private func isReasonableTemperature(_ value: Double) -> Bool {
    value.isFinite && value > 0 && value < 140
  }

  /// 文字列末尾の数値連番を抽出してセンサー番号に使います。
  private func trailingInteger(in text: String) -> Int? {
    let suffix = text.reversed().prefix { $0.isNumber }.reversed()
    guard !suffix.isEmpty else {
      return nil
    }
    return Int(String(suffix))
  }

  /// `NAND CHx temp` 表記からチャンネル番号を抜き出します。
  private func channelNumber(in text: String) -> Int? {
    guard let chRange = text.range(of: "CH"),
          let tempRange = text.range(of: " temp") else {
      return nil
    }

    let value = text[chRange.upperBound..<tempRange.lowerBound]
    return Int(value)
  }

  /// センサーが取得できなかったときの状況説明文を生成します。
  private func missingSensorNote() -> String? {
    switch chipModel.generation {
    case .unknown:
      return "AppleSMC opened successfully, but this chip generation (\(chipBrand)) is not mapped yet."
    case .m1, .m2, .m3, .m4:
      return "AppleSMC opened successfully, but none of the mapped temperature keys matched \(chipBrand)."
    }
  }

  /// CPU 温度の取得で優先するセンサー経路をモデルごとに切り替えます。
  private var cpuThermalStrategy: CpuThermalStrategy {
    switch chipModel {
    case .m4Pro:
      return .preferPmuTdieThenSmcFallback
    default:
      return .smcOnly
    }
  }

  /// CPU 温度取得に使う SMC フォールバックセンサー一覧を返します。
  private var cpuFallbackSmcSensorCatalog: [SensorDescriptor] {
    switch chipModel {
    case .m4Pro:
      return Self.m4CpuFallbackSensors
    default:
      return generationSmcSensorCatalog.filter { $0.kind == .cpu }
    }
  }

  /// GPU センサーとして採用する SMC センサー一覧を返します。
  private var gpuSensorCatalog: [SensorDescriptor] {
    switch chipModel {
    case .m4Pro:
      return Self.m4ProGpuSensors
    default:
      return generationSmcSensorCatalog.filter { $0.kind == .gpu }
    }
  }

  /// CPU/GPU 以外の補助 SMC センサー一覧を組み立てます。
  private var supplementalSmcSensorCatalog: [SensorDescriptor] {
    generationSmcSensorCatalog.filter { $0.kind != .cpu && $0.kind != .gpu } +
      Self.appleSiliconCommonSensors +
      modelSpecificSupplementalSmcSensors
  }

  /// Apple Silicon 世代ごとの基本センサーカタログを返します。
  private var generationSmcSensorCatalog: [SensorDescriptor] {
    switch chipModel.generation {
    case .m1:
      return Self.m1Sensors
    case .m2:
      return Self.m2Sensors
    case .m3:
      return Self.m3Sensors
    case .m4:
      return Self.m4Sensors
    case .unknown:
      return []
    }
  }

  /// 一部モデル専用の補助センサー一覧を返します。
  private var modelSpecificSupplementalSmcSensors: [SensorDescriptor] {
    switch chipModel {
    case .m4Pro:
      return Self.m4ProSupplementalSensors
    default:
      switch chipModel.generation {
      case .m4:
        return Self.m4SupplementalSensors
      case .m1, .m2, .m3, .unknown:
        return []
      }
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

/// Flutter からのハードウェア API 呼び出しを macOS 実装へ橋渡しします。
final class HardwareBridge: HardwareHostApi {
  private let monitor = AppleSiliconHardwareMonitor()

  /// この Mac で利用できるハードウェア機能の一覧を返します。
  func getCapabilities() throws -> HardwareCapabilitiesData {
    monitor.capabilities()
  }

  /// 現在のセンサー値とファン状態のスナップショットを返します。
  func getSnapshot() throws -> HardwareSnapshotData {
    monitor.snapshot(thermalState: mapThermalState(ProcessInfo.processInfo.thermalState))
  }

  /// Flutter から受け取ったファンモード変更要求をネイティブ側で実行します。
  func setFanMode(fanId: String, mode: FanModeData) throws {
    do {
      try monitor.setFanMode(fanId: fanId, mode: mode)
    } catch let error as FanControlHelperClientError {
      throw PigeonError(
        code: "fan-control",
        message: error.message,
        details: "\(fanId):\(mode)"
      )
    } catch {
      throw PigeonError(
        code: "fan-control",
        message: "Fan mode update failed: \(error)",
        details: "\(fanId):\(mode)"
      )
    }
  }

  /// Flutter から受け取った目標 RPM 変更要求をネイティブ側で実行します。
  func setFanTargetRpm(fanId: String, targetRpm: Int64) throws {
    do {
      try monitor.setFanTargetRpm(fanId: fanId, targetRpm: targetRpm)
    } catch let error as FanControlHelperClientError {
      throw PigeonError(
        code: "fan-control",
        message: error.message,
        details: "\(fanId):\(targetRpm)"
      )
    } catch {
      throw PigeonError(
        code: "fan-control",
        message: "Fan target update failed: \(error)",
        details: "\(fanId):\(targetRpm)"
      )
    }
  }

  /// Flutter から受け取った手動制御リース更新要求をネイティブ側で実行します。
  func renewManualFanLease(fanId: String) throws {
    do {
      try monitor.renewManualFanLease(fanId: fanId)
    } catch let error as FanControlHelperClientError {
      throw PigeonError(
        code: "fan-control",
        message: error.message,
        details: fanId
      )
    } catch {
      throw PigeonError(
        code: "fan-control",
        message: "Manual fan lease renewal failed: \(error)",
        details: fanId
      )
    }
  }

  /// `ProcessInfo` の熱状態を共有 API の列挙値へ変換します。
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
