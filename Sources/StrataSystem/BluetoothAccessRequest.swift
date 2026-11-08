import CoreBluetooth
import Foundation

@MainActor public protocol BluetoothAccessRequesting {
  func request(didChange: @escaping @MainActor () -> Void)
  func stop()
}

/// Created by an explicit permission button. This manager never scans or
/// connects, and suppresses the unrelated system power-on alert.
@MainActor
public final class BluetoothAccessRequest: NSObject, @MainActor CBCentralManagerDelegate,
  BluetoothAccessRequesting
{
  private var manager: CBCentralManager?
  private var didChange: (@MainActor () -> Void)?
  public override init() { super.init() }
  public func request(didChange: @escaping @MainActor () -> Void) {
    guard manager == nil else { return }
    self.didChange = didChange
    manager = CBCentralManager(
      delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])
  }
  public func centralManagerDidUpdateState(_ central: CBCentralManager) {
    guard central === manager, CBManager.authorization != .notDetermined else { return }
    let completion = didChange
    stop()
    completion?()
  }
  public func stop() {
    manager?.delegate = nil
    manager = nil
    didChange = nil
  }
}
