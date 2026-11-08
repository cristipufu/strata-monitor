import Foundation
import StrataCore
import Testing

@testable import StrataBar
@testable import StrataSystem

actor GatedSampler: SystemSampling {
  private var continuation: CheckedContinuation<SystemSample, Never>?
  private(set) var requests: [Bool] = []
  private(set) var resets = 0
  func sample(includeProcesses: Bool, includeGPU: Bool) async -> SystemSample {
    requests.append(includeProcesses)
    return await withCheckedContinuation { continuation = $0 }
  }
  func reset() { resets += 1 }
  func complete(with sample: SystemSample? = nil) {
    continuation?.resume(
      returning: sample
        ?? SystemSample(
          uptime: 10, cpu: 0.25, cores: [0.25], memory: nil, network: nil, interfaces: [],
          processes: []))
    continuation = nil
  }
}

@MainActor func waitUntil(_ condition: @escaping @MainActor () async -> Bool) async throws {
  let clock = ContinuousClock()
  let deadline = clock.now + .seconds(3)
  while !(await condition()) && clock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
  try #require(await condition(), "The asynchronous operation must finish before the deadline")
}

@Test @MainActor func stoppedMonitoringCannotPublishLateMeasurements() async throws {
  let sampler = GatedSampler()
  let defaults = try #require(UserDefaults(suiteName: "StrataBar.Tests.\(UUID())"))
  let model = AppModel(defaults: defaults, collector: sampler)
  model.start()
  try await waitUntil { await sampler.requests.count == 1 }
  model.stop()
  await sampler.complete()
  for _ in 0..<10 { await Task.yield() }
  #expect(model.sample == nil)
  #expect(model.history.points.isEmpty)
}

@Test @MainActor func processSamplingFollowsVisibleDemand() async throws {
  let sampler = GatedSampler()
  let defaults = try #require(UserDefaults(suiteName: "StrataBar.Tests.\(UUID())"))
  let model = AppModel(defaults: defaults, collector: sampler)
  model.setDemand("explorer", active: true)
  model.start()
  try await waitUntil { await sampler.requests.count == 1 }
  #expect(await sampler.requests == [true])
  await sampler.complete()
  try await waitUntil { model.sample != nil }
  #expect(model.history.points.count == 1)
  model.stop()
}

@Test @MainActor func backgroundSamplingDoesNotEnumerateProcesses() async throws {
  let sampler = GatedSampler()
  let model = AppModel(
    defaults: try #require(UserDefaults(suiteName: "StrataBar.Tests.\(UUID())")), collector: sampler
  )
  model.start()
  try await waitUntil { await sampler.requests.count == 1 }
  #expect(await sampler.requests == [false])
  model.stop()
  await sampler.complete()
}

@Test(arguments: [false, true]) @MainActor
func firstDevicePresetSurvivesGlobalSettingsEditsAndHonorsManualProfileChoice(_ manualChoice: Bool)
  async throws
{
  let sampler = GatedSampler()
  let model = AppModel(
    collector: sampler, deviceCollector: ControlledDevices(includesBattery: true),
    persistsPreferences: false)
  model.preferences.appearance = .dark
  if manualChoice { model.selectedProfile = model.preferences.profiles[2].id }
  model.start()
  try await waitUntil { await sampler.requests.count == 1 }
  await sampler.complete()
  try await waitUntil { model.devices != nil }
  #expect(model.profile.name == (manualChoice ? "Performance" : "Everyday"))
  model.stop()
}

@Test(arguments: [false, true]) @MainActor
func initialPresetSelectionSurvivesRestartBeforeFirstDeviceReading(_ explicitDesktopChoice: Bool)
  async throws
{
  let suite = "StrataBar.Tests.\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  do {
    let initial = AppModel(defaults: defaults)
    initial.preferences.appearance = .dark
    initial.preferences.hasCompletedWelcome = true
    if explicitDesktopChoice { initial.selectedProfile = initial.selectedProfile }
  }
  let sampler = GatedSampler()
  let restored = AppModel(
    defaults: defaults, collector: sampler,
    deviceCollector: ControlledDevices(includesBattery: true))
  restored.start()
  try await waitUntil { await sampler.requests.count == 1 }
  await sampler.complete()
  try await waitUntil { restored.devices != nil }
  #expect(restored.profile.name == (explicitDesktopChoice ? "Desktop" : "Everyday"))
  #expect(restored.preferences.appearance == .dark)
  #expect(restored.preferences.hasCompletedWelcome)
  restored.stop()
  #expect(AppModel(defaults: defaults).preferences.hasSelectedInitialPreset)
}

@Test @MainActor func profileEditsAreValidatedAndPersisted() throws {
  let name = "StrataBar.Tests.\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: name))
  defer { defaults.removePersistentDomain(forName: name) }
  let model = AppModel(defaults: defaults)
  var profile = model.profile
  profile.name = " Work "
  profile.ring = .wifi
  profile.iconSize = 100
  model.profile = profile
  let restored = AppModel(defaults: defaults)
  #expect(restored.profile.name == "Work")
  #expect(restored.profile.ring == .cpu)
  #expect(restored.profile.iconSize == Profile.iconSizeRange.upperBound)
}

@Test @MainActor func momentPriorityAndStopOwnPresentationLifetime() {
  let model = AppModel(defaults: UserDefaults(suiteName: "StrataBar.Tests.\(UUID())")!)
  model.presentMoment(StatusMoment(symbol: "bolt", title: "Power", priority: 2))
  model.presentMoment(StatusMoment(symbol: "speaker", title: "Audio", priority: 1))
  #expect(model.moment?.title == "Power")
  model.stop()
  #expect(model.moment == nil)
}

private actor ControlledDevices: DeviceControlling {
  private let includesBattery: Bool
  private var pending: [Int: CheckedContinuation<Void, Never>] = [:]
  private(set) var calls = 0
  private(set) var samples = 0
  init(includesBattery: Bool = false) { self.includesBattery = includesBattery }
  func sample() -> DeviceSnapshot {
    samples += 1
    return DeviceSnapshot(
      battery: includesBattery
        ? .present(
          BatteryState(
            fraction: 0.8, charging: false, externalPower: false, minutesRemaining: 30,
            health: "Good"
          )) : .absent,
      audio: AudioState(
        outputs: [], volume: nil, muted: nil, canSetVolume: false, canSetMute: false),
      wifi: WiFiState(powered: false, ssid: nil, rssi: nil, interface: nil), volumes: [],
      lowPowerMode: false)
  }
  func setVolume(_ value: Double, on output: AudioOutputIdentity) async throws {
    calls += 1
    let call = calls
    await withCheckedContinuation { pending[call] = $0 }
  }
  func setMuted(_ muted: Bool, on output: AudioOutputIdentity) throws {
    throw DeviceError.unavailable("Output was disconnected")
  }
  func selectOutput(_ output: AudioOutputIdentity) throws {
    throw DeviceError.unavailable("Output was disconnected")
  }
  func setWiFiPower(_ powered: Bool) throws {
    throw DeviceError.unavailable("Wi-Fi is unavailable")
  }
  func complete(_ call: Int) { pending.removeValue(forKey: call)?.resume() }
}

@Test @MainActor func deviceFailuresAreVisibleAndStoppedActionsAreNotPerformed() async throws {
  let devices = ControlledDevices()
  let model = AppModel(
    defaults: try #require(UserDefaults(suiteName: "StrataBar.Tests.\(UUID())")),
    deviceCollector: devices)
  model.setMuted(true, on: audioOutputFixture)
  try await waitUntil { model.errorMessage != nil }
  #expect(model.errorMessage == "Output was disconnected")
  model.stop()
  model.setVolume(0.5, on: audioOutputFixture)
  for _ in 0..<10 { await Task.yield() }
  #expect(await devices.calls == 0)
}

@Test @MainActor func supersededDeviceActionsCannotPublishOrEraseTheCurrentRequest() async throws {
  let devices = ControlledDevices()
  let model = AppModel(
    defaults: try #require(UserDefaults(suiteName: "StrataBar.Tests.\(UUID())")),
    deviceCollector: devices)
  model.setVolume(0.1, on: audioOutputFixture)
  try await waitUntil { await devices.calls == 1 }
  model.setVolume(0.9, on: audioOutputFixture)
  try await waitUntil { await devices.calls == 2 }
  await devices.complete(2)
  try await waitUntil { model.devices != nil }
  await devices.complete(1)
  for _ in 0..<10 { await Task.yield() }
  #expect(await devices.samples == 1)
  #expect(model.errorMessage == nil)
  model.stop()
}

private actor CountingPower: PowerSampling {
  private(set) var samples = 0
  func sample() -> PowerSnapshot {
    samples += 1
    return PowerSnapshot(reading: PowerReading(), sleepBlockers: [])
  }
}

@Test @MainActor func powerIsReadOnlyWhileTheBatteryPageIsShown() async throws {
  let sampler = GatedSampler()
  let power = CountingPower()
  let model = AppModel(
    defaults: try #require(UserDefaults(suiteName: "StrataBar.Tests.\(UUID())")), collector: sampler,
    powerCollector: power)
  model.page = .cpu
  model.setDemand("popover", active: true)
  model.start()
  try await waitUntil { await sampler.requests.count >= 1 }
  await sampler.complete()
  try await waitUntil { model.sample != nil }
  #expect(await power.samples == 0)
  model.page = .battery
  try await waitUntil { await sampler.requests.count >= 2 }
  await sampler.complete(
    with: SystemSample(
      uptime: 12, cpu: 0.2, cores: [0.2], memory: nil, network: nil, interfaces: [], processes: []))
  try await waitUntil { model.powerSnapshot != nil }
  #expect(await power.samples == 1)
  model.stop()
}

private actor CountingNetworkUsage: NetworkUsageSampling {
  private(set) var samples = 0
  func sample(of processes: [ProcessIdentity]) -> NetworkUsageState {
    samples += 1
    return .measuring
  }
  func reset() {}
}

@Test @MainActor func perProcessTrafficIsReadOnlyWhileANetworkViewIsShown() async throws {
  let sampler = GatedSampler()
  let network = CountingNetworkUsage()
  let model = AppModel(
    defaults: try #require(UserDefaults(suiteName: "StrataBar.Tests.\(UUID())")), collector: sampler,
    networkUsageCollector: network)
  let process = ProcessSample(
    id: ProcessIdentity(pid: 30, startSeconds: 1, startMicroseconds: 0), parentPID: 1, userID: 501,
    name: "curl", path: "", cpuTimeNanoseconds: nil, residentBytes: nil, footprintBytes: nil,
    threads: nil)
  func reading(_ uptime: TimeInterval) -> SystemSample {
    SystemSample(
      uptime: uptime, cpu: 0.1, cores: [0.1], memory: nil, network: nil, interfaces: [],
      processes: [process])
  }
  model.page = .cpu
  model.setDemand("popover", active: true)
  model.start()
  try await waitUntil { await sampler.requests.count >= 1 }
  await sampler.complete(with: reading(10))
  try await waitUntil { model.sample?.uptime == 10 }
  #expect(await network.samples == 0)
  model.setDemand(AppModel.networkUsageDemand, active: true)
  try await waitUntil { await sampler.requests.count >= 2 }
  await sampler.complete(with: reading(12))
  try await waitUntil { await network.samples == 1 }
  model.stop()
}
