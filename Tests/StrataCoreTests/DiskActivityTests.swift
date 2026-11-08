import StrataCore
import Testing

private func diskProcess(_ pid: Int32, read: Double?, written: Double?) -> ProcessSample {
  ProcessSample(
    id: ProcessIdentity(pid: pid, startSeconds: 1, startMicroseconds: 0), parentPID: 1, userID: 501,
    name: "Fixture", path: "", cpuTimeNanoseconds: nil, residentBytes: nil, footprintBytes: nil,
    threads: nil,
    diskReadBytesPerSecond: read, diskWrittenBytesPerSecond: written)
}

@Test func diskSubtotalsDistinguishUnavailableSamplesFromIdleProcesses() throws {
  #expect(ObservedDiskActivity([]) == nil)
  #expect(ObservedDiskActivity([diskProcess(10, read: nil, written: nil)]) == nil)
  let activity = try #require(
    ObservedDiskActivity([
      diskProcess(10, read: 0, written: 0), diskProcess(20, read: 200, written: 300),
      diskProcess(30, read: .nan, written: 20), diskProcess(40, read: -1, written: 10),
    ]))
  #expect(activity.read == 200 && activity.written == 300)
  #expect(activity.measuredProcesses == 2 && activity.unavailableProcesses == 2)
}

@Test func observedDiskHistoryPreservesGapsOutsideProcessSampling() {
  func sample(_ time: Double, processes: [ProcessSample]) -> SystemSample {
    SystemSample(
      uptime: time, cpu: nil, cores: [], memory: nil, network: nil, interfaces: [],
      processes: processes)
  }
  var history = RecentHistory()
  history.append(sample(1, processes: []))
  history.append(sample(2, processes: [diskProcess(10, read: 0, written: 100)]))
  #expect(history.points.first?.diskRead == nil)
  #expect(history.points.last?.diskRead == 0 && history.points.last?.diskWritten == 100)
}
