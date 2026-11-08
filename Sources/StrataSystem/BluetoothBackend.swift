import CoreBluetooth
import Foundation
import IOBluetooth

protocol BluetoothBackend: Sendable {
  func access() -> BluetoothAccess
  func powered() -> Bool?
  func pairedDevices() -> [BluetoothPeripheral]
  func setConnected(_ connected: Bool, deviceID: String) throws
}

struct NativeBluetoothBackend: BluetoothBackend {
  // HCI page timeout uses 0.625 ms units: 0x2000 is 5.12 seconds.
  private let connectionPageTimeout: BluetoothHCIPageTimeout = 0x2000
  func access() -> BluetoothAccess {
    switch CBManager.authorization {
    case .notDetermined: .notDetermined
    case .allowedAlways: .allowed
    case .denied: .denied
    case .restricted: .restricted
    @unknown default: .restricted
    }
  }
  func powered() -> Bool? {
    guard let controller = IOBluetoothHostController.default() else { return nil }
    switch controller.powerState {
    case kBluetoothHCIPowerStateON: return true
    case kBluetoothHCIPowerStateOFF: return false
    default: return nil
    }
  }
  func pairedDevices() -> [BluetoothPeripheral] {
    nativeDevices().compactMap { device in
      guard let address = device.addressString else { return nil }
      return BluetoothPeripheral(
        id: address, name: device.nameOrAddress ?? address, connected: device.isConnected())
    }
  }
  func setConnected(_ connected: Bool, deviceID: String) throws {
    // Resolve only among currently paired devices. Never create a device from
    // an arbitrary address, discover accessories, or initiate pairing.
    guard let device = nativeDevices().first(where: { $0.addressString == deviceID }),
      device.isPaired()
    else { throw DeviceError.unavailable("This device is no longer paired. Refresh Bluetooth.") }
    try Task.checkCancellation()
    guard device.isConnected() != connected else { return }
    let status =
      connected
      ? device.openConnection(
        nil, withPageTimeout: connectionPageTimeout, authenticationRequired: true)
      : device.closeConnection()
    // A concurrent connection may make 'already connected' an error return.
    // The observed final state determines whether the requested state was reached.
    guard device.isConnected() != connected else { return }
    if status == kIOReturnUnsupported {
      throw DeviceError.unavailable(
        "This accessory does not support this connection control. Use Bluetooth settings.")
    }
    if status != kIOReturnSuccess {
      throw DeviceError.operationFailed(
        connected ? "Connecting Bluetooth" : "Disconnecting Bluetooth", status)
    }
    throw DeviceError.unavailable(
      "The device did not reach the requested connection state. Refresh Bluetooth or use System Settings."
    )
  }
  private func nativeDevices() -> [IOBluetoothDevice] {
    IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
  }
}
