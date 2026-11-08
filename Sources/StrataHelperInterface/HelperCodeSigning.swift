import Foundation
import Security

/// Both sides require the peer to be signed by the team that signed the running process, so the
/// team is chosen once, by the signing identity at build time. Ad-hoc builds have no team and
/// therefore never talk to the helper.
public enum HelperCodeSigning {
  public static func teamIdentifierOfCurrentProcess() -> String? {
    var code: SecCode?
    guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
      return nil
    }
    var information: CFDictionary?
    let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
    guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
      let information = information as? [String: Any]
    else { return nil }
    return information[kSecCodeInfoTeamIdentifier as String] as? String
  }

  public static func requirement(signingIdentifier: String, team: String) -> String? {
    guard isTeamIdentifier(team), isSigningIdentifier(signingIdentifier) else { return nil }
    let text =
      "identifier \"\(signingIdentifier)\" and anchor apple generic"
      + " and certificate leaf[subject.OU] = \"\(team)\""
    // NSXPC raises an uncatchable exception for a malformed requirement, so it is parsed here first.
    var parsed: SecRequirement?
    guard SecRequirementCreateWithString(text as CFString, [], &parsed) == errSecSuccess,
      parsed != nil
    else { return nil }
    return text
  }

  public static func peerRequirement(signingIdentifier: String) -> String? {
    teamIdentifierOfCurrentProcess().flatMap {
      requirement(signingIdentifier: signingIdentifier, team: $0)
    }
  }

  static func isTeamIdentifier(_ value: String) -> Bool {
    value.utf8.count == 10
      && value.utf8.allSatisfy { (0x30...0x39).contains($0) || (0x41...0x5A).contains($0) }
  }
  static func isSigningIdentifier(_ value: String) -> Bool {
    !value.isEmpty
      && value.utf8.allSatisfy {
        (0x30...0x39).contains($0) || (0x41...0x5A).contains($0) || (0x61...0x7A).contains($0)
          || $0 == 0x2E || $0 == 0x2D
      }
  }
}
