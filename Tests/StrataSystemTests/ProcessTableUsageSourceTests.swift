import Foundation
import StrataCore
import Testing

@testable import StrataSystem

private final class ScriptedProcessTable: ProcessTableReading, @unchecked Sendable {
  private let lock = NSLock()
  private var tables: [ExternalProcessTable?]
  private(set) var reads = 0
  init(_ tables: [ExternalProcessTable?]) { self.tables = tables }
  func read() async throws -> ExternalProcessTable {
    let next = lock.withLock {
      reads += 1
      return tables.isEmpty ? nil : tables.removeFirst()
    }
    guard let next else { throw SystemToolError.unrecognizedOutput }
    return next
  }
}

private final class ManualUptime: @unchecked Sendable {
  var now: TimeInterval = 100
}

private func table(rootCPU seconds: UInt64, ownCPU: UInt64 = 0) -> ExternalProcessTable {
  ExternalProcessTable(
    records: [
      ExternalProcessRecord(
        pid: 50, parentPID: 1, userID: 0, cpuTimeNanoseconds: seconds * 1_000_000_000,
        residentBytes: 4096, state: .running, command: "falcon"),
      ExternalProcessRecord(
        pid: 60, parentPID: 1, userID: 501, cpuTimeNanoseconds: ownCPU, residentBytes: 1,
        state: .running, command: "own"),
    ], skippedLines: 0)
}

@Test func processTableEstimatesMeasureCPUAcrossTheirOwnLaunches() async throws {
  let clock = ManualUptime()
  let reader = ScriptedProcessTable([table(rootCPU: 10), table(rootCPU: 18), table(rootCPU: 20)])
  let source = ProcessTableUsageSource(
    reader: reader, currentUser: 501, refreshInterval: 5, uptime: { clock.now },
    identity: { ProcessIdentity(pid: $0, startSeconds: 7, startMicroseconds: 0) })
  let first = try #require(await source.usageEstimates())
  #expect(first.map(\.pid) == [50], "The current user's processes are measured directly")
  #expect(first[0].cpuPercent == nil && first[0].residentBytes == 4096)

  clock.now += 2
  #expect(await source.usageEstimates() == first, "Between launches the last estimates are reused")
  #expect(reader.reads == 1)

  clock.now += 3
  let second = try #require(await source.usageEstimates())
  #expect(second[0].cpuPercent == 160, "8 s of CPU over 5 s is 1.6 cores")

  clock.now += 60
  let afterPause = try #require(await source.usageEstimates())
  #expect(afterPause[0].cpuPercent == nil, "A baseline from before a long pause is not used")
}

@Test func anUnreadableProcessTableGivesNoEstimatesRatherThanZeros() async {
  let source = ProcessTableUsageSource(
    reader: ScriptedProcessTable([nil]), currentUser: 501, uptime: { 1 },
    identity: { ProcessIdentity(pid: $0, startSeconds: 7, startMicroseconds: 0) })
  #expect(await source.usageEstimates() == nil)
}

private actor TimedInventories: ProcessListing {
  private var next: [ProcessInventory]
  init(_ inventories: [ProcessInventory]) { next = inventories }
  func inventory() -> ProcessInventory { next.isEmpty ? ProcessInventory(processes: []) : next.removeFirst() }
}

private func process(cpu: UInt64?, estimated: Bool = false, percent: Double? = nil) -> ProcessSample {
  var sample = ProcessSample(
    id: ProcessIdentity(pid: 70, startSeconds: 1, startMicroseconds: 0), parentPID: 1, userID: 0,
    name: "busy", path: "", cpuTimeNanoseconds: cpu, cpuPercent: percent, residentBytes: nil,
    footprintBytes: nil, threads: nil)
  sample.isEstimated = estimated
  return sample
}

@Test func ratesUseWhenCountersWereReadNotWhenTheyArrived() async throws {
  let collector = SystemCollector(
    inventory: MergedProcessInventory(
      local: TimedInventories([
        ProcessInventory(processes: [process(cpu: 0)], capturedAt: 100),
        ProcessInventory(processes: [process(cpu: 2_000_000_000)], capturedAt: 102),
      ])))
  _ = await collector.sample(includeProcesses: true)
  let second = await collector.sample(includeProcesses: true)
  #expect(second.processes.first?.cpuPercent == 100, "2 s of CPU over the 2 s between reads")
}

@Test func estimatedRowsShowOnlyTheirSourcesPercentage() async throws {
  let collector = SystemCollector(
    inventory: MergedProcessInventory(
      local: TimedInventories([
        ProcessInventory(processes: [process(cpu: 0, estimated: true)], capturedAt: 100),
        ProcessInventory(processes: [process(cpu: 0, estimated: true, percent: 40)], capturedAt: 102),
      ])))
  let first = await collector.sample(includeProcesses: true)
  #expect(first.processes.first?.cpuPercent == nil, "No percentage yet is unavailable, not 0%")
  let second = await collector.sample(includeProcesses: true)
  #expect(second.processes.first?.cpuPercent == 40)
}

@Test func aRepeatedScanKeepsTheRatesAlreadyMeasured() async throws {
  let collector = SystemCollector(
    inventory: MergedProcessInventory(
      local: TimedInventories([
        ProcessInventory(processes: [process(cpu: 0)], capturedAt: 100),
        ProcessInventory(processes: [process(cpu: 1_000_000_000)], capturedAt: 102),
        ProcessInventory(processes: [process(cpu: 1_000_000_000)], capturedAt: 102),
      ])))
  _ = await collector.sample(includeProcesses: true)
  #expect(await collector.sample(includeProcesses: true).processes.first?.cpuPercent == 50)
  #expect(await collector.sample(includeProcesses: true).processes.first?.cpuPercent == 50)
}
