import Foundation

/// Public Bluetooth queries and connection calls stay off the UI actor.
/// Observation never initiates an authorization request. A native connection
/// already issued cannot be rolled back by canceling its awaiting UI task.
public actor BluetoothCollector: BluetoothManaging {
  private let backend: any BluetoothBackend
  public init() { backend = NativeBluetoothBackend() }
  init(backend: any BluetoothBackend) { self.backend = backend }
  public func snapshot() -> BluetoothSnapshot {
    let access = backend.access()
    guard access == .allowed else {
      return BluetoothSnapshot(access: access)
    }
    guard !Task.isCancelled else { return BluetoothSnapshot(access: access) }
    let powered = backend.powered()
    let devices = powered == true ? backend.pairedDevices() : []
    let currentAccess = backend.access()
    guard currentAccess == .allowed else { return BluetoothSnapshot(access: currentAccess) }
    return BluetoothSnapshot(
      access: currentAccess, powered: powered,
      devices: devices.sorted {
        if $0.connected != $1.connected { return $0.connected }
        let order = $0.name.localizedStandardCompare($1.name)
        return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
      })
  }
  public func setConnected(_ connected: Bool, deviceID: String) throws {
    try Task.checkCancellation()
    try requireConnectionAccess()
    guard backend.pairedDevices().contains(where: { $0.id == deviceID }) else {
      throw DeviceError.unavailable("This device is no longer paired. Refresh Bluetooth.")
    }
    try Task.checkCancellation()
    try requireConnectionAccess()
    try backend.setConnected(connected, deviceID: deviceID)
  }
  private func requireConnectionAccess() throws {
    guard backend.access() == .allowed else {
      throw DeviceError.unavailable("Allow Bluetooth access before changing a connection.")
    }
    guard backend.powered() == true else {
      throw DeviceError.unavailable(
        "Turn on Bluetooth in System Settings before connecting a device.")
    }
  }
}
