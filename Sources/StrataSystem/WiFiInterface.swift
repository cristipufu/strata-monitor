import CoreWLAN
import Foundation

protocol WiFiAccessPoint: AnyObject {
  var name: String? { get }
  var ssid: Data? { get }
  var bssid: String? { get }
  var rssi: Int { get }
  var securityModes: Set<WiFiSecurityMode> { get }
  var adHoc: Bool { get }
}
protocol WiFiInterfaceHandle: AnyObject {
  var name: String? { get }
  var powered: Bool { get }
  var administratorRequired: Bool? { get }
  var associatedSSID: Data? { get }
  var associatedWithUnprotectedNetwork: Bool { get }
  func scan(ssid: Data?) throws -> [any WiFiAccessPoint]
  func associate(_ network: any WiFiAccessPoint) throws
}
protocol WiFiInterfaceFinding: Sendable {
  func interface(named: String?) -> (any WiFiInterfaceHandle)?
}

struct NativeWiFiInterfaces: WiFiInterfaceFinding {
  func interface(named name: String?) -> (any WiFiInterfaceHandle)? {
    let client = CWWiFiClient()
    let interface: CWInterface?
    if let name {
      interface = client.interface(withName: name)
    } else {
      interface = client.interface()
    }
    return interface.map(NativeWiFiInterface.init)
  }
}
/// Native handles stay within one synchronous backend call on the scanner
/// actor. They never cross actors or become stored in presentation state.
private final class NativeWiFiInterface: WiFiInterfaceHandle {
  private let interface: CWInterface
  init(_ interface: CWInterface) { self.interface = interface }
  var name: String? { interface.interfaceName }
  var powered: Bool { interface.powerOn() }
  var administratorRequired: Bool? { interface.configuration()?.requireAdministratorForAssociation }
  var associatedSSID: Data? { interface.ssidData() }
  var associatedWithUnprotectedNetwork: Bool { interface.security() == .none }
  func scan(ssid: Data?) throws -> [any WiFiAccessPoint] {
    try interface.scanForNetworks(withSSID: ssid).map(NativeWiFiAccessPoint.init)
  }
  func associate(_ network: any WiFiAccessPoint) throws {
    guard let network = network as? NativeWiFiAccessPoint else {
      throw DeviceError.unavailable(
        String(localized: "The selected network handle is unavailable. Refresh nearby networks."))
    }
    try interface.associate(to: network.network, password: nil)
  }
}
private final class NativeWiFiAccessPoint: WiFiAccessPoint {
  let network: CWNetwork
  init(_ network: CWNetwork) { self.network = network }
  var name: String? { network.ssid }
  var ssid: Data? { network.ssidData }
  var bssid: String? { network.bssid }
  var rssi: Int { network.rssiValue }
  var adHoc: Bool { network.ibss }
  var securityModes: Set<WiFiSecurityMode> {
    let supported: [(CWSecurity, WiFiSecurityMode)] = [
      (.none, .none), (.WEP, .wep), (.wpaPersonal, .wpaPersonal),
      (.wpaPersonalMixed, .wpaPersonalMixed),
      (.wpa2Personal, .wpa2Personal), (.personal, .personal), (.dynamicWEP, .dynamicWEP),
      (.wpaEnterprise, .wpaEnterprise), (.wpaEnterpriseMixed, .wpaEnterpriseMixed),
      (.wpa2Enterprise, .wpa2Enterprise), (.enterprise, .enterprise),
      (.wpa3Personal, .wpa3Personal),
      (.wpa3Enterprise, .wpa3Enterprise), (.wpa3Transition, .wpa3Transition),
      (.OWE, .owe), (.oweTransition, .oweTransition), (.unknown, .unknown),
    ]
    return Set(supported.compactMap { network.supportsSecurity($0.0) ? $0.1 : nil })
  }
}
