import Foundation
import StrataCore
import Testing

@testable import StrataBar

private func process(_ pid: Int32, gpu: Double?, watts: Double? = nil) -> ProcessSample {
  var sample = ProcessSample(
    id: ProcessIdentity(pid: pid, startSeconds: 1, startMicroseconds: 0), parentPID: 1,
    userID: 501, name: "Process \(pid)", path: "", cpuTimeNanoseconds: nil, cpuPercent: 1,
    residentBytes: nil, footprintBytes: 1, threads: nil)
  sample.gpuPercent = gpu
  sample.watts = watts
  return sample
}

@Test func tabsGroupTheSummaryResourcesPowerAndConnections() {
  #expect(
    Reading.allCases == [
      .overview, .cpu, .gpu, .memory, .disk, .network, .battery, .wifi, .bluetooth, .sound,
      .display,
    ])
  #expect(Profile.scalarReadings.contains(.gpu), "GPU can fill the ring and the bar")
}

@Test func leadersListOnlyProcessesDoingSomething() {
  let roots = ProcessFamilies([
    process(10, gpu: 40, watts: 2), process(20, gpu: 0, watts: 0), process(30, gpu: nil),
  ]).roots
  #expect(LeaderMeasure.gpu.rows(from: roots).map(\.id.pid) == [10])
  #expect(LeaderMeasure.power.rows(from: roots).map(\.id.pid) == [10])
  #expect(LeaderMeasure.cpu.rows(from: roots).count == 3, "CPU always names its leaders")
}

@Test func leadersAreLimitedToTheTopThree() {
  let roots = ProcessFamilies((1...6).map { process(Int32(100 + $0), gpu: Double($0)) }).roots
  #expect(LeaderMeasure.gpu.rows(from: roots).map(\.id.pid) == [106, 105, 104])
}

@Test @MainActor func viewAllOpensTheExplorerSortedByThatReading() {
  let navigation = ExplorerNavigation()
  let identity = ProcessIdentity(pid: 7, startSeconds: 1, startMicroseconds: 0)
  navigation.open(.ranked(.gpu, identity))
  #expect(navigation.section == .processes && navigation.grouping == .families)
  #expect(navigation.processOrder == ProcessOrder(.gpu) && navigation.identity == identity)
}
