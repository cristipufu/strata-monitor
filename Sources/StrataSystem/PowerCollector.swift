import StrataCore

public struct PowerSnapshot: Sendable {
  public let reading: PowerReading
  // Nil when macOS did not answer which processes keep the Mac awake.
  public let sleepBlockers: [SleepBlocker]?
  public init(reading: PowerReading, sleepBlockers: [SleepBlocker]?) {
    self.reading = reading
    self.sleepBlockers = sleepBlockers
  }
}

public protocol PowerSampling: Sendable {
  func sample() async -> PowerSnapshot
}

public actor PowerCollector: PowerSampling {
  private let telemetry: PowerTelemetryReader
  private let assertions: SleepAssertionReader
  public init(
    telemetry: PowerTelemetryReader = PowerTelemetryReader(),
    assertions: SleepAssertionReader = SleepAssertionReader()
  ) {
    self.telemetry = telemetry
    self.assertions = assertions
  }
  public func sample() -> PowerSnapshot {
    PowerSnapshot(reading: telemetry.read(), sleepBlockers: assertions.read())
  }
}
