import CSystem
import Darwin
import Foundation
import StrataCore

public enum ProcessActionError: LocalizedError, Sendable {
  case ineligible, expired, targetChanged, accessDenied
  public var errorDescription: String? {
    switch self {
    case .ineligible:
      "This process cannot be controlled from Strata Monitor. System processes and other users' processes are protected."
    case .expired: "This confirmation expired. Select the process and try again."
    case .targetChanged: "The process ended or changed. Refresh before trying again."
    case .accessDenied: "macOS did not permit controlling this process. No signal was sent."
    }
  }
}

public protocol ProcessControlling: Sendable {
  func prepare(_ process: ProcessSample, signal: ProcessSignal) async throws
    -> PreparedProcessAction
  func perform(_ action: PreparedProcessAction) async throws
  func cancel(_ identifier: UUID) async
  // Only for undoing Strata Monitor's own pause, so it needs no confirmation.
  func resumePaused(_ identity: ProcessIdentity) async throws
}

public actor ProcessControl: ProcessControlling {
  private struct Pending {
    let action: PreparedProcessAction
    let token: SBActionToken
    let created: TimeInterval
  }
  private var pending: Pending?
  private let uptime: @Sendable () -> TimeInterval
  public init(
    uptime: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
  ) {
    self.uptime = uptime
  }
  public func prepare(_ process: ProcessSample, signal: ProcessSignal) throws
    -> PreparedProcessAction
  {
    try Task.checkCancellation()
    pending = nil
    guard
      ProcessActionPolicy.allows(
        signal, for: process, currentPID: getpid(), currentUser: getuid())
    else {
      throw ProcessActionError.ineligible
    }
    let identity = process.id
    let token = try Self.token(for: identity)
    try Task.checkCancellation()
    let action = PreparedProcessAction(
      id: UUID(), identity: identity, name: process.name, signal: signal)
    pending = Pending(action: action, token: token, created: uptime())
    return action
  }
  public func perform(_ action: PreparedProcessAction) throws {
    try Task.checkCancellation()
    guard let stored = pending, stored.action.id == action.id else {
      throw ProcessActionError.expired
    }
    pending = nil
    guard stored.action.identity == action.identity,
      ProcessActionPolicy.confirmationIsCurrent(created: stored.created, now: uptime())
    else {
      throw ProcessActionError.expired
    }
    let identity = stored.action.identity
    guard sb_process_identity(identity.pid, identity.startSeconds, identity.startMicroseconds)
    else {
      throw ProcessActionError.targetChanged
    }
    try Self.send(stored.action.signal, with: stored.token)
    // A paused process keeps Terminate pending until it runs again, and a pause can still be
    // landing; continuing right after, as service managers do, lets it handle Terminate either way.
    if stored.action.signal == .terminate { try? Self.send(.resume, with: stored.token) }
  }
  public func resumePaused(_ identity: ProcessIdentity) throws {
    try Self.send(.resume, with: Self.token(for: identity))
  }
  private static func token(for identity: ProcessIdentity) throws -> SBActionToken {
    guard sb_process_identity(identity.pid, identity.startSeconds, identity.startMicroseconds)
    else {
      throw ProcessActionError.targetChanged
    }
    var token = SBActionToken()
    let status = sb_prepare_signal(
      identity.pid, identity.startSeconds, identity.startMicroseconds, &token)
    guard status == 0 else {
      throw status == ESRCH ? ProcessActionError.targetChanged : ProcessActionError.accessDenied
    }
    return token
  }
  private static func send(_ signal: ProcessSignal, with token: SBActionToken) throws {
    var token = token
    let number: Int32 =
      switch signal {
      case .terminate: SIGTERM
      case .forceQuit: SIGKILL
      case .pause: SIGSTOP
      case .resume: SIGCONT
      }
    let status = sb_send_signal(&token, number)
    if status == ESRCH { throw ProcessActionError.targetChanged }
    guard status == 0 else { throw ProcessActionError.accessDenied }
  }
  public func cancel(_ identifier: UUID) {
    if pending?.action.id == identifier { pending = nil }
  }
}
