import Foundation
import Synchronization
import StrataHelperInterface

struct HelperCore: Sendable {
  let snapshots: ProcessSnapshotCache
  let resources: HelperResourceInspector
  let activity: HelperActivity
  let uptime: @Sendable () -> TimeInterval
  let effectiveUserID: @Sendable () -> uid_t

  static func live() -> HelperCore {
    let uptime: @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    return HelperCore(
      snapshots: ProcessSnapshotCache(uptime: uptime), resources: HelperResourceInspector(),
      activity: HelperActivity(uptime: uptime), uptime: uptime, effectiveUserID: { geteuid() })
  }
}

final class HelperConnectionService: NSObject, StrataHelperProtocol, Sendable {
  private let core: HelperCore
  private let caller: CallerScope
  private let limiter: RequestRateLimiter
  // One inspection at a time per connection, so queued work cannot pile up behind a slow one;
  // it stops when the connection closes. A generation ties each slot to the request holding it.
  private struct Inspection {
    var current: UInt64?
    var generation: UInt64 = 0
    var task: Task<Void, Never>?
  }
  private let inspection = Mutex(Inspection())

  init(core: HelperCore, caller: CallerScope) {
    self.core = core
    self.caller = caller
    limiter = RequestRateLimiter(uptime: core.uptime)
  }
  func handshake(reply: @escaping @Sendable (Data) -> Void) {
    let info = HelperInfo(
      helperVersion: HelperContract.helperVersion, schemaVersion: HelperContract.schemaVersion,
      effectiveUserID: core.effectiveUserID())
    respond(.query, reply: reply) { HelperCoding.reply(info) }
  }
  func processSnapshot(reply: @escaping @Sendable (Data) -> Void) {
    respond(.query, reply: reply) { [core] in await core.snapshots.reply() }
  }
  func resources(_ request: Data, reply: @escaping @Sendable (Data) -> Void) {
    let slot: UInt64? = inspection.withLock { state in
      guard state.current == nil else { return nil }
      state.generation &+= 1
      state.current = state.generation
      return state.generation
    }
    guard let slot else {
      reply(HelperCoding.failureReply(.rateLimited))
      return
    }
    let task = respond(.resources, reply: reply) { [self] in
      defer { finishInspection(slot) }
      return await core.resources.reply(to: request, for: caller)
    }
    inspection.withLock { state in
      guard state.current == slot else { return }
      if let task { state.task = task } else { state.current = nil }
    }
  }
  func connectionClosed() {
    inspection.withLock { $0.task?.cancel() }
  }
  private func finishInspection(_ slot: UInt64) {
    inspection.withLock { state in
      guard state.current == slot else { return }
      state.current = nil
      state.task = nil
    }
  }
  // Every path below calls reply exactly once.
  @discardableResult
  private func respond(
    _ kind: HelperRequestKind, reply: @escaping @Sendable (Data) -> Void,
    work: @escaping @Sendable () async -> Data
  ) -> Task<Void, Never>? {
    guard limiter.admits(kind) else {
      reply(HelperCoding.failureReply(.rateLimited))
      return nil
    }
    let activity = core.activity
    activity.requestStarted()
    return Task {
      let data = await work()
      activity.requestFinished()
      reply(data)
    }
  }
}
