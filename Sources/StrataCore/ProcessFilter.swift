import Foundation

public enum ProcessFilter: String, CaseIterable, Codable, Sendable {
  case all, mine, otherUsers, system, applications, active, paused
}

public struct ProcessFilterContext: Sendable, Equatable {
  public let currentUser: UInt32
  public let applicationPIDs: Set<Int32>
  public init(currentUser: UInt32, applicationPIDs: Set<Int32> = []) {
    self.currentUser = currentUser
    self.applicationPIDs = applicationPIDs
  }
}

extension ProcessFilter {
  // A process is active when it used measurable CPU between the last two readings.
  static let activeCPUPercent = 0.1

  public func includes(_ process: ProcessSample, in context: ProcessFilterContext) -> Bool {
    switch self {
    case .all: true
    case .mine: process.userID == context.currentUser
    case .otherUsers:
      process.userID != context.currentUser && !Self.isSystemAccount(process.userID)
    case .system: Self.isSystemAccount(process.userID)
    case .applications: context.applicationPIDs.contains(process.id.pid)
    case .active: (process.cpuPercent ?? 0) >= Self.activeCPUPercent
    case .paused: process.runState == .stopped
    }
  }
  // macOS gives people accounts from 501 and daemons accounts below 500; nobody sits at the top.
  static func isSystemAccount(_ userID: UInt32) -> Bool {
    userID < 500 || userID >= UInt32.max - 1
  }
}
