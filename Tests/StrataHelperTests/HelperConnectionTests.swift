import Foundation
import StrataCore
import StrataHelperInterface
import StrataInventory
import Testing

@testable import StrataBarHelper
@testable import StrataSystem

@Test func handshakeAndSnapshotRoundTripThroughXPC() async throws {
  let others = fixtureSample(pid: 88, userID: 0, cpu: 7_000, resident: 4_096)
  let unreadable = fixtureSample(pid: 89, userID: 0)
  let helper = InProcessHelper(
    core: helperCore { HelperCoding.reply(fixtureInventory([others, unreadable])) })
  let client = helper.client()
  let info = try await client.verify()
  #expect(info.matchesThisBuild && info.effectiveUserID == 0)
  let inventory = try await client.processInventory()
  #expect(inventory.processes.map(\.id) == [others.id, unreadable.id])
  #expect(inventory.processes[0].cpuTimeNanoseconds == 7_000)
  let missing = inventory.processes[1]
  #expect(missing.cpuTimeNanoseconds == nil && missing.residentBytes == nil)
  await client.disconnect()
}

@Test func xpcSnapshotsAreReusedWithinTheWindow() async throws {
  let clock = ManualClock()
  let scans = Counter()
  let helper = InProcessHelper(
    core: helperCore(clock: clock) {
      scans.increment()
      return HelperCoding.reply(fixtureInventory([]))
    })
  let client = helper.client()
  _ = try await client.processInventory()
  _ = try await client.processInventory()
  #expect(scans.count == 1)
  clock.advance(by: 1)
  _ = try await client.processInventory()
  #expect(scans.count == 2)
  await client.disconnect()
}

@Test func liveSnapshotThroughXPCListsThisProcessWithinTheReplyLimit() async throws {
  let helper = InProcessHelper(
    core: helperCore(scan: { HelperCoding.reply(NativeProcessInventory.read()) }))
  let client = helper.client()
  let inventory = try await client.processInventory()
  #expect(inventory.processes.count > 10)
  let own = try #require(inventory.processes.first { $0.id.pid == getpid() })
  #expect(own.cpuTimeNanoseconds != nil)
  await client.disconnect()
}

@Test func resourcesThroughXPCKeepOnlyRequestedProcesses() async throws {
  let listener = try LoopbackListener()
  let helper = InProcessHelper(core: helperCore())
  let client = helper.client()
  let own = try #require(NativeProcessInventory.read().processes.first { $0.id.pid == getpid() })
  let report = try await client.resources(for: [own], socketsOnly: true)
  #expect(report.resources.contains { $0.isListener && $0.localPort == listener.port })
  let stale = fixtureSample(pid: getpid(), start: 1)
  let refused = try await client.resources(for: [stale], socketsOnly: true)
  #expect(refused.resources.isEmpty && refused.summary.changedDuringScan)
  await client.disconnect()
}

@Test func helperFromAnotherVersionNeedsRegistrationAgain() async throws {
  let older = HelperInfo(
    helperVersion: HelperContract.helperVersion,
    schemaVersion: HelperContract.schemaVersion + 1, effectiveUserID: 0)
  let helper = InProcessHelper(
    delegate: ScriptedHelperDelegate(ScriptedHelper(info: older, snapshotReply: nil)))
  let client = helper.client()
  await #expect(throws: PrivilegedHelperError.needsReregistration) {
    try await client.processInventory()
  }
  await client.disconnect()
}

@Test func snapshotEncodedWithAnotherSchemaIsNotMisread() async throws {
  let foreign = try HelperCoding.encode(
    HelperReply(.success(fixtureInventory([])), schemaVersion: HelperContract.schemaVersion + 1))
  let helper = InProcessHelper(
    delegate: ScriptedHelperDelegate(ScriptedHelper(snapshotReply: foreign)))
  let client = helper.client()
  await #expect(throws: PrivilegedHelperError.needsReregistration) {
    try await client.processInventory()
  }
  await client.disconnect()
}

@Test func helperNotRunningAsRootIsNotTrusted() async throws {
  let helper = InProcessHelper(core: helperCore(effectiveUserID: 501))
  let client = helper.client()
  await #expect(throws: PrivilegedHelperError.notPrivileged) { try await client.verify() }
  await client.disconnect()
}

@Test func refusedRequestsSurfaceTheHelpersReason() async throws {
  let helper = InProcessHelper(
    delegate: ScriptedHelperDelegate(
      ScriptedHelper(snapshotReply: HelperCoding.failureReply(.rateLimited))))
  let client = helper.client()
  await #expect(throws: PrivilegedHelperError.refused(.rateLimited)) {
    try await client.processInventory()
  }
  await client.disconnect()
}

@Test func callerWithoutTheAppSignatureIsRejectedBeforeTheDelegate() async throws {
  let requirement = try #require(
    HelperCodeSigning.requirement(
      signingIdentifier: HelperContract.appSigningIdentifier, team: "WKQLY75R65"))
  let delegate = HelperListenerDelegate(core: helperCore())
  let helper = InProcessHelper(delegate: delegate, callerRequirement: requirement)
  let client = helper.client()
  await #expect(throws: PrivilegedHelperError.connectionRefused) { try await client.verify() }
  #expect(delegate.connectionCount == 0)
  await client.disconnect()
}

@Test func helperWithoutTheExpectedSignatureIsNotUsed() async throws {
  let requirement = try #require(
    HelperCodeSigning.requirement(
      signingIdentifier: HelperContract.helperSigningIdentifier, team: "WKQLY75R65"))
  let helper = InProcessHelper(core: helperCore())
  let client = PrivilegedHelperClient(connector: helper.connector(requirement: requirement))
  await #expect(throws: PrivilegedHelperError.untrustedHelper) { try await client.verify() }
  await client.disconnect()
}

@Test func missingHelperFailsWithoutCrashingAndBacksOff() async throws {
  let connector = MissingServiceConnector()
  let clock = ManualClock()
  let client = PrivilegedHelperClient(
    connector: connector, timeout: .seconds(5), retryDelay: 10, uptime: clock.uptime)
  await #expect(throws: PrivilegedHelperError.unreachable) { try await client.processInventory() }
  await #expect(throws: PrivilegedHelperError.unreachable) { try await client.processInventory() }
  #expect(connector.connections.count == 1, "Calls within the retry delay fail fast")
  clock.advance(by: 10)
  try await waitUntil { await !client.hasConnection }
  await #expect(throws: PrivilegedHelperError.unreachable) { try await client.processInventory() }
  #expect(connector.connections.count == 2)
  await client.disconnect()
}

@Test(.enabled(if: HelperCodeSigning.teamIdentifierOfCurrentProcess() == nil))
func buildWithoutATeamNeverConnects() async throws {
  #expect(throws: PrivilegedHelperError.unsignedBuild) {
    try MachServiceHelperConnector().makeConnection()
  }
  let client = PrivilegedHelperClient()
  await #expect(throws: PrivilegedHelperError.unsignedBuild) { try await client.verify() }
}

@Test func silentHelperTimesOut() async throws {
  let scripted = ScriptedHelper(snapshotReply: nil)
  let helper = InProcessHelper(delegate: ScriptedHelperDelegate(scripted))
  let client = helper.client(timeout: .milliseconds(200))
  let started = ContinuousClock.now
  await #expect(throws: PrivilegedHelperError.timedOut) { try await client.processInventory() }
  #expect(ContinuousClock.now - started < .seconds(2))
  scripted.releaseHeldReplies()
  await client.disconnect()
}

@Test func cancellationEndsAPendingCallPromptly() async throws {
  let scripted = ScriptedHelper(snapshotReply: nil)
  let helper = InProcessHelper(delegate: ScriptedHelperDelegate(scripted))
  let client = helper.client(timeout: .seconds(30))
  _ = try await client.verify()
  let task = Task { try await client.processInventory() }
  try await Task.sleep(for: .milliseconds(50))
  let started = ContinuousClock.now
  task.cancel()
  await #expect(throws: CancellationError.self) { try await task.value }
  #expect(ContinuousClock.now - started < .seconds(1))
  scripted.releaseHeldReplies()
  await client.disconnect()
}

@Test func clientResendsAfterTheHelperClosesItsConnection() async throws {
  let delegate = ClosingDelegate(core: helperCore())
  let helper = InProcessHelper(delegate: delegate)
  let connector = helper.connector()
  let client = PrivilegedHelperClient(connector: connector)
  _ = try await client.verify()
  delegate.closeAll()
  _ = try await client.processInventory()
  #expect(connector.connections.count == 1, "The same connection reaches the helper again")
  #expect(delegate.acceptedCount == 2)
  await client.disconnect()
}

@Test func listenerRefusesConnectionsBeyondItsLimit() async throws {
  let delegate = HelperListenerDelegate(core: helperCore(), maximumConnections: 1)
  let helper = InProcessHelper(delegate: delegate)
  let first = helper.client()
  _ = try await first.verify()
  let second = helper.client()
  await #expect(throws: PrivilegedHelperError.connectionRefused) { try await second.verify() }
  await #expect(throws: PrivilegedHelperError.connectionRefused) { try await second.verify() }
  #expect(delegate.connectionCount == 1)
  await first.disconnect()
  try await waitUntil { delegate.connectionCount == 0 }
  let third = helper.client()
  _ = try await third.verify()
  await third.disconnect()
}

@Test func oneUserCannotHoldEveryHelperConnection() async throws {
  let delegate = HelperListenerDelegate(
    core: helperCore(), maximumConnections: 8, maximumConnectionsPerUser: 1)
  let helper = InProcessHelper(delegate: delegate)
  let first = helper.client()
  _ = try await first.verify()
  await #expect(throws: PrivilegedHelperError.connectionRefused) { try await helper.client().verify() }
  #expect(delegate.connectionCount == 1)
  await first.disconnect()
}

struct MissingServiceConnector: PrivilegedHelperConnecting {
  let connections = Counter()
  func makeConnection() throws(PrivilegedHelperError) -> NSXPCConnection {
    connections.increment()
    return NSXPCConnection(machServiceName: "dev.stratabar.helper.tests.missing-\(UUID())")
  }
}

final class ClosingDelegate: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
  private let wrapped: HelperListenerDelegate
  private let accepted = NSMutableArray()
  init(core: HelperCore) { wrapped = HelperListenerDelegate(core: core) }
  func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection)
    -> Bool
  {
    accepted.add(connection)
    return wrapped.listener(listener, shouldAcceptNewConnection: connection)
  }
  var acceptedCount: Int { accepted.count }
  func closeAll() {
    for case let connection as NSXPCConnection in accepted { connection.invalidate() }
  }
}

func waitUntil(
  timeout: Duration = .seconds(5), _ condition: @Sendable () async -> Bool
) async throws {
  let deadline = ContinuousClock.now + timeout
  while await !condition() {
    try #require(ContinuousClock.now < deadline, "Condition not met in time")
    try await Task.sleep(for: .milliseconds(5))
  }
}
