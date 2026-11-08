import Foundation
import IOKit.ps
import Testing

@testable import StrataSystem

private struct PowerSourcesFixture: PowerSourceReading {
  let values: [[String: Any]?]?
  func descriptions() -> [[String: Any]?]? { values }
}
private func batteryDescription(_ fields: [String: Any] = [:]) -> [String: Any] {
  [
    kIOPSTypeKey: kIOPSInternalBatteryType, kIOPSIsPresentKey: true,
    kIOPSCurrentCapacityKey: 83, kIOPSMaxCapacityKey: 100,
    kIOPSIsChargingKey: false, kIOPSPowerSourceStateKey: kIOPSBatteryPowerValue,
  ]
  .merging(fields) { _, new in new }
}
private func batteryRead(_ values: [[String: Any]?]?) -> BatteryObservation {
  BatteryReader(sources: PowerSourcesFixture(values: values), health: NoBatteryHealthFixture())
    .snapshot()
}
private struct NoBatteryHealthFixture: BatteryHealthReading {
  func cycleCount() -> Int? { nil }
  func maximumCapacityFraction(from details: [String: Any]) -> Double? { nil }
}

@Test func batteryQueryFailuresAndUnknownDescriptionsCannotBecomeAnAbsentBattery() {
  for values in [
    nil, [nil], [[:]], [[kIOPSTypeKey: "Unknown"]],
    [[kIOPSTypeKey: kIOPSInternalBatteryType]],
  ] as [[[String: Any]?]?] {
    let observation = batteryRead(values)
    #expect(observation.isInstalled == nil && observation.state == nil)
  }
  #expect(batteryRead([]).isInstalled == false)
  #expect(batteryRead([[kIOPSTypeKey: kIOPSUPSType]]).isInstalled == false)
  #expect(batteryRead([batteryDescription([kIOPSIsPresentKey: false])]).isInstalled == false)
}

@Test func batteryKnownPresenceSurvivesPartialReadingsWithoutInventingValues() throws {
  let observation = batteryRead([[kIOPSTypeKey: kIOPSInternalBatteryType, kIOPSIsPresentKey: true]])
  #expect(observation.isInstalled == true)
  let state = try #require(observation.state)
  #expect(state.fraction == nil && state.charging == nil && state.externalPower == nil)
  #expect(state.minutesRemaining == nil)
  let valid = try #require(batteryRead([batteryDescription()]).state)
  #expect(valid.fraction == 0.83 && valid.charging == false && valid.externalPower == false)
}

@Test func batteryAmbiguousSourcesNeverAttachAnArbitraryBatteryReading() throws {
  for values in [[batteryDescription(), batteryDescription()], [batteryDescription(), nil]]
    as [[[String: Any]?]]
  {
    let observation = batteryRead(values)
    #expect(observation.isInstalled == true)
    let state = try #require(observation.state)
    #expect(state.fraction == nil && state.charging == nil && state.externalPower == nil)
  }
}

@Test func batteryNumbersAndBooleanFieldsKeepTheirDeclaredTypesAndRanges() throws {
  for invalid in [-1, 101, 1.5, Double.nan, Double.infinity, true] as [Any] {
    let state = try #require(
      batteryRead([batteryDescription([kIOPSCurrentCapacityKey: invalid])]).state)
    #expect(state.fraction == nil)
  }
  for invalid in [0, -1, 1.5, true] as [Any] {
    let state = try #require(
      batteryRead([batteryDescription([kIOPSMaxCapacityKey: invalid])]).state)
    #expect(state.fraction == nil)
  }
  let zero = try #require(batteryRead([batteryDescription([kIOPSCurrentCapacityKey: 0])]).state)
  #expect(zero.fraction == 0)
  let untyped = batteryRead([batteryDescription([kIOPSIsPresentKey: 1])])
  #expect(untyped.isInstalled == nil)
  let unknown = try #require(
    batteryRead([batteryDescription([kIOPSIsChargingKey: 1, kIOPSPowerSourceStateKey: "Unknown"])])
      .state)
  #expect(unknown.charging == nil && unknown.externalPower == nil)
}

@Test func batteryTimeEstimatesRequireTheCorrespondingObservedPowerState() throws {
  let charging = try #require(
    batteryRead([
      batteryDescription([
        kIOPSIsChargingKey: true, kIOPSPowerSourceStateKey: kIOPSACPowerValue,
        kIOPSTimeToFullChargeKey: 12, kIOPSTimeToEmptyKey: 99,
      ])
    ]).state)
  #expect(charging.minutesRemaining == 12)
  let empty = try #require(batteryRead([batteryDescription([kIOPSTimeToEmptyKey: 0])]).state)
  #expect(empty.minutesRemaining == 0)
  let calculating = try #require(batteryRead([batteryDescription([kIOPSTimeToEmptyKey: -1])]).state)
  #expect(calculating.minutesRemaining == nil)
  let adapter = try #require(
    batteryRead([
      batteryDescription([
        kIOPSIsChargingKey: false, kIOPSPowerSourceStateKey: kIOPSACPowerValue,
        kIOPSTimeToEmptyKey: 99,
      ])
    ]).state)
  #expect(adapter.minutesRemaining == nil)
}

extension SystemIntegrationTests {
  // Shares process-wide IOKit send rights with the registry ownership check.
  @Test func nativeBatteryObservationDoesNotInferAbsenceFromMissingMeterValues() {
    for _ in 0..<20 {
      let observation = BatteryReader().snapshot()
      if observation.state != nil { #expect(observation.isInstalled == true) }
      if let fraction = observation.state?.fraction { #expect((0...1).contains(fraction)) }
    }
  }
}
