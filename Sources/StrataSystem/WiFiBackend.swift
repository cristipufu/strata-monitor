import Foundation

protocol WiFiBackend: Sendable {
  func scan() throws -> [WiFiScanCandidate]
  func join(_ candidate: WiFiScanCandidate) throws
}

struct NativeWiFiBackend: WiFiBackend {
  private let interfaces: any WiFiInterfaceFinding
  init(interfaces: any WiFiInterfaceFinding = NativeWiFiInterfaces()) {
    self.interfaces = interfaces
  }
  func scan() throws -> [WiFiScanCandidate] {
    guard let interface = interfaces.interface(named: nil), let name = interface.name, !name.isEmpty
    else { throw DeviceError.unavailable("No Wi-Fi interface is available.") }
    guard interface.powered else { throw DeviceError.unavailable("Turn on Wi-Fi before scanning.") }
    try Task.checkCancellation()
    let networks = try interface.scan(ssid: nil)
    let administrativePolicy = interface.administratorRequired
    return networks.map { network in
      WiFiScanCandidate(
        id: UUID(), interfaceName: name, name: network.name, ssid: network.ssid,
        bssid: network.bssid?.lowercased(), rssi: network.rssi,
        securityModes: network.securityModes, administratorRequired: administrativePolicy,
        adHoc: network.adHoc)
    }
  }
  func join(_ candidate: WiFiScanCandidate) throws {
    guard candidate.joinCapability.permitsDirectJoin, let ssid = candidate.ssid,
      let bssid = candidate.bssid,
      let interface = interfaces.interface(named: candidate.interfaceName),
      interface.name == candidate.interfaceName, interface.powered
    else {
      throw DeviceError.unavailable(
        "This network cannot be joined directly. Refresh or use System Settings.")
    }
    try requireOrdinaryAssociation(interface)
    try Task.checkCancellation()
    // Revalidate the exact observed access point, bytes and security. A second
    // same-name network must not silently replace the selected scan result.
    let fresh = try interface.scan(ssid: ssid)
    guard
      let network = fresh.first(where: {
        $0.ssid == ssid && $0.bssid?.lowercased() == bssid
          && $0.securityModes == candidate.securityModes && !$0.adHoc
      })
    else {
      throw DeviceError.unavailable(
        "The selected network changed or disappeared. Refresh nearby networks.")
    }
    try requireOrdinaryAssociation(interface)
    try Task.checkCancellation()
    try interface.associate(network)
    guard interface.associatedSSID == ssid, interface.associatedWithUnprotectedNetwork else {
      throw DeviceError.unavailable(
        "Wi-Fi did not report the selected network after joining. Check System Settings.")
    }
  }
  private func requireOrdinaryAssociation(_ interface: any WiFiInterfaceHandle) throws {
    guard interface.administratorRequired == false else {
      throw DeviceError.unavailable(WiFiJoinRestriction.administratorRequired.explanation)
    }
  }
}
