import AppKit
import Foundation
import StrataCore

@MainActor public protocol ApplicationQuitTarget: AnyObject {
  var processIdentifier: Int32 { get }
  var isTerminated: Bool { get }
  var hasApplicationBundle: Bool { get }
  func isSameApplication(as other: any ApplicationQuitTarget) -> Bool
  func requestQuit() -> Bool
}
@MainActor public protocol ApplicationFinding {
  func application(for pid: Int32) -> (any ApplicationQuitTarget)?
}
@MainActor public struct RunningApplicationDirectory: ApplicationFinding {
  public init() {}
  public func application(for pid: Int32) -> (any ApplicationQuitTarget)? {
    NSRunningApplication(processIdentifier: pid).map(NativeQuitTarget.init)
  }
}
@MainActor private final class NativeQuitTarget: ApplicationQuitTarget {
  private let application: NSRunningApplication
  init(_ application: NSRunningApplication) { self.application = application }
  var processIdentifier: Int32 { application.processIdentifier }
  var isTerminated: Bool { application.isTerminated }
  var hasApplicationBundle: Bool { application.bundleURL?.isFileURL == true }
  func isSameApplication(as other: any ApplicationQuitTarget) -> Bool {
    guard let other = other as? NativeQuitTarget else { return false }
    // AppKit explicitly requires application equality, not PID comparison.
    // A retained application instance remains valid after it exits.
    return application.isEqual(other.application)
  }
  func requestQuit() -> Bool { application.terminate() }
}

public enum ApplicationQuitError: LocalizedError, Sendable {
  case notAnApplication, targetChanged, expired, requestRejected
  public var errorDescription: String? {
    switch self {
    case .notAnApplication: String(localized: "Normal Quit is available only for eligible applications.")
    case .targetChanged: String(localized: "The application ended or changed. Select it again before requesting Quit.")
    case .expired: String(localized: "This Quit confirmation expired. Select the application and try again.")
    case .requestRejected:
      String(localized: "macOS did not accept the Quit request. The application was not force-quit.")
    }
  }
}
@MainActor public protocol ApplicationQuitting {
  func canQuit(_ process: ProcessSample) -> Bool
  func prepare(_ process: ProcessSample) async throws -> PreparedApplicationQuit
  func perform(_ action: PreparedApplicationQuit) async throws
  func cancel(_ identifier: UUID)
}

@MainActor public final class ApplicationQuitService: ApplicationQuitting {
  private struct Pending {
    let action: PreparedApplicationQuit
    let application: any ApplicationQuitTarget
    let created: TimeInterval
  }
  private let applications: any ApplicationFinding
  private let identities: any ProcessIdentityVerifying
  private let uptime: @MainActor () -> TimeInterval
  private var pending: Pending?
  public init(
    applications: any ApplicationFinding = RunningApplicationDirectory(),
    identities: any ProcessIdentityVerifying = ProcessIdentityVerifier(),
    uptime: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
  ) {
    self.applications = applications
    self.identities = identities
    self.uptime = uptime
  }
  public func canQuit(_ process: ProcessSample) -> Bool {
    ProcessActionPolicy.allows(process, currentPID: getpid(), currentUser: getuid())
      && applications.application(for: process.id.pid).map {
        !$0.isTerminated && $0.hasApplicationBundle
      } == true
  }
  public func prepare(_ process: ProcessSample) throws -> PreparedApplicationQuit {
    try Task.checkCancellation()
    pending = nil
    guard canQuit(process) else { throw ApplicationQuitError.notAnApplication }
    guard identities.isCurrent(process.id),
      let application = applications.application(for: process.id.pid),
      application.processIdentifier == process.id.pid, !application.isTerminated,
      application.hasApplicationBundle,
      identities.isCurrent(process.id)
    else { throw ApplicationQuitError.targetChanged }
    let action = PreparedApplicationQuit(id: UUID(), identity: process.id, name: process.name)
    pending = Pending(action: action, application: application, created: uptime())
    return action
  }
  public func perform(_ action: PreparedApplicationQuit) throws {
    try Task.checkCancellation()
    guard let stored = pending, stored.action.id == action.id else {
      throw ApplicationQuitError.expired
    }
    pending = nil
    guard stored.action.identity == action.identity,
      ProcessActionPolicy.confirmationIsCurrent(created: stored.created, now: uptime())
    else { throw ApplicationQuitError.expired }
    guard let current = applications.application(for: stored.action.identity.pid),
      stored.application.isSameApplication(as: current), !stored.application.isTerminated,
      stored.application.processIdentifier == stored.action.identity.pid,
      identities.isCurrent(stored.action.identity)
    else { throw ApplicationQuitError.targetChanged }
    try Task.checkCancellation()
    guard stored.application.requestQuit() else { throw ApplicationQuitError.requestRejected }
  }
  public func cancel(_ identifier: UUID) { if pending?.action.id == identifier { pending = nil } }
}
