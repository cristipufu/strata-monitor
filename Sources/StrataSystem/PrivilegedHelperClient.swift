import Foundation
import StrataCore
import StrataHelperInterface
import Synchronization

public enum PrivilegedHelperError: LocalizedError, Sendable, Equatable {
  case unsignedBuild, unreachable, untrustedHelper, connectionRefused, needsReregistration
  case notPrivileged, timedOut, interrupted, refused(HelperFailure)
  public var errorDescription: String? {
    switch self {
    case .unsignedBuild:
      "This build isn't signed by a developer team, so it can't verify the helper."
    case .unreachable:
      "The helper isn't running. Turn it on in System Settings › General › Login Items & Extensions."
    case .untrustedHelper: "The helper's signature doesn't match this copy of Strata Monitor."
    case .connectionRefused: "The helper refused the connection from this copy of Strata Monitor."
    case .needsReregistration: "The helper is from another version of Strata Monitor and needs approval again."
    case .notPrivileged: "The helper isn't running as an administrator service."
    case .timedOut: "The helper didn't answer in time."
    case .interrupted: "The helper stopped while answering."
    case .refused(.rateLimited): "The helper is busy. Try again in a moment."
    case .refused: "The helper couldn't answer this request."
    }
  }
  var persists: Bool {
    switch self {
    case .timedOut, .interrupted, .refused: false
    default: true
    }
  }
}

public protocol PrivilegedHelperConnecting: Sendable {
  func makeConnection() throws(PrivilegedHelperError) -> NSXPCConnection
}

public struct MachServiceHelperConnector: PrivilegedHelperConnecting {
  public init() {}
  public func makeConnection() throws(PrivilegedHelperError) -> NSXPCConnection {
    guard
      let requirement = HelperCodeSigning.peerRequirement(
        signingIdentifier: HelperContract.helperSigningIdentifier)
    else { throw .unsignedBuild }
    let connection = NSXPCConnection(
      machServiceName: HelperContract.machServiceName, options: .privileged)
    connection.setCodeSigningRequirement(requirement)
    return connection
  }
}

public protocol PrivilegedProcessSnapshotting: Sendable {
  func processInventory() async throws -> ProcessInventory
}
public protocol PrivilegedResourceInspecting: Sendable {
  func resources(for processes: [ProcessSample], socketsOnly: Bool) async throws -> ResourceReport
}

/// Keeps one connection and verifies the helper's versions and privilege once per helper launch.
/// After a failure that will not resolve by itself, calls fail fast with it for `retryDelay`
/// instead of asking launchd again on every refresh.
public actor PrivilegedHelperClient: PrivilegedProcessSnapshotting, PrivilegedResourceInspecting {
  private typealias Send = @Sendable (any StrataHelperProtocol, @escaping @Sendable (Data) -> Void)
    -> Void
  private let connector: any PrivilegedHelperConnecting
  private let timeout: Duration
  // Snapshots answer within milliseconds; inspecting every process's descriptors takes longer.
  private let inspectionTimeout: Duration
  private let retryDelay: TimeInterval
  private let uptime: @Sendable () -> TimeInterval
  private var connection: NSXPCConnection?
  private var connectionGeneration = 0
  private var verifiedHelper: HelperInfo?
  private var backoff: (until: TimeInterval, error: PrivilegedHelperError)?

  public init(
    connector: any PrivilegedHelperConnecting = MachServiceHelperConnector(),
    timeout: Duration = .seconds(2), inspectionTimeout: Duration = .seconds(30),
    retryDelay: TimeInterval = 10,
    uptime: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
  ) {
    self.connector = connector
    self.timeout = timeout
    self.inspectionTimeout = inspectionTimeout
    self.retryDelay = retryDelay
    self.uptime = uptime
  }

  public func verify() async throws -> HelperInfo {
    try await withBackoff { try await self.verifiedHelperInfo() }
  }
  public func processInventory() async throws -> ProcessInventory {
    try await withBackoff {
      try await self.exchange(ProcessInventory.self, timeout: self.timeout) {
        $0.processSnapshot(reply: $1)
      }
    }
  }
  public func resources(for processes: [ProcessSample], socketsOnly: Bool) async throws
    -> ResourceReport
  {
    let requested = Set(processes.map(\.id))
    let identities = requested.map {
      ProcessIdentityWire(
        pid: $0.pid, startSeconds: $0.startSeconds, startMicroseconds: $0.startMicroseconds)
    }
    var report = ResourceReport(resources: [])
    for batch in stride(from: 0, to: identities.count, by: HelperContract.maximumResourceIdentities)
    {
      let end = min(batch + HelperContract.maximumResourceIdentities, identities.count)
      let request = try encoded(
        ResourceRequest(identities: Array(identities[batch..<end]), socketsOnly: socketsOnly))
      let partial = try await withBackoff {
        try await self.exchange(ResourceReport.self, timeout: self.inspectionTimeout) {
          $0.resources(request, reply: $1)
        }
      }
      report.summary.merge(partial.summary)
      report.resources += partial.resources.filter { requested.contains($0.owner) }
    }
    return report
  }
  var hasConnection: Bool { connection != nil }
  public func disconnect() {
    connection?.invalidate()
    connection = nil
    verifiedHelper = nil
    backoff = nil
  }

  private func withBackoff<Value: Sendable>(
    _ operation: @Sendable () async throws -> Value
  ) async throws -> Value {
    if let backoff, uptime() < backoff.until { throw backoff.error }
    do {
      return try await resendingOnce(operation)
    } catch let error as PrivilegedHelperError where error.persists {
      backoff = (uptime() + retryDelay, error)
      throw error
    }
  }
  // launchd stops an idle helper while this connection stays open, and the next message starts it
  // again. The helper refusing a connection also looks like an interruption, so a second one in a
  // row is reported as a refusal.
  private func resendingOnce<Value: Sendable>(
    _ operation: @Sendable () async throws -> Value
  ) async throws -> Value {
    do { return try await operation() } catch PrivilegedHelperError.interrupted {}
    verifiedHelper = nil
    do {
      return try await operation()
    } catch PrivilegedHelperError.interrupted {
      throw PrivilegedHelperError.connectionRefused
    }
  }
  private func verifiedHelperInfo() async throws -> HelperInfo {
    if let verifiedHelper { return verifiedHelper }
    let reply = try await send(timeout: timeout) { $0.handshake(reply: $1) }
    let info = try decoded(HelperInfo.self, from: reply)
    guard info.matchesThisBuild else { throw PrivilegedHelperError.needsReregistration }
    guard info.effectiveUserID == 0 else { throw PrivilegedHelperError.notPrivileged }
    verifiedHelper = info
    return info
  }
  private func exchange<Payload: Codable & Sendable>(
    _ type: Payload.Type, timeout: Duration, _ message: @escaping Send
  ) async throws -> Payload {
    _ = try await verifiedHelperInfo()
    return try decoded(type, from: try await send(timeout: timeout, message))
  }
  private func send(timeout: Duration, _ message: @escaping Send) async throws -> Data {
    let connection = try liveConnection()
    let pending = PendingReply()
    let timer = Task {
      try await Task.sleep(for: timeout)
      pending.finish(.failure(PrivilegedHelperError.timedOut))
    }
    defer { timer.cancel() }
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        pending.install(continuation)
        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
          pending.finish(.failure(Self.helperError(error)))
        }
        guard let helper = proxy as? any StrataHelperProtocol else {
          pending.finish(.failure(PrivilegedHelperError.refused(.malformedReply)))
          return
        }
        message(helper) { pending.finish(.success($0)) }
      }
    } onCancel: {
      pending.finish(.failure(CancellationError()))
    }
  }
  private func liveConnection() throws(PrivilegedHelperError) -> NSXPCConnection {
    if let connection { return connection }
    let connection = try connector.makeConnection()
    connectionGeneration += 1
    let generation = connectionGeneration
    connection.remoteObjectInterface = HelperContract.makeInterface()
    connection.interruptionHandler = { [weak self] in
      Task { await self?.connectionInterrupted(generation) }
    }
    connection.invalidationHandler = { [weak self] in
      Task { await self?.connectionInvalidated(generation) }
    }
    connection.activate()
    self.connection = connection
    return connection
  }
  private func connectionInterrupted(_ generation: Int) {
    guard generation == connectionGeneration else { return }
    verifiedHelper = nil
  }
  private func connectionInvalidated(_ generation: Int) {
    guard generation == connectionGeneration else { return }
    connection = nil
    verifiedHelper = nil
  }
  private func encoded(_ request: ResourceRequest) throws -> Data {
    do throws(HelperFailure) {
      return try HelperCoding.encode(request, limit: HelperContract.maximumRequestBytes)
    } catch {
      throw PrivilegedHelperError.refused(error)
    }
  }
  private func decoded<Payload: Codable & Sendable>(_ type: Payload.Type, from data: Data) throws
    -> Payload
  {
    do throws(HelperFailure) {
      return try HelperCoding.decode(HelperReply<Payload>.self, from: data).payload()
    } catch .unsupportedSchema {
      throw PrivilegedHelperError.needsReregistration
    } catch {
      throw PrivilegedHelperError.refused(error)
    }
  }
  private static func helperError(_ error: any Error) -> PrivilegedHelperError {
    let error = error as NSError
    guard error.domain == NSCocoaErrorDomain else { return .unreachable }
    switch error.code {
    case NSXPCConnectionInterrupted: return .interrupted
    case NSXPCConnectionCodeSigningRequirementFailure: return .untrustedHelper
    default: return .unreachable
    }
  }
}

/// Resumes its continuation exactly once, with whichever of reply, error, timeout or
/// cancellation arrives first.
private final class PendingReply: Sendable {
  private struct State {
    var continuation: CheckedContinuation<Data, any Error>?
    var outcome: Result<Data, any Error>?
  }
  private let state = Mutex(State())

  func install(_ continuation: CheckedContinuation<Data, any Error>) {
    state.withLock {
      if let outcome = $0.outcome {
        continuation.resume(with: outcome)
      } else {
        $0.continuation = continuation
      }
    }
  }
  func finish(_ outcome: Result<Data, any Error>) {
    state.withLock {
      guard $0.outcome == nil else { return }
      $0.outcome = outcome
      $0.continuation?.resume(with: outcome)
      $0.continuation = nil
    }
  }
}
