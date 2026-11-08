import AppKit
import Foundation
import StrataCore
import StrataSystem
import Testing

@testable import StrataBar

private actor GatedBluetooth: BluetoothManaging {
  private var snapshots: [Int: CheckedContinuation<BluetoothSnapshot, Never>] = [:]
  private var operations: [Int: CheckedContinuation<Void, Error>] = [:]
  private(set) var reads = 0
  private(set) var changes: [String] = []
  func snapshot() async -> BluetoothSnapshot {
    reads += 1
    let index = reads
    return await withCheckedContinuation { snapshots[index] = $0 }
  }
  func finishRead(_ index: Int, snapshot: BluetoothSnapshot = bluetoothFixture()) {
    snapshots.removeValue(forKey: index)?.resume(returning: snapshot)
  }
  func setConnected(_ connected: Bool, deviceID: String) async throws {
    changes.append("\(deviceID):\(connected)")
    let index = changes.count
    try await withCheckedThrowingContinuation { operations[index] = $0 }
  }
  func finishChange(index: Int? = nil, failure: Bool = false) {
    let operation = operations.removeValue(forKey: index ?? changes.count)
    if failure {
      operation?.resume(throwing: DeviceError.unavailable("Fixture connection failed"))
    } else {
      operation?.resume()
    }
  }
}

private func bluetoothFixture(_ name: String = "Headphones", connected: Bool = false)
  -> BluetoothSnapshot
{
  BluetoothSnapshot(
    access: .allowed, powered: true,
    devices: [BluetoothPeripheral(id: "paired", name: name, connected: connected)])
}
@MainActor private final class BluetoothPermissionFixture: BluetoothAccessRequesting {
  private(set) var requests = 0
  var completion: (@MainActor () -> Void)?
  func request(didChange: @escaping @MainActor () -> Void) {
    requests += 1
    completion = didChange
  }
  func stop() { completion = nil }
}

@Test @MainActor func bluetoothObservationFollowsActualPanelVisibilityAndSelectedIndicator()
  async throws
{
  let service = GatedBluetooth()
  let model = AppModel(bluetoothService: service, persistsPreferences: false)
  model.bluetooth.start()
  defer { model.stop() }
  model.page = .bluetooth
  for _ in 0..<10 { await Task.yield() }
  #expect(await service.reads == 0)
  model.setDemand("popover", active: true)
  try await waitUntil { await service.reads == 1 }
  await service.finishRead(1)
  try await waitUntil { model.bluetooth.snapshot != nil }
  model.setDemand("popover", active: false)
  #expect(model.bluetooth.snapshot == nil)
  var profile = model.profile
  profile.center = .bluetooth
  model.profile = profile
  try await waitUntil { await service.reads == 2 }
  profile.center = .wifi
  model.profile = profile
  await service.finishRead(2, snapshot: bluetoothFixture("Obsolete"))
  for _ in 0..<10 { await Task.yield() }
  #expect(model.bluetooth.snapshot == nil)
}

@Test @MainActor func bluetoothPermissionRequiresAnExplicitVisiblePageRequestAndDropsLateCallbacks()
  async throws
{
  let service = GatedBluetooth()
  let permission = BluetoothPermissionFixture()
  let controller = BluetoothController(service: service, accessRequest: permission)
  controller.start()
  defer { controller.stop() }
  controller.setDemand(.indicator, active: true)
  try await waitUntil { await service.reads == 1 }
  await service.finishRead(1, snapshot: BluetoothSnapshot(access: .notDetermined))
  try await waitUntil { controller.snapshot != nil }
  controller.requestAccess()
  #expect(permission.requests == 0)
  controller.setDemand(.page, active: true)
  try await waitUntil { await service.reads == 2 }
  await service.finishRead(2, snapshot: BluetoothSnapshot(access: .notDetermined))
  controller.requestAccess()
  #expect(permission.requests == 1)
  let late = try #require(permission.completion)
  controller.stop()
  late()
  for _ in 0..<10 { await Task.yield() }
  #expect(await service.reads == 2)
}

@Test @MainActor
func bluetoothSerializesExplicitConnectionsAcrossPageClosureAndDiscardsStoppedResults() async throws
{
  let service = GatedBluetooth()
  let controller = BluetoothController(service: service)
  controller.start()
  controller.setDemand(.page, active: true)
  try await waitUntil { await service.reads == 1 }
  await service.finishRead(1)
  try await waitUntil { controller.snapshot != nil }
  controller.setConnected(true, deviceID: "paired")
  controller.setConnected(false, deviceID: "paired")
  try await waitUntil { await service.changes.count == 1 }
  controller.setDemand(.page, active: false)
  await service.finishChange()
  try await waitUntil { controller.busyDeviceID == nil }
  #expect(await service.reads == 1)
  controller.setDemand(.page, active: true)
  try await waitUntil { await service.reads == 2 }
  await service.finishRead(2)
  try await waitUntil { controller.snapshot != nil }
  controller.setConnected(false, deviceID: "paired")
  try await waitUntil { await service.changes.count == 2 }
  controller.stop()
  await service.finishChange(failure: true)
  for _ in 0..<10 { await Task.yield() }
  #expect(
    controller.snapshot == nil && controller.errorMessage == nil && controller.busyDeviceID == nil)
  #expect(await service.changes == ["paired:true", "paired:false"])
}

@Test @MainActor func bluetoothReportsConnectionFailureInlineAndRefreshesActualState() async throws
{
  let service = GatedBluetooth()
  let controller = BluetoothController(service: service)
  controller.start()
  defer { controller.stop() }
  controller.setDemand(.page, active: true)
  try await waitUntil { await service.reads == 1 }
  await service.finishRead(1)
  try await waitUntil { controller.snapshot != nil }
  controller.setConnected(true, deviceID: "missing")
  #expect(controller.busyDeviceID == nil)
  controller.setConnected(true, deviceID: "paired")
  try await waitUntil { await service.changes.count == 1 }
  await service.finishChange(failure: true)
  try await waitUntil { await service.reads == 2 }
  #expect(controller.errorMessage == "Fixture connection failed")
  await service.finishRead(2, snapshot: bluetoothFixture(connected: true))
  try await waitUntil { controller.snapshot?.connectedCount == 1 }
  controller.dismissError()
  #expect(controller.errorMessage == nil)
}

@Test @MainActor func bluetoothObservationDoesNotRetainAClosedOwner() async throws {
  let service = GatedBluetooth()
  var controller: BluetoothController? = BluetoothController(service: service)
  weak let owner = controller
  controller?.setDemand(.page, active: true)
  controller?.start()
  try await waitUntil { await service.reads == 1 }
  controller = nil
  #expect(owner == nil)
  await service.finishRead(1)
}

@Test @MainActor func bluetoothStoppedOperationCannotFinishANewerRequest() async throws {
  let service = GatedBluetooth()
  let controller = BluetoothController(service: service)
  controller.setDemand(.page, active: true)
  controller.start()
  defer { controller.stop() }
  try await waitUntil { await service.reads == 1 }
  await service.finishRead(1)
  try await waitUntil { controller.snapshot != nil }
  controller.setConnected(true, deviceID: "paired")
  try await waitUntil { await service.changes.count == 1 }
  controller.stop()
  controller.start()
  try await waitUntil { await service.reads == 2 }
  await service.finishRead(2)
  try await waitUntil { controller.snapshot != nil }
  controller.setConnected(true, deviceID: "paired")
  try await waitUntil { await service.changes.count == 2 }
  await service.finishChange(index: 1, failure: true)
  for _ in 0..<10 { await Task.yield() }
  #expect(controller.busyDeviceID == "paired" && controller.errorMessage == nil)
  await service.finishChange(index: 2)
  try await waitUntil { await service.reads == 3 }
  await service.finishRead(3)
  #expect(controller.busyDeviceID == nil)
}

@Test @MainActor func bluetoothPollingStopsWhenTheLastVisibleDemandEnds() async throws {
  let service = GatedBluetooth()
  let controller = BluetoothController(service: service, observationInterval: .milliseconds(20))
  controller.setDemand(.page, active: true)
  controller.start()
  defer { controller.stop() }
  try await waitUntil { await service.reads == 1 }
  await service.finishRead(1)
  try await waitUntil { await service.reads == 2 }
  controller.setDemand(.page, active: false)
  await service.finishRead(2)
  try await Task.sleep(for: .milliseconds(50))
  #expect(await service.reads == 2)
  #expect(controller.snapshot == nil)
}

@Test @MainActor func bluetoothRejectsHiddenPageActionsAndCancelsAnUnstartedConnection()
  async throws
{
  let service = GatedBluetooth()
  let controller = BluetoothController(service: service)
  controller.setDemand(.indicator, active: true)
  controller.start()
  defer { controller.stop() }
  try await waitUntil { await service.reads == 1 }
  await service.finishRead(1)
  try await waitUntil { controller.snapshot != nil }
  controller.setConnected(true, deviceID: "paired")
  #expect(controller.busyDeviceID == nil)
  controller.setDemand(.page, active: true)
  try await waitUntil { await service.reads == 2 }
  await service.finishRead(2)
  controller.setConnected(true, deviceID: "paired")
  controller.stop()
  for _ in 0..<10 { await Task.yield() }
  #expect(await service.changes.isEmpty)
}

@Test @MainActor func bluetoothMomentsReachTheGlyphWithoutReplayingAfterObservationRestarts()
  async throws
{
  let service = GatedBluetooth()
  let sampler = GatedSampler()
  let model = AppModel(collector: sampler, bluetoothService: service, persistsPreferences: false)
  model.start()
  defer { model.stop() }
  model.page = .bluetooth
  model.setDemand("popover", active: true)
  try await waitUntil { await service.reads == 1 }
  await service.finishRead(1)
  try await waitUntil { model.bluetooth.snapshot != nil }
  #expect(model.moment == nil)
  model.bluetooth.refresh()
  try await waitUntil { await service.reads == 2 }
  await service.finishRead(2, snapshot: bluetoothFixture(connected: true))
  try await waitUntil { model.moment?.title == "Headphones connected" }
  model.stop()
  await sampler.complete()
  #expect(model.moment == nil)
  model.start()
  try await waitUntil { await service.reads == 3 }
  await service.finishRead(3, snapshot: bluetoothFixture(connected: true))
  try await waitUntil { model.bluetooth.snapshot != nil }
  #expect(model.moment == nil)
  model.stop()
  await sampler.complete()
}

@Test @MainActor func bluetoothIndicatorDistinguishesUnknownOffEmptyAndConnectedStates()
  async throws
{
  _ = NSApplication.shared
  let service = GatedBluetooth()
  let model = AppModel(bluetoothService: service, persistsPreferences: false)
  var profile = model.profile
  model.preferences.momentsEnabled = false
  profile.center = .bluetooth
  model.profile = profile
  model.bluetooth.start()
  defer { model.stop() }
  let observations: [(BluetoothSnapshot, String, GlyphCenter)] = [
    (BluetoothSnapshot(access: .allowed), "Unavailable", .symbol("questionmark")),
    (
      BluetoothSnapshot(access: .allowed, powered: false), "Bluetooth off",
      .symbol("bolt.horizontal")
    ),
    (
      BluetoothSnapshot(access: .allowed, powered: true), "0 connected",
      .count(0, symbol: "wave.3.right")
    ),
    (bluetoothFixture(connected: true), "1 connected", .count(1, symbol: "wave.3.right")),
  ]
  for (index, observation) in observations.enumerated() {
    if index > 0 { model.bluetooth.refresh() }
    try await waitUntil { await service.reads == index + 1 }
    await service.finishRead(index + 1, snapshot: observation.0)
    try await waitUntil { model.value(for: .bluetooth) == observation.1 }
    #expect(NSImage(systemSymbolName: model.centerSymbol, accessibilityDescription: nil) != nil)
    #expect(model.glyphCenter == observation.2)
  }
}
