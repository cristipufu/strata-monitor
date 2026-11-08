import Foundation
import StrataCore
import Testing

@testable import StrataBar
@testable import StrataSystem

private actor GatedWiFi: WiFiNetworking {
  private var scans: [UUID: CheckedContinuation<WiFiScanReport, Error>] = [:]
  private var joins: [Int: CheckedContinuation<Void, Error>] = [:]
  private(set) var requests: [UUID] = []
  private(set) var changes: [UUID] = []
  private(set) var discarded: [UUID] = []
  func scan(requestID: UUID) async throws -> WiFiScanReport {
    requests.append(requestID)
    return try await withCheckedThrowingContinuation { scans[requestID] = $0 }
  }
  func finishScan(
    _ id: UUID, name: String = "Cafe", failure: Bool = false, uptime: TimeInterval? = nil
  ) {
    let continuation = scans.removeValue(forKey: id)
    if failure {
      continuation?.resume(throwing: DeviceError.unavailable("Fixture scan failed"))
    } else {
      continuation?.resume(
        returning: WiFiScanReport(
          id: id,
          networks: [
            NearbyNetwork(
              id: UUID(), name: name, rssi: -45, securityModes: [.none],
              joinCapability: .unprotectedNetwork),
            NearbyNetwork(
              id: UUID(), name: "Protected", rssi: -40, securityModes: [.wpa2Personal],
              joinCapability: .systemSettings(.protectedNetwork)),
          ], observationUptime: uptime ?? ProcessInfo.processInfo.systemUptime))
    }
  }
  func join(networkID: UUID, scanID: UUID) async throws {
    changes.append(networkID)
    let index = changes.count
    try await withCheckedThrowingContinuation { joins[index] = $0 }
  }
  func finishJoin(_ index: Int, failure: Bool = false) {
    let continuation = joins.removeValue(forKey: index)
    if failure {
      continuation?.resume(throwing: DeviceError.unavailable("Fixture join failed"))
    } else {
      continuation?.resume()
    }
  }
  func discard(scanID: UUID) { discarded.append(scanID) }
}

@MainActor private final class WiFiClockFixture { var now: TimeInterval = 10 }

@Test @MainActor func wifiCompletedResultsSurviveBriefNavigationAndExpireBeforeAnotherJoin()
  async throws
{
  let service = GatedWiFi()
  let clock = WiFiClockFixture()
  let controller = WiFiController(service: service, uptime: { clock.now })
  controller.start()
  defer { controller.stop() }
  controller.setVisible(true)
  controller.scan()
  try await waitUntil { await service.requests.count == 1 }
  let scan = try #require(await service.requests.first)
  await service.finishScan(scan, uptime: clock.now)
  try await waitUntil { controller.report != nil }
  let network = try #require(controller.report?.networks.first?.id)
  controller.setVisible(false)
  controller.setVisible(true)
  #expect(controller.report?.id == scan && controller.hasCurrentResults)
  #expect(await service.requests.count == 1)
  #expect(await service.discarded.isEmpty)
  clock.now = 71
  controller.join(network)
  #expect(controller.joiningNetworkID == nil)
  controller.setVisible(false)
  controller.setVisible(true)
  #expect(controller.report == nil)
  try await waitUntil { await service.discarded.contains(scan) }
  #expect(await service.changes.isEmpty)
}

@Test @MainActor func wifiHiddenAndCanceledScansCannotPublishOrEndANewerScan() async throws {
  let service = GatedWiFi()
  let controller = WiFiController(service: service)
  controller.start()
  defer { controller.stop() }
  controller.scan()
  for _ in 0..<10 { await Task.yield() }
  #expect(await service.requests.isEmpty)
  controller.setVisible(true)
  controller.scan()
  try await waitUntil { await service.requests.count == 1 }
  let old = try #require(await service.requests.first)
  controller.setVisible(false)
  controller.setVisible(true)
  controller.scan()
  try await waitUntil { await service.requests.count == 2 }
  let current = try #require(await service.requests.last)
  await service.finishScan(old, name: "Obsolete")
  for _ in 0..<10 { await Task.yield() }
  #expect(controller.isScanning && controller.report == nil)
  await service.finishScan(current, name: "Current")
  try await waitUntil { !controller.isScanning }
  #expect(controller.report?.networks.first?.name == "Current")
  #expect(await service.discarded.contains(old))
}

@Test @MainActor
func wifiJoinRequiresAnEligibleCurrentResultAndRetainsAnExplicitAttemptAcrossPageClosure()
  async throws
{
  let service = GatedWiFi()
  let controller = WiFiController(service: service)
  controller.start()
  defer { controller.stop() }
  controller.setVisible(true)
  controller.scan()
  try await waitUntil { await service.requests.count == 1 }
  let scan = try #require(await service.requests.first)
  await service.finishScan(scan)
  try await waitUntil { controller.report != nil }
  let networks = try #require(controller.report?.networks)
  controller.join(UUID())
  controller.join(networks[1].id)
  #expect(controller.joiningNetworkID == nil)
  controller.join(networks[0].id)
  controller.join(networks[0].id)
  try await waitUntil { await service.changes.count == 1 }
  controller.setVisible(false)
  #expect(controller.report?.id == scan && controller.joiningNetworkID == networks[0].id)
  await service.finishJoin(1)
  try await waitUntil { controller.joiningNetworkID == nil }
  #expect(controller.connectionAttemptFinished != nil)
  try await waitUntil { await service.discarded.contains(scan) }
}

@Test @MainActor func wifiStoppedJoinCannotClearOrReportAnErrorForANewerRequest() async throws {
  let service = GatedWiFi()
  let controller = WiFiController(service: service)
  controller.start()
  defer { controller.stop() }
  controller.setVisible(true)
  controller.scan()
  try await waitUntil { await service.requests.count == 1 }
  await service.finishScan(try #require(await service.requests.first))
  try await waitUntil { controller.report != nil }
  let first = try #require(controller.report?.networks.first?.id)
  controller.join(first)
  try await waitUntil { await service.changes.count == 1 }
  controller.stop()
  controller.start()
  controller.scan()
  try await waitUntil { await service.requests.count == 2 }
  await service.finishScan(try #require(await service.requests.last))
  try await waitUntil { controller.report != nil }
  let second = try #require(controller.report?.networks.first?.id)
  controller.join(second)
  try await waitUntil { await service.changes.count == 2 }
  await service.finishJoin(1, failure: true)
  for _ in 0..<10 { await Task.yield() }
  #expect(controller.joiningNetworkID == second && controller.errorMessage == nil)
  await service.finishJoin(2, failure: true)
  try await waitUntil { controller.joiningNetworkID == nil }
  #expect(
    controller.errorMessage == "Fixture join failed" && controller.connectionAttemptFinished != nil)
}

@Test @MainActor func wifiCancellationBeforeAQueuedJoinNeverReachesTheService() async throws {
  let service = GatedWiFi()
  let controller = WiFiController(service: service)
  controller.start()
  controller.setVisible(true)
  controller.scan()
  try await waitUntil { await service.requests.count == 1 }
  await service.finishScan(try #require(await service.requests.first))
  try await waitUntil { controller.report != nil }
  controller.join(try #require(controller.report?.networks.first?.id))
  controller.stop()
  for _ in 0..<10 { await Task.yield() }
  #expect(await service.changes.isEmpty)
}

@Test @MainActor func wifiScanFailureIsVisibleAndItsOwnerCanDeallocateDuringANativeWait()
  async throws
{
  let service = GatedWiFi()
  var controller: WiFiController? = WiFiController(service: service)
  controller?.start()
  controller?.setVisible(true)
  controller?.scan()
  try await waitUntil { await service.requests.count == 1 }
  await service.finishScan(try #require(await service.requests.first), failure: true)
  try await waitUntil { controller?.isScanning == false }
  #expect(controller?.errorMessage == "Fixture scan failed")
  controller?.dismissError()
  #expect(controller?.errorMessage == nil)
  controller?.scan()
  try await waitUntil { await service.requests.count == 2 }
  weak let owner = controller
  controller = nil
  #expect(owner == nil)
  await service.finishScan(try #require(await service.requests.last))
}

private actor WiFiDeviceFixture: DeviceControlling {
  private var pending: CheckedContinuation<DeviceSnapshot, Never>?
  private(set) var reads = 0
  private(set) var powerChanges: [Bool] = []
  func sample() async -> DeviceSnapshot {
    reads += 1
    return await withCheckedContinuation { pending = $0 }
  }
  func finish() {
    pending?.resume(
      returning: DeviceSnapshot(
        battery: .absent,
        audio: AudioState(
          outputs: [], volume: nil, muted: nil, canSetVolume: false, canSetMute: false),
        wifi: WiFiState(powered: true, ssid: "Joined", rssi: -40, interface: "en0"),
        volumes: [], lowPowerMode: false))
    pending = nil
  }
  func setWiFiPower(_ powered: Bool) { powerChanges.append(powered) }
  func setVolume(_ value: Double, on output: AudioOutputIdentity) {}
  func setMuted(_ muted: Bool, on output: AudioOutputIdentity) {}
  func selectOutput(_ output: AudioOutputIdentity) {}
}

@Test(arguments: [false, true]) @MainActor
func wifiJoinRefreshesActualDeviceStateUnlessMonitoringStops(_ stopBeforeRefresh: Bool) async throws
{
  let service = GatedWiFi()
  let devices = WiFiDeviceFixture()
  let model = AppModel(deviceCollector: devices, wifiService: service, persistsPreferences: false)
  model.wifi.start()
  defer { model.stop() }
  model.page = .wifi
  model.wifi.scan()
  for _ in 0..<10 { await Task.yield() }
  #expect(await service.requests.isEmpty)
  model.setDemand("popover", active: true)
  model.wifi.scan()
  try await waitUntil { await service.requests.count == 1 }
  await service.finishScan(try #require(await service.requests.first))
  try await waitUntil { model.wifi.report != nil }
  model.wifi.join(try #require(model.wifi.report?.networks.first?.id))
  try await waitUntil { await service.changes.count == 1 }
  model.setWiFiPower(false)
  #expect(await devices.powerChanges.isEmpty)
  await service.finishJoin(1)
  try await waitUntil { await devices.reads == 1 }
  if stopBeforeRefresh { model.stop() }
  await devices.finish()
  if stopBeforeRefresh {
    for _ in 0..<10 { await Task.yield() }
    #expect(model.devices == nil)
  } else {
    try await waitUntil { model.devices?.wifi.ssid == "Joined" }
  }
}
