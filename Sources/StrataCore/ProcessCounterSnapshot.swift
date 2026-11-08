import Foundation

/// Counters are keyed by full process identity, so a reused PID never pairs with
/// the previous owner's counter.
public struct ProcessCounterSnapshot<Counter: Equatable & Sendable>: Equatable, Sendable {
  public let capturedAt: TimeInterval
  public let counters: [ProcessIdentity: Counter]
  public init(capturedAt: TimeInterval, counters: [ProcessIdentity: Counter]) {
    self.capturedAt = capturedAt
    self.counters = counters
  }
  /// PIDs without a current identity are left out rather than guessed.
  public init(
    capturedAt: TimeInterval, countersByPID: [Int32: Counter], identities: [Int32: ProcessIdentity]
  ) {
    let identified = countersByPID.compactMap { pid, counter in
      identities[pid].flatMap { $0.pid == pid ? ($0, counter) : nil }
    }
    self.init(capturedAt: capturedAt, counters: Dictionary(identified) { first, _ in first })
  }

  func rates<Rate>(
    since previous: Self, _ rate: (_ earlier: Counter, _ later: Counter, _ seconds: Double) -> Rate?
  ) -> [ProcessIdentity: Rate] {
    let elapsed = capturedAt - previous.capturedAt
    guard elapsed.isFinite, elapsed > 0 else { return [:] }
    return counters.reduce(into: [:]) { rates, entry in
      guard let earlier = previous.counters[entry.key],
        let value = rate(earlier, entry.value, elapsed)
      else { return }
      rates[entry.key] = value
    }
  }
}

public enum ProcessCPUUsage {
  /// Percent of one core, as Activity Monitor reports it; a counter that went
  /// backwards gives no value.
  public static func percentages(
    from previous: ProcessCounterSnapshot<UInt64>, to current: ProcessCounterSnapshot<UInt64>
  ) -> [ProcessIdentity: Double] {
    current.rates(since: previous) { earlier, later, seconds in
      later >= earlier ? Double(later - earlier) / seconds / 1_000_000_000 * 100 : nil
    }
  }
}
