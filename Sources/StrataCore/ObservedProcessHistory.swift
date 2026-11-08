import Foundation

public struct ProcessHistoryPoint: Identifiable, Codable, Sendable {
  public var id: TimeInterval { uptime }
  public let uptime: TimeInterval
  public let cpu: Double?
  public let footprint: UInt64?
  public let present: Bool
  public let diskRead: Double?
  public let diskWritten: Double?
}

public struct ObservedProcessHistory: Sendable {
  public private(set) var identity: ProcessIdentity?
  public private(set) var points: [ProcessHistoryPoint] = []
  private var started: TimeInterval = 0
  private let duration: TimeInterval = 60
  private let maximumCount = 240
  public init() {}
  public mutating func restart(at time: TimeInterval) {
    guard time.isFinite else { return }
    started = time
    points.removeAll(keepingCapacity: true)
  }
  public mutating func track(_ identity: ProcessIdentity?, at time: TimeInterval) {
    guard self.identity != identity, time.isFinite else { return }
    self.identity = identity
    started = time
    points.removeAll(keepingCapacity: true)
  }
  public mutating func append(_ sample: SystemSample) {
    guard let identity, sample.processScan != nil, sample.uptime.isFinite, sample.uptime >= started,
      points.last.map({ sample.uptime > $0.uptime }) ?? true
    else { return }
    let process = sample.processes.first { $0.id == identity }
    let cpu = process?.cpuPercent.flatMap { $0.isFinite && $0 >= 0 ? $0 / 100 : nil }
    points.append(
      ProcessHistoryPoint(
        uptime: sample.uptime, cpu: cpu,
        footprint: process?.footprintBytes, present: process != nil,
        diskRead: process?.diskReadBytesPerSecond, diskWritten: process?.diskWrittenBytesPerSecond))
    points.removeAll { $0.uptime < sample.uptime - duration }
    if points.count > maximumCount { points.removeFirst(points.count - maximumCount) }
  }
}
