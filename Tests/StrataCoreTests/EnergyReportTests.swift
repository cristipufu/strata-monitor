import Foundation
import StrataCore
import Testing

private func blocker(
  _ pid: Int32, _ type: String, createdAt: Date? = nil, assertionID: Int64? = nil
) -> SleepBlocker {
  SleepBlocker(
    pid: pid, processName: nil, assertionID: assertionID, assertionType: type, name: nil,
    createdAt: createdAt, prevention: SleepPrevention(assertionType: type))
}

private func report(
  power: PowerReading = PowerReading(), blockers: [SleepBlocker]? = [], ownPID: Int32 = 99
) -> EnergyReport {
  EnergyReport(power: power, sleepBlockers: blockers, ownPID: ownPID)
}

@Test func awakeReasonsLabelStrataBarsOwnKeepAwake() throws {
  let reasons = try #require(
    report(blockers: [blocker(99, "PreventUserIdleDisplaySleep"), blocker(5, "UserIsActive")])
      .awakeReasons)
  #expect(reasons.map(\.isStrataBarKeepAwake) == [true, false])
}

@Test func awakeReasonsPutTheStrongestAndOldestFirstAndDropNonBlockers() throws {
  let early = Date(timeIntervalSince1970: 1_000)
  let late = Date(timeIntervalSince1970: 2_000)
  let reasons = try #require(
    report(blockers: [
      blocker(1, "UserIsActive", createdAt: early),
      blocker(2, "PreventDiskIdle", createdAt: early),
      blocker(3, "PreventUserIdleSystemSleep", createdAt: late),
      blocker(4, "PreventUserIdleSystemSleep", createdAt: early),
      blocker(5, "PreventUserIdleSystemSleep"),
      blocker(6, "SomethingNew", createdAt: early),
      blocker(7, "PreventUserIdleDisplaySleep", createdAt: late),
      blocker(8, "PreventUserIdleSystemSleep", createdAt: late, assertionID: 1),
    ]).awakeReasons)
  #expect(reasons.map(\.blocker.pid) == [7, 4, 3, 8, 5, 6, 1])
}

@Test func unreadableSleepAssertionsStayDistinctFromNone() {
  #expect(report(blockers: nil).awakeReasons == nil)
  #expect(report(blockers: []).awakeReasons == [])
}

@Test func powerSummaryDescribesAdapterAndBatteryDraw() {
  let adapter = PowerReading(systemWatts: 59.5, adapterWatts: 94, onExternalPower: true)
  #expect(
    report(power: adapter).powerSummary == .drawingFromAdapter(systemWatts: 59.5, adapterWatts: 94))
  let battery = PowerReading(batteryWatts: -14, onExternalPower: false)
  #expect(report(power: battery).powerSummary == .drawingFromBattery(watts: 14))
  let measured = PowerReading(systemWatts: 12, batteryWatts: -14, onExternalPower: false)
  #expect(report(power: measured).powerSummary == .drawingFromBattery(watts: 12))
}

@Test func powerSummaryIsUnavailableWithoutAMeasurement() {
  for power in [
    PowerReading(), PowerReading(systemWatts: 10), PowerReading(onExternalPower: true),
    PowerReading(batteryWatts: 5, onExternalPower: false),
    PowerReading(onExternalPower: false),
  ] {
    #expect(report(power: power).powerSummary == .unavailable)
  }
}

@Test func sleepAssertionTypesMapToWhatTheyKeepAwake() {
  for type in ["PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion"] {
    let prevention = SleepPrevention(assertionType: type)
    #expect(prevention.preventsDisplaySleep == true && prevention.preventsSystemSleep == true)
  }
  for type in [
    "PreventUserIdleSystemSleep", "NoIdleSleepAssertion", "PreventSystemSleep",
    "NetworkClientActive", "BackgroundTask",
  ] {
    let prevention = SleepPrevention(assertionType: type)
    #expect(prevention.preventsDisplaySleep == false && prevention.preventsSystemSleep == true)
  }
  let user = SleepPrevention(assertionType: "UserIsActive")
  #expect(user == .userActivity && user.preventsSystemSleep == false)
  let disk = SleepPrevention(assertionType: "PreventDiskIdle")
  #expect(disk.preventsDisplaySleep == false && disk.preventsSystemSleep == false)
  let unknown = SleepPrevention(assertionType: "preventuseridlesystemsleep")
  #expect(unknown.preventsDisplaySleep == nil && unknown.preventsSystemSleep == nil)
}

@Test func sleepBlockerAgeNeedsACreationDateAndNeverGoesNegative() {
  let created = Date(timeIntervalSince1970: 1_000)
  #expect(blocker(1, "UserIsActive", createdAt: created).age(at: created + 90) == 90)
  #expect(blocker(1, "UserIsActive", createdAt: created).age(at: created - 5) == 0)
  #expect(blocker(1, "UserIsActive").age(at: created) == nil)
}

@Test func energyReportRoundTripsThroughJSON() throws {
  let original = report(
    power: PowerReading(systemWatts: 20, onExternalPower: true),
    blockers: [blocker(1, "PreventUserIdleSystemSleep", createdAt: Date(timeIntervalSince1970: 5))])
  let decoded = try JSONDecoder().decode(
    EnergyReport.self, from: JSONEncoder().encode(original))
  #expect(decoded == original)
}
