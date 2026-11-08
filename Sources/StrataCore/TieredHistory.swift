import Foundation

public struct HistoryAppendResult: Sendable {
  public let isAccepted: Bool
  /// Finest-tier process intervals that ended with this append, ready to persist.
  public let completedProcessBuckets: [HistoryProcessBucket]

  static let rejected = HistoryAppendResult(isAccepted: false, completedProcessBuckets: [])
}

public struct HistoryFootprint: Equatable, Sendable {
  public let systemPoints: Int
  public let processBuckets: Int
  public let processEntries: Int
  public let catalogedProcesses: Int
  public let estimatedBytes: Int
}

/// System readings at several resolutions plus, per process interval, the
/// leading processes for each process metric.
///
/// Memory is bounded by the tiers: each system tier keeps at most
/// `capacity` summaries of `MemoryLayout<HistorySummaryPoint>.stride` bytes, each
/// process tier at most `capacity` intervals of `5 × processesPerMetric` entries,
/// and the catalog one name record per distinct process in those intervals.
/// With the daily defaults that is 2,463 summaries (about 0.3 MB) and at most
/// 72,050 process entries (about 2 MB) plus their names.
public struct TieredHistory: Sendable {
  public let configuration: HistoryConfiguration
  private var systemTiers: [SystemTierBuffer]
  private var processTiers: [ProcessTierBuffer]
  private var processInterval: ProcessIntervalAccumulator?
  private var catalog = ProcessCatalog()
  private var latestSystem: Double?
  private var latestProcesses: Double?
  /// The newest time any reading or restored interval reached; tier spans count back from it.
  private var newest: Double?

  public init(configuration: HistoryConfiguration = HistoryConfiguration()) {
    self.configuration = configuration
    systemTiers = configuration.systemTiers.map(SystemTierBuffer.init)
    processTiers = configuration.processTiers.map(ProcessTierBuffer.init)
  }

  public var latestTime: Date? { newest.map(Date.init(timeIntervalSinceReferenceDate:)) }

  /// A reading no later than the newest one is ignored, so a clock set backwards
  /// pauses recording until it passes the newest reading again.
  @discardableResult
  public mutating func append(_ point: HistorySystemPoint) -> HistoryAppendResult {
    let time = point.time.timeIntervalSinceReferenceDate
    guard time.isFinite, latestSystem.map({ time > $0 }) ?? true else { return .rejected }
    latestSystem = time
    advanceNewest(to: time)
    for index in systemTiers.indices { systemTiers[index].add(point, at: time) }
    return HistoryAppendResult(isAccepted: true, completedProcessBuckets: completeProcessInterval(before: time))
  }

  @discardableResult
  public mutating func append(processes: [HistoryProcessPoint], at date: Date) -> HistoryAppendResult {
    let time = date.timeIntervalSinceReferenceDate
    guard time.isFinite, latestProcesses.map({ time > $0 }) ?? true else { return .rejected }
    latestProcesses = time
    advanceNewest(to: time)
    let completed = completeProcessInterval(before: time)
    let finest = processTiers[0].tier
    if processInterval == nil {
      processInterval = ProcessIntervalAccumulator(
        start: finest.bucketStart(containing: time), duration: finest.resolution)
    }
    for process in processes { processInterval?.add(process) }
    return HistoryAppendResult(isAccepted: true, completedProcessBuckets: completed)
  }

  /// Adds a finest-tier process interval recorded earlier, such as one read
  /// back from disk. An interval not after the last one is ignored.
  @discardableResult
  public mutating func restore(_ bucket: HistoryProcessBucket) -> Bool {
    guard insertCompleted(bucket) else { return false }
    advanceNewest(to: bucket.time.timeIntervalSinceReferenceDate + bucket.duration)
    return true
  }

  public mutating func removeAll() {
    for index in systemTiers.indices { systemTiers[index].removeAll() }
    for index in processTiers.indices { processTiers[index].removeAll() }
    processInterval = nil
    catalog.removeAll()
    latestSystem = nil
    latestProcesses = nil
    newest = nil
  }

  /// Summaries overlapping `range` from the finest tier that reaches back to its
  /// start, at no finer than `resolution`, merged to at most `maximumCount`.
  public func points(
    in range: ClosedRange<Date>, resolution: TimeInterval = 0, maximumCount: Int = 360
  ) -> [HistorySummaryPoint] {
    guard let newest, maximumCount > 0 else { return [] }
    let tiers = systemTiers.map(\.tier)
    let buffer = systemTiers[tierIndex(covering: range.lowerBound, in: tiers, minimum: resolution, newest: newest)]
    let lower = max(range.lowerBound.timeIntervalSinceReferenceDate, newest - buffer.tier.span)
    let points = buffer.points(overlapping: lower, range.upperBound.timeIntervalSinceReferenceDate)
    return Self.merged(points, maximumCount: maximumCount)
  }

  /// Completed process intervals overlapping `range`, from the finest process
  /// tier that reaches back to its start.
  public func processBuckets(in range: ClosedRange<Date>) -> [HistoryProcessBucket] {
    guard let newest else { return [] }
    let tiers = processTiers.map(\.tier)
    let buffer = processTiers[tierIndex(covering: range.lowerBound, in: tiers, minimum: 0, newest: newest)]
    let lower = max(range.lowerBound.timeIntervalSinceReferenceDate, newest - buffer.tier.span)
    let upper = range.upperBound.timeIntervalSinceReferenceDate
    let first = buffer.closed.firstIndex(after: lower) { $0.start + $0.duration }
    return buffer.closed[first...].prefix { $0.start <= upper }.map(materialized)
  }

  /// Processes in the completed intervals of `range`, ranked by their total for
  /// `metric` (memory by its peak), each with its values over the intervals it led.
  public func topProcesses(
    in range: ClosedRange<Date>, by metric: HistoryProcessMetric, limit: Int = 10
  ) -> [HistoryProcessEntry] {
    var totals: [ProcessIdentity: (entry: HistoryProcessEntry, values: ProcessValuesAccumulator)] = [:]
    for bucket in processBuckets(in: range) {
      for entry in bucket.entries {
        totals[entry.identity, default: (entry, ProcessValuesAccumulator())]
          .values.add(entry.values, sampleCount: entry.sampleCount)
      }
    }
    let ranked = totals.values.compactMap { total -> (HistoryProcessEntry, Double)? in
      let entry = HistoryProcessEntry(
        identity: total.entry.identity, name: total.entry.name, project: total.entry.project,
        sampleCount: total.values.sampleCount, values: total.values.values())
      guard let value = entry[metric], value > 0 else { return nil }
      return (entry, metric == .memory ? value : value * Double(entry.sampleCount))
    }
    return ranked
      .sorted { ($0.1, $1.0.identity.pid) > ($1.1, $0.0.identity.pid) }
      .prefix(max(0, limit))
      .map(\.0)
  }

  public var footprint: HistoryFootprint {
    let systemPoints = systemTiers.reduce(0) { $0 + $1.closed.count }
    let processBuckets = processTiers.reduce(0) { $0 + $1.closed.count }
    let processEntries = processTiers.reduce(0) { $0 + $1.entryCount }
    let bytes =
      systemTiers.reduce(0) { $0 + $1.closed.capacityInUse * MemoryLayout<HistorySummaryPoint>.stride }
      + processTiers.reduce(0) { $0 + $1.estimatedBytes } + catalog.estimatedBytes
    return HistoryFootprint(
      systemPoints: systemPoints, processBuckets: processBuckets, processEntries: processEntries,
      catalogedProcesses: catalog.count, estimatedBytes: bytes)
  }

  private mutating func completeProcessInterval(before time: Double) -> [HistoryProcessBucket] {
    guard let interval = processInterval, interval.start + interval.duration <= time else { return [] }
    processInterval = nil
    let bucket = interval.ranked(limit: configuration.processesPerMetric)
    return insertCompleted(bucket) ? [bucket] : []
  }

  private mutating func advanceNewest(to time: Double) {
    newest = max(newest ?? time, time)
  }

  /// Keeps intervals in time order, which queries rely on.
  private mutating func insertCompleted(_ bucket: HistoryProcessBucket) -> Bool {
    let start = bucket.time.timeIntervalSinceReferenceDate
    guard start.isFinite, processTiers[0].closed.last.map({ start > $0.start }) ?? true else { return false }
    let entries = bucket.entries.prefix(configuration.processesPerMetric * HistoryProcessMetric.all.count)
      .map { entry in
        StoredProcessEntry(
          slot: catalog.slot(for: entry, referencedAt: start), sampleCount: Int32(clamping: entry.sampleCount),
          values: entry.values)
      }
    let stored = StoredProcessBucket(start: start, duration: bucket.duration, entries: entries)
    processTiers[0].appendCompleted(stored)
    for index in processTiers.indices.dropFirst() {
      processTiers[index].fold(stored, limit: configuration.processesPerMetric)
    }
    if let oldest = processTiers.compactMap(\.oldestStart).min() {
      catalog.removeRecords(referencedBefore: oldest)
    }
    return true
  }

  private func materialized(_ bucket: StoredProcessBucket) -> HistoryProcessBucket {
    let entries = bucket.entries.compactMap { entry -> HistoryProcessEntry? in
      guard let record = catalog.record(at: entry.slot) else { return nil }
      return HistoryProcessEntry(
        identity: record.identity, name: record.name, project: record.project,
        sampleCount: Int(entry.sampleCount), values: entry.values)
    }
    return HistoryProcessBucket(
      time: Date(timeIntervalSinceReferenceDate: bucket.start), duration: bucket.duration, entries: entries)
  }

  private func tierIndex(
    covering start: Date, in tiers: [HistoryTier], minimum resolution: TimeInterval, newest: Double
  ) -> Int {
    let eligible = tiers.indices.filter { tiers[$0].resolution >= resolution }
    let covering = eligible.first { newest - tiers[$0].span <= start.timeIntervalSinceReferenceDate }
    return covering ?? eligible.last ?? tiers.indices.last ?? 0
  }

  private static func merged(_ points: [HistorySummaryPoint], maximumCount: Int) -> [HistorySummaryPoint] {
    guard points.count > maximumCount else { return points }
    let groupSize = (points.count + maximumCount - 1) / maximumCount
    return stride(from: 0, to: points.count, by: groupSize).map { first in
      let group = points[first..<min(first + groupSize, points.count)]
      var accumulator = SummaryAccumulator(
        start: group[first].time.timeIntervalSinceReferenceDate, duration: group[first].duration)
      for point in group { accumulator.add(point) }
      return accumulator.summary()
    }
  }
}

struct SystemTierBuffer: Sendable {
  let tier: HistoryTier
  private(set) var closed: TimeRing<HistorySummaryPoint>
  private var open: SummaryAccumulator?

  init(tier: HistoryTier) {
    self.tier = tier
    closed = TimeRing(capacity: tier.capacity)
  }

  mutating func add(_ point: HistorySystemPoint, at time: Double) {
    let start = tier.bucketStart(containing: time)
    if open?.start != start {
      if let open { closed.append(open.summary()) }
      open = SummaryAccumulator(start: start, duration: tier.resolution)
    }
    open?.add(point)
  }

  func points(overlapping lower: Double, _ upper: Double) -> [HistorySummaryPoint] {
    let first = closed.firstIndex(after: lower) { $0.end.timeIntervalSinceReferenceDate }
    var points = closed[first...].prefix { $0.time.timeIntervalSinceReferenceDate <= upper }.map { $0 }
    if let open, open.start <= upper, open.start + tier.resolution > lower {
      points.append(open.summary())
    }
    return points
  }

  mutating func removeAll() {
    closed.removeAll()
    open = nil
  }
}

extension TimeRing {
  var capacityInUse: Int { isEmpty ? 0 : capacity }
}
