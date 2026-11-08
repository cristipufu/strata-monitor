import Foundation
import StrataCore
import StrataSystem
import Testing

private final class FixedListing: ProcessListing {
  let result: ProcessInventory
  let calls = Counter()
  init(result: ProcessInventory) { self.result = result }
  func inventory() async -> ProcessInventory {
    calls.increment()
    return result
  }
}

private struct FixedPrivilegedSource: PrivilegedProcessSnapshotting, PrivilegedResourceInspecting {
  let result: Result<ProcessInventory, PrivilegedHelperError>
  var resources: Result<ResourceReport, PrivilegedHelperError> = .failure(.unreachable)
  func processInventory() async throws -> ProcessInventory { try result.get() }
  func resources(for processes: [ProcessSample], socketsOnly: Bool) async throws
    -> ResourceReport
  { try resources.get() }
}

private final class CountingEstimates: OtherUsersUsageSource {
  let calls = Counter()
  let estimates: [ProcessUsageEstimate]?
  init(_ estimates: [ProcessUsageEstimate]?) { self.estimates = estimates }
  func usageEstimates() async -> [ProcessUsageEstimate]? {
    calls.increment()
    return estimates
  }
}

private struct FixedResources: ResourceInspecting {
  let report: ResourceReport
  func inspect(_ processes: [ProcessSample], socketsOnly: Bool) async throws -> ResourceReport {
    try Task.checkCancellation()
    return report
  }
  func identityIsCurrent(_ identity: ProcessIdentity) async -> Bool { true }
}

private let own = fixtureSample(pid: 50, userID: 501, cpu: 9, resident: 90, footprint: 99)
private let rootListed = fixtureSample(pid: 1, userID: 0, parent: 0)
private let rootMeasured = fixtureSample(
  pid: 1, userID: 0, parent: 0, cpu: 12, resident: 3, footprint: 4)

@Test func helperDataIsUsedForEveryProcessWithoutRepeatingTheLocalScan() async {
  let estimates = CountingEstimates([])
  let local = FixedListing(result: fixtureInventory([rootListed, own]))
  let merged = MergedProcessInventory(
    local: local,
    privileged: FixedPrivilegedSource(result: .success(fixtureInventory([rootMeasured, own]))),
    otherUsers: estimates)
  let covered = await merged.coveredInventory()
  #expect(covered.coverage == .allProcesses)
  #expect(covered.inventory.processes.map(\.cpuTimeNanoseconds) == [12, 9])
  #expect(covered.measuredCount == 2)
  #expect(local.calls.count == 0 && estimates.calls.count == 0)
  #expect(await merged.privilegedIssue == nil)
}

@Test func helperScanThatFailedFallsBackToTheLocalScan() async {
  var failed = ScanSummary()
  failed.failed = true
  let local = FixedListing(result: fixtureInventory([rootListed, own]))
  let merged = MergedProcessInventory(
    local: local,
    privileged: FixedPrivilegedSource(
      result: .success(ProcessInventory(processes: [], summary: failed))))
  let covered = await merged.coveredInventory()
  #expect(covered.coverage == .ownProcesses)
  #expect(covered.inventory.processes.map(\.id) == [rootListed.id, own.id])
  #expect(covered.inventory.processes[1].cpuTimeNanoseconds == 9, "Own processes stay measured")
}

@Test func failingHelperFallsBackToEstimatesAndRecordsWhy() async {
  let estimates = CountingEstimates([
    ProcessUsageEstimate(
      pid: 1, parentPID: 0, userID: 0, cpuTimeNanoseconds: 70, residentBytes: 80)
  ])
  let merged = MergedProcessInventory(
    local: FixedListing(result: fixtureInventory([rootListed, own])),
    privileged: FixedPrivilegedSource(result: .failure(.needsReregistration)),
    otherUsers: estimates)
  let covered = await merged.coveredInventory()
  #expect(covered.coverage == .ownProcessesWithEstimates)
  let root = covered.inventory.processes[0]
  #expect(root.cpuTimeNanoseconds == 70 && root.residentBytes == 80)
  #expect(root.footprintBytes == nil && root.threads == nil, "Unavailable, never zero")
  #expect(await merged.privilegedIssue == .needsReregistration)
}

@Test func withoutHelperOrFallbackOthersStayUnavailable() async {
  let merged = MergedProcessInventory(
    local: FixedListing(result: fixtureInventory([rootListed, own])))
  let covered = await merged.coveredInventory()
  #expect(covered.coverage == .ownProcesses)
  #expect(covered.inventory.processes[0].cpuTimeNanoseconds == nil)
  #expect(covered.measuredCount == 1)
  await merged.usePrivilegedSource(
    FixedPrivilegedSource(result: .success(fixtureInventory([rootMeasured, own]))))
  #expect(await merged.coveredInventory().coverage == .allProcesses)
}

@Test func resourceInspectionPrefersTheHelperAndFallsBackToLocalAccess() async throws {
  let helperReport = ResourceReport(resources: [
    ProcessResource(owner: rootListed.id, processName: "launchd", descriptor: 3, kind: .tcp)
  ])
  var restricted = ScanSummary()
  restricted.restricted = true
  let local = FixedResources(report: ResourceReport(resources: [], summary: restricted))
  let preferred = MergedResourceInspector(
    local: local,
    privileged: FixedPrivilegedSource(
      result: .failure(.unreachable), resources: .success(helperReport)))
  #expect(try await preferred.inspect([rootListed], socketsOnly: true).resources.count == 1)
  let fallback = MergedResourceInspector(
    local: local, privileged: FixedPrivilegedSource(result: .failure(.unreachable)))
  #expect(try await fallback.inspect([rootListed], socketsOnly: true).summary.restricted)
}
