import CSystem
import Darwin
import Foundation
import StrataCore

public enum ProcessActionError: LocalizedError, Sendable {
  case ineligible, expired, targetChanged, accessDenied
  public var errorDescription: String? {
    switch self {
    case .ineligible:
      String(localized: "This process cannot be controlled from Strata Monitor. System processes and other users' processes are protected.")
    case .expired: String(localized: "This confirmation expired. Select the process and try again.")
    case .targetChanged: String(localized: "The process ended or changed. Refresh before trying again.")
    case .accessDenied: String(localized: "macOS did not permit controlling this process. No signal was sent.")
    }
  }
}

public protocol ProcessControlling: Sendable {
  func prepare(_ process: ProcessSample, signal: ProcessSignal) async throws
    -> PreparedProcessAction
  func prepare(_ processes: [ProcessSample], name: String, signal: ProcessSignal) async throws
    -> PreparedProcessAction
  func perform(_ action: PreparedProcessAction) async throws
  func cancel(_ identifier: UUID) async
  // Only for undoing Strata Monitor's own pause, so it needs no confirmation.
  func resumePaused(_ identity: ProcessIdentity) async throws
}

extension ProcessControlling {
  public func prepare(_ processes: [ProcessSample], name: String, signal: ProcessSignal)
    async throws -> PreparedProcessAction
  {
    guard let first = processes.first else { throw ProcessActionError.ineligible }
    let single = try await prepare(first, signal: signal)
    return PreparedProcessAction(
      id: single.id, identities: processes.map(\.id), name: name, signal: signal)
  }
}

public actor ProcessControl: ProcessControlling {
  private struct Target {
    let identity: ProcessIdentity
    let token: SBActionToken
  }
  private struct Pending {
    let action: PreparedProcessAction
    let targets: [Target]
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
    try prepare([process], name: process.name, signal: signal)
  }
  public func prepare(_ processes: [ProcessSample], name: String, signal: ProcessSignal) throws
    -> PreparedProcessAction
  {
    try Task.checkCancellation()
    pending = nil
    let eligible = ProcessActionPolicy.eligible(
      signal, in: processes, currentPID: getpid(), currentUser: getuid())
    guard !eligible.isEmpty else {
      throw ProcessActionError.ineligible
    }
    var targets: [Target] = []
    var lastError: ProcessActionError = .targetChanged
    for process in eligible {
      try Task.checkCancellation()
      do {
        let token = try Self.token(for: process.id)
        targets.append(Target(identity: process.id, token: token))
      } catch let error as ProcessActionError {
        lastError = error
        if eligible.count == 1 { throw error }
      }
    }
    guard !targets.isEmpty else { throw lastError }
    let action = PreparedProcessAction(
      id: UUID(), identities: targets.map(\.identity), name: name, signal: signal)
    pending = Pending(action: action, targets: targets, created: uptime())
    return action
  }
  public func perform(_ action: PreparedProcessAction) throws {
    try Task.checkCancellation()
    guard let stored = pending, stored.action.id == action.id else {
      throw ProcessActionError.expired
    }
    pending = nil
    guard stored.action.identities == action.identities,
      ProcessActionPolicy.confirmationIsCurrent(created: stored.created, now: uptime())
    else {
      throw ProcessActionError.expired
    }
    var sentCount = 0
    var lastError: ProcessActionError = .targetChanged
    for target in stored.targets {
      let identity = target.identity
      guard sb_process_identity(identity.pid, identity.startSeconds, identity.startMicroseconds)
      else {
        if stored.targets.count == 1 { throw ProcessActionError.targetChanged }
        continue
      }
      do {
        try Self.send(stored.action.signal, with: target.token)
        // A paused process keeps Terminate pending until it runs again, and a pause can still be
        // landing; continuing right after, as service managers do, lets it handle Terminate either way.
        if stored.action.signal == .terminate { try? Self.send(.resume, with: target.token) }
        sentCount += 1
      } catch let error as ProcessActionError {
        lastError = error
        if stored.targets.count == 1 { throw error }
      }
    }
    guard sentCount > 0 else { throw lastError }
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
