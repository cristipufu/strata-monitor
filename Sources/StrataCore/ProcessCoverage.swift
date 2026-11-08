import Foundation

public enum ProcessCoverage: String, Codable, Sendable {
  case allProcesses, ownProcessesWithEstimates, ownProcesses
  public var title: String {
    switch self {
    case .allProcesses: "All processes"
    case .ownProcessesWithEstimates: "Own processes; CPU and memory for others"
    case .ownProcesses: "Own processes; others listed"
    }
  }
}

/// CPU time and resident memory for a process the current user cannot measure directly. Sources
/// such as `ps` identify processes by pid only, so owner and parent must also match.
public struct ProcessUsageEstimate: Sendable, Equatable {
  public let pid: Int32
  public let parentPID: Int32
  public let userID: UInt32
  public let cpuTimeNanoseconds: UInt64?
  public let residentBytes: UInt64?
  // Measured by the source across its own, slower cadence; the app keeps it as given.
  public let cpuPercent: Double?
  public init(
    pid: Int32, parentPID: Int32, userID: UInt32, cpuTimeNanoseconds: UInt64?,
    residentBytes: UInt64?, cpuPercent: Double? = nil
  ) {
    self.pid = pid
    self.parentPID = parentPID
    self.userID = userID
    self.cpuTimeNanoseconds = cpuTimeNanoseconds
    self.residentBytes = residentBytes
    self.cpuPercent = cpuPercent
  }
  func describes(_ process: ProcessSample) -> Bool {
    pid == process.id.pid && parentPID == process.parentPID && userID == process.userID
  }
}

public struct CoveredProcessInventory: Sendable {
  public var inventory: ProcessInventory
  public let coverage: ProcessCoverage
  public init(inventory: ProcessInventory, coverage: ProcessCoverage) {
    self.inventory = inventory
    self.coverage = coverage
  }
  public var measuredCount: Int {
    inventory.processes.count { $0.cpuTimeNanoseconds != nil }
  }
}

/// Combines the current user's own scan with estimates for other users' processes. Values a
/// source does not provide stay nil.
public enum ProcessInventoryMerge {
  public static func merge(local: ProcessInventory, estimates: [ProcessUsageEstimate]?)
    -> CoveredProcessInventory
  {
    guard let estimates else {
      return CoveredProcessInventory(inventory: local, coverage: .ownProcesses)
    }
    return CoveredProcessInventory(
      inventory: supplementing(local, with: estimates), coverage: .ownProcessesWithEstimates)
  }

  private static func supplementing(
    _ local: ProcessInventory, with estimates: [ProcessUsageEstimate]
  ) -> ProcessInventory {
    let estimatesByPID = Dictionary(
      estimates.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
    let processes = local.processes.map { process in
      guard process.cpuTimeNanoseconds == nil || process.residentBytes == nil,
        let estimate = estimatesByPID[process.id.pid], estimate.describes(process)
      else { return process }
      return process.supplemented(by: estimate)
    }
    return ProcessInventory(processes: processes, summary: local.summary, capturedAt: local.capturedAt)
  }
}

extension ProcessSample {
  fileprivate func supplemented(by estimate: ProcessUsageEstimate) -> ProcessSample {
    var result = self
    result.cpuTimeNanoseconds = cpuTimeNanoseconds ?? estimate.cpuTimeNanoseconds
    result.residentBytes = residentBytes ?? estimate.residentBytes
    result.cpuPercent = cpuPercent ?? estimate.cpuPercent
    result.isEstimated = cpuTimeNanoseconds == nil
    return result
  }

}
