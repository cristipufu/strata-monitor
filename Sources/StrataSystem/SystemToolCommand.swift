import Foundation

/// The complete set of tool launches. Every argument is fixed or rendered from a
/// typed value, and no command passes through a shell.
struct SystemToolCommand: Equatable, Sendable {
  let executablePath: String
  let arguments: [String]

  static let processTable = SystemToolCommand(
    executablePath: "/bin/ps", arguments: ["-ax", "-o", "pid=,ppid=,uid=,time=,rss=,state=,comm="])
  /// One logging sample of cumulative counters; delta mode would wait a full second.
  static let networkUsage = SystemToolCommand(
    executablePath: "/usr/bin/nettop",
    arguments: ["-P", "-L", "1", "-x", "-n", "-J", "bytes_in,bytes_out"])
  static func sample(pid: Int32, seconds: Int, reportFile: URL) -> SystemToolCommand {
    SystemToolCommand(
      executablePath: "/usr/bin/sample",
      arguments: [String(pid), String(seconds), "-file", reportFile.path])
  }
}

public struct SystemToolLimits: Sendable {
  public var outputBytes: Int
  public var diagnosticBytes: Int
  public var timeout: Duration
  public var terminationGrace: Duration
  public init(
    outputBytes: Int = 8 << 20, diagnosticBytes: Int = 64 << 10, timeout: Duration = .seconds(10),
    terminationGrace: Duration = .seconds(1)
  ) {
    self.outputBytes = outputBytes
    self.diagnosticBytes = diagnosticBytes
    self.timeout = timeout
    self.terminationGrace = terminationGrace
  }
}
