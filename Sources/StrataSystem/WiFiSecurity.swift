import Foundation
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
    case .protectedNetwork: String(localized: "Use System Settings for networks that need a password or identity.")
    case .enhancedOpen: String(localized: "Use System Settings for Enhanced Open networks.")
    case .unknownSecurity: String(localized: "This network's security could not be established. Use System Settings.")
    case .identityUnavailable:
      String(localized: "Network identity is unavailable. Allow network names or use System Settings.")
    case .administratorRequired:
      String(localized: "Network changes require system authorization. Use System Settings.")
    case .adHoc: String(localized: "Use System Settings for computer-to-computer networks.")
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
    if isEmpty || contains(.unknown) { return String(localized: "Security unavailable") }
    if self == [.none] { return String(localized: "Unprotected") }
    if contains(.none) { return String(localized: "Mixed security") }
    if contains(.oweTransition) { return String(localized: "Enhanced Open transition") }
    if contains(.owe) { return String(localized: "Enhanced Open") }
    if contains(.wpa3Transition) { return String(localized: "WPA2/WPA3 Personal") }
    if contains(.wpa3Enterprise) { return String(localized: "WPA3 Enterprise") }
    if contains(.wpa3Personal) { return String(localized: "WPA3 Personal") }
    if contains(.wpaEnterpriseMixed) { return String(localized: "WPA/WPA2 Enterprise") }
    if contains(.wpaPersonalMixed) { return String(localized: "WPA/WPA2 Personal") }
    if contains(.wpa2Enterprise) { return String(localized: "WPA2 Enterprise") }
    if contains(.wpa2Personal) { return String(localized: "WPA2 Personal") }
    if contains(.wpaEnterprise) || contains(.enterprise) { return String(localized: "Enterprise") }
    if contains(.wpaPersonal) || contains(.personal) { return String(localized: "WPA Personal") }
    if contains(.wep) || contains(.dynamicWEP) { return "WEP" }
    return String(localized: "Security unavailable")
  }
}
