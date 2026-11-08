import StrataCore
import Testing

private func sample(_ time: Double) -> SystemSample {
  SystemSample(
    uptime: time, cpu: 0.5, cores: [0.5], memory: nil, network: nil, interfaces: [], processes: [])
}

@Test func historyExpiresByTimeRatherThanSampleCount() {
  var history = RecentHistory()
  for time in stride(from: 0.0, through: 100, by: 2) { history.append(sample(time)) }
  #expect(history.points.first?.uptime == 40)
  #expect(history.points.count == 31)
  #expect(history.points.allSatisfy { $0.memory == nil && $0.download == nil })
  history.append(sample(99))
  #expect(history.points.last?.uptime == 100)
  history.reset()
  #expect(history.points.isEmpty)
}

@Test func historyHasHardBoundEvenWithHighFrequencySamples() {
  var history = RecentHistory()
  for index in 0..<500 { history.append(sample(Double(index) / 100)) }
  #expect(history.points.count == 240)
}

@Test func graphDoesNotStretchEarlySamplesAcrossAnEntireMinute() {
  #expect(HistoryLayout.horizontalPosition(at: 60, latest: 60) == 1)
  #expect(HistoryLayout.horizontalPosition(at: 0, latest: 60) == 0)
  #expect(HistoryLayout.horizontalPosition(at: 58, latest: 60) == 58.0 / 60)
  #expect(HistoryLayout.horizontalPosition(at: 61, latest: 60) == nil)
  #expect(HistoryLayout.horizontalPosition(at: -1, latest: 60) == nil)
  #expect(HistoryLayout.horizontalPosition(at: .nan, latest: 60) == nil)
}

@Test func residentAndFootprintQueriesRemainDifferentMeasurements() {
  let id = ProcessIdentity(pid: 42, startSeconds: 1, startMicroseconds: 0)
  let process = ProcessSample(
    id: id, parentPID: 1, userID: 501, name: "Worker", path: "/tmp/worker",
    cpuTimeNanoseconds: nil, residentBytes: 100, footprintBytes: 80, threads: nil)
  #expect(process.residentBytes != process.footprintBytes)
  #expect(ExplorerQuery("worker pid:42").matches(process))
  #expect(!ExplorerQuery("port:42").matches(process))
  #expect(!ExplorerQuery("$(touch /tmp/nope)").matches(process))
}
