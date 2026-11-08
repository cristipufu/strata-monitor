import Foundation
import StrataCore
import Testing

@testable import StrataHelperInterface

@Test func callerRequirementNamesIdentifierAppleAnchorAndTeam() throws {
  let requirement = try #require(
    HelperCodeSigning.requirement(signingIdentifier: "dev.stratabar.app", team: "WKQLY75R65"))
  #expect(
    requirement
      == #"identifier "dev.stratabar.app" and anchor apple generic and certificate leaf[subject.OU] = "WKQLY75R65""#
  )
}

@Test(arguments: [
  "", "wkqly75r65", "WKQLY75R6", "WKQLY75R655", #"WKQLY75R6""#, #"A" or true"#, "WKQLY 75R6",
])
func malformedTeamCannotShapeTheRequirement(_ team: String) {
  #expect(HelperCodeSigning.requirement(signingIdentifier: "dev.stratabar.app", team: team) == nil)
}

@Test(arguments: ["", #"dev.stratabar.app" or anchor apple"#, "dev stratabar"])
func malformedIdentifierCannotShapeTheRequirement(_ identifier: String) {
  #expect(HelperCodeSigning.requirement(signingIdentifier: identifier, team: "WKQLY75R65") == nil)
}

@Test func replyRoundTripPreservesUnavailableValuesAndLargeCounters() throws {
  let sample = ProcessSample(
    id: ProcessIdentity(pid: 7, startSeconds: .max, startMicroseconds: 999_999),
    parentPID: 1, userID: 0, name: "kernel_task", path: "",
    cpuTimeNanoseconds: .max, residentBytes: nil, footprintBytes: nil, threads: nil)
  let data = HelperCoding.reply(ProcessInventory(processes: [sample]))
  let decoded = try HelperCoding.decode(HelperReply<ProcessInventory>.self, from: data).payload()
  let process = try #require(decoded.processes.first)
  #expect(process.id == sample.id && process.cpuTimeNanoseconds == .max)
  #expect(process.residentBytes == nil && process.footprintBytes == nil && process.threads == nil)
  #expect(process.activity == nil)
}

@Test func payloadsBeyondTheLimitAreRejectedBeforeDecoding() {
  let data = HelperCoding.reply(HelperInfo(helperVersion: 1, schemaVersion: 1, effectiveUserID: 0))
  #expect(throws: HelperFailure.payloadTooLarge) {
    try HelperCoding.decode(HelperReply<HelperInfo>.self, from: data, limit: data.count - 1)
  }
  #expect(throws: HelperFailure.payloadTooLarge) {
    try HelperCoding.encode(ProcessInventory(processes: []), limit: 8)
  }
  #expect(throws: HelperFailure.malformedReply) {
    try HelperCoding.decode(HelperReply<HelperInfo>.self, from: Data("not a reply".utf8))
  }
}

@Test func replyFromAnotherSchemaIsRefused() throws {
  let info = HelperInfo(helperVersion: 1, schemaVersion: 1, effectiveUserID: 0)
  let data = try HelperCoding.encode(
    HelperReply(.success(info), schemaVersion: HelperContract.schemaVersion + 1))
  let reply = try HelperCoding.decode(HelperReply<HelperInfo>.self, from: data)
  #expect(throws: HelperFailure.unsupportedSchema) { try reply.payload() }
}

@Test func resourceRequestsAreBoundedAndNamePositiveProcesses() throws {
  let identity = ProcessIdentityWire(pid: 10, startSeconds: 1, startMicroseconds: 2)
  #expect(throws: Never.self) {
    try ResourceRequest(identities: [identity], socketsOnly: true).validated()
  }
  let tooMany = Array(
    repeating: identity, count: HelperContract.maximumResourceIdentities + 1)
  #expect(throws: HelperFailure.invalidRequest) {
    try ResourceRequest(identities: tooMany, socketsOnly: false).validated()
  }
  for pid: Int32 in [0, -1] {
    let invalid = ProcessIdentityWire(pid: pid, startSeconds: 1, startMicroseconds: 0)
    #expect(throws: HelperFailure.invalidRequest) {
      try ResourceRequest(identities: [invalid], socketsOnly: false).validated()
    }
  }
  #expect(throws: HelperFailure.unsupportedSchema) {
    try ResourceRequest(identities: [identity], socketsOnly: false, schemaVersion: 0).validated()
  }
  let largest = try HelperCoding.encode(
    ResourceRequest(
      identities: Array(repeating: identity, count: HelperContract.maximumResourceIdentities),
      socketsOnly: false), limit: HelperContract.maximumRequestBytes)
  #expect(largest.count <= HelperContract.maximumRequestBytes)
}

// Changing any encoded payload must come with a new HelperContract.schemaVersion, so an older
// registered helper is replaced instead of misread.
@Test func encodedPayloadShapeMatchesTheSchemaVersion() throws {
  let identity = ProcessIdentity(pid: 2, startSeconds: 3, startMicroseconds: 4)
  var sample = ProcessSample(
    id: identity, parentPID: 1, userID: 0, name: "n", path: "/p", cpuTimeNanoseconds: 1,
    cpuPercent: 1, residentBytes: 1, footprintBytes: 1, threads: 1, diskReadBytes: 1,
    diskWrittenBytes: 1, diskReadBytesPerSecond: 1, diskWrittenBytesPerSecond: 1,
    runState: .running, isTranslated: false,
    activity: ProcessActivityCounters(
      energyNanojoules: 1, wakeups: 1, instructions: 1, cycles: 1,
      performanceCoreNanoseconds: 1, peakFootprintBytes: 1))
  sample.watts = 1
  sample.wakeupsPerSecond = 1
  sample.performanceCoreShare = 1
  var summary = ScanSummary()
  summary.failureMessage = "m"
  let resource = ProcessResource(
    owner: identity, processName: "n", descriptor: 3, kind: .tcp,
    fileSystem: FileSystemIdentity(firstComponent: 1, secondComponent: 2))
  func keys<Value: Encodable>(_ value: Value) throws -> [String] {
    let object = try JSONSerialization.jsonObject(with: try HelperCoding.encode(value))
    return ((object as? [String: Any])?.keys).map { $0.sorted() } ?? []
  }
  #expect(HelperContract.schemaVersion == 2)
  #expect(
    try keys(sample) == [
      "activity", "cpuPercent", "cpuTimeNanoseconds", "diskReadBytes", "diskReadBytesPerSecond",
      "diskWrittenBytes", "diskWrittenBytesPerSecond", "footprintBytes", "id", "isEstimated",
      "isTranslated", "name", "parentPID", "path", "performanceCoreShare", "residentBytes",
      "runState",
      "threads", "userID", "wakeupsPerSecond", "watts",
    ])
  #expect(try keys(identity) == ["pid", "startMicroseconds", "startSeconds"])
  #expect(
    try keys(sample.activity) == [
      "cycles", "energyNanojoules", "instructions", "peakFootprintBytes",
      "performanceCoreNanoseconds", "wakeups",
    ])
  #expect(
    try keys(summary) == [
      "changedDuringScan", "failed", "failureMessage", "restricted", "truncated",
      "unreadableHandles",
    ])
  #expect(try keys(ProcessInventory(processes: [], capturedAt: 1)) == ["capturedAt", "processes", "summary"])
  #expect(
    try keys(resource) == [
      "descriptor", "fileSystem", "kind", "localAddress", "localPort", "owner", "path",
      "processName", "remoteAddress", "remotePort", "state",
    ])
  #expect(try keys(ResourceReport(resources: [])) == ["resources", "summary"])
  #expect(try keys(resource.fileSystem) == ["firstComponent", "secondComponent"])
}
