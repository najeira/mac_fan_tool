import Foundation
import Security

/// コード署名から取り出した識別子やチーム ID をまとめる共有データです。
struct CodeSignatureDetails {
  let identifier: String?
  let teamIdentifier: String?

  /// 署名情報ディクショナリから必要な項目だけを抽出します。
  init(dictionary: NSDictionary) {
    identifier = dictionary[kSecCodeInfoIdentifier as String] as? String
    teamIdentifier = dictionary[kSecCodeInfoTeamIdentifier as String] as? String
  }
}

/// コード署名情報の取得処理における低レベルな失敗理由を表します。
enum CodeSignatureReaderError: Error {
  case currentCodeUnavailable
  case currentStaticCodeUnavailable
  case executableStaticCodeUnavailable
  case signingInformationUnavailable
}

/// Security フレームワークを使ってコード署名情報を読み出す共通ユーティリティです。
enum CodeSignatureReader {
  /// 実行中プロセス自身のコード署名情報を取得します。
  static func currentProcessDetails() throws -> CodeSignatureDetails {
    var dynamicCode: SecCode?
    let status = SecCodeCopySelf([], &dynamicCode)
    guard status == errSecSuccess, let dynamicCode else {
      throw CodeSignatureReaderError.currentCodeUnavailable
    }

    var staticCode: SecStaticCode?
    let staticStatus = SecCodeCopyStaticCode(dynamicCode, [], &staticCode)
    guard staticStatus == errSecSuccess, let staticCode else {
      throw CodeSignatureReaderError.currentStaticCodeUnavailable
    }

    return try details(for: staticCode)
  }

  /// 指定した実行ファイルのコード署名情報を取得します。
  static func details(forExecutableAt url: URL) throws -> CodeSignatureDetails {
    var staticCode: SecStaticCode?
    let status = SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode)
    guard status == errSecSuccess, let staticCode else {
      throw CodeSignatureReaderError.executableStaticCodeUnavailable
    }

    return try details(for: staticCode)
  }

  /// `SecStaticCode` から署名識別子とチーム ID を取り出します。
  static func details(for staticCode: SecStaticCode) throws -> CodeSignatureDetails {
    var information: CFDictionary?
    let status = SecCodeCopySigningInformation(
      staticCode,
      SecCSFlags(rawValue: kSecCSSigningInformation),
      &information
    )
    guard status == errSecSuccess, let information else {
      throw CodeSignatureReaderError.signingInformationUnavailable
    }

    return CodeSignatureDetails(dictionary: information as NSDictionary)
  }
}
