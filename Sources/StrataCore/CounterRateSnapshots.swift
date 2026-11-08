import Foundation

extension CounterRates {
  // Rates for one sample of every live counter. A nil count is unreadable, not zero, so its
  // baseline is kept for the next readable sample. Keys missing from `counts` have ended.
  public mutating func rates(of counts: [Key: UInt64?], at time: TimeInterval) -> [Key: Double] {
    guard time.isFinite, time >= 0 else { return [:] }
    retain(keys: Set(counts.keys))
    var rates: [Key: Double] = [:]
    for case (let key, let count?) in counts {
      rates[key] = rate(for: key, value: count, at: time)
    }
    return rates
  }
}
