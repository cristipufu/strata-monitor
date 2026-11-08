import Foundation

/// A subtotal of readable per-process I/O, never a physical-drive throughput claim.
public struct ObservedDiskActivity: Sendable {
  public let read: Double
  public let written: Double
  public let measuredProcesses: Int
  public let unavailableProcesses: Int
  public init?(_ processes: [ProcessSample]) {
    var read = 0.0
    var written = 0.0
    var measured = 0
    var unavailable = 0
    for process in processes {
      guard let incoming = process.diskReadBytesPerSecond,
        let outgoing = process.diskWrittenBytesPerSecond,
        incoming.isFinite, outgoing.isFinite, incoming >= 0, outgoing >= 0
      else {
        unavailable += 1
        continue
      }
      read += incoming
      written += outgoing
      measured += 1
    }
    guard measured > 0, read.isFinite, written.isFinite else { return nil }
    self.read = read
    self.written = written
    measuredProcesses = measured
    unavailableProcesses = unavailable
  }
}
