import Foundation
import StrataCore
import StrataHelperInterface
import StrataSystem
import Synchronization

@testable import StrataBarHelper

final class ManualClock: Sendable {
  private let value = Mutex<TimeInterval>(1_000)
  var now: TimeInterval { value.withLock { $0 } }
  func advance(by seconds: TimeInterval) { value.withLock { $0 += seconds } }
  var uptime: @Sendable () -> TimeInterval { { self.now } }
}

final class Counter: Sendable {
  private let value = Mutex(0)
  var count: Int { value.withLock { $0 } }
  @discardableResult func increment() -> Int { value.withLock { $0 += 1; return $0 } }
}

func fixtureSample(
  pid: Int32, start: UInt64 = 10, userID: UInt32 = 501, parent: Int32 = 1,
  cpu: UInt64? = nil, resident: UInt64? = nil, footprint: UInt64? = nil
) -> ProcessSample {
  ProcessSample(
    id: ProcessIdentity(pid: pid, startSeconds: start, startMicroseconds: 0),
    parentPID: parent, userID: userID, name: "process-\(pid)", path: "/bin/process-\(pid)",
    cpuTimeNanoseconds: cpu, residentBytes: resident, footprintBytes: footprint,
    threads: cpu == nil ? nil : 1)
}

func fixtureInventory(_ processes: [ProcessSample]) -> ProcessInventory {
  ProcessInventory(processes: processes)
}

func helperCore(
  clock: ManualClock = ManualClock(), effectiveUserID: uid_t = 0,
  scan: @escaping @Sendable () -> Data = {
    HelperCoding.reply(fixtureInventory([fixtureSample(pid: 1, userID: 0, cpu: 5)]))
  }
) -> HelperCore {
  HelperCore(
    snapshots: ProcessSnapshotCache(uptime: clock.uptime, scan: scan),
    resources: HelperResourceInspector(), activity: HelperActivity(uptime: clock.uptime),
    uptime: clock.uptime, effectiveUserID: { effectiveUserID })
}

/// NSXPCListenerEndpoint is immutable once created; the listener owns its lifetime.
struct EndpointConnector: PrivilegedHelperConnecting, @unchecked Sendable {
  let endpoint: NSXPCListenerEndpoint
  let connections = Counter()
  var requirement: String?
  func makeConnection() throws(PrivilegedHelperError) -> NSXPCConnection {
    connections.increment()
    let connection = NSXPCConnection(listenerEndpoint: endpoint)
    if let requirement { connection.setCodeSigningRequirement(requirement) }
    return connection
  }
}

/// An in-process helper reachable through an anonymous listener, as the app reaches the daemon.
final class InProcessHelper: @unchecked Sendable {
  let listener = NSXPCListener.anonymous()
  let delegate: any NSXPCListenerDelegate
  init(delegate: any NSXPCListenerDelegate, callerRequirement: String? = nil) {
    self.delegate = delegate
    if let callerRequirement { listener.setConnectionCodeSigningRequirement(callerRequirement) }
    listener.delegate = delegate
    listener.activate()
  }
  convenience init(core: HelperCore, callerRequirement: String? = nil) {
    self.init(delegate: HelperListenerDelegate(core: core), callerRequirement: callerRequirement)
  }
  func connector(requirement: String? = nil) -> EndpointConnector {
    EndpointConnector(endpoint: listener.endpoint, requirement: requirement)
  }
  func client(timeout: Duration = .seconds(5), retryDelay: TimeInterval = 10)
    -> PrivilegedHelperClient
  {
    PrivilegedHelperClient(connector: connector(), timeout: timeout, retryDelay: retryDelay)
  }
  deinit { listener.invalidate() }
}

/// Exports a scripted helper object instead of the real service.
final class ScriptedHelperDelegate: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
  let helper: ScriptedHelper
  init(_ helper: ScriptedHelper) { self.helper = helper }
  func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection)
    -> Bool
  {
    connection.exportedInterface = HelperContract.makeInterface()
    connection.exportedObject = helper
    connection.activate()
    return true
  }
}

final class ScriptedHelper: NSObject, StrataHelperProtocol, Sendable {
  let handshakeReply: Data
  let snapshotReply: Data?
  private let heldReplies = Mutex<[@Sendable (Data) -> Void]>([])

  init(info: HelperInfo = HelperInfo(
    helperVersion: HelperContract.helperVersion, schemaVersion: HelperContract.schemaVersion,
    effectiveUserID: 0), snapshotReply: Data?)
  {
    handshakeReply = HelperCoding.reply(info)
    self.snapshotReply = snapshotReply
  }
  func handshake(reply: @escaping @Sendable (Data) -> Void) { reply(handshakeReply) }
  func processSnapshot(reply: @escaping @Sendable (Data) -> Void) {
    if let snapshotReply {
      reply(snapshotReply)
    } else {
      heldReplies.withLock { $0.append(reply) }
    }
  }
  func resources(_ request: Data, reply: @escaping @Sendable (Data) -> Void) {
    reply(HelperCoding.failureReply(.invalidRequest))
  }
  func releaseHeldReplies() {
    for reply in heldReplies.withLock({ replies in defer { replies.removeAll() }; return replies }) {
      reply(HelperCoding.failureReply(.rateLimited))
    }
  }
}

/// Collects replies from direct calls to an exported object.
final class ReplyRecorder: Sendable {
  private let replies = Mutex<[Data]>([])
  var reply: @Sendable (Data) -> Void { { data in self.replies.withLock { $0.append(data) } } }
  var count: Int { replies.withLock { $0.count } }
  var all: [Data] { replies.withLock { $0 } }
  func waitFor(_ expected: Int, timeout: Duration = .seconds(5)) async throws {
    let deadline = ContinuousClock.now + timeout
    while count < expected, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(5))
    }
  }
}

func decodedFailure(_ data: Data) -> HelperFailure? {
  guard let reply = try? HelperCoding.decode(HelperReply<HelperInfo>.self, from: data) else {
    return nil
  }
  if case .failure(let failure) = reply.outcome { return failure }
  return nil
}

let testCaller = CallerScope(userID: getuid()) { _ in false }
