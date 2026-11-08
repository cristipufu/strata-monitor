import Foundation

public enum WiFiScanPolicy {
  public static let resultLifetime: TimeInterval = 60
  public static func isCurrent(observationUptime: TimeInterval, now: TimeInterval) -> Bool {
    observationUptime.isFinite && now.isFinite && now >= observationUptime
      && now - observationUptime <= resultLifetime
  }
}

public struct NearbyNetwork: Identifiable, Sendable {
  public let id: UUID
  public let name: String
  public let rssi: Int
  public let securityModes: Set<WiFiSecurityMode>
  public let joinCapability: WiFiJoinCapability
  public var securityLabel: String { securityModes.networkSecurityLabel }
  public var isProtected: Bool? {
    guard !securityModes.isEmpty, !securityModes.contains(.unknown) else { return nil }
    if securityModes.contains(.oweTransition) { return nil }
    if securityModes.contains(.none) && securityModes.count > 1 { return nil }
    return securityModes != [.none]
  }
  public init(
    id: UUID, name: String, rssi: Int, securityModes: Set<WiFiSecurityMode>,
    joinCapability: WiFiJoinCapability
  ) {
    self.id = id
    self.name = name
    self.rssi = rssi
    self.securityModes = securityModes
    self.joinCapability = joinCapability
  }
}

public struct WiFiScanReport: Sendable {
  public let id: UUID
  public let networks: [NearbyNetwork]
  public let unavailableNames: Int
  public let observationUptime: TimeInterval
  public init(
    id: UUID, networks: [NearbyNetwork], unavailableNames: Int = 0,
    observationUptime: TimeInterval = ProcessInfo.processInfo.systemUptime
  ) {
    self.id = id
    self.networks = networks
    self.unavailableNames = unavailableNames
    self.observationUptime = observationUptime
  }
  public func isCurrent(at uptime: TimeInterval) -> Bool {
    WiFiScanPolicy.isCurrent(observationUptime: observationUptime, now: uptime)
  }
}
public protocol WiFiNetworking: Sendable {
  func scan(requestID: UUID) async throws -> WiFiScanReport
  func join(networkID: UUID, scanID: UUID) async throws
  func discard(scanID: UUID) async
}

struct WiFiScanCandidate: Sendable {
  let id: UUID
  let interfaceName: String
  let name: String?
  let ssid: Data?
  let bssid: String?
  let rssi: Int
  let securityModes: Set<WiFiSecurityMode>
  let administratorRequired: Bool?
  let adHoc: Bool
  var joinCapability: WiFiJoinCapability {
    if adHoc { return .systemSettings(.adHoc) }
    if securityModes.contains(.owe) || securityModes.contains(.oweTransition) {
      return .systemSettings(.enhancedOpen)
    }
    guard securityModes == [.none] else {
      return .systemSettings(
        securityModes.isEmpty || securityModes.contains(.unknown)
          ? .unknownSecurity : .protectedNetwork)
    }
    guard let ssid, !ssid.isEmpty, ssid.count <= 32, let bssid, !bssid.isEmpty else {
      return .systemSettings(.identityUnavailable)
    }
    guard administratorRequired == false else { return .systemSettings(.administratorRequired) }
    return .unprotectedNetwork
  }
  var presentation: NearbyNetwork? {
    guard let name, !name.isEmpty else { return nil }
    return NearbyNetwork(
      id: id, name: name, rssi: rssi, securityModes: securityModes, joinCapability: joinCapability)
  }
}
