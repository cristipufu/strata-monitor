public enum WorkspaceAvailabilityEvent: Sendable {
  case systemWillSleep, systemDidWake, screensDidSleep, screensDidWake, sessionResigned,
    sessionBecameActive
}
public enum MonitoringAvailabilityEffect: Equatable, Sendable { case suspend, resume }

public struct MonitoringAvailability: Sendable {
  private enum Reason: Hashable { case systemSleep, displaySleep, inactiveSession }
  private var reasons: Set<Reason> = []
  public var isAvailable: Bool { reasons.isEmpty }
  public init(isConsoleSession: Bool = true) {
    if !isConsoleSession { reasons.insert(.inactiveSession) }
  }
  public mutating func receive(_ event: WorkspaceAvailabilityEvent) -> MonitoringAvailabilityEffect?
  {
    let wasAvailable = isAvailable
    switch event {
    case .systemWillSleep: reasons.insert(.systemSleep)
    case .systemDidWake: reasons.remove(.systemSleep)
    case .screensDidSleep: reasons.insert(.displaySleep)
    case .screensDidWake: reasons.remove(.displaySleep)
    case .sessionResigned: reasons.insert(.inactiveSession)
    case .sessionBecameActive: reasons.remove(.inactiveSession)
    }
    guard wasAvailable != isAvailable else { return nil }
    return isAvailable ? .resume : .suspend
  }
}
