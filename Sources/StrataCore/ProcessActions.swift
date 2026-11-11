import Foundation

public enum ProcessSignal: String, Sendable {
  case terminate, forceQuit, pause, resume
  public var title: String {
    switch self {
    case .terminate: String(localized: "Terminate")
    case .forceQuit: String(localized: "Force Quit")
    case .pause: String(localized: "Pause")
    case .resume: String(localized: "Resume")
    }
  }
  public var explanation: String {
    switch self {
    case .terminate: String(localized: "Send SIGTERM so the process can handle its shutdown.")
    case .forceQuit: String(localized: "Send SIGKILL to stop the process immediately. Unsaved work may be lost.")
    case .pause: String(localized: "Send SIGSTOP to freeze the process until it is resumed.")
    case .resume: String(localized: "Send SIGCONT so a paused process continues.")
    }
  }
  // Reversible signals act at once; only ending a process asks for confirmation.
  public var needsConfirmation: Bool { self == .terminate || self == .forceQuit }
}

public struct PreparedProcessAction: Identifiable, Sendable {
  public let id: UUID
  public let identity: ProcessIdentity
  public let identities: [ProcessIdentity]
  public let name: String
  public let signal: ProcessSignal
  public init(id: UUID, identity: ProcessIdentity, name: String, signal: ProcessSignal) {
    self.init(id: id, identities: [identity], name: name, signal: signal)
  }
  public init(id: UUID, identities: [ProcessIdentity], name: String, signal: ProcessSignal) {
    self.id = id
    self.identity =
      identities.first ?? ProcessIdentity(pid: 0, startSeconds: 0, startMicroseconds: 0)
    self.identities = identities
    self.name = name
    self.signal = signal
  }
}

public enum ProcessActionPolicy {
  public static let confirmationLifetime: TimeInterval = 30
  public static func allows(_ process: ProcessSample, currentPID: Int32, currentUser: UInt32)
    -> Bool
  {
    currentUser != 0 && process.userID == currentUser && process.id.pid > 1
      && process.id.pid != currentPID
  }
  // Pausing one of these freezes the desktop itself, even though the user owns them.
  public static let sessionCriticalNames: Set<String> = [
    "loginwindow", "WindowManager", "Dock", "ControlCenter", "SystemUIServer", "Finder",
  ]
  // Terminating loginwindow or WindowManager tears down the user's login session or window server.
  public static let nonTerminableNames: Set<String> = [
    "loginwindow", "WindowManager",
  ]
  public static func allows(
    _ signal: ProcessSignal, for process: ProcessSample, currentPID: Int32, currentUser: UInt32
  ) -> Bool {
    guard allows(process, currentPID: currentPID, currentUser: currentUser) else { return false }
    switch signal {
    case .pause: return process.runState != .stopped && !sessionCriticalNames.contains(process.name)
    case .resume: return process.runState == .stopped
    case .terminate, .forceQuit: return !nonTerminableNames.contains(process.name)
    }
  }
  public static func eligible(
    _ signal: ProcessSignal, in processes: [ProcessSample], currentPID: Int32, currentUser: UInt32
  ) -> [ProcessSample] {
    var seen: Set<ProcessIdentity> = []
    return processes.filter {
      allows(signal, for: $0, currentPID: currentPID, currentUser: currentUser)
        && seen.insert($0.id).inserted
    }
  }
  public static func confirmationIsCurrent(created: TimeInterval, now: TimeInterval) -> Bool {
    created.isFinite && now.isFinite && now >= created && now - created <= confirmationLifetime
  }
}

// Processes Strata Monitor paused, so they can be resumed when Strata Monitor quits or after it crashed.
public struct PausedProcessLedger: Codable, Sendable, Equatable {
  public private(set) var identities: Set<ProcessIdentity> = []
  public init() {}
  public mutating func record(_ signal: ProcessSignal, for identity: ProcessIdentity) {
    switch signal {
    case .pause: identities.insert(identity)
    case .resume, .terminate, .forceQuit: identities.remove(identity)
    }
  }
  public mutating func record(_ signal: ProcessSignal, for identities: [ProcessIdentity]) {
    for identity in identities { record(signal, for: identity) }
  }
  public mutating func forget(_ identity: ProcessIdentity) { identities.remove(identity) }
}
