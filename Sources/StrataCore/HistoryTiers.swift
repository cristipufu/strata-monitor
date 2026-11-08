import Foundation

public struct HistoryTier: Hashable, Sendable {
  public let resolution: TimeInterval
  public let span: TimeInterval

  public init(resolution: TimeInterval, span: TimeInterval) {
    let resolution = resolution.isFinite ? max(1, resolution) : 60
    self.resolution = resolution
    self.span = span.isFinite ? max(resolution, span) : resolution
  }

  /// One extra bucket holds the partly elapsed interval at the start of the span.
  public var capacity: Int { Int((span / resolution).rounded(.up)) + 1 }

  func bucketStart(containing time: Double) -> Double {
    (time / resolution).rounded(.down) * resolution
  }
}

public enum HistoryRetention: String, CaseIterable, Codable, Sendable {
  case day, week

  public var duration: TimeInterval {
    switch self {
    case .day: 86_400
    case .week: 7 * 86_400
    }
  }
}

public struct HistoryConfiguration: Equatable, Sendable {
  public let systemTiers: [HistoryTier]
  public let processTiers: [HistoryTier]
  public let processesPerMetric: Int

  public init(retention: HistoryRetention = .day) {
    let daily = [
      HistoryTier(resolution: 2, span: 600),
      HistoryTier(resolution: 10, span: 7_200),
      HistoryTier(resolution: 60, span: 86_400),
    ]
    let minutes = HistoryTier(resolution: 60, span: 86_400)
    let weekly = HistoryTier(resolution: 300, span: HistoryRetention.week.duration)
    switch retention {
    case .day: self.init(systemTiers: daily, processTiers: [minutes])
    case .week: self.init(systemTiers: daily + [weekly], processTiers: [minutes, weekly])
    }
  }

  /// Tiers are ordered from finest to coarsest. An empty list becomes a single
  /// one-minute tier spanning a day, so a reading always has somewhere to go.
  public init(systemTiers: [HistoryTier], processTiers: [HistoryTier], processesPerMetric: Int = 10) {
    let fallback = HistoryTier(resolution: 60, span: HistoryRetention.day.duration)
    let byResolution: (HistoryTier, HistoryTier) -> Bool = { $0.resolution < $1.resolution }
    self.systemTiers = systemTiers.isEmpty ? [fallback] : systemTiers.sorted(by: byResolution)
    self.processTiers = processTiers.isEmpty ? [fallback] : processTiers.sorted(by: byResolution)
    self.processesPerMetric = max(1, processesPerMetric)
  }

  public var retentionSpan: TimeInterval {
    (systemTiers + processTiers).map(\.span).max() ?? HistoryRetention.day.duration
  }
}

public struct HistoryValue: Equatable, Sendable {
  public let mean: Double
  public let maximum: Double
}

/// Values are kept in single precision: charts need no more, and it halves the
/// footprint of a day of buckets.
public struct HistorySummaryPoint: Equatable, Sendable {
  public let time: Date
  public let duration: TimeInterval
  public let sampleCount: Int
  public let uptime: TimeInterval?
  public let memoryPressure: HistoryPressure?
  public let thermal: HistoryPressure?
  fileprivate let means: InlineArray<9, Float>
  fileprivate let maxima: InlineArray<9, Float>

  public subscript(metric: HistoryMetric) -> HistoryValue? {
    let mean = means[metric.rawValue]
    guard !mean.isNaN else { return nil }
    return HistoryValue(mean: Double(mean), maximum: Double(maxima[metric.rawValue]))
  }

  public var end: Date { time.addingTimeInterval(duration) }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.time == rhs.time && lhs.duration == rhs.duration && lhs.sampleCount == rhs.sampleCount
      && lhs.uptime == rhs.uptime && lhs.memoryPressure == rhs.memoryPressure
      && lhs.thermal == rhs.thermal
      && HistoryMetric.all.allSatisfy { lhs[$0] == rhs[$0] }
  }
}

struct SummaryAccumulator: Sendable {
  let start: Double
  private(set) var duration: TimeInterval
  private var sampleCount = 0
  private var sums = InlineArray<9, Double>(repeating: 0)
  private var weights = InlineArray<9, Double>(repeating: 0)
  private var maxima = InlineArray<9, Float>(repeating: -.infinity)
  private var uptime: TimeInterval?
  private var memoryPressure: HistoryPressure?
  private var thermal: HistoryPressure?

  init(start: Double, duration: TimeInterval) {
    self.start = start
    self.duration = duration
  }

  mutating func add(_ point: HistorySystemPoint) {
    sampleCount += 1
    for metric in HistoryMetric.all {
      guard let value = Self.storable(point[metric]) else { continue }
      include(mean: value, maximum: value, weight: 1, at: metric.rawValue)
    }
    if let uptime = point.uptime, uptime.isFinite { self.uptime = uptime }
    memoryPressure = HistoryPressure.worst(memoryPressure, point.memoryPressure)
    thermal = HistoryPressure.worst(thermal, point.thermal)
  }

  mutating func add(_ summary: HistorySummaryPoint) {
    let weight = Double(max(1, summary.sampleCount))
    sampleCount += summary.sampleCount
    duration = max(duration, summary.end.timeIntervalSinceReferenceDate - start)
    for metric in HistoryMetric.all {
      guard let value = summary[metric] else { continue }
      include(mean: Float(value.mean), maximum: Float(value.maximum), weight: weight, at: metric.rawValue)
    }
    uptime = summary.uptime ?? uptime
    memoryPressure = HistoryPressure.worst(memoryPressure, summary.memoryPressure)
    thermal = HistoryPressure.worst(thermal, summary.thermal)
  }

  func summary() -> HistorySummaryPoint {
    var means = InlineArray<9, Float>(repeating: .nan)
    var maxima = InlineArray<9, Float>(repeating: .nan)
    for index in means.indices where weights[index] > 0 {
      means[index] = Float(sums[index] / weights[index])
      maxima[index] = self.maxima[index]
    }
    return HistorySummaryPoint(
      time: Date(timeIntervalSinceReferenceDate: start), duration: duration,
      sampleCount: sampleCount, uptime: uptime, memoryPressure: memoryPressure, thermal: thermal,
      means: means, maxima: maxima)
  }

  /// Rounding to single precision on entry makes a history rebuilt from disk,
  /// where values are stored as `Float`, identical to the live one.
  static func storable(_ value: Double?) -> Float? {
    guard let value, value >= 0 else { return nil }
    let rounded = Float(value)
    return rounded.isFinite ? rounded : nil
  }

  private mutating func include(mean: Float, maximum: Float, weight: Double, at index: Int) {
    sums[index] += Double(mean) * weight
    weights[index] += weight
    maxima[index] = max(maxima[index], maximum)
  }
}

struct TimeRing<Element: Sendable>: Sendable {
  let capacity: Int
  private var storage: [Element] = []
  private var oldest = 0

  init(capacity: Int) { self.capacity = Swift.max(1, capacity) }

  mutating func append(_ element: Element) {
    if storage.count < capacity {
      if storage.isEmpty { storage.reserveCapacity(capacity) }
      storage.append(element)
      return
    }
    storage[oldest] = element
    oldest = (oldest + 1) % capacity
  }

  mutating func removeAll() {
    storage = []
    oldest = 0
  }
}

extension TimeRing: RandomAccessCollection {
  var startIndex: Int { 0 }
  var endIndex: Int { storage.count }
  subscript(position: Int) -> Element { storage[(oldest + position) % storage.count] }
}

extension RandomAccessCollection where Index == Int {
  /// The first position whose key exceeds `value`; elements must be ordered by `key`.
  func firstIndex(after value: Double, by key: (Element) -> Double) -> Int {
    var low = startIndex
    var high = endIndex
    while low < high {
      let middle = (low + high) / 2
      if key(self[middle]) <= value { low = middle + 1 } else { high = middle }
    }
    return low
  }
}
