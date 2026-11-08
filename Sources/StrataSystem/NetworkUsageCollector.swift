import Foundation
import StrataCore

public enum NetworkUsageState: Sendable, Equatable {
  // The first launch only sets a baseline, so there is nothing to show yet.
  case measuring
  case unavailable
  case measured([ProcessIdentity: NetworkRate])
  public var rates: [ProcessIdentity: NetworkRate] {
    if case .measured(let rates) = self { return rates }
    return [:]
  }
}

public protocol NetworkUsageSampling: Sendable {
  func sample(of processes: [ProcessIdentity]) async -> NetworkUsageState
  func reset() async
}

/// Bytes each process sent and received, from `nettop`; read only while a view shows them, and
/// at most every few seconds because each launch costs about 15 ms.
public actor NetworkUsageCollector: NetworkUsageSampling {
  private let reader: any NetworkUsageReading
  private let refreshInterval: TimeInterval
  private let uptime: @Sendable () -> TimeInterval
  private var previous: ProcessCounterSnapshot<NetworkByteCounts>?
  private var latest = NetworkUsageState.measuring
  private var lastRead: TimeInterval?

  public init(
    reader: any NetworkUsageReading = NetworkUsageReader(), refreshInterval: TimeInterval = 4,
    uptime: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
  ) {
    self.reader = reader
    self.refreshInterval = refreshInterval
    self.uptime = uptime
  }

  public func sample(of processes: [ProcessIdentity]) async -> NetworkUsageState {
    let now = uptime()
    if let lastRead, now - lastRead < refreshInterval { return latest }
    lastRead = now
    guard let usage = try? await reader.read() else {
      previous = nil
      latest = .unavailable
      return latest
    }
    let identities = Dictionary(
      processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
    let snapshot = ProcessCounterSnapshot(
      capturedAt: now, countersByPID: usage.countsByPID, identities: identities)
    latest = previous.map { .measured(NetworkUsageRates.rates(from: $0, to: snapshot)) } ?? .measuring
    previous = snapshot
    return latest
  }

  public func reset() {
    previous = nil
    lastRead = nil
    latest = .measuring
  }
}
