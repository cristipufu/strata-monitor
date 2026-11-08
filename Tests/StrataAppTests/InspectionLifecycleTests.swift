import Foundation
import StrataCore
import StrataSystem
import Testing

@testable import StrataBar

private func inspectionProcess(_ pid: Int32) -> ProcessSample {
  ProcessSample(
    id: ProcessIdentity(pid: pid, startSeconds: 1, startMicroseconds: 0), parentPID: 1,
    userID: 501, name: "Fixture", path: "/fixture", cpuTimeNanoseconds: nil, residentBytes: nil,
    footprintBytes: nil, threads: nil)
}
private actor GatedDetails: ProcessDetailInspecting {
  private var pending: [Int32: CheckedContinuation<ProcessDetails, Error>] = [:]
  private(set) var requests: [Int32] = []
  func inspect(_ process: ProcessSample) async throws -> ProcessDetails {
    requests.append(process.id.pid)
    return try await withCheckedThrowingContinuation { pending[process.id.pid] = $0 }
  }
  func finish(_ pid: Int32) {
    pending.removeValue(forKey: pid)?.resume(
      returning: ProcessDetails(
        identity: inspectionProcess(pid).id,
        signing: SigningInfo(kind: .unsigned), arguments: [], executableMappings: [],
        mappingSummary: ScanSummary()))
  }
}
private actor CountingSampler: SystemSampling {
  private(set) var calls = 0
  func reset() {}
  func sample(includeProcesses: Bool, includeGPU: Bool) -> SystemSample {
    calls += 1
    return SystemSample(
      uptime: 0, cpu: nil, cores: [], memory: nil, network: nil, interfaces: [], processes: [])
  }
}
private struct InventoryFixture: ProcessListing {
  func inventory() async -> ProcessInventory {
    var summary = ScanSummary()
    summary.restricted = true
    return ProcessInventory(processes: [inspectionProcess(10)], summary: summary)
  }
}
private struct ResourceFixture: ResourceInspecting {
  func identityIsCurrent(_ identity: ProcessIdentity) async -> Bool { true }
  func inspect(_ processes: [ProcessSample], socketsOnly: Bool) async throws -> ResourceReport {
    var summary = ScanSummary()
    summary.changedDuringScan = true
    return ResourceReport(
      resources: processes.map {
        ProcessResource(
          owner: $0.id, processName: $0.name, descriptor: 3, kind: .file, path: "/fixture")
      }, summary: summary)
  }
}

@Test @MainActor func supersededDetailInspectionsCannotPublishAfterSelectionOrClose() async throws {
  let service = GatedDetails()
  let model = AppModel(detailsCollector: service, persistsPreferences: false)
  model.trackProcess(inspectionProcess(10).id)
  model.inspectDetails(inspectionProcess(10))
  try await waitUntil { await service.requests == [10] }
  model.trackProcess(inspectionProcess(20).id)
  model.inspectDetails(inspectionProcess(20))
  try await waitUntil { await service.requests == [10, 20] }
  await service.finish(10)
  for _ in 0..<10 { await Task.yield() }
  #expect(model.processDetails == nil && model.isLoadingDetails)
  await service.finish(20)
  try await waitUntil { model.processDetails?.identity.pid == 20 }
  model.inspectDetails(inspectionProcess(30))
  try await waitUntil { await service.requests.count == 3 }
  model.endExplorerSession()
  await service.finish(30)
  for _ in 0..<10 { await Task.yield() }
  #expect(model.processDetails == nil && !model.isLoadingDetails)
  #expect(model.processHistory.identity == nil)
  model.stop()
}

@Test @MainActor func manualInventoryPreservesSamplingBaselineAndCombinesCoverage() async throws {
  let sampler = CountingSampler()
  let model = AppModel(
    collector: sampler, resourceCollector: ResourceFixture(),
    inventoryCollector: InventoryFixture(), persistsPreferences: false)
  model.inspect()
  try await waitUntil { !model.isInspecting }
  #expect(await sampler.calls == 0)
  #expect(model.resources.resources.count == 1)
  #expect(model.resources.summary.restricted && model.resources.summary.changedDuringScan)
  #expect(model.resourceInspectedAt != nil)
  model.stop()
}

@Test @MainActor func previewPreferencesDoNotReadOrOverwriteSavedSettings() throws {
  let suite = "StrataBar.Tests.\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  var preferences = Preferences()
  preferences.appearance = .dark
  let data = try JSONEncoder().encode(preferences)
  defaults.set(data, forKey: "StrataBar.preferences.v1")
  let model = AppModel(defaults: defaults, persistsPreferences: false)
  #expect(model.preferences.appearance == .system)
  model.preferences.appearance = .light
  #expect(defaults.data(forKey: "StrataBar.preferences.v1") == data)
}
