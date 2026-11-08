import Foundation

public struct CounterRates<Key: Hashable & Sendable>: Sendable {
  private struct Baseline: Sendable {
    let value: UInt64
    let time: TimeInterval
  }
  private var baselines: [Key: Baseline] = [:]
  // A longer gap usually spans sleep, where an average would misrepresent activity.
  private let maximumInterval: TimeInterval
  public init(maximumInterval: TimeInterval = 10) { self.maximumInterval = maximumInterval }

  public mutating func rate(for key: Key, value: UInt64, at time: TimeInterval) -> Double? {
    guard time.isFinite, time >= 0 else { return nil }
    if let previous = baselines[key], time <= previous.time { return nil }
    let previous = baselines.updateValue(Baseline(value: value, time: time), forKey: key)
    guard let previous, time.isFinite, time > previous.time, time - previous.time <= maximumInterval,
      value >= previous.value
    else { return nil }
    return Double(value - previous.value) / (time - previous.time)
  }
  public mutating func retain(keys: Set<Key>) { retain(where: keys.contains) }
  // Few keys end between readings, so removing them beats rebuilding thousands of baselines.
  public mutating func retain(where isKept: (Key) -> Bool) {
    for key in baselines.keys.filter({ !isKept($0) }) { baselines.removeValue(forKey: key) }
  }
  public mutating func reset() { baselines.removeAll(keepingCapacity: true) }
}

public struct CPUDelta: Sendable {
  private var previous: (busy: UInt64, total: UInt64)?
  public init() {}
  public mutating func fraction(busy: UInt64, total: UInt64) -> Double? {
    defer { previous = (busy, total) }
    guard let previous, total > previous.total, busy >= previous.busy else { return nil }
    return min(1, Double(busy - previous.busy) / Double(total - previous.total))
  }
}

public enum ValueFormat {
  public static func bytes(_ bytes: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .memory)
  }
  public static func rate(_ value: Double?) -> String {
    guard let value, value.isFinite, value >= 0 else { return "—" }
    if value < 1_000 { return String(format: "%.0f B/s", value) }
    if value < 1_000_000 { return String(format: "%.0f KB/s", value / 1_000) }
    return String(format: "%.1f MB/s", value / 1_000_000)
  }
  public static func processCPU(_ percent: Double) -> String {
    String(format: "%.1f%%", percent)
  }
  public static func percent(_ fraction: Double?) -> String {
    guard let fraction, fraction.isFinite else { return "—" }
    return String(format: "%.0f%%", fraction * 100)
  }
  public static func cpuTime(nanoseconds: UInt64) -> String {
    let centiseconds = nanoseconds / 10_000_000
    let seconds = centiseconds / 100
    let (hours, minutes, remainder) = (seconds / 3600, seconds / 60 % 60, seconds % 60)
    if hours > 0 { return String(format: "%llu:%02llu:%02llu", hours, minutes, remainder) }
    return String(format: "%llu:%02llu.%02llu", minutes, remainder, centiseconds % 100)
  }
  public static func watts(_ value: Double) -> String {
    guard value.isFinite, value >= 0 else { return "—" }
    if value >= 10 { return String(format: "%.0f W", value) }
    if value >= 1 { return String(format: "%.1f W", value) }
    return String(format: "%.0f mW", value * 1_000)
  }
  public static func perSecond(_ value: Double) -> String {
    guard value.isFinite, value >= 0 else { return "—" }
    return value.formatted(.number.precision(.fractionLength(0))) + "/s"
  }
}
