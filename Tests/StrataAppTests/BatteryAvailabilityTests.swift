import Foundation
import StrataCore
import Testing

@testable import StrataBar
@testable import StrataSystem

private actor BatteryDevicesFixture: DeviceControlling {
  private var reading: BatteryObservation = .unavailable
  func set(_ reading: BatteryObservation) { self.reading = reading }
  func sample() -> DeviceSnapshot {
    DeviceSnapshot(
      battery: reading,
      audio: AudioState(
        outputs: [], volume: nil, muted: nil, canSetVolume: false, canSetMute: false),
      wifi: WiFiState(powered: false, ssid: nil, rssi: nil, interface: nil), volumes: [],
      lowPowerMode: false)
  }
  func setVolume(_ value: Double, on output: AudioOutputIdentity) {}
  func setMuted(_ muted: Bool, on output: AudioOutputIdentity) {}
  func selectOutput(_ output: AudioOutputIdentity) {}
  func setWiFiPower(_ powered: Bool) {}
}
private enum KnownBatteryPresence: CaseIterable, Sendable {
  case absent, partial, measured
  var observation: BatteryObservation {
    switch self {
    case .absent: .absent
    case .partial:
      .present(
        BatteryState(
          fraction: nil, charging: nil, externalPower: nil, minutesRemaining: nil, health: nil))
    case .measured:
      .present(
        BatteryState(
          fraction: 0.83, charging: true, externalPower: true, minutesRemaining: 12, health: "Good")
      )
    }
  }
}

@Test(arguments: KnownBatteryPresence.allCases) @MainActor
private func batteryPresetWaitsForKnownPresenceAndDoesNotNeedAChargeReading(
  _ presence: KnownBatteryPresence
) async throws {
  let devices = BatteryDevicesFixture()
  let model = AppModel(deviceCollector: devices, persistsPreferences: false)
  defer { model.stop() }
  model.refreshDeviceReadings()
  try await waitUntil { model.devices != nil }
  #expect(!model.preferences.hasSelectedInitialPreset)
  #expect(model.value(for: .battery) == "Unavailable")
  model.preferences.appearance = .dark
  await devices.set(presence.observation)
  model.refreshDeviceReadings()
  try await waitUntil { model.preferences.hasSelectedInitialPreset }
  #expect(model.profile.ring == (presence == .absent ? .cpu : .battery))
  #expect(
    model.value(for: .battery)
      == (presence == .absent ? "No battery" : presence == .partial ? "Unavailable" : "83%"))
  if presence == .partial {
    #expect(model.glyphPresentation.ring == nil && model.glyphPresentation.badge == nil)
  }
}

@Test @MainActor func unknownBatteryPresenceSurvivesRestartWithoutCommittingTheDesktopPreset()
  async throws
{
  let suite = "StrataBar.Tests.\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let devices = BatteryDevicesFixture()
  do {
    let model = AppModel(defaults: defaults, deviceCollector: devices)
    model.refreshDeviceReadings()
    try await waitUntil { model.devices != nil }
    model.preferences.appearance = .dark
    #expect(!model.preferences.hasSelectedInitialPreset)
    model.stop()
  }
  await devices.set(KnownBatteryPresence.partial.observation)
  let restored = AppModel(defaults: defaults, deviceCollector: devices)
  defer { restored.stop() }
  restored.refreshDeviceReadings()
  try await waitUntil { restored.preferences.hasSelectedInitialPreset }
  #expect(restored.profile.ring == .battery && restored.preferences.appearance == .dark)
}

@Test @MainActor func batteryRecoveryRespectsAManuallySelectedProfile() async throws {
  let devices = BatteryDevicesFixture()
  let model = AppModel(deviceCollector: devices, persistsPreferences: false)
  defer { model.stop() }
  model.refreshDeviceReadings()
  try await waitUntil { model.devices != nil }
  model.selectedProfile = model.preferences.profiles[2].id
  await devices.set(KnownBatteryPresence.measured.observation)
  model.refreshDeviceReadings()
  try await waitUntil { model.devices?.battery?.fraction == 0.83 }
  #expect(model.profile.name == "Performance")
}
