import Darwin

/// `sysctlbyname` を使ったシステム情報取得をまとめる共有ユーティリティです。
enum Sysctl {
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

  /// 実行環境が Apple Silicon かどうかを判定します。
  static var isAppleSilicon: Bool {
    int32("hw.optional.arm64") == 1
  }
}
