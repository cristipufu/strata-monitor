import Foundation
import Security
import StrataCore

struct SigningInspector {
  func inspect(pid: Int32) -> SigningInfo {
    let defaults = SecCSFlags()
    var code: SecCode?
    let lookup = SecCodeCopyGuestWithAttributes(
      nil, [kSecGuestAttributePid: NSNumber(value: pid)] as CFDictionary, defaults, &code)
    guard lookup == errSecSuccess, let code else { return unavailable(lookup) }
    var staticCode: SecStaticCode?
    let staticStatus = SecCodeCopyStaticCode(code, defaults, &staticCode)
    guard staticStatus == errSecSuccess, let staticCode else { return unavailable(staticStatus) }
    var raw: CFDictionary?
    let infoStatus = SecCodeCopySigningInformation(
      staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &raw)
    let info = raw as? [String: Any] ?? [:]
    let identifier = info[kSecCodeInfoIdentifier as String] as? String
    let team = info[kSecCodeInfoTeamIdentifier as String] as? String
    let validity = SecCodeCheckValidity(code, defaults, nil)
    if validity == errSecCSUnsigned || infoStatus == errSecCSUnsigned {
      return SigningInfo(kind: .unsigned, identifier: identifier)
    }
    guard infoStatus == errSecSuccess else { return unavailable(infoStatus) }
    guard validity == errSecSuccess else {
      return SigningInfo(
        kind: .invalid, identifier: identifier, teamIdentifier: team, explanation: message(validity)
      )
    }
    let flags = (info[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
    if flags & SecCodeSignatureFlags.adhoc.rawValue != 0 {
      return SigningInfo(kind: .adHoc, identifier: identifier)
    }
    var apple: SecRequirement?
    let requirementStatus = SecRequirementCreateWithString(
      "anchor apple" as CFString, defaults, &apple)
    let isApple =
      requirementStatus == errSecSuccess
      && apple.map { SecCodeCheckValidity(code, defaults, $0) == errSecSuccess } == true
    return SigningInfo(
      kind: isApple ? .apple : .signed, identifier: identifier, teamIdentifier: team)
  }
  private func unavailable(_ status: OSStatus) -> SigningInfo {
    SigningInfo(kind: .unavailable, explanation: message(status))
  }
  private func message(_ status: OSStatus) -> String {
    (SecCopyErrorMessageString(status, nil) as String?)
      ?? "Code-signing information is not available (\(status))."
  }
}
