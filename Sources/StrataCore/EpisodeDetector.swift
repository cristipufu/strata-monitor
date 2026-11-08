import Foundation

/// Episode values use the units of their signal: CPU in percent of one core,
/// power in watts, wakeups per second, memory growth in bytes above the
/// footprint where it started, system CPU as a share of the machine and memory
/// pressure as a `HistoryPressure` raw value.
public enum EpisodeKind: UInt8, CaseIterable, Sendable {
  case cpu, watts, memoryGrowth, wakeups, systemCPU, memoryPressure
}

public struct Episode: Identifiable, Equatable, Sendable {
  public struct ID: Hashable, Sendable {
    public let kind: EpisodeKind
    public let process: ProcessIdentity?
    public let start: Date
  }

  public let kind: EpisodeKind
  public let process: HistoryProcessLabel?
  public let start: Date
  public let end: Date?
  public let lastObserved: Date
  public let peak: Double
  public let average: Double

  public init(
    kind: EpisodeKind, process: HistoryProcessLabel?, start: Date, end: Date?, lastObserved: Date,
    peak: Double, average: Double
  ) {
    self.kind = kind
    self.process = process
    self.start = start
    self.end = end
    self.lastObserved = lastObserved
    self.peak = peak
    self.average = average
  }

  public var id: ID { ID(kind: kind, process: process?.identity, start: start) }
  public var isOngoing: Bool { end == nil }
  public var duration: TimeInterval { (end ?? lastObserved).timeIntervalSince(start) }

  /// Recording stopped while the episode was ongoing, so it ends where it was last seen.
  func interrupted() -> Episode {
    guard isOngoing else { return self }
    return Episode(
      kind: kind, process: process, start: start, end: lastObserved, lastObserved: lastObserved,
      peak: peak, average: average)
  }
}

public enum EpisodeChange: Equatable, Sendable {
  case started(Episode)
  case ended(Episode)

  public var episode: Episode {
    switch self {
    case let .started(episode), let .ended(episode): episode
    }
  }
}

public struct SustainedThreshold: Equatable, Sendable {
  public var level: Double
  public var duration: TimeInterval

  public init(level: Double, duration: TimeInterval) {
    self.level = level
    self.duration = duration
  }
}

public struct EpisodeThresholds: Equatable, Sendable {
  public var cpuPercent = SustainedThreshold(level: 150, duration: 180)
  public var watts = SustainedThreshold(level: 3, duration: 300)
  public var wakeupsPerSecond = SustainedThreshold(level: 300, duration: 300)
  public var memoryGrowthBytes: Double = 2 * 1_073_741_824
  public var memoryGrowthWindow: TimeInterval = 600
  public var systemCPU = SustainedThreshold(level: 0.9, duration: 180)
  public var memoryPressure = HistoryPressure.elevated
  public var memoryPressureDuration: TimeInterval = 120
  /// An episode ends only below `level × releaseFraction`, which keeps a value
  /// hovering at the threshold from starting and ending episodes repeatedly.
  public var releaseFraction = 0.8
  /// Dips shorter than this neither cancel a starting episode nor end a running one.
  public var releaseDuration: TimeInterval = 30
  /// A longer silence, such as sleep, ends episodes at their last observation.
  public var maximumGap: TimeInterval = 60
  public var maximumClosedEpisodes = 200

  public init() {}

  var sustainedMemoryPressure: SustainedThreshold {
    SustainedThreshold(level: Double(memoryPressure.rawValue), duration: memoryPressureDuration)
  }
}

public struct EpisodeDetector: Sendable {
  public let thresholds: EpisodeThresholds
  public private(set) var closedEpisodes: [Episode] = []
  private var processes: [ProcessIdentity: ProcessEpisodeState] = [:]
  private var processesWithEpisodes: Set<ProcessIdentity> = []
  private var systemCPU: SustainedTracker?
  private var memoryPressure: SustainedTracker?
  private var lastSystemTime: Double?
  private var lastProcessTime: Double?

  public init(thresholds: EpisodeThresholds = EpisodeThresholds()) {
    self.thresholds = thresholds
  }

  public var ongoingEpisodes: [Episode] {
    let system = [
      systemCPU.flatMap { $0.isActive ? $0.episode(.systemCPU, process: nil) : nil },
      memoryPressure.flatMap { $0.isActive ? $0.episode(.memoryPressure, process: nil) : nil },
    ].compactMap { $0 }
    let perProcess = processesWithEpisodes.flatMap { processes[$0]?.ongoingEpisodes() ?? [] }
    return (system + perProcess).sorted { $0.start < $1.start }
  }

  public var episodes: [Episode] { closedEpisodes + ongoingEpisodes }

  public mutating func observe(system point: HistorySystemPoint) -> [EpisodeChange] {
    let time = point.time.timeIntervalSinceReferenceDate
    guard time.isFinite, lastSystemTime.map({ time > $0 }) ?? true else { return [] }
    var changes: [EpisodeChange] = []
    if let last = lastSystemTime, time - last > thresholds.maximumGap {
      changes += Self.interrupt(&systemCPU, .systemCPU) + Self.interrupt(&memoryPressure, .memoryPressure)
    }
    lastSystemTime = time
    changes += SustainedTracker.advance(
      &systemCPU, .systemCPU, process: nil, value: point.cpu, at: time, threshold: thresholds.systemCPU,
      thresholds: thresholds)
    changes += SustainedTracker.advance(
      &memoryPressure, .memoryPressure, process: nil, value: point.memoryPressure.map { Double($0.rawValue) },
      at: time, threshold: thresholds.sustainedMemoryPressure, thresholds: thresholds)
    return recordEnded(changes)
  }

  /// `processes` must be a complete snapshot: a process missing from it has
  /// ended, so its episodes end where it was last seen.
  public mutating func observe(processes points: [HistoryProcessPoint], at date: Date) -> [EpisodeChange] {
    let time = date.timeIntervalSinceReferenceDate
    guard time.isFinite, lastProcessTime.map({ time > $0 }) ?? true else { return [] }
    var changes: [EpisodeChange] = []
    if let last = lastProcessTime, time - last > thresholds.maximumGap {
      changes += endAllProcesses()
    }
    lastProcessTime = time
    var observed = 0
    for point in points {
      guard
        let observation = processes[point.identity, default: ProcessEpisodeState(process: point.label)]
          .observe(point, at: time, thresholds: thresholds)
      else { continue }
      observed += 1
      guard !observation.isEmpty else { continue }
      changes += observation
      if processes[point.identity]?.hasOngoingEpisode == true {
        processesWithEpisodes.insert(point.identity)
      } else {
        processesWithEpisodes.remove(point.identity)
      }
    }
    if observed < processes.count { changes += endProcesses(notSeenAt: time) }
    return recordEnded(changes)
  }

  /// Restores episodes recorded earlier; any that were ongoing end at their last observation.
  public mutating func restore(_ episodes: [Episode]) {
    let restored = episodes.map { $0.interrupted() }
    closedEpisodes = (restored + closedEpisodes).sorted { $0.start < $1.start }
    trimClosedEpisodes()
  }

  public mutating func removeEpisodes(endingBefore date: Date) {
    closedEpisodes.removeAll { ($0.end ?? $0.lastObserved) < date }
  }

  public mutating func reset() {
    closedEpisodes = []
    processes = [:]
    processesWithEpisodes = []
    systemCPU = nil
    memoryPressure = nil
    lastSystemTime = nil
    lastProcessTime = nil
  }

  private static func interrupt(_ tracker: inout SustainedTracker?, _ kind: EpisodeKind) -> [EpisodeChange] {
    defer { tracker = nil }
    guard let tracker, tracker.isActive else { return [] }
    return [.ended(tracker.endedEpisode(kind, process: nil))]
  }

  private mutating func endProcesses(notSeenAt time: Double) -> [EpisodeChange] {
    var ended: [ProcessIdentity] = []
    for (identity, state) in processes where state.lastSeen < time { ended.append(identity) }
    return ended.sorted { $0.pid < $1.pid }.flatMap { identity in
      processesWithEpisodes.remove(identity)
      return processes.removeValue(forKey: identity)?.interruptAll() ?? []
    }
  }

  private mutating func endAllProcesses() -> [EpisodeChange] {
    let identities = processes.keys.sorted { $0.pid < $1.pid }
    defer {
      processes = [:]
      processesWithEpisodes = []
    }
    return identities.flatMap { processes[$0]?.interruptAll() ?? [] }
  }

  private mutating func recordEnded(_ changes: [EpisodeChange]) -> [EpisodeChange] {
    for case let .ended(episode) in changes { closedEpisodes.append(episode) }
    trimClosedEpisodes()
    return changes
  }

  private mutating func trimClosedEpisodes() {
    let excess = closedEpisodes.count - max(0, thresholds.maximumClosedEpisodes)
    if excess > 0 { closedEpisodes.removeFirst(excess) }
  }
}

struct EpisodeStatistics: Sendable {
  private(set) var sum = 0.0
  private(set) var count = 0
  private(set) var peak = -Double.infinity

  var average: Double { count > 0 ? sum / Double(count) : 0 }

  mutating func add(_ value: Double) {
    sum += value
    count += 1
    peak = max(peak, value)
  }

  mutating func add(_ other: EpisodeStatistics) {
    sum += other.sum
    count += other.count
    peak = max(peak, other.peak)
  }
}

/// Schmitt trigger with debounce: a signal at or above the level for the
/// threshold's duration starts an episode, and only a stretch below the
/// release level lasting `releaseDuration` ends it.
struct SustainedTracker: Sendable {
  let start: Double
  private(set) var lastObserved: Double
  private(set) var isActive = false
  private var lowSince: Double?
  private var statistics = EpisodeStatistics()
  private var lowStatistics = EpisodeStatistics()

  private enum Step {
    case continuing, started, ended, cancelled
  }

  /// Advances `tracker` with one observation. A missing value is no observation:
  /// it ends an episode only once the silence exceeds the maximum gap.
  static func advance(
    _ tracker: inout SustainedTracker?, _ kind: EpisodeKind, process: HistoryProcessLabel?, value: Double?,
    at time: Double, threshold: SustainedThreshold, thresholds: EpisodeThresholds
  ) -> [EpisodeChange] {
    guard let value, value.isFinite else {
      guard let current = tracker, time - current.lastObserved > thresholds.maximumGap else { return [] }
      tracker = nil
      return current.isActive ? [.ended(current.endedEpisode(kind, process: process))] : []
    }
    guard var current = tracker ?? (value >= threshold.level ? SustainedTracker(at: time) : nil) else {
      return []
    }
    switch current.observe(value, at: time, threshold: threshold, thresholds: thresholds) {
    case .continuing:
      tracker = current
      return []
    case .started:
      tracker = current
      return [.started(current.episode(kind, process: process))]
    case .ended:
      tracker = nil
      return [.ended(current.endedEpisode(kind, process: process))]
    case .cancelled:
      tracker = nil
      return []
    }
  }

  private init(at time: Double) {
    start = time
    lastObserved = time
  }

  private mutating func observe(
    _ value: Double, at time: Double, threshold: SustainedThreshold, thresholds: EpisodeThresholds
  ) -> Step {
    lastObserved = time
    let releaseLevel = isActive ? threshold.level * thresholds.releaseFraction : threshold.level
    if value < releaseLevel {
      let since = lowSince ?? time
      lowSince = since
      lowStatistics.add(value)
      guard time - since >= thresholds.releaseDuration else { return .continuing }
      return isActive ? .ended : .cancelled
    }
    lowSince = nil
    statistics.add(lowStatistics)
    lowStatistics = EpisodeStatistics()
    statistics.add(value)
    guard !isActive, time - start >= threshold.duration else { return .continuing }
    isActive = true
    return .started
  }

  func episode(_ kind: EpisodeKind, process: HistoryProcessLabel?) -> Episode {
    Episode(
      kind: kind, process: process, start: Date(timeIntervalSinceReferenceDate: start), end: nil,
      lastObserved: Date(timeIntervalSinceReferenceDate: lastObserved), peak: statistics.peak,
      average: statistics.average)
  }

  /// A running low stretch is not part of the episode: it ends where that stretch began.
  func endedEpisode(_ kind: EpisodeKind, process: HistoryProcessLabel?) -> Episode {
    let end = Date(timeIntervalSinceReferenceDate: lowSince ?? lastObserved)
    return Episode(
      kind: kind, process: process, start: Date(timeIntervalSinceReferenceDate: start), end: end,
      lastObserved: Date(timeIntervalSinceReferenceDate: lastObserved), peak: statistics.peak,
      average: statistics.average)
  }
}

/// Minimum footprint per tenth of the growth window, so growth over the window
/// costs a few numbers per process rather than every reading.
struct FootprintWindow: Sendable {
  private struct Slot: Sendable {
    let start: Double
    var minimum: Double
    var minimumTime: Double
  }

  private var slots: [Slot] = []

  mutating func add(_ footprint: Double, at time: Double, window: TimeInterval) {
    let slotLength = max(1, window / 10)
    let start = (time / slotLength).rounded(.down) * slotLength
    if let last = slots.last, last.start == start {
      if footprint <= last.minimum { slots[slots.count - 1] = Slot(start: start, minimum: footprint, minimumTime: time) }
      return
    }
    slots.append(Slot(start: start, minimum: footprint, minimumTime: time))
    slots.removeAll { $0.start + slotLength <= time - window }
  }

  /// The lowest footprint and the last time it was seen there, where growth began.
  var minimum: (footprint: Double, time: Double)? {
    slots.min { ($0.minimum, -$0.minimumTime) < ($1.minimum, -$1.minimumTime) }.map { ($0.minimum, $0.minimumTime) }
  }
}

struct GrowthEpisode: Sendable {
  let start: Double
  let baseline: Double
  private(set) var peakGrowth: Double
  private(set) var peakTime: Double
  private(set) var lastObserved: Double
  private var statistics = EpisodeStatistics()

  init(start: Double, baseline: Double, footprint: Double, at time: Double) {
    self.start = start
    self.baseline = baseline
    peakGrowth = footprint - baseline
    peakTime = time
    lastObserved = time
    statistics.add(peakGrowth)
  }

  mutating func add(_ footprint: Double, at time: Double) {
    let growth = footprint - baseline
    lastObserved = time
    statistics.add(growth)
    if growth > peakGrowth {
      peakGrowth = growth
      peakTime = time
    }
  }

  func episode(process: HistoryProcessLabel, ended: Bool) -> Episode {
    Episode(
      kind: .memoryGrowth, process: process, start: Date(timeIntervalSinceReferenceDate: start),
      end: ended ? Date(timeIntervalSinceReferenceDate: peakTime) : nil,
      lastObserved: Date(timeIntervalSinceReferenceDate: lastObserved), peak: peakGrowth,
      average: statistics.average)
  }
}

struct ProcessEpisodeState: Sendable {
  let process: HistoryProcessLabel
  private(set) var lastSeen = -Double.infinity
  private var cpu: SustainedTracker?
  private var watts: SustainedTracker?
  private var wakeups: SustainedTracker?
  private var footprints = FootprintWindow()
  private var growth: GrowthEpisode?
  // A restarted episode never reuses the low point of the one before, so episodes stay distinct.
  private var lastGrowthEnd: Double?

  init(process: HistoryProcessLabel) { self.process = process }

  /// Returns nil for a second observation at the same time, such as a
  /// duplicate in one snapshot.
  mutating func observe(
    _ point: HistoryProcessPoint, at time: Double, thresholds: EpisodeThresholds
  ) -> [EpisodeChange]? {
    guard lastSeen < time else { return nil }
    lastSeen = time
    var changes = SustainedTracker.advance(
      &cpu, .cpu, process: process, value: point.cpuPercent, at: time, threshold: thresholds.cpuPercent,
      thresholds: thresholds)
    changes += SustainedTracker.advance(
      &watts, .watts, process: process, value: point.watts, at: time, threshold: thresholds.watts,
      thresholds: thresholds)
    changes += SustainedTracker.advance(
      &wakeups, .wakeups, process: process, value: point.wakeupsPerSecond, at: time,
      threshold: thresholds.wakeupsPerSecond, thresholds: thresholds)
    if let footprint = point.footprintBytes {
      changes += observeFootprint(Double(footprint), at: time, thresholds: thresholds)
    }
    return changes
  }

  var hasOngoingEpisode: Bool {
    cpu?.isActive == true || watts?.isActive == true || wakeups?.isActive == true || growth != nil
  }

  func ongoingEpisodes() -> [Episode] {
    let sustained = activeTrackers.map { $0.tracker.episode($0.kind, process: process) }
    return sustained + [growth?.episode(process: process, ended: false)].compactMap { $0 }
  }

  func interruptAll() -> [EpisodeChange] {
    let sustained = activeTrackers.map { EpisodeChange.ended($0.tracker.endedEpisode($0.kind, process: process)) }
    return sustained + [growth.map { .ended($0.episode(process: process, ended: true)) }].compactMap { $0 }
  }

  private var activeTrackers: [(kind: EpisodeKind, tracker: SustainedTracker)] {
    [(EpisodeKind.cpu, cpu), (.watts, watts), (.wakeups, wakeups)].compactMap { kind, tracker in
      tracker.flatMap { $0.isActive ? (kind, $0) : nil }
    }
  }

  private mutating func observeFootprint(
    _ footprint: Double, at time: Double, thresholds: EpisodeThresholds
  ) -> [EpisodeChange] {
    footprints.add(footprint, at: time, window: thresholds.memoryGrowthWindow)
    // Growing by the threshold needs at least that much footprint, which spares
    // nearly every process the window scan.
    guard growth != nil || footprint >= thresholds.memoryGrowthBytes, let minimum = footprints.minimum else {
      return []
    }
    let trailingGrowth = footprint - minimum.footprint
    guard var running = growth else {
      guard trailingGrowth >= thresholds.memoryGrowthBytes else { return [] }
      let start = max(minimum.time, lastGrowthEnd ?? minimum.time)
      let started = GrowthEpisode(start: start, baseline: minimum.footprint, footprint: footprint, at: time)
      growth = started
      return [.started(started.episode(process: process, ended: false))]
    }
    running.add(footprint, at: time)
    guard trailingGrowth < thresholds.memoryGrowthBytes * thresholds.releaseFraction else {
      growth = running
      return []
    }
    growth = nil
    lastGrowthEnd = time
    return [.ended(running.episode(process: process, ended: true))]
  }
}
