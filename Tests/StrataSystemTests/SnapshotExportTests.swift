import Foundation
import StrataCore
import StrataSystem
import Testing

private func exportFixture(includeArguments: Bool = false) -> InspectionExport {
  let identity = ProcessIdentity(pid: 42, startSeconds: 1, startMicroseconds: 0)
  var summary = ScanSummary()
  summary.restricted = true
  let details = ProcessDetails(
    identity: identity, signing: SigningInfo(kind: .adHoc),
    arguments: ["worker", "SENSITIVE_ARGUMENT_FIXTURE"], executableMappings: ["/tmp/worker"],
    mappingSummary: summary)
  return InspectionExport(
    scope: .processes, query: "worker", processes: [], processScan: summary,
    resources: ResourceReport(resources: [], summary: summary), selectedDetails: details,
    observedHistory: [], includeArguments: includeArguments)
}

@Test func exportedSnapshotsPreserveCoverageAndOmitArgumentsByDefault() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
  defer { try? FileManager.default.removeItem(at: directory) }
  let destination = directory.appendingPathComponent("snapshot.json")
  let writer = SnapshotWriter()
  try await writer.write(exportFixture(), to: destination)
  let data = try Data(contentsOf: destination)
  #expect(!String(decoding: data, as: UTF8.self).contains("SENSITIVE_ARGUMENT_FIXTURE"))
  let decoder = JSONDecoder()
  decoder.dateDecodingStrategy = .iso8601
  let exported = try decoder.decode(InspectionExport.self, from: data)
  #expect(exported.schemaVersion == 1 && exported.scope == .processes)
  #expect(exported.resources.summary.restricted)
  #expect(exported.selectedDetails?.arguments == nil)
  try await writer.write(exportFixture(includeArguments: true), to: destination)
  let explicit = try decoder.decode(InspectionExport.self, from: Data(contentsOf: destination))
  #expect(explicit.selectedDetails?.arguments?.last == "SENSITIVE_ARGUMENT_FIXTURE")
  #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["snapshot.json"])
}

@Test func exportCancellationAndInvalidDestinationDoNotCreateOutput() async throws {
  let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    .appendingPathComponent("snapshot.json")
  let writer = SnapshotWriter()
  let snapshot = exportFixture()
  let canceled = Task {
    withUnsafeCurrentTask { $0?.cancel() }
    try await writer.write(snapshot, to: destination)
  }
  do {
    try await canceled.value
    Issue.record("A canceled export must stop before writing")
  } catch { #expect(error is CancellationError) }
  do {
    try await writer.write(snapshot, to: destination)
    Issue.record("A missing parent directory must fail")
  } catch { #expect(!(error is CancellationError)) }
  #expect(!FileManager.default.fileExists(atPath: destination.path))
}
