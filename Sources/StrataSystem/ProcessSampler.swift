import Foundation
import StrataCore

public enum ProcessSamplingError: Error, Equatable, Sendable {
  case notPermitted
  case processEnded
  case unrecognizedReport
  /// sample falls back to matching process names when a PID is gone, so a
  /// report about any other process is rejected.
  case differentProcess
}

public protocol ProcessSampling: Sendable {
  func sample(pid: Int32, seconds: Int) async throws -> SampleReport
}

/// Works only on processes the user may inspect; others fail with `notPermitted`.
public struct ProcessSampler: ProcessSampling {
  private let tool: any SystemToolLaunching
  public init(tool: any SystemToolLaunching = SystemTool()) {
    self.tool = tool
  }

  public func sample(pid: Int32, seconds: Int) async throws -> SampleReport {
    let data: Data
    do {
      data = try await tool.run(.sample(pid: pid, seconds: seconds))
    } catch let error as SystemToolError {
      throw Self.classified(error)
    }
    guard let report = SampleReportParser.parse(String(decoding: data, as: UTF8.self)) else {
      throw ProcessSamplingError.unrecognizedReport
    }
    guard report.pid == pid else { throw ProcessSamplingError.differentProcess }
    return report
  }

  /// sample reports refusals only through its own English diagnostics.
  private static func classified(_ error: SystemToolError) -> any Error {
    guard case .exited(_, let diagnostics) = error else { return error }
    if diagnostics.contains("appropriate privileges") { return ProcessSamplingError.notPermitted }
    if diagnostics.contains("no longer appears to be running") {
      return ProcessSamplingError.processEnded
    }
    return error
  }
}
