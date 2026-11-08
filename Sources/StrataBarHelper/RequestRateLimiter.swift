import Foundation
import Synchronization

enum HelperRequestKind: CaseIterable {
  case query, resources
}

struct TokenBucket {
  let capacity: Double
  let refillPerSecond: Double
  private var tokens: Double
  private var refilledAt: TimeInterval

  init(capacity: Double, refillPerSecond: Double, now: TimeInterval) {
    self.capacity = capacity
    self.refillPerSecond = refillPerSecond
    tokens = capacity
    refilledAt = now
  }
  mutating func take(at now: TimeInterval) -> Bool {
    tokens = min(capacity, tokens + max(0, now - refilledAt) * refillPerSecond)
    refilledAt = now
    guard tokens >= 1 else { return false }
    tokens -= 1
    return true
  }
}

/// Each connection gets its own limiter. The app polls snapshots every few seconds and requests
/// resources on selection, so these limits only stop runaway loops.
final class RequestRateLimiter: Sendable {
  private let buckets: Mutex<[HelperRequestKind: TokenBucket]>
  private let uptime: @Sendable () -> TimeInterval

  init(uptime: @escaping @Sendable () -> TimeInterval) {
    self.uptime = uptime
    let now = uptime()
    buckets = Mutex([
      .query: TokenBucket(capacity: 10, refillPerSecond: 4, now: now),
      .resources: TokenBucket(capacity: 10, refillPerSecond: 4, now: now),
    ])
  }
  func admits(_ kind: HelperRequestKind) -> Bool {
    let now = uptime()
    return buckets.withLock { $0[kind]?.take(at: now) ?? false }
  }
}
