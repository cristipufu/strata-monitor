import Foundation

public struct ScanSummary: Codable, Sendable {
  public var restricted = false
  public var failed = false
  public var changedDuringScan = false
  public var truncated = false
  public var unreadableHandles = 0
  public var failureMessage: String?
  public init() {}
  public var isComplete: Bool {
    !restricted && !failed && !changedDuringScan && !truncated && unreadableHandles == 0
  }
  public var explanation: String? {
    if failed { return failureMessage ?? "Some system queries failed. Refresh to try again." }
    if restricted { return "macOS restricted access to some processes or resources." }
    if truncated {
      return "The scan reached its result limit. Select a process to narrow the scan."
    }
    if unreadableHandles > 0 { return "Some handles could not be inspected." }
    if changedDuringScan { return "Some processes changed or ended during this snapshot." }
    return nil
  }
  public mutating func merge(_ other: ScanSummary) {
    restricted = restricted || other.restricted
    failed = failed || other.failed
    changedDuringScan = changedDuringScan || other.changedDuringScan
    truncated = truncated || other.truncated
    unreadableHandles += other.unreadableHandles
    failureMessage = failureMessage ?? other.failureMessage
  }
}
