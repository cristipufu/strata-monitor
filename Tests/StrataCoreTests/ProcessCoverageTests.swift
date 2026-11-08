import Foundation
import StrataCore
import Testing

private func sample(
  pid: Int32, start: UInt64 = 10, user: UInt32 = 0, parent: Int32 = 1, cpu: UInt64? = nil,
  resident: UInt64? = nil
) -> ProcessSample {
  ProcessSample(
    id: ProcessIdentity(pid: pid, startSeconds: start, startMicroseconds: 0), parentPID: parent,
    userID: user, name: "p\(pid)", path: "", cpuTimeNanoseconds: cpu, residentBytes: resident,
    footprintBytes: nil, threads: nil)
}

@Test func estimatesFillOnlyMissingValuesOfTheMatchingProcess() {
  let local = ProcessInventory(processes: [
    sample(pid: 1), sample(pid: 2, parent: 5), sample(pid: 3, user: 501, cpu: 8, resident: 9),
  ])
  let estimates = [
    ProcessUsageEstimate(pid: 1, parentPID: 1, userID: 0, cpuTimeNanoseconds: 20, residentBytes: nil),
    ProcessUsageEstimate(pid: 2, parentPID: 1, userID: 0, cpuTimeNanoseconds: 30, residentBytes: 30),
    ProcessUsageEstimate(pid: 3, parentPID: 1, userID: 501, cpuTimeNanoseconds: 1, residentBytes: 1),
  ]
  let merged = ProcessInventoryMerge.merge(local: local, estimates: estimates)
  #expect(merged.coverage == .ownProcessesWithEstimates)
  let processes = merged.inventory.processes
  #expect(processes[0].cpuTimeNanoseconds == 20 && processes[0].residentBytes == nil)
  #expect(processes[1].cpuTimeNanoseconds == nil, "A different parent means another process")
  #expect(processes[2].cpuTimeNanoseconds == 8 && processes[2].residentBytes == 9)
  #expect(processes.allSatisfy { $0.footprintBytes == nil && $0.threads == nil })
}

@Test func withoutOtherSourcesTheLocalScanIsReturnedUnchanged() {
  let local = ProcessInventory(processes: [sample(pid: 1), sample(pid: 2, user: 501, cpu: 1)])
  let merged = ProcessInventoryMerge.merge(local: local, estimates: nil)
  #expect(merged.coverage == .ownProcesses)
  #expect(merged.inventory.processes.map(\.cpuTimeNanoseconds) == [nil, 1])
  #expect(merged.measuredCount == 1)
}

@Test func coverageTitlesDescribeWhatIsMeasured() {
  #expect(ProcessCoverage.allProcesses.title == "All processes")
  #expect(ProcessCoverage.ownProcessesWithEstimates.title == "Own processes; CPU and memory for others")
  #expect(ProcessCoverage.ownProcesses.title == "Own processes; others listed")
}
