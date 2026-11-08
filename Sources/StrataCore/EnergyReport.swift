import Foundation

public struct AwakeReason: Codable, Equatable, Sendable {
  public let blocker: SleepBlocker
  public let isStrataBarKeepAwake: Bool

  public init(blocker: SleepBlocker, isStrataBarKeepAwake: Bool) {
    self.blocker = blocker
    self.isStrataBarKeepAwake = isStrataBarKeepAwake
  }
}

public enum PowerSummary: Equatable, Sendable {
  case drawingFromAdapter(systemWatts: Double, adapterWatts: Double?)
  case drawingFromBattery(watts: Double)
  case unavailable
}

public struct EnergyReport: Codable, Equatable, Sendable {
  public let power: PowerReading
  // Nil when the sleep assertions could not be read.
  public let awakeReasons: [AwakeReason]?
  public init(power: PowerReading, sleepBlockers: [SleepBlocker]?, ownPID: Int32) {
    self.power = power
    awakeReasons = sleepBlockers.map { Self.awakeReasons($0, ownPID: ownPID) }
  }
  public var powerSummary: PowerSummary {
    switch power.onExternalPower {
    case true?:
      guard let systemWatts = power.systemWatts else { return .unavailable }
      return .drawingFromAdapter(systemWatts: systemWatts, adapterWatts: power.adapterWatts)
    case false?:
      let discharge = power.batteryWatts.flatMap { $0 <= 0 ? -$0 : nil }
      guard let watts = power.systemWatts ?? discharge else { return .unavailable }
      return .drawingFromBattery(watts: watts)
    case nil:
      return .unavailable
    }
  }

  private static func awakeReasons(_ blockers: [SleepBlocker], ownPID: Int32) -> [AwakeReason] {
    blockers
      .filter { $0.prevention != .doesNotPreventSleep }
      .sorted(by: precedesInAwakeList)
      .map { AwakeReason(blocker: $0, isStrataBarKeepAwake: $0.pid == ownPID) }
  }

  private static func precedesInAwakeList(_ left: SleepBlocker, _ right: SleepBlocker) -> Bool {
    let leftRank = awakeRank(left.prevention)
    let rightRank = awakeRank(right.prevention)
    if leftRank != rightRank { return leftRank < rightRank }
    switch (left.createdAt, right.createdAt) {
    case (let leftDate?, let rightDate?) where leftDate != rightDate: return leftDate < rightDate
    case (.some, nil): return true
    case (nil, .some): return false
    default: return (left.pid, left.assertionID ?? 0) < (right.pid, right.assertionID ?? 0)
    }
  }

  private static func awakeRank(_ prevention: SleepPrevention) -> Int {
    switch prevention {
    case .keepsDisplayOn: 0
    case .keepsSystemAwake: 1
    case .unrecognized: 2
    case .userActivity: 3
    case .doesNotPreventSleep: 4
    }
  }
}
