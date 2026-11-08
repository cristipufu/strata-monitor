import Foundation
import StrataCore
import Testing

private struct TimedChange {
  let time: Double
  let change: EpisodeChange
}

private func observe(
  _ detector: inout EpisodeDetector, from start: Double, through end: Double, step: Double = 2,
  _ snapshot: (Double) -> [HistoryProcessPoint]
) -> [TimedChange] {
  stride(from: start, through: end, by: step).flatMap { second in
    detector.observe(processes: snapshot(second), at: historyTime(second)).map { TimedChange(time: second, change: $0) }
  }
}

private func startedEpisodes(_ changes: [TimedChange]) -> [TimedChange] {
  changes.filter { if case .started = $0.change { true } else { false } }
}

private func endedEpisodes(_ changes: [TimedChange]) -> [TimedChange] {
  changes.filter { if case .ended = $0.change { true } else { false } }
}

@Test func sustainedCPUBecomesAnEpisodeWithItsPeakAndAverage() throws {
  var detector = EpisodeDetector()
  let changes = observe(&detector, from: 0, through: 300) { second in
    let cpu: Double = second < 240 ? (second == 100 ? 410 : 300) : 100
    return [historyProcess(9, name: "mds_stores", cpu: cpu)]
  }
  let started = try #require(startedEpisodes(changes).first)
  let ended = try #require(endedEpisodes(changes).first)
  #expect(started.time == 180)
  #expect(started.change.episode.isOngoing)
  #expect(ended.time == 270)
  let episode = ended.change.episode
  #expect(episode.kind == .cpu)
  #expect(episode.process?.name == "mds_stores")
  #expect(episode.start == historyTime(0))
  #expect(episode.end == historyTime(240))
  #expect(episode.peak == 410)
  #expect(abs(episode.average - (119 * 300 + 410) / 120) < 1e-9)
  #expect(episode.duration == 240)
  #expect(detector.closedEpisodes == [episode])
  #expect(detector.ongoingEpisodes.isEmpty)
}

@Test func briefBurstsDoNotBecomeEpisodes() {
  var detector = EpisodeDetector()
  let changes = observe(&detector, from: 0, through: 600) { second in
    [historyProcess(1, cpu: second < 120 ? 200 : 50)]
  }
  #expect(changes.isEmpty)
  #expect(detector.ongoingEpisodes.isEmpty)
}

@Test func shortDipsKeepAStartingEpisodeButLongDipsRestartIt() throws {
  var detector = EpisodeDetector()
  let changes = observe(&detector, from: 0, through: 400) { second in
    let shortDip = (60..<70).contains(second)
    let longDip = (60..<110).contains(second)
    return [historyProcess(1, cpu: shortDip ? 100 : 200), historyProcess(2, cpu: longDip ? 100 : 200)]
  }
  let started = startedEpisodes(changes)
  #expect(started.map(\.change.episode.process?.identity.pid) == [1, 2])
  #expect(started.map(\.time) == [180, 290])
  #expect(started.last?.change.episode.start == historyTime(110))
}

@Test func anEpisodeContinuesBetweenTheReleaseAndStartLevels() throws {
  var detector = EpisodeDetector()
  let changes = observe(&detector, from: 0, through: 800) { second in
    let cpu: Double = second < 200 ? 200 : second < 600 ? 130 : 110
    return [historyProcess(3, cpu: cpu)]
  }
  #expect(startedEpisodes(changes).map(\.time) == [180])
  let ended = try #require(endedEpisodes(changes).first)
  #expect(ended.time == 630)
  #expect(ended.change.episode.end == historyTime(600))
}

@Test func aProcessThatEndsClosesItsEpisodeWhereItWasLastSeen() throws {
  var detector = EpisodeDetector()
  let changes = observe(&detector, from: 0, through: 260) { second in
    second <= 200 ? [historyProcess(4, cpu: 300), historyProcess(5, cpu: 1)] : [historyProcess(5, cpu: 1)]
  }
  let ended = try #require(endedEpisodes(changes).first)
  #expect(ended.time == 202)
  #expect(ended.change.episode.end == historyTime(200))
  #expect(detector.ongoingEpisodes.isEmpty)
}

@Test func aReusedProcessIDIsADifferentProcess() throws {
  var detector = EpisodeDetector()
  let changes = observe(&detector, from: 0, through: 400) { second in
    [historyProcess(7, generation: second <= 200 ? 0 : 1, cpu: 300)]
  }
  let started = startedEpisodes(changes)
  let ended = endedEpisodes(changes)
  #expect(started.map(\.time) == [180, 382])
  #expect(started.map(\.change.episode.process?.identity) == [historyIdentity(7), historyIdentity(7, generation: 1)])
  #expect(ended.count == 1)
  #expect(ended.first?.change.episode.process?.identity == historyIdentity(7))
  #expect(ended.first?.change.episode.end == historyTime(200))
  #expect(detector.ongoingEpisodes.map(\.process?.identity) == [historyIdentity(7, generation: 1)])
}

@Test func aLongSilenceEndsEpisodesAtTheirLastObservation() throws {
  var detector = EpisodeDetector()
  var changes = observe(&detector, from: 0, through: 200) { _ in [historyProcess(8, cpu: 300)] }
  changes += observe(&detector, from: 600, through: 610) { _ in [historyProcess(8, cpu: 300)] }
  let ended = try #require(endedEpisodes(changes).first)
  #expect(ended.time == 600)
  #expect(ended.change.episode.end == historyTime(200))
  #expect(detector.ongoingEpisodes.isEmpty)
}

@Test func unavailableReadingsEndEpisodesOnlyAfterTheGap() throws {
  var detector = EpisodeDetector()
  let changes = observe(&detector, from: 0, through: 400) { second in
    [historyProcess(6, cpu: second <= 200 ? 300 : nil)]
  }
  #expect(startedEpisodes(changes).map(\.time) == [180])
  let ended = try #require(endedEpisodes(changes).first)
  #expect(ended.time == 262)
  #expect(ended.change.episode.end == historyTime(200))
}

@Test func memoryGrowthIsMeasuredFromWhereGrowthBegan() throws {
  let gibibyte: UInt64 = 1 << 30
  var detector = EpisodeDetector()
  let changes = observe(&detector, from: 0, through: 1_500) { second in
    let elapsed = UInt64(min(420, max(0, second - 60)))
    let footprint = gibibyte + elapsed * 3 * gibibyte / 420
    return [historyProcess(11, name: "Xcode", footprint: footprint)]
  }
  let started = try #require(startedEpisodes(changes).first)
  let ended = try #require(endedEpisodes(changes).first)
  #expect(started.time == 340)
  #expect(started.change.episode.start == historyTime(60))
  #expect(ended.time == 900)
  let episode = ended.change.episode
  #expect(episode.kind == .memoryGrowth)
  #expect(episode.end == historyTime(480))
  #expect(episode.peak == Double(3 * gibibyte))
  #expect(changes.count == 2)
}

@Test func powerAndWakeupThresholdsAreConfigurable() {
  var thresholds = EpisodeThresholds()
  thresholds.watts = SustainedThreshold(level: 1, duration: 20)
  thresholds.wakeupsPerSecond = SustainedThreshold(level: 100, duration: 40)
  var detector = EpisodeDetector(thresholds: thresholds)
  let changes = observe(&detector, from: 0, through: 60) { _ in
    [historyProcess(12, watts: 2), historyProcess(13, wakeups: 500), historyProcess(14, watts: 0.5, wakeups: 50)]
  }
  let started = startedEpisodes(changes).map { ($0.time, $0.change.episode.kind) }
  #expect(started.map(\.0) == [20, 40])
  #expect(started.map(\.1) == [.watts, .wakeups])
  #expect(EpisodeDetector().thresholds.cpuPercent == SustainedThreshold(level: 150, duration: 180))
}

@Test func systemSaturationAndMemoryPressureBecomeSystemEpisodes() throws {
  var detector = EpisodeDetector()
  var changes: [EpisodeChange] = []
  for second in stride(from: 0.0, through: 400, by: 2) {
    let pressure: HistoryPressure = second < 150 ? .critical : .normal
    changes += detector.observe(
      system: HistorySystemPoint(time: historyTime(second), cpu: second < 300 ? 0.95 : 0.2, memoryPressure: pressure))
  }
  let started = changes.compactMap { if case let .started(episode) = $0 { episode } else { nil } }
  let ended = changes.compactMap { if case let .ended(episode) = $0 { episode } else { nil } }
  #expect(started.map(\.kind) == [.memoryPressure, .systemCPU])
  #expect(started.allSatisfy { $0.process == nil })
  #expect(ended.map(\.kind) == [.memoryPressure, .systemCPU])
  let pressure = try #require(ended.first)
  #expect(pressure.end == historyTime(150))
  #expect(pressure.peak == Double(HistoryPressure.critical.rawValue))
  #expect(ended.last?.end == historyTime(300))
}

@Test func closedEpisodesAreBoundedToTheMostRecent() {
  var thresholds = EpisodeThresholds()
  thresholds.cpuPercent = SustainedThreshold(level: 100, duration: 0)
  thresholds.releaseDuration = 0
  thresholds.maximumClosedEpisodes = 3
  var detector = EpisodeDetector(thresholds: thresholds)
  let changes = observe(&detector, from: 0, through: 20) { second in
    [historyProcess(1, cpu: Int(second / 2).isMultiple(of: 2) ? 200 : 10)]
  }
  #expect(endedEpisodes(changes).count == 5)
  #expect(detector.closedEpisodes.map(\.start) == [historyTime(8), historyTime(12), historyTime(16)])
  detector.removeEpisodes(endingBefore: historyTime(15))
  #expect(detector.closedEpisodes.map(\.start) == [historyTime(16)])
  detector.reset()
  #expect(detector.episodes.isEmpty)
}

@Test func restoredEpisodesThatWereOngoingEndWhereTheyWereLastSeen() {
  var detector = EpisodeDetector()
  let ongoing = Episode(
    kind: .cpu, process: historyProcess(2).label, start: historyTime(0), end: nil,
    lastObserved: historyTime(300), peak: 400, average: 250)
  let closed = Episode(
    kind: .watts, process: historyProcess(3).label, start: historyTime(-100), end: historyTime(-50),
    lastObserved: historyTime(-50), peak: 5, average: 4)
  detector.restore([ongoing, closed])
  #expect(detector.closedEpisodes.map(\.end) == [historyTime(-50), historyTime(300)])
  #expect(detector.closedEpisodes.allSatisfy { !$0.isOngoing })
}

@Test func outOfOrderSnapshotsAreIgnored() {
  var detector = EpisodeDetector()
  _ = detector.observe(processes: [historyProcess(1, cpu: 300)], at: historyTime(10))
  #expect(detector.observe(processes: [], at: historyTime(5)).isEmpty)
  #expect(detector.observe(system: HistorySystemPoint(time: Date(timeIntervalSinceReferenceDate: .infinity))).isEmpty)
}

@Test func memoryGrowthThatRestartsWithinTheWindowIsANewEpisode() throws {
  let gibibyte: UInt64 = 1 << 30
  var detector = EpisodeDetector()
  // Grows by 3 GiB, falls back near the start, then grows again before the window forgets it.
  let changes = observe(&detector, from: 0, through: 500) { second in
    let footprint: UInt64 =
      switch second {
      case ..<60: gibibyte
      case ..<180: 4 * gibibyte
      case ..<240: gibibyte + gibibyte / 4
      default: 5 * gibibyte
      }
    return [historyProcess(11, name: "Xcode", footprint: footprint)]
  }
  let starts = startedEpisodes(changes).map(\.change.episode)
  #expect(starts.count == 2)
  #expect(Set(starts.map(\.id)).count == starts.count, "Each episode keeps its own identity")
}
