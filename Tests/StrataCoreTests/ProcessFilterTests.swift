import Foundation
import StrataCore
import Testing

@Test func filtersSeparatePeopleDaemonsAppsActivityAndPausedProcesses() {
  func process(
    _ pid: Int32, user: UInt32, cpu: Double? = nil, state: ProcessRunState? = .running
  ) -> ProcessSample {
    ProcessSample(
      id: ProcessIdentity(pid: pid, startSeconds: 1, startMicroseconds: 0), parentPID: 1,
      userID: user, name: "P\(pid)", path: "", cpuTimeNanoseconds: nil, cpuPercent: cpu,
      residentBytes: nil, footprintBytes: nil, threads: nil, runState: state)
  }
  let processes = [
    process(10, user: 501, cpu: 12), process(11, user: 501, cpu: 0, state: .stopped),
    process(20, user: 502), process(30, user: 0), process(31, user: 88),
    process(32, user: UInt32.max - 1),
  ]
  let context = ProcessFilterContext(currentUser: 501, applicationPIDs: [10, 20])
  func pids(_ filter: ProcessFilter) -> [Int32] {
    processes.filter { filter.includes($0, in: context) }.map(\.id.pid)
  }
  #expect(pids(.all).count == processes.count)
  #expect(pids(.mine) == [10, 11])
  #expect(pids(.otherUsers) == [20])
  #expect(pids(.system) == [30, 31, 32])
  #expect(pids(.applications) == [10, 20])
  #expect(pids(.active) == [10])
  #expect(pids(.paused) == [11])
}

@Test func aFilteredTreeKeepsTheAncestorsThatExplainEachMatch() {
  func process(_ pid: Int32, parent: Int32, state: ProcessRunState) -> ProcessSample {
    ProcessSample(
      id: ProcessIdentity(pid: pid, startSeconds: UInt64(pid), startMicroseconds: 0),
      parentPID: parent, userID: 501, name: "P\(pid)", path: "", cpuTimeNanoseconds: nil,
      residentBytes: nil, footprintBytes: nil, threads: nil, runState: state)
  }
  let families = ProcessFamilies([
    process(10, parent: 1, state: .running), process(11, parent: 10, state: .stopped),
    process(20, parent: 1, state: .running),
  ])
  let context = ProcessFilterContext(currentUser: 501)
  let hierarchy = ProcessHierarchy(families) { ProcessFilter.paused.includes($0, in: context) }
  #expect(hierarchy.matchingIdentities.map(\.pid) == [11])
  #expect(Set(hierarchy.processes.map(\.id.pid)) == [10, 11])
}

@Test func searchFindsAccountAndProjectNames() {
  var process = ProcessSample(
    id: ProcessIdentity(pid: 40, startSeconds: 1, startMicroseconds: 0), parentPID: 1,
    userID: 0, name: "falcon", path: "/Library/falcon", cpuTimeNanoseconds: nil,
    residentBytes: nil, footprintBytes: nil, threads: nil)
  process.userName = "root"
  process.project = "agent"
  #expect(ExplorerQuery("user:root").matches(process))
  #expect(!ExplorerQuery("user:roo").matches(process), "The account token is an exact name")
  #expect(ExplorerQuery("agent").matches(process))
}
