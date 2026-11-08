import Foundation

public enum BluetoothAccess: Sendable { case notDetermined, allowed, denied, restricted }

public struct BluetoothPeripheral: Identifiable, Equatable, Sendable {
  public let id: String
  public let name: String
  public let connected: Bool
  public let batteryFraction: Double?
  public init(id: String, name: String, connected: Bool, batteryFraction: Double? = nil) {
    self.id = id
    self.name = name
    self.connected = connected
    self.batteryFraction = batteryFraction
  }
}

public struct BluetoothSnapshot: Sendable {
  public let access: BluetoothAccess
  public let powered: Bool?
  public let devices: [BluetoothPeripheral]
  public let observedAt: Date
  public let issue: String?
  public init(
    access: BluetoothAccess, powered: Bool? = nil, devices: [BluetoothPeripheral] = [],
    observedAt: Date = Date(), issue: String? = nil
  ) {
    self.access = access
    self.powered = powered
    self.devices = devices
    self.observedAt = observedAt
    self.issue = issue
  }
  public var connectedCount: Int? {
    guard access == .allowed, powered != nil, issue == nil else { return nil }
    return powered == false ? 0 : connectedDeviceNames?.count
  }
  public var connectedDeviceNames: [String: String]? {
    guard access == .allowed, powered == true, issue == nil else { return nil }
    return Dictionary(
      devices.filter(\.connected).map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
  }
}

public protocol BluetoothManaging: Sendable {
  func snapshot() async -> BluetoothSnapshot
  func setConnected(_ connected: Bool, deviceID: String) async throws
}
