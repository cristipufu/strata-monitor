import Foundation

public struct NetworkByteCounts: Equatable, Sendable {
  public let bytesIn: UInt64
  public let bytesOut: UInt64
  public init(bytesIn: UInt64, bytesOut: UInt64) {
    self.bytesIn = bytesIn
    self.bytesOut = bytesOut
  }
}

public struct ProcessNetworkUsage: Equatable, Sendable {
  public let countsByPID: [Int32: NetworkByteCounts]
  public let skippedRows: Int
  public init(countsByPID: [Int32: NetworkByteCounts], skippedRows: Int) {
    self.countsByPID = countsByPID
    self.skippedRows = skippedRows
  }
}

public enum NetworkUsageRates {
  /// Counters shrink when a process's sockets close; such an interval has no
  /// trustworthy rate in either direction.
  public static func rates(
    from previous: ProcessCounterSnapshot<NetworkByteCounts>,
    to current: ProcessCounterSnapshot<NetworkByteCounts>
  ) -> [ProcessIdentity: NetworkRate] {
    current.rates(since: previous) { earlier, later, seconds in
      guard later.bytesIn >= earlier.bytesIn, later.bytesOut >= earlier.bytesOut else { return nil }
      return NetworkRate(
        received: Double(later.bytesIn - earlier.bytesIn) / seconds,
        sent: Double(later.bytesOut - earlier.bytesOut) / seconds)
    }
  }
}
