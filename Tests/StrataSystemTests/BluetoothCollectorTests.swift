import Foundation
import Synchronization
import Testing

@testable import StrataSystem

private final class BluetoothBackendFixture: BluetoothBackend, Sendable {
  struct State: Sendable {
    var access: BluetoothAccess = .allowed
    var powered: Bool? = true
    var devices = [BluetoothPeripheral(id: "paired", name: "Headphones", connected: false)]
    var powerQueries = 0
    var deviceQueries = 0
    var changes: [String] = []
    var failure: DeviceError?
    var revokeOnEnumeration = false
  }
  private let state = Mutex(State())
  func configure(_ change: (inout State) -> Void) { state.withLock { change(&$0) } }
  func read() -> State { state.withLock { $0 } }
  func access() -> BluetoothAccess { state.withLock { $0.access } }
  func powered() -> Bool? {
    state.withLock {
      $0.powerQueries += 1
      return $0.powered
    }
  }
  func pairedDevices() -> [BluetoothPeripheral] {
    state.withLock {
      $0.deviceQueries += 1
      if $0.revokeOnEnumeration { $0.access = .denied }
      return $0.devices
    }
  }
  func setConnected(_ connected: Bool, deviceID: String) throws {
    try state.withLock {
      $0.changes.append("\(deviceID):\(connected)")
      if let failure = $0.failure { throw failure }
    }
  }
}

@Test(arguments: [BluetoothAccess.notDetermined, .denied, .restricted])
func bluetoothObservationCannotPromptOrQueryDevicesBeforeAccessIsAllowed(_ access: BluetoothAccess)
  async
{
  let backend = BluetoothBackendFixture()
  backend.configure { $0.access = access }
  let collector = BluetoothCollector(backend: backend)
  let snapshot = await collector.snapshot()
  #expect(snapshot.access == access && snapshot.connectedCount == nil)
  #expect(snapshot.devices.isEmpty && snapshot.powered == nil)
  #expect(backend.read().powerQueries == 0 && backend.read().deviceQueries == 0)
}

@Test func bluetoothCountsConnectionsAndPreservesUnavailableControllerAndBatteryState() async {
  let backend = BluetoothBackendFixture()
  backend.configure {
    $0.devices = [
      BluetoothPeripheral(id: "b", name: "Same name", connected: false),
      BluetoothPeripheral(id: "a", name: "Same name", connected: true),
    ]
  }
  let collector = BluetoothCollector(backend: backend)
  let active = await collector.snapshot()
  #expect(active.devices.map(\.id) == ["a", "b"] && active.connectedCount == 1)
  #expect(active.devices.allSatisfy { $0.batteryFraction == nil })
  backend.configure { $0.powered = nil }
  let unavailable = await collector.snapshot()
  #expect(unavailable.powered == nil && unavailable.connectedCount == nil)
  #expect(backend.read().deviceQueries == 1)
  backend.configure { $0.powered = false }
  let disabled = await collector.snapshot()
  #expect(disabled.powered == false && disabled.connectedCount == 0)
  #expect(backend.read().deviceQueries == 1)
}

@Test func bluetoothDiscardsDataWhenAuthorizationChangesDuringEnumeration() async {
  let backend = BluetoothBackendFixture()
  backend.configure { $0.revokeOnEnumeration = true }
  let snapshot = await BluetoothCollector(backend: backend).snapshot()
  #expect(snapshot.access == .denied && snapshot.devices.isEmpty && snapshot.connectedCount == nil)
}

@Test func bluetoothConnectionRequiresCurrentAccessPowerAndPairingWithoutRetryingFailure()
  async throws
{
  let backend = BluetoothBackendFixture()
  let collector = BluetoothCollector(backend: backend)
  do {
    try await collector.setConnected(true, deviceID: "unpaired")
    Issue.record("An arbitrary address must not start a connection")
  } catch { #expect(error is DeviceError) }
  backend.configure { $0.access = .denied }
  do {
    try await collector.setConnected(true, deviceID: "paired")
    Issue.record("Denied access must prevent connection")
  } catch { #expect(error is DeviceError) }
  backend.configure {
    $0.access = .allowed
    $0.powered = false
  }
  do {
    try await collector.setConnected(true, deviceID: "paired")
    Issue.record("Powered-off Bluetooth must not start a connection")
  } catch { #expect(error is DeviceError) }
  #expect(backend.read().changes.isEmpty)
  backend.configure {
    $0.powered = true
    $0.failure = .operationFailed("Fixture", -1)
  }
  do {
    try await collector.setConnected(true, deviceID: "paired")
    Issue.record("A native connection failure must be reported")
  } catch { #expect(error is DeviceError) }
  #expect(backend.read().changes == ["paired:true"])
  backend.configure { $0.failure = nil }
  try await collector.setConnected(false, deviceID: "paired")
  #expect(backend.read().changes == ["paired:true", "paired:false"])
}

@Test func bluetoothRevalidatesAuthorizationImmediatelyBeforeAConnectionAndHonorsCancellation()
  async
{
  let backend = BluetoothBackendFixture()
  let collector = BluetoothCollector(backend: backend)
  backend.configure { $0.revokeOnEnumeration = true }
  do {
    try await collector.setConnected(true, deviceID: "paired")
    Issue.record("Revoked access must prevent connection")
  } catch { #expect(error is DeviceError) }
  backend.configure {
    $0.access = .allowed
    $0.revokeOnEnumeration = false
  }
  let operation = Task {
    withUnsafeCurrentTask { $0?.cancel() }
    try await collector.setConnected(true, deviceID: "paired")
  }
  do {
    try await operation.value
    Issue.record("An already canceled operation must not reach a native device")
  } catch { #expect(error is CancellationError) }
  #expect(backend.read().changes.isEmpty)
}
