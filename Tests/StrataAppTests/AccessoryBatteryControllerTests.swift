import Foundation
import Testing

@testable import StrataBar
@testable import StrataSystem

private actor GatedAccessoryBattery: AccessoryBatteryReading {
  private var continuations: [Int: CheckedContinuation<AccessoryBatteryReport, Error>] = [:]
  private(set) var reads = 0
  private(set) var cancellations: Set<Int> = []
  func read() async throws -> AccessoryBatteryReport {
    reads += 1
    let index = reads
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuations[index] = $0 }
    } onCancel: {
      Task { await self.canceled(index) }
    }
  }
  private func canceled(_ index: Int) { cancellations.insert(index) }
  func finish(_ index: Int, failure: Bool = false, name: String = "Accessory") {
    let continuation = continuations.removeValue(forKey: index)
    if failure {
      continuation?.resume(throwing: AccessoryBatteryError.failed("Controlled battery read failed"))
    } else {
      continuation?.resume(
        returning: AccessoryBatteryReport(
          devices: [
            AccessoryBatteryDevice(
              id: UUID(), name: name,
              levels: [AccessoryBatteryLevel(id: 1, percent: 42, issue: nil)], issue: nil)
          ], totalCandidates: 1, observedAt: Date(), issue: nil))
    }
  }
}
private func accessoryRadio(_ access: BluetoothAccess = .allowed, powered: Bool? = true)
  -> BluetoothSnapshot
{
  BluetoothSnapshot(
    access: access, powered: powered,
    devices: [BluetoothPeripheral(id: "paired", name: "Accessory", connected: true)])
}
@MainActor private func makeAccessoryController(_ reader: GatedAccessoryBattery)
  -> AccessoryBatteryController
{
  let controller = AccessoryBatteryController(reader: reader)
  controller.setVisible(true)
  controller.update(accessoryRadio(), blockedByConnection: false)
  return controller
}

@Test @MainActor func accessoryBatteryReadingRequiresAnExplicitVisibleAuthorizedAction()
  async throws
{
  let reader = GatedAccessoryBattery()
  let controller = AccessoryBatteryController(reader: reader)
  controller.read()
  controller.setVisible(true)
  controller.read()
  for access in [BluetoothAccess.notDetermined, .denied, .restricted] {
    controller.update(accessoryRadio(access), blockedByConnection: false)
    controller.read()
  }
  controller.update(accessoryRadio(powered: false), blockedByConnection: false)
  controller.read()
  controller.update(accessoryRadio(), blockedByConnection: true)
  controller.read()
  for _ in 0..<10 { await Task.yield() }
  #expect(await reader.reads == 0)
  controller.update(accessoryRadio(), blockedByConnection: false)
  controller.read()
  controller.read()
  try await waitUntil { await reader.reads == 1 }
  await reader.finish(1)
  try await waitUntil { !controller.isReading }
  #expect(controller.report?.devices.first?.levels.first?.percent == 42)
}

@Test @MainActor func accessoryBatteryHiddenOrSupersededReadCannotPublishOrClearANewerRead()
  async throws
{
  let reader = GatedAccessoryBattery()
  let controller = makeAccessoryController(reader)
  controller.read()
  try await waitUntil { await reader.reads == 1 }
  controller.setVisible(false)
  try await waitUntil { await reader.cancellations.contains(1) }
  controller.setVisible(true)
  controller.read()
  #expect(controller.isReading && controller.isCanceling)
  #expect(await reader.reads == 1)
  await reader.finish(1, failure: true)
  try await waitUntil { !controller.isReading }
  #expect(controller.report == nil && controller.errorMessage == nil)
  controller.read()
  try await waitUntil { await reader.reads == 2 }
  #expect(controller.isReading && controller.report == nil && controller.errorMessage == nil)
  await reader.finish(2, name: "Current")
  try await waitUntil { !controller.isReading }
  #expect(controller.report?.devices.first?.name == "Current")
}

@Test @MainActor func accessoryBatteryHistoricalResultsSurviveNavigationButNotKnownRevocation()
  async throws
{
  let reader = GatedAccessoryBattery()
  let controller = makeAccessoryController(reader)
  controller.read()
  try await waitUntil { await reader.reads == 1 }
  await reader.finish(1)
  try await waitUntil { controller.report != nil }
  let timestamp = controller.report?.observedAt
  controller.setVisible(false)
  controller.update(nil, blockedByConnection: false)
  #expect(controller.report?.observedAt == timestamp && !controller.canRead)
  controller.setVisible(true)
  controller.update(accessoryRadio(.denied), blockedByConnection: false)
  #expect(controller.report == nil && !controller.canRead)
}

@Test @MainActor func accessoryBatteryRevocationCancelsAnIssuedReadingAndDropsItsResult()
  async throws
{
  let reader = GatedAccessoryBattery()
  let controller = makeAccessoryController(reader)
  controller.read()
  try await waitUntil { await reader.reads == 1 }
  controller.update(accessoryRadio(.denied), blockedByConnection: false)
  try await waitUntil { await reader.cancellations.contains(1) }
  await reader.finish(1)
  for _ in 0..<10 { await Task.yield() }
  #expect(controller.report == nil && !controller.isReading && !controller.canRead)
}

@Test @MainActor func accessoryBatteryFailureIsVisibleAndOwnerCanDeallocateDuringARead()
  async throws
{
  let reader = GatedAccessoryBattery()
  var controller: AccessoryBatteryController? = makeAccessoryController(reader)
  controller?.read()
  try await waitUntil { await reader.reads == 1 }
  await reader.finish(1, failure: true)
  try await waitUntil { controller?.errorMessage != nil }
  #expect(controller?.errorMessage == "Controlled battery read failed")
  controller?.dismissError()
  #expect(controller?.errorMessage == nil)
  controller?.read()
  try await waitUntil { await reader.reads == 2 }
  weak let owner = controller
  controller = nil
  #expect(owner == nil)
  try await waitUntil { await reader.cancellations.contains(2) }
  await reader.finish(2)
}

@Test @MainActor func accessoryBatteryStoppedQueuedActionNeverReachesTheReader() async throws {
  let reader = GatedAccessoryBattery()
  let controller = makeAccessoryController(reader)
  controller.read()
  controller.stop()
  for _ in 0..<10 { await Task.yield() }
  #expect(await reader.reads == 0)
  #expect(!controller.isReading && controller.report == nil)
}

private actor AccessoryBluetoothFixture: BluetoothManaging {
  private var connection: CheckedContinuation<Void, Error>?
  private(set) var changes = 0
  func snapshot() -> BluetoothSnapshot { accessoryRadio() }
  func setConnected(_ connected: Bool, deviceID: String) async throws {
    changes += 1
    try await withCheckedThrowingContinuation { connection = $0 }
  }
  func finishConnection() {
    connection?.resume()
    connection = nil
  }
}

@Test @MainActor func accessoryBatteryAndClassicConnectionActionsCannotOverlap() async throws {
  let radio = AccessoryBluetoothFixture()
  let reader = GatedAccessoryBattery()
  let controller = BluetoothController(service: radio, batteryReader: reader)
  controller.setDemand(.page, active: true)
  controller.start()
  defer { controller.stop() }
  try await waitUntil { controller.batteries.canRead }
  controller.batteries.read()
  try await waitUntil { await reader.reads == 1 }
  controller.setConnected(false, deviceID: "paired")
  #expect(await radio.changes == 0)
  controller.batteries.cancel()
  controller.setConnected(false, deviceID: "paired")
  #expect(await radio.changes == 0)
  await reader.finish(1)
  try await waitUntil { !controller.batteries.isReading }
  controller.setConnected(false, deviceID: "paired")
  try await waitUntil { await radio.changes == 1 }
  controller.batteries.read()
  #expect(!controller.batteries.isReading)
  #expect(await reader.reads == 1)
  await radio.finishConnection()
  try await waitUntil { controller.batteries.canRead }
}

@Test @MainActor func accessoryBatteryIndicatorDemandNeverStartsReadsAndPageClosureCancelsOne()
  async throws
{
  let radio = AccessoryBluetoothFixture()
  let reader = GatedAccessoryBattery()
  let controller = BluetoothController(service: radio, batteryReader: reader)
  controller.setDemand(.indicator, active: true)
  controller.start()
  defer { controller.stop() }
  try await waitUntil { controller.snapshot != nil }
  controller.batteries.read()
  #expect(await reader.reads == 0)
  controller.setDemand(.page, active: true)
  controller.batteries.read()
  try await waitUntil { await reader.reads == 1 }
  controller.setDemand(.page, active: false)
  try await waitUntil { await reader.cancellations.contains(1) }
  await reader.finish(1)
  #expect(controller.batteries.report == nil)
}

@Test @MainActor func accessoryBatteryParentTeardownStopsAnIndependentlyRetainedChild() async throws
{
  let reader = GatedAccessoryBattery()
  var controller: BluetoothController? = BluetoothController(
    service: AccessoryBluetoothFixture(), batteryReader: reader)
  let child = try #require(controller?.batteries)
  controller?.setDemand(.page, active: true)
  controller?.start()
  try await waitUntil { child.canRead }
  child.read()
  try await waitUntil { await reader.reads == 1 }
  weak let owner = controller
  controller = nil
  #expect(owner == nil && child.isCanceling && !child.canRead)
  try await waitUntil { await reader.cancellations.contains(1) }
  await reader.finish(1)
  try await waitUntil { !child.isReading }
}
