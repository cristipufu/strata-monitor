import Foundation

typealias ProcessValues = InlineArray<5, Float>

/// CPU, power, disk and network are means over the interval; memory is the
/// interval's peak footprint.
public struct HistoryProcessEntry: Equatable, Sendable {
  public let identity: ProcessIdentity
  public let name: String
  public let project: String?
  public let sampleCount: Int
  let values: ProcessValues

  public init(
    identity: ProcessIdentity, name: String, project: String?, sampleCount: Int,
    cpuPercent: Double? = nil, footprintBytes: Double? = nil, watts: Double? = nil,
    diskBytesPerSecond: Double? = nil, networkBytesPerSecond: Double? = nil
  ) {
    var values = ProcessValues(repeating: .nan)
    let measured = [cpuPercent, footprintBytes, watts, diskBytesPerSecond, networkBytesPerSecond]
    for metric in HistoryProcessMetric.all {
      values[metric.rawValue] = SummaryAccumulator.storable(measured[metric.rawValue]) ?? .nan
    }
    self.init(identity: identity, name: name, project: project, sampleCount: sampleCount, values: values)
  }

  init(identity: ProcessIdentity, name: String, project: String?, sampleCount: Int, values: ProcessValues) {
    self.identity = identity
    self.name = name
    self.project = project
    self.sampleCount = max(1, sampleCount)
    self.values = values
  }

  public subscript(metric: HistoryProcessMetric) -> Double? {
    let value = values[metric.rawValue]
    return value.isNaN ? nil : Double(value)
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.identity == rhs.identity && lhs.name == rhs.name && lhs.project == rhs.project
      && lhs.sampleCount == rhs.sampleCount
      && HistoryProcessMetric.all.allSatisfy { lhs[$0] == rhs[$0] }
  }
}

public struct HistoryProcessBucket: Equatable, Sendable {
  public let time: Date
  public let duration: TimeInterval
  public let entries: [HistoryProcessEntry]

  public init(time: Date, duration: TimeInterval, entries: [HistoryProcessEntry]) {
    self.time = time
    self.duration = duration
    self.entries = entries
  }
}

struct ProcessValuesAccumulator: Sendable {
  private(set) var sampleCount = 0
  private var sums = InlineArray<5, Double>(repeating: 0)
  private var weights = InlineArray<5, Double>(repeating: 0)
  private var peakMemory: Float = -.infinity

  mutating func add(_ values: ProcessValues, sampleCount: Int) {
    let weight = Double(sampleCount)
    self.sampleCount += sampleCount
    for index in values.indices where !values[index].isNaN {
      sums[index] += Double(values[index]) * weight
      weights[index] += weight
    }
    let memory = values[HistoryProcessMetric.memory.rawValue]
    if !memory.isNaN { peakMemory = max(peakMemory, memory) }
  }

  func values() -> ProcessValues {
    var values = ProcessValues(repeating: .nan)
    for index in values.indices where weights[index] > 0 {
      values[index] = Float(sums[index] / weights[index])
    }
    if peakMemory.isFinite { values[HistoryProcessMetric.memory.rawValue] = peakMemory }
    return values
  }

  static func values(of point: HistoryProcessPoint) -> ProcessValues {
    var values = ProcessValues(repeating: .nan)
    for metric in HistoryProcessMetric.all {
      values[metric.rawValue] = SummaryAccumulator.storable(point[metric]) ?? .nan
    }
    return values
  }
}

enum ProcessRanking {
  /// Positions of the candidates that rank within `limit` for at least one
  /// metric, leaders of the first metric first. Equal values keep the order
  /// given by `precedes`, so the result does not depend on dictionary order.
  static func leaders(
    _ candidates: [ProcessValues], limit: Int, precedes: (Int, Int) -> Bool
  ) -> [Int] {
    var chosen = Set<Int>()
    var order: [Int] = []
    for metric in HistoryProcessMetric.all {
      for position in top(candidates, metric: metric.rawValue, limit: limit, precedes: precedes)
      where chosen.insert(position).inserted {
        order.append(position)
      }
    }
    return order
  }

  private static func top(
    _ candidates: [ProcessValues], metric: Int, limit: Int, precedes: (Int, Int) -> Bool
  ) -> [Int] {
    var leaders: [Int] = []
    leaders.reserveCapacity(limit + 1)
    func ranksAbove(_ lhs: Int, _ rhs: Int) -> Bool {
      let left = candidates[lhs][metric]
      let right = candidates[rhs][metric]
      return left == right ? precedes(lhs, rhs) : left > right
    }
    for position in candidates.indices {
      let value = candidates[position][metric]
      guard value > 0 else { continue }
      if leaders.count == limit, let last = leaders.last, !ranksAbove(position, last) { continue }
      var insertion = leaders.endIndex
      while insertion > 0, ranksAbove(position, leaders[insertion - 1]) { insertion -= 1 }
      leaders.insert(position, at: insertion)
      if leaders.count > limit { leaders.removeLast() }
    }
    return leaders
  }
}

/// Raw observations for the interval in progress at the finest process tier.
struct ProcessIntervalAccumulator: Sendable {
  private struct Labeled: Sendable {
    var name: String
    var project: String?
    var values = ProcessValuesAccumulator()
  }

  let start: Double
  let duration: TimeInterval
  private var processes: [ProcessIdentity: Labeled] = [:]

  init(start: Double, duration: TimeInterval) {
    self.start = start
    self.duration = duration
  }

  mutating func add(_ point: HistoryProcessPoint) {
    let values = ProcessValuesAccumulator.values(of: point)
    processes[point.identity, default: Labeled(name: point.name, project: point.project)]
      .values.add(values, sampleCount: 1)
  }

  func ranked(limit: Int) -> HistoryProcessBucket {
    var identities: [ProcessIdentity] = []
    var values: [ProcessValues] = []
    identities.reserveCapacity(processes.count)
    values.reserveCapacity(processes.count)
    for (identity, process) in processes {
      identities.append(identity)
      values.append(process.values.values())
    }
    let leaders = ProcessRanking.leaders(values, limit: limit) {
      Self.precedes(identities[$0], identities[$1])
    }
    let entries = leaders.compactMap { position -> HistoryProcessEntry? in
      guard let process = processes[identities[position]] else { return nil }
      return HistoryProcessEntry(
        identity: identities[position], name: process.name, project: process.project,
        sampleCount: process.values.sampleCount, values: values[position])
    }
    return HistoryProcessBucket(
      time: Date(timeIntervalSinceReferenceDate: start), duration: duration, entries: entries)
  }

  private static func precedes(_ lhs: ProcessIdentity, _ rhs: ProcessIdentity) -> Bool {
    (lhs.pid, lhs.startSeconds, lhs.startMicroseconds) < (rhs.pid, rhs.startSeconds, rhs.startMicroseconds)
  }
}

struct StoredProcessEntry: Sendable {
  let slot: Int32
  let sampleCount: Int32
  let values: ProcessValues
}

struct StoredProcessBucket: Sendable {
  let start: Double
  let duration: TimeInterval
  let entries: [StoredProcessEntry]
}

/// Process names live once per identity instead of once per minute.
struct ProcessCatalog: Sendable {
  struct Record: Sendable {
    let identity: ProcessIdentity
    var name: String
    var project: String?
    var lastReferenced: Double
  }

  private var records: [Record?] = []
  private var slots: [ProcessIdentity: Int32] = [:]
  private var vacant: [Int32] = []

  var count: Int { slots.count }

  mutating func slot(for entry: HistoryProcessEntry, referencedAt time: Double) -> Int32 {
    if let slot = slots[entry.identity], var record = records[Int(slot)] {
      record.name = entry.name
      record.project = entry.project
      record.lastReferenced = max(record.lastReferenced, time)
      records[Int(slot)] = record
      return slot
    }
    let record = Record(
      identity: entry.identity, name: entry.name, project: entry.project, lastReferenced: time)
    let slot: Int32
    if let reused = vacant.popLast() {
      slot = reused
      records[Int(slot)] = record
    } else {
      slot = Int32(records.count)
      records.append(record)
    }
    slots[entry.identity] = slot
    return slot
  }

  func record(at slot: Int32) -> Record? {
    records.indices.contains(Int(slot)) ? records[Int(slot)] : nil
  }

  mutating func removeRecords(referencedBefore time: Double) {
    for index in records.indices {
      guard let record = records[index], record.lastReferenced < time else { continue }
      records[index] = nil
      slots[record.identity] = nil
      vacant.append(Int32(index))
    }
  }

  mutating func removeAll() {
    records = []
    slots = [:]
    vacant = []
  }

  var estimatedBytes: Int {
    let strings = records.reduce(0) { total, record in
      guard let record else { return total }
      return total + Self.heapBytes(record.name) + (record.project.map(Self.heapBytes) ?? 0)
    }
    let dictionaryEntry = MemoryLayout<ProcessIdentity>.stride + MemoryLayout<Int32>.stride
    return records.count * MemoryLayout<Record?>.stride + slots.capacity * dictionaryEntry
      + vacant.capacity * MemoryLayout<Int32>.stride + strings
  }

  /// Strings of up to 15 UTF-8 bytes are stored inline.
  private static func heapBytes(_ text: String) -> Int {
    let length = text.utf8.count
    return length > 15 ? 32 + length : 0
  }
}

struct ProcessTierBuffer: Sendable {
  let tier: HistoryTier
  private(set) var closed: TimeRing<StoredProcessBucket>
  private var openStart: Double?
  private var open: [Int32: ProcessValuesAccumulator] = [:]

  init(tier: HistoryTier) {
    self.tier = tier
    closed = TimeRing(capacity: tier.capacity)
  }

  mutating func appendCompleted(_ bucket: StoredProcessBucket) {
    closed.append(bucket)
  }

  /// Folds a finer completed bucket into this tier's interval.
  mutating func fold(_ bucket: StoredProcessBucket, limit: Int) {
    let start = tier.bucketStart(containing: bucket.start)
    if let openStart, openStart != start { closeOpen(limit: limit) }
    openStart = start
    for entry in bucket.entries {
      open[entry.slot, default: ProcessValuesAccumulator()]
        .add(entry.values, sampleCount: Int(entry.sampleCount))
    }
  }

  var oldestStart: Double? { closed.first?.start }

  var entryCount: Int { closed.reduce(0) { $0 + $1.entries.count } }

  var estimatedBytes: Int {
    closed.count * MemoryLayout<StoredProcessBucket>.stride
      + entryCount * MemoryLayout<StoredProcessEntry>.stride
      + open.capacity * (MemoryLayout<Int32>.stride + MemoryLayout<ProcessValuesAccumulator>.stride)
  }

  mutating func removeAll() {
    closed.removeAll()
    openStart = nil
    open = [:]
  }

  private mutating func closeOpen(limit: Int) {
    guard let openStart else { return }
    let slots = open.keys.sorted()
    let values = slots.map { open[$0]?.values() ?? ProcessValues(repeating: .nan) }
    let leaders = ProcessRanking.leaders(values, limit: limit) { slots[$0] < slots[$1] }
    let entries = leaders.map { position in
      StoredProcessEntry(
        slot: slots[position], sampleCount: Int32(clamping: open[slots[position]]?.sampleCount ?? 1),
        values: values[position])
    }
    closed.append(StoredProcessBucket(start: openStart, duration: tier.resolution, entries: entries))
    open.removeAll(keepingCapacity: true)
  }
}
