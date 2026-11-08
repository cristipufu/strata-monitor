public enum WiFiSecurityMode: String, CaseIterable, Hashable, Sendable {
  case none, wep, wpaPersonal, wpaPersonalMixed, wpa2Personal, personal, dynamicWEP
  case wpaEnterprise, wpaEnterpriseMixed, wpa2Enterprise, enterprise
  case wpa3Personal, wpa3Enterprise, wpa3Transition, owe, oweTransition, unknown
}

public enum WiFiJoinRestriction: Sendable {
  case protectedNetwork, enhancedOpen, unknownSecurity, identityUnavailable, administratorRequired,
    adHoc
  public var explanation: String {
    switch self {
    case .protectedNetwork: "Use System Settings for networks that need a password or identity."
    case .enhancedOpen: "Use System Settings for Enhanced Open networks."
    case .unknownSecurity: "This network's security could not be established. Use System Settings."
    case .identityUnavailable:
      "Network identity is unavailable. Allow network names or use System Settings."
    case .administratorRequired:
      "Network changes require system authorization. Use System Settings."
    case .adHoc: "Use System Settings for computer-to-computer networks."
    }
  }
}
public enum WiFiJoinCapability: Sendable {
  case unprotectedNetwork
  case systemSettings(WiFiJoinRestriction)
  public var permitsDirectJoin: Bool {
    if case .unprotectedNetwork = self { return true }
    return false
  }
}

extension Set where Element == WiFiSecurityMode {
  var networkSecurityLabel: String {
    if isEmpty || contains(.unknown) { return "Security unavailable" }
    if self == [.none] { return "Unprotected" }
    if contains(.none) { return "Mixed security" }
    if contains(.oweTransition) { return "Enhanced Open transition" }
    if contains(.owe) { return "Enhanced Open" }
    if contains(.wpa3Transition) { return "WPA2/WPA3 Personal" }
    if contains(.wpa3Enterprise) { return "WPA3 Enterprise" }
    if contains(.wpa3Personal) { return "WPA3 Personal" }
    if contains(.wpaEnterpriseMixed) { return "WPA/WPA2 Enterprise" }
    if contains(.wpaPersonalMixed) { return "WPA/WPA2 Personal" }
    if contains(.wpa2Enterprise) { return "WPA2 Enterprise" }
    if contains(.wpa2Personal) { return "WPA2 Personal" }
    if contains(.wpaEnterprise) || contains(.enterprise) { return "Enterprise" }
    if contains(.wpaPersonal) || contains(.personal) { return "WPA Personal" }
    if contains(.wep) || contains(.dynamicWEP) { return "WEP" }
    return "Security unavailable"
  }
}
