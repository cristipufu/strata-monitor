import Foundation
import Testing

@testable import StrataCore

@Test func firstRunPresetMatchesBatteryPresence() {
  var preferences = Preferences()
  preferences.selectInitialPreset(hasBattery: true)
  #expect(preferences.activeProfile.ring == .battery)
  preferences.selectInitialPreset(hasBattery: false)
  #expect(preferences.activeProfile.ring == .cpu)
}

@Test func hoverRequiresIntentAndProtectsPointerTransit() {
  var policy = PresentationPolicy()
  #expect(policy.receive(.entered(.indicator)) == [.cancelLeave, .scheduleHover])
  #expect(policy.state == .collapsed)
  policy.receive(.hoverElapsed)
  #expect(policy.state == .unfolded)
  policy.receive(.entered(.popover))
  policy.receive(.exited(.indicator))
  policy.receive(.leaveElapsed)
  #expect(policy.state == .unfolded)
  policy.receive(.exited(.popover))
  policy.receive(.leaveElapsed)
  #expect(policy.state == .folding)
  policy.receive(.foldFinished)
  #expect(policy.state == .collapsed)
}

@Test func returningDuringAFoldReversesImmediatelyAndIgnoresOldCompletion() {
  for hoverPage in [false, true] {
    var policy = PresentationPolicy()
    policy.hoverOpensPage = hoverPage
    policy.receive(.entered(.indicator))
    policy.receive(.hoverElapsed)
    policy.receive(.exited(.indicator))
    policy.receive(.leaveElapsed)
    #expect(policy.state == .folding)
    #expect(policy.receive(.entered(.popover)) == [.cancelLeave])
    #expect(policy.state == (hoverPage ? .peeking : .unfolded))
    policy.receive(.foldFinished)
    #expect(policy.state == (hoverPage ? .peeking : .unfolded))
    policy.receive(.click)
    policy.receive(.foldFinished)
    #expect(policy.state == .engaged)
  }
}

@Test func clickEngagementSurvivesLeaveAndDoesNotImmediatelyReopenAfterDismissal() {
  var policy = PresentationPolicy()
  policy.receive(.entered(.indicator))
  policy.receive(.click)
  policy.receive(.exited(.indicator))
  policy.receive(.leaveElapsed)
  #expect(policy.state == .engaged)
  policy.receive(.entered(.indicator))
  policy.receive(.dismiss)
  policy.receive(.hoverElapsed)
  #expect(policy.state == .collapsed)
  policy.receive(.exited(.indicator))
  policy.receive(.entered(.indicator))
  policy.receive(.hoverElapsed)
  #expect(policy.state == .unfolded)
}

@Test func staleHoverTimerCannotOpenAfterExit() {
  var policy = PresentationPolicy()
  policy.receive(.entered(.indicator))
  policy.receive(.exited(.indicator))
  policy.receive(.hoverElapsed)
  #expect(policy.state == .collapsed)
}

@Test func hoverPagePreferencePeeksWithoutEngagement() {
  var policy = PresentationPolicy()
  policy.hoverOpensPage = true
  policy.receive(.entered(.indicator))
  policy.receive(.hoverElapsed)
  #expect(policy.state == .peeking)
  policy.receive(.engage)
  policy.receive(.exited(.indicator))
  policy.receive(.leaveElapsed)
  #expect(policy.state == .engaged)
}

@Test func disablingHoverOverviewClosesThePeekAndKeepsClickEngagement() {
  var policy = PresentationPolicy()
  policy.hoverOpensPage = true
  policy.receive(.entered(.indicator))
  policy.receive(.hoverElapsed)
  #expect(policy.state == .peeking)
  policy.hoverOpensPage = false
  #expect(policy.state == .unfolded)
  policy.receive(.click)
  #expect(policy.state == .engaged)
  policy.hoverOpensPage = true
  policy.hoverOpensPage = false
  #expect(policy.state == .engaged)
}

@Test func ringWeightPresetsSnapSavedValuesAndRejectInvalidMeasurements() {
  for preset in RingThicknessPreset.allCases {
    #expect(RingThicknessPreset.nearest(to: preset.thickness) == preset)
  }
  #expect(RingThicknessPreset.nearest(to: -100) == .thin)
  #expect(RingThicknessPreset.nearest(to: 100) == .heavy)
  #expect(RingThicknessPreset.nearest(to: 1.65) == .regular)
  #expect(RingThicknessPreset.nearest(to: .nan) == .regular)
  #expect(RingThicknessPreset.nearest(to: .infinity) == .regular)
}

@Test func countersRejectFirstSampleResetAndSleepGap() {
  var rates = CounterRates<String>()
  #expect(rates.rate(for: "rx", value: 100, at: 1) == nil)
  #expect(rates.rate(for: "rx", value: 300, at: 3) == 100)
  #expect(rates.rate(for: "rx", value: 10, at: 4) == nil)
  #expect(rates.rate(for: "rx", value: 20, at: 50) == nil)
  #expect(rates.rate(for: "rx", value: 30, at: 50) == nil)
  // A duplicate timestamp cannot replace the last valid baseline.
  #expect(rates.rate(for: "rx", value: 50, at: 51) == 30)
}

@Test func invalidCounterTimestampsCannotPoisonBaseline() {
  var rates = CounterRates<String>()
  _ = rates.rate(for: "cpu", value: 100, at: 1)
  #expect(rates.rate(for: "cpu", value: 1000, at: .nan) == nil)
  #expect(rates.rate(for: "cpu", value: 1000, at: 0) == nil)
  #expect(rates.rate(for: "cpu", value: 200, at: 2) == 100)
}

@Test func removedProcessCannotReuseCounterBaseline() {
  var rates = CounterRates<String>()
  _ = rates.rate(for: "pid:2:old", value: 100, at: 1)
  #expect(rates.rate(for: "pid:2:new", value: 200, at: 2) == nil)
  rates.retain(keys: [])
  #expect(rates.rate(for: "pid:2:old", value: 300, at: 3) == nil)
}

@Test func cpuDeltaUsesBusyAndTotalDeltas() {
  var delta = CPUDelta()
  #expect(delta.fraction(busy: 20, total: 100) == nil)
  #expect(delta.fraction(busy: 70, total: 200) == 0.5)
  #expect(delta.fraction(busy: 2, total: 10) == nil)
}

@Test func profilesValidateUntrustedPersistedChoices() throws {
  var profile = Profile(name: "  ", ring: .wifi, bar: .overview)
  profile.ringThickness = .infinity
  profile.iconSize = 200
  profile.validate()
  #expect(profile.name == "Untitled")
  #expect(profile.ring == .cpu && profile.bar == .network)
  #expect(profile.ringThickness == 1.8 && profile.iconSize == Profile.iconSizeRange.upperBound)
  var preferences = Preferences()
  preferences.profiles = [profile, profile]
  preferences.validate()
  #expect(preferences.profiles.count == 1)
  let data = try JSONEncoder().encode(preferences)
  #expect(Preferences.decode(data).activeProfile == profile)
  #expect(!Preferences.decode(Data("invalid".utf8)).profiles.isEmpty)
}

@Test func emptyProfileListRecovers() {
  var preferences = Preferences()
  preferences.profiles = []
  preferences.validate()
  #expect(!preferences.profiles.isEmpty)
  #expect(preferences.profiles.contains { $0.id == preferences.selectedProfile })
}

@Test func savedProfilesMigrateWithoutReplacingAnExistingChoice() throws {
  var preferences = Preferences()
  preferences.selectProfile(preferences.profiles[2].id)
  var legacy = try #require(
    JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences)) as? [String: Any])
  legacy.removeValue(forKey: "hasSelectedInitialPreset")
  legacy.removeValue(forKey: "launchAnimationEnabled")
  let restored = Preferences.decode(try JSONSerialization.data(withJSONObject: legacy))
  #expect(restored.activeProfile == preferences.activeProfile)
  #expect(restored.hasSelectedInitialPreset)
  #expect(!Preferences.decode(Data("invalid".utf8)).hasSelectedInitialPreset)
  #expect(!Preferences.decode(try JSONEncoder().encode(Preferences())).hasSelectedInitialPreset)
}

@Test func queriesMatchStructuredPortsAndLiteralPaths() {
  let id = ProcessIdentity(pid: 123, startSeconds: 1, startMicroseconds: 2)
  let resource = ProcessResource(
    owner: id, processName: "node", descriptor: 5, kind: .tcp,
    localAddress: "::1", localPort: 3000, state: "Listening")
  #expect(ExplorerQuery("port:3000 pid:123 node").matches(resource))
  #expect(!ExplorerQuery("port:0").matches(resource))
  #expect(!ExplorerQuery("port:70000").matches(resource))
  #expect(!ExplorerQuery("pid:124").matches(resource))
  #expect(resource.endpoint == "[::1]:3000")
  #expect(resource.isListener)
}

@Test func formattingDoesNotFabricateUnavailableMeasurements() {
  #expect(ValueFormat.rate(nil) == "—")
  #expect(ValueFormat.rate(.infinity) == "—")
  #expect(ValueFormat.percent(nil) == "—")
  #expect(ValueFormat.rate(1500) == "2 KB/s")
}
