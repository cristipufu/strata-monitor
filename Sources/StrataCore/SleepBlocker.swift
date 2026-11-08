import Foundation

public enum SleepPrevention: String, Codable, Sendable {
  // While the display is kept on, the system cannot idle sleep either.
  case keepsDisplayOn
  case keepsSystemAwake
  // Postpones sleep only until the user's display and sleep timers run out.
  case userActivity
  case doesNotPreventSleep
  case unrecognized

  public init(assertionType: String) {
    switch assertionType {
    case "PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion", "InternalPreventDisplaySleep":
      self = .keepsDisplayOn
    case "PreventUserIdleSystemSleep", "NoIdleSleepAssertion", "PreventSystemSleep",
      "DenySystemSleep", "InternalPreventSleep", "SystemIsActive", "NetworkClientActive",
      "BackgroundTask", "ApplePushServiceTask", "InteractivePushServiceTask":
      self = .keepsSystemAwake
    case "UserIsActive":
      self = .userActivity
    case "PreventDiskIdle", "ExternalMedia":
      self = .doesNotPreventSleep
    default:
      self = .unrecognized
    }
  }

  public var preventsDisplaySleep: Bool? {
    switch self {
    case .keepsDisplayOn: true
    case .keepsSystemAwake, .userActivity, .doesNotPreventSleep: false
    case .unrecognized: nil
    }
  }
  public var preventsSystemSleep: Bool? {
    switch self {
    case .keepsDisplayOn, .keepsSystemAwake: true
    case .userActivity, .doesNotPreventSleep: false
    case .unrecognized: nil
    }
  }
}

public struct SleepBlocker: Codable, Equatable, Sendable {
  public let pid: Int32
  public let processName: String?
  public let assertionID: Int64?
  public let assertionType: String
  public let name: String?
  public let createdAt: Date?
  public let prevention: SleepPrevention
  public var preventsDisplaySleep: Bool? { prevention.preventsDisplaySleep }
  public var preventsSystemSleep: Bool? { prevention.preventsSystemSleep }

  public init(
    pid: Int32, processName: String?, assertionID: Int64?, assertionType: String, name: String?,
    createdAt: Date?, prevention: SleepPrevention
  ) {
    self.pid = pid
    self.processName = processName
    self.assertionID = assertionID
    self.assertionType = assertionType
    self.name = name
    self.createdAt = createdAt
    self.prevention = prevention
  }

  public func age(at now: Date) -> TimeInterval? {
    guard let createdAt else { return nil }
    return max(0, now.timeIntervalSince(createdAt))
  }
}
