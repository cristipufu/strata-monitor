import Foundation
import StrataCore
import Testing

/// A UTC midnight, so day files and every tier boundary line up with it.
let historyEpoch = Date(timeIntervalSinceReferenceDate: 812_160_000)

func historyTime(_ seconds: Double) -> Date { historyEpoch.addingTimeInterval(seconds) }

func historyIdentity(_ pid: Int32, generation: UInt64 = 0) -> ProcessIdentity {
  ProcessIdentity(pid: pid, startSeconds: 1_700_000_000 + generation, startMicroseconds: 0)
}

func historyProcess(
  _ pid: Int32, name: String? = nil, generation: UInt64 = 0, cpu: Double? = nil,
  footprint: UInt64? = nil, watts: Double? = nil, disk: Double? = nil, network: Double? = nil,
  wakeups: Double? = nil
) -> HistoryProcessPoint {
  HistoryProcessPoint(
    identity: historyIdentity(pid, generation: generation), name: name ?? "process-\(pid)",
    cpuPercent: cpu, footprintBytes: footprint, watts: watts, diskBytesPerSecond: disk,
    networkBytesPerSecond: network, wakeupsPerSecond: wakeups)
}

@Test func storageShapesMatchTheMetricLists() {
  #expect(HistoryMetric.allCases.count == 9)
  #expect(HistoryProcessMetric.allCases.count == 5)
}

@Test func coarserTiersKeepTheMeanAndTheMaximumOfEachBucket() throws {
  var history = TieredHistory()
  let readings = [0.1, 0.2, 0.3, 0.4, 0.5]
  for (index, cpu) in readings.enumerated() {
    history.append(HistorySystemPoint(time: historyTime(Double(index) * 2), cpu: cpu))
  }
  history.append(HistorySystemPoint(time: historyTime(10), cpu: 0.9))
  let tenSeconds = history.points(in: historyTime(0)...historyTime(10), resolution: 10)
  let bucket = try #require(tenSeconds.first)
  let cpu = try #require(bucket[.cpu])
  #expect(bucket.duration == 10)
  #expect(bucket.sampleCount == 5)
  #expect(abs(cpu.mean - 0.3) < 1e-6)
  #expect(abs(cpu.maximum - 0.5) < 1e-6)
  #expect(bucket[.gpu] == nil)
  #expect(tenSeconds.count == 2)
}

@Test func queriesUseTheFinestTierThatReachesTheRangeStart() {
  var history = TieredHistory()
  for second in stride(from: 0.0, through: 3 * 3_600, by: 2) {
    history.append(HistorySystemPoint(time: historyTime(second), cpu: 0.5))
  }
  let end = historyTime(3 * 3_600)
  let lastMinutes = history.points(in: end.addingTimeInterval(-300)...end)
  let lastHour = history.points(in: end.addingTimeInterval(-3_600)...end, maximumCount: 400)
  let lastThreeHours = history.points(in: end.addingTimeInterval(-3 * 3_600)...end)
  #expect(lastMinutes.allSatisfy { $0.duration == 2 })
  #expect(lastMinutes.count == 151)
  #expect(lastHour.allSatisfy { $0.duration == 10 })
  #expect(lastThreeHours.allSatisfy { $0.duration == 60 })
  #expect(lastThreeHours.count == 181)
}

@Test func chartQueriesAreBoundedAndKeepWeightedMeans() throws {
  var history = TieredHistory()
  for second in stride(from: 0.0, to: 86_400, by: 10) {
    history.append(HistorySystemPoint(time: historyTime(second), cpu: second < 43_200 ? 0.2 : 0.6))
  }
  let day = history.points(in: historyTime(0)...historyTime(86_400), maximumCount: 360)
  #expect(day.count <= 360)
  #expect(day.count >= 300)
  let first = try #require(day.first?[.cpu])
  #expect(abs(first.mean - 0.2) < 1e-6)
  let total = day.reduce(0) { $0 + $1.sampleCount }
  #expect(total == 8_640)
  #expect(history.points(in: historyTime(0)...historyTime(1), maximumCount: 0).isEmpty)
}

@Test func outOfOrderAndUnmeasurableReadingsAreNotRecorded() throws {
  var history = TieredHistory()
  #expect(history.append(HistorySystemPoint(time: historyTime(10), cpu: 0.4)).isAccepted)
  #expect(!history.append(HistorySystemPoint(time: historyTime(10), cpu: 0.9)).isAccepted)
  #expect(!history.append(HistorySystemPoint(time: historyTime(4), cpu: 0.9)).isAccepted)
  #expect(!history.append(HistorySystemPoint(time: Date(timeIntervalSinceReferenceDate: .nan))).isAccepted)
  history.append(
    HistorySystemPoint(
      time: historyTime(11), cpu: -1, memoryUsedFraction: .infinity, memoryPressure: nil,
      swapBytes: .nan, thermal: .high))
  let point = try #require(history.points(in: historyTime(0)...historyTime(12)).last)
  #expect(point[.cpu]?.mean == Double(Float(0.4)))
  #expect(point[.memoryUsed] == nil)
  #expect(point[.swap] == nil)
  #expect(point.thermal == .high)
  #expect(history.latestTime == historyTime(11))
}

@Test func processAndSystemReadingsTakenTogetherAreBothKept() {
  var history = TieredHistory()
  #expect(history.append(processes: [historyProcess(1, cpu: 5)], at: historyTime(0)).isAccepted)
  #expect(history.append(HistorySystemPoint(time: historyTime(0), cpu: 0.1)).isAccepted)
  #expect(!history.append(processes: [], at: historyTime(0)).isAccepted)
  #expect(history.points(in: historyTime(0)...historyTime(1)).first?.sampleCount == 1)
}

@Test func restoredIntervalsMustMoveForwardInTime() {
  var history = TieredHistory()
  let entry = HistoryProcessEntry(identity: historyIdentity(1), name: "one", project: nil, sampleCount: 1, cpuPercent: 9)
  history.restore(HistoryProcessBucket(time: historyTime(60), duration: 60, entries: [entry]))
  history.restore(HistoryProcessBucket(time: historyTime(0), duration: 60, entries: [entry]))
  history.restore(HistoryProcessBucket(time: historyTime(60), duration: 60, entries: []))
  #expect(history.processBuckets(in: historyTime(0)...historyTime(120)).map(\.time) == [historyTime(60)])
  #expect(history.latestTime == historyTime(120))
  #expect(history.append(processes: [historyProcess(1, cpu: 3)], at: historyTime(120)).isAccepted)
}

@Test func pressureSummariesKeepTheWorstLevel() throws {
  var history = TieredHistory()
  let levels: [HistoryPressure?] = [.normal, .critical, nil, .elevated, .normal]
  for (index, level) in levels.enumerated() {
    history.append(HistorySystemPoint(time: historyTime(Double(index) * 2), memoryPressure: level))
  }
  let bucket = try #require(history.points(in: historyTime(0)...historyTime(9), resolution: 10).first)
  #expect(bucket.memoryPressure == .critical)
  #expect(bucket.thermal == nil)
}

@Test func eachMinuteKeepsTheLeadersOfEveryProcessMetric() throws {
  var history = TieredHistory()
  var processes: [HistoryProcessPoint] = []
  for pid in Int32(1)...80 {
    let rank = Double(pid)
    processes.append(
      historyProcess(
        pid, cpu: pid <= 20 ? rank : 0, footprint: pid > 20 && pid <= 40 ? UInt64(pid) << 20 : 1,
        watts: pid <= 15 ? rank / 10 : nil, disk: pid > 40 && pid <= 60 ? rank : nil,
        network: pid > 60 ? rank : 0))
  }
  history.append(processes: processes, at: historyTime(0))
  history.append(processes: processes, at: historyTime(30))
  let completed = history.append(HistorySystemPoint(time: historyTime(60))).completedProcessBuckets
  let minute = try #require(completed.first)
  let pids = Set(minute.entries.map(\.identity.pid))
  #expect(minute.entries.count == pids.count)
  #expect(pids == Set(Array(11...20) + Array(31...40) + Array(51...60) + Array(71...80) + Array(6...10)))
  let leader = try #require(minute.entries.first)
  #expect(leader.identity.pid == 20)
  #expect(leader.sampleCount == 2)
  #expect(leader[.cpu] == 20)
  #expect(history.processBuckets(in: historyTime(0)...historyTime(60)) == [minute])
}

@Test func equalValuesRankInIdentityOrder() throws {
  var history = TieredHistory(
    configuration: HistoryConfiguration(
      systemTiers: [HistoryTier(resolution: 2, span: 600)], processTiers: [HistoryTier(resolution: 60, span: 600)],
      processesPerMetric: 2))
  let tied = (Int32(1)...6).reversed().map { historyProcess($0, cpu: 50) }
  history.append(processes: tied, at: historyTime(0))
  let minute = try #require(history.append(processes: [], at: historyTime(61)).completedProcessBuckets.first)
  #expect(minute.entries.map(\.identity.pid) == [1, 2])
}

@Test func processMemoryIsThePeakAndOtherMetricsAreMeans() throws {
  var history = TieredHistory()
  history.append(processes: [historyProcess(7, cpu: 100, footprint: 300)], at: historyTime(0))
  history.append(processes: [historyProcess(7, cpu: 50, footprint: 900)], at: historyTime(20))
  history.append(processes: [historyProcess(7, cpu: nil, footprint: 600)], at: historyTime(40))
  let entry = try #require(history.append(HistorySystemPoint(time: historyTime(60))).completedProcessBuckets.first?.entries.first)
  #expect(entry[.cpu] == 75)
  #expect(entry[.memory] == 900)
  #expect(entry[.watts] == nil)
  #expect(entry.sampleCount == 3)
}

@Test func weeklyRetentionFoldsMinutesIntoFiveMinuteIntervals() throws {
  var history = TieredHistory(configuration: HistoryConfiguration(retention: .week))
  for minute in 0..<11 {
    let time = historyTime(Double(minute) * 60)
    history.append(HistorySystemPoint(time: time, cpu: 0.1))
    history.append(processes: [historyProcess(1, cpu: Double(minute + 1)), historyProcess(2, cpu: 1)], at: time)
  }
  history.append(HistorySystemPoint(time: historyTime(11 * 60)))
  let week = history.processBuckets(in: historyTime(-6 * 86_400)...historyTime(660))
  #expect(week.map(\.duration) == [300, 300])
  let first = try #require(week.first?.entries.first { $0.identity.pid == 1 })
  #expect(first[.cpu] == 3)
  #expect(first.sampleCount == 5)
  #expect(history.points(in: historyTime(-6 * 86_400)...historyTime(660)).allSatisfy { $0.duration == 300 })
}

@Test func topProcessesAggregateAcrossMinutes() {
  var history = TieredHistory()
  for minute in 0..<3 {
    let time = historyTime(Double(minute) * 60)
    history.append(
      processes: [historyProcess(1, cpu: 10), historyProcess(2, cpu: minute == 0 ? 90 : 0), historyProcess(3, cpu: 40)],
      at: time)
  }
  history.append(HistorySystemPoint(time: historyTime(180)))
  let top = history.topProcesses(in: historyTime(0)...historyTime(180), by: .cpu, limit: 2)
  #expect(top.map(\.identity.pid) == [3, 2])
  #expect(top.first?[.cpu] == 40)
}

@Test func processPointsKeepOnlyNamesAndProjects() {
  let point = HistoryProcessPoint(
    identity: historyIdentity(4), name: "/Applications/Xcode.app/Contents/MacOS/Xcode",
    project: "/Users/someone/Developer/strata-bar")
  #expect(point.name == "Xcode")
  #expect(point.project == "strata-bar")
  let sample = ProcessSample(
    id: historyIdentity(5), parentPID: 1, userID: 501, name: "bun", path: "/opt/bun/bin/bun",
    cpuTimeNanoseconds: nil, cpuPercent: 42, residentBytes: nil, footprintBytes: 2_048, threads: 3,
    diskReadBytesPerSecond: 10, diskWrittenBytesPerSecond: nil)
  let converted = HistoryProcessPoint(sample, project: "culprit")
  #expect(converted.name == "bun")
  #expect(converted.cpuPercent == 42)
  #expect(converted.diskBytesPerSecond == 10)
  #expect(converted.footprintBytes == 2_048)
}

@Test func systemPointsMapFromSamplesWithoutInventingValues() {
  let memory = MemorySample(
    total: 100, active: 30, wired: 10, compressed: 10, cached: 0, free: 50, swap: 7, pressure: .unavailable)
  let sample = SystemSample(
    uptime: 12, cpu: 0.25, cores: [], memory: memory, network: nil, interfaces: [], processes: [],
    thermalPressure: .elevated)
  let point = HistorySystemPoint(sample, time: historyTime(0), systemWatts: 9)
  #expect(point.cpu == 0.25)
  #expect(point.memoryUsedFraction == 0.5)
  #expect(point.memoryPressure == nil)
  #expect(point.swapBytes == 7)
  #expect(point.networkInBytesPerSecond == nil)
  #expect(point.thermal == .elevated)
  #expect(point.systemWatts == 9)
  #expect(point.gpu == nil)
}

@Test func aBusyDayStaysWithinTheDocumentedMemoryBound() {
  var history = TieredHistory()
  for second in stride(from: 0.0, to: 86_400, by: 10) {
    history.append(
      HistorySystemPoint(
        time: historyTime(second), uptime: second, cpu: 0.3, memoryUsedFraction: 0.6, memoryPressure: .normal,
        swapBytes: 1e9, networkInBytesPerSecond: 1e5, networkOutBytesPerSecond: 1e4,
        diskReadBytesPerSecond: 1e6, diskWriteBytesPerSecond: 1e6, gpu: 0.1, systemWatts: 8, thermal: .normal))
    guard second.truncatingRemainder(dividingBy: 60) == 0 else { continue }
    history.append(processes: simulatedProcesses(at: second), at: historyTime(second))
  }
  let footprint = history.footprint
  let configuration = history.configuration
  #expect(footprint.systemPoints <= configuration.systemTiers.reduce(0) { $0 + $1.capacity })
  #expect(footprint.processBuckets <= configuration.processTiers.reduce(0) { $0 + $1.capacity })
  #expect(footprint.processEntries <= footprint.processBuckets * 5 * configuration.processesPerMetric)
  #expect(footprint.catalogedProcesses <= footprint.processEntries)
  #expect(footprint.estimatedBytes < 4_000_000)
  history.removeAll()
  #expect(history.footprint.systemPoints == 0)
  #expect(history.latestTime == nil)
}

/// About 150 processes, a few of them short-lived, with distinct leaders per metric.
func simulatedProcesses(at second: Double) -> [HistoryProcessPoint] {
  let generation = UInt64(second / 600)
  return (Int32(1)...150).map { pid in
    let transient = pid > 140
    let phase = Double(pid) + second / 60
    return historyProcess(
      pid, name: transient ? "clang" : "com.example.long-process-name-\(pid)", generation: transient ? generation : 0,
      cpu: (sin(phase) + 1) * Double(pid % 17), footprint: UInt64(pid) * 20_000_000 + UInt64(second),
      watts: pid % 3 == 0 ? (cos(phase) + 1.1) * 0.5 : nil, disk: pid % 5 == 0 ? Double(pid) * 1_000 : 0,
      network: pid % 7 == 0 ? (sin(phase * 2) + 1) * 10_000 : nil)
  }
}
