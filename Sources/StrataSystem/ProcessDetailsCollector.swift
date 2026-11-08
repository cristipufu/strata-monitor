import CSystem
import Foundation
import StrataCore
import StrataInventory

public protocol ProcessDetailInspecting: Sendable {
  func inspect(_ process: ProcessSample) async throws -> ProcessDetails
}

public actor ProcessDetailsCollector: ProcessDetailInspecting {
  public init() {}
  public func inspect(_ process: ProcessSample) async throws -> ProcessDetails {
    let cancellation = try NativeScanCancellation()
    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      guard current(process) else { throw InspectionError.processEnded }
      let signing = SigningInspector().inspect(pid: process.id.pid)
      try Task.checkCancellation()
      let arguments = arguments(pid: process.id.pid)
      try Task.checkCancellation()
      let mappings = mappings(pid: process.id.pid, cancellation: cancellation)
      try Task.checkCancellation()
      guard current(process) else { throw InspectionError.processEnded }
      return ProcessDetails(
        identity: process.id, signing: signing, arguments: arguments.values,
        argumentsIssue: arguments.issue, executableMappings: mappings.paths,
        mappingSummary: mappings.summary)
    } onCancel: {
      cancellation.cancel()
    }
  }
  private func current(_ process: ProcessSample) -> Bool {
    sb_process_identity(process.id.pid, process.id.startSeconds, process.id.startMicroseconds)
      && process.path.withCString { sb_process_path_matches(process.id.pid, $0) }
  }
  private func arguments(pid: Int32) -> (values: [String]?, issue: String?) {
    var length = 0
    var error: Int32 = 0
    guard let buffer = sb_process_arguments(pid, &length, &error) else {
      return (nil, POSIXError(POSIXErrorCode(rawValue: error) ?? .EIO).localizedDescription)
    }
    let data = Data(
      bytesNoCopy: buffer, count: length,
      deallocator: .custom { pointer, length in sb_sensitive_free(pointer, length) })
    guard let values = ProcessArguments.parse(data) else {
      return (nil, "The system returned incomplete argument data.")
    }
    return (values, nil)
  }
  private func mappings(pid: Int32, cancellation: NativeScanCancellation) -> (
    paths: [String], summary: ScanSummary
  ) {
    var count = 0
    var status = SBScanStatus()
    guard let buffer = sb_executable_mappings(pid, &count, &status, cancellation.handle) else {
      return ([], scanSummary(status))
    }
    defer { sb_free(buffer) }
    let paths = Set(UnsafeBufferPointer(start: buffer, count: count).map { nativeString($0.path) })
    return (paths.sorted(), scanSummary(status))
  }
}
