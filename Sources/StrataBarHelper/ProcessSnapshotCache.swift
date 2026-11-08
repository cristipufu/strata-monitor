import Foundation
import StrataHelperInterface
import StrataInventory

/// Holds one encoded snapshot reply, so memory stays bounded by a single payload. Callers that
/// arrive during a scan share it instead of starting another.
actor ProcessSnapshotCache {
  private struct Snapshot {
    let reply: Data
    let startedAt: TimeInterval
  }
  private let reuseInterval: TimeInterval
  private let uptime: @Sendable () -> TimeInterval
  private let scan: @Sendable () -> Data
  private var latest: Snapshot?
  private var scanInProgress: Task<Snapshot, Never>?

  init(
    reuseInterval: TimeInterval = 0.9, uptime: @escaping @Sendable () -> TimeInterval,
    scan: @escaping @Sendable () -> Data = { SnapshotReply.encode(NativeProcessInventory.read()) }
  ) {
    self.reuseInterval = reuseInterval
    self.uptime = uptime
    self.scan = scan
  }
  func reply() async -> Data {
    if let latest, uptime() - latest.startedAt < reuseInterval { return latest.reply }
    if let scanInProgress { return await scanInProgress.value.reply }
    let task = Task.detached(priority: .utility) { [uptime, scan] in
      let startedAt = uptime()
      return Snapshot(reply: scan(), startedAt: startedAt)
    }
    scanInProgress = task
    let snapshot = await task.value
    latest = snapshot
    scanInProgress = nil
    return snapshot.reply
  }
}
