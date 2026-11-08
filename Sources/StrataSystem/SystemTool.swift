import Foundation

public enum SystemToolInvocation: Hashable, Sendable {
  case processTable
  case networkUsage
  case sample(pid: Int32, seconds: Int)

  public static let samplingSeconds = 1...30
}

public enum SystemToolError: Error, Equatable, Sendable {
  case invalidRequest
  case launchFailed(String)
  case exited(status: Int32, diagnostics: String)
  case terminated(signal: Int32)
  case timedOut
  case outputLimitExceeded(limit: Int)
  case reportUnavailable
  case unrecognizedOutput
}

public protocol SystemToolLaunching: Sendable {
  func run(_ invocation: SystemToolInvocation) async throws -> Data
}

/// The only way Strata Monitor runs an Apple tool.
public struct SystemTool: SystemToolLaunching {
  /// Symbolicating a large app's report can take several seconds after sampling ends.
  static let symbolicationAllowance = Duration.seconds(30)
  private let limits: SystemToolLimits
  public init(limits: SystemToolLimits = SystemToolLimits()) {
    self.limits = limits
  }

  public func run(_ invocation: SystemToolInvocation) async throws -> Data {
    switch invocation {
    case .processTable: try await runner().run(.processTable).output
    case .networkUsage: try await runner().run(.networkUsage).output
    case .sample(let pid, let seconds): try await sample(pid: pid, seconds: seconds)
    }
  }

  private func runner(extendedBy extra: Duration = .zero) -> ChildProcessRunner {
    ChildProcessRunner(limits: limits, timeout: limits.timeout + extra)
  }

  /// Without `-file`, sample also leaves a copy of every report in /tmp.
  private func sample(pid: Int32, seconds: Int) async throws -> Data {
    guard pid > 0, SystemToolInvocation.samplingSeconds.contains(seconds) else {
      throw SystemToolError.invalidRequest
    }
    let directory = try PrivateReportDirectory()
    defer { directory.remove() }
    let command = SystemToolCommand.sample(
      pid: pid, seconds: seconds, reportFile: directory.reportFile)
    _ = try await runner(extendedBy: .seconds(seconds) + Self.symbolicationAllowance).run(command)
    return try directory.readReport(limit: limits.outputBytes)
  }
}

struct PrivateReportDirectory {
  let url: URL
  var reportFile: URL { url.appending(path: "report.txt", directoryHint: .notDirectory) }

  init(parent: URL = FileManager.default.temporaryDirectory) throws {
    url = parent.appending(
      path: "dev.stratabar.report-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
      at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
  }

  func readReport(limit: Int) throws -> Data {
    let data: Data
    do {
      let handle = try FileHandle(forReadingFrom: reportFile)
      defer { try? handle.close() }
      data = try handle.read(upToCount: Swift.min(limit, Int.max - 1) + 1) ?? Data()
    } catch {
      throw SystemToolError.reportUnavailable
    }
    guard data.count <= limit else { throw SystemToolError.outputLimitExceeded(limit: limit) }
    return data
  }

  /// A leftover private directory in the per-user temporary folder is harmless,
  /// and the system clears that folder.
  func remove() {
    try? FileManager.default.removeItem(at: url)
  }
}
