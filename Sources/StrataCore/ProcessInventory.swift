import Foundation

public struct ProcessInventory: Codable, Sendable {
  public var processes: [ProcessSample]
  public var summary: ScanSummary
  // System uptime when the counters were read; rates use it rather than when they arrived.
  public var capturedAt: TimeInterval?
  public init(
    processes: [ProcessSample], summary: ScanSummary = ScanSummary(), capturedAt: TimeInterval? = nil
  ) {
    self.processes = processes
    self.summary = summary
    self.capturedAt = capturedAt
  }
}
