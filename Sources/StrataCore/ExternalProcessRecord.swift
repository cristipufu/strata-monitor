import Foundation

public struct ExternalProcessRecord: Equatable, Codable, Sendable {
  public let pid: Int32
  public let parentPID: Int32
  public let userID: UInt32
  public let cpuTimeNanoseconds: UInt64
  public let residentBytes: UInt64
  public let state: ProcessRunState?
  public let command: String
  public init(
    pid: Int32, parentPID: Int32, userID: UInt32, cpuTimeNanoseconds: UInt64,
    residentBytes: UInt64, state: ProcessRunState?, command: String
  ) {
    self.pid = pid
    self.parentPID = parentPID
    self.userID = userID
    self.cpuTimeNanoseconds = cpuTimeNanoseconds
    self.residentBytes = residentBytes
    self.state = state
    self.command = command
  }
}

public struct ExternalProcessTable: Equatable, Sendable {
  public let records: [ExternalProcessRecord]
  public let skippedLines: Int
  public init(records: [ExternalProcessRecord], skippedLines: Int) {
    self.records = records
    self.skippedLines = skippedLines
  }
}
