import CSystem
import Foundation
import StrataCore

/// Other users' CPU and resident memory from `/bin/ps`, which macOS lets read every process.
/// One launch costs about 50 ms of CPU, so readings refresh at most every few seconds and
/// percentages compare consecutive launches rather than consecutive app readings.
public actor ProcessTableUsageSource: OtherUsersUsageSource {
  private let reader: any ProcessTableReading
  private let currentUser: UInt32
  private let refreshInterval: TimeInterval
  private let uptime: @Sendable () -> TimeInterval
  private let identity: @Sendable (Int32) -> ProcessIdentity?
  private var previous: ProcessCounterSnapshot<UInt64>?
  private var estimates: [ProcessUsageEstimate]?
  private var lastRead: TimeInterval?

  public init(
    reader: any ProcessTableReading = ProcessTableReader(), currentUser: UInt32 = getuid(),
    refreshInterval: TimeInterval = 5,
    uptime: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
    identity: @escaping @Sendable (Int32) -> ProcessIdentity? = ProcessTableUsageSource.kernelIdentity
  ) {
    self.reader = reader
    self.currentUser = currentUser
    self.refreshInterval = refreshInterval
    self.uptime = uptime
    self.identity = identity
  }

  public func usageEstimates() async -> [ProcessUsageEstimate]? {
    let now = uptime()
    if let lastRead, now - lastRead < refreshInterval, let estimates { return estimates }
    // After a long pause, such as sleep or closed views, an old baseline would average across it.
    if let lastRead, now - lastRead > 3 * refreshInterval { previous = nil }
    lastRead = now
    guard let table = try? await reader.read() else {
      previous = nil
      estimates = nil
      return nil
    }
    let others = table.records.filter { $0.userID != currentUser }
    var identities: [Int32: ProcessIdentity] = [:]
    for record in others { identities[record.pid] = identity(record.pid) }
    let snapshot = ProcessCounterSnapshot(
      capturedAt: now,
      countersByPID: Dictionary(
        others.map { ($0.pid, $0.cpuTimeNanoseconds) }, uniquingKeysWith: { first, _ in first }),
      identities: identities)
    let percentages = previous.map { ProcessCPUUsage.percentages(from: $0, to: snapshot) } ?? [:]
    previous = snapshot
    let current = others.map { record in
      ProcessUsageEstimate(
        pid: record.pid, parentPID: record.parentPID, userID: record.userID,
        cpuTimeNanoseconds: record.cpuTimeNanoseconds, residentBytes: record.residentBytes,
        cpuPercent: identities[record.pid].flatMap { percentages[$0] })
    }
    estimates = current
    return current
  }

  public static let kernelIdentity: @Sendable (Int32) -> ProcessIdentity? = { pid in
    var seconds: UInt64 = 0
    var microseconds: UInt64 = 0
    guard sb_process_start_time(pid, &seconds, &microseconds) else { return nil }
    return ProcessIdentity(pid: pid, startSeconds: seconds, startMicroseconds: microseconds)
  }
}
