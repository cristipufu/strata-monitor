import AppKit
import StrataCore
import Testing

@testable import StrataBar
@testable import StrataSystem

private actor GlyphDevices: DeviceControlling {
  private let battery: BatteryState?
  init(battery: BatteryState? = nil) { self.battery = battery }
  func sample() -> DeviceSnapshot {
    DeviceSnapshot(
      battery: battery.map(BatteryObservation.present) ?? .absent,
      audio: AudioState(
        outputs: [], volume: nil, muted: nil, canSetVolume: false, canSetMute: false),
      wifi: WiFiState(powered: false, ssid: nil, rssi: nil, interface: nil),
      volumes: [], lowPowerMode: false)
  }
  func setVolume(_ value: Double, on output: AudioOutputIdentity) throws {
    throw DeviceError.unavailable("No output")
  }
  func setMuted(_ muted: Bool, on output: AudioOutputIdentity) throws {
    throw DeviceError.unavailable("No output")
  }
  func selectOutput(_ output: AudioOutputIdentity) throws {
    throw DeviceError.unavailable("No output")
  }
  func setWiFiPower(_ powered: Bool) throws { throw DeviceError.unavailable("No Wi-Fi") }
}

@Test @MainActor func networkCenterUsesDirectionSymbolsWhileUnfoldedValuesKeepBothRates()
  async throws
{
  let cases: [(NetworkRate?, GlyphCenter)] = [
    (nil, .symbol("questionmark")),
    (NetworkRate(received: 0, sent: 0), .symbol("arrow.up.arrow.down", subdued: true)),
    (NetworkRate(received: 1_000, sent: 2_000), .symbol("arrow.up.arrow.down", subdued: true)),
    (NetworkRate(received: 10_000, sent: 0), .symbol("arrow.down")),
    (NetworkRate(received: 0, sent: 20_000), .symbol("arrow.up")),
    (NetworkRate(received: 10_000, sent: 20_000), .symbol("arrow.up.arrow.down")),
    (NetworkRate(received: .nan, sent: 0), .symbol("questionmark")),
  ]
  for (rate, expected) in cases {
    let sampler = GatedSampler()
    let model = AppModel(
      collector: sampler, deviceCollector: GlyphDevices(), persistsPreferences: false)
    defer { model.stop() }
    model.preferences.momentsEnabled = false
    var profile = model.profile
    profile.center = .network
    model.profile = profile
    model.start()
    try await waitUntil { await sampler.requests.count == 1 }
    await sampler.complete(
      with: SystemSample(
        uptime: 1, cpu: 1, cores: [1], memory: nil, network: rate, interfaces: [], processes: []))
    try await waitUntil { model.sample != nil }
    #expect(model.glyphCenter == expected)
    #expect(model.fraction(for: .network) == rate?.activityIntensity)
    #expect(model.accessibleValue(for: .network).contains("receiving"))
    #expect(model.accessibleValue(for: .network).contains("sending"))
    if rate?.received == 10_000 && rate?.sent == 20_000 {
      #expect(model.accessibleValue(for: .network) == "receiving 10 KB/s, sending 20 KB/s")
    }
  }
}

private struct BatteryGlyphCase: Sendable {
  let fraction: Double
  var charging = true
  let percentage: Int?
  let tone: GlyphRingTone
  static let examples = [
    Self(fraction: 1, percentage: 100, tone: .green),
    Self(fraction: 0.83, percentage: 83, tone: .green),
    Self(fraction: 0.5, charging: false, percentage: 50, tone: .yellow),
    Self(fraction: 0.3, percentage: 30, tone: .orange),
    Self(fraction: 0.15, charging: false, percentage: 15, tone: .red),
    Self(fraction: 0.09, percentage: 9, tone: .red),
    Self(fraction: .nan, percentage: nil, tone: .accent),
    Self(fraction: .infinity, percentage: nil, tone: .accent),
  ]
}

@Test(arguments: BatteryGlyphCase.examples) @MainActor
private func batteryPercentageAndChargingCoexistAndRejectInvalidMeasurements(
  _ example: BatteryGlyphCase
)
  async throws
{
  let fraction = example.fraction
  let battery = BatteryState(
    fraction: fraction, charging: example.charging, externalPower: true, minutesRemaining: nil,
    health: nil)
  let model = AppModel(deviceCollector: GlyphDevices(battery: battery), persistsPreferences: false)
  defer { model.stop() }
  var profile = model.preferences.profiles[0]
  profile.showsBatteryPercent = true
  model.selectedProfile = profile.id
  model.profile = profile
  model.refreshDeviceReadings()
  try await waitUntil { model.devices != nil }
  let badge = try #require(model.glyphPresentation.badge)
  #expect(badge.charging == example.charging)
  #expect(badge.externalPower)
  #expect(badge.percentage == example.percentage)
  #expect(model.glyphPresentation.ringTone == example.tone)
  #expect(model.glyphPresentation.ring == (fraction.isFinite ? fraction : nil))
  #expect(model.accessibleValue(for: .battery).contains("charging") == example.charging)
  profile.showsBatteryPercent = false
  model.profile = profile
  #expect(
    model.glyphPresentation.badge
      == GlyphBatteryBadge(percentage: nil, charging: example.charging, externalPower: true))
  profile.ring = .cpu
  model.profile = profile
  #expect(model.glyphPresentation.badge == nil)
}

@Test @MainActor func startupAndMissingReadingsDoNotPresentFullStrengthOrInventValues() {
  let model = AppModel(persistsPreferences: false)
  defer { model.stop() }
  #expect(model.glyphCenter == .symbol("questionmark"))
  var profile = model.profile
  for reading in [Reading.cpu, .memory, .battery, .disk, .sound] {
    profile.center = reading
    model.profile = profile
    #expect(model.glyphCenter == .percentage(nil))
  }
  profile.center = .display
  model.profile = profile
  #expect(model.glyphCenter == .count(NSScreen.screens.count, symbol: "display"))
}

@Test @MainActor func momentsTemporarilyOverrideTheCenterAndRestoreTheCurrentProfile() async throws
{
  let model = AppModel(persistsPreferences: false, momentDuration: .milliseconds(40))
  defer { model.stop() }
  model.presentMoment(StatusMoment(symbol: "speaker.slash.fill", title: "Muted", priority: 1))
  #expect(model.glyphCenter == .symbol("speaker.slash.fill"))
  #expect(model.glyphPresentation.accessibilityLabel.contains("Muted"))
  var profile = model.profile
  profile.center = .cpu
  model.profile = profile
  #expect(model.glyphCenter == .symbol("speaker.slash.fill"))
  try await waitUntil { model.moment == nil }
  #expect(model.glyphCenter == .percentage(nil))
}

@Test func indicatorLayoutKeepsEveryConfiguredSizeInsideTheMenuBarAndReservesBatteryBadges() {
  for reading in [Reading.cpu, .battery] {
    for size in [18.0, 22, 28] {
      var profile = Profile(name: "Layout", ring: reading)
      profile.iconSize = size
      for showsPercentage in [false, true] {
        profile.showsBatteryPercent = showsPercentage
        let width = GlyphLayout.statusItemWidth(for: profile)
        for height in [24.0, 37] {
          let diameter = GlyphLayout.diameter(
            for: profile, available: CGSize(width: width, height: height))
          #expect(diameter > 0 && diameter <= size)
          #expect(diameter <= height)
          #expect(diameter * GlyphLayout.widthRatio(for: profile) <= width)
        }
      }
    }
  }
  let profile = Profile(name: "Layout")
  for bounds in [
    CGSize.zero, CGSize(width: -1, height: 24), CGSize(width: CGFloat.infinity, height: 24),
    CGSize(width: 36, height: CGFloat.nan),
  ] {
    #expect(GlyphLayout.diameter(for: profile, available: bounds) == 0)
  }
}

@Test func everyIconSizeSliderStepChangesTheVisibleMenuBarDiameter() {
  for height in [24.0, 37] {
    for percentage in [false, true] {
      var profile = Profile(name: "Size", ring: .battery)
      profile.showsBatteryPercent = percentage
      var previous = 0.0
      for size in stride(
        from: Profile.iconSizeRange.lowerBound, through: Profile.iconSizeRange.upperBound, by: 0.5
      ) {
        profile.iconSize = size
        let diameter = GlyphLayout.diameter(
          for: profile,
          available: CGSize(width: GlyphLayout.statusItemWidth(for: profile), height: height))
        #expect(diameter > previous)
        #expect(diameter == size)
        previous = diameter
      }
    }
  }
}

@Test func lowerDotsContinueTheRingAtTheSameRadiusAndStrokeWeight() {
  for diameter in [18.0, 22, 24, 70] {
    for stroke in [1.0, 1.8, 3] {
      let circle = GlyphRingGeometry(diameter: diameter, strokeWidth: stroke)
      let dots = (0..<GlyphRingGeometry.dotCount).map { circle.dotOffset(at: $0) }
      for point in dots {
        #expect(abs(hypot(point.x, point.y) - circle.radius) < 0.000_001)
        #expect(abs(point.x) + circle.dotDiameter / 2 <= diameter / 2)
        #expect(point.y + circle.dotDiameter / 2 <= diameter / 2)
      }
      #expect(abs(dots[0].x + dots[3].x) < 0.000_001)
      #expect(abs(dots[1].x + dots[2].x) < 0.000_001)
      #expect(abs(dots[0].y - dots[3].y) < 0.000_001)
      #expect(abs(dots[1].y - dots[2].y) < 0.000_001)
      #expect(dots[0].y < dots[1].y && dots[3].y < dots[2].y)
    }
  }
}

@Test func changingIconSizePreservesTheRingAndDotProportions() {
  for preset in RingThicknessPreset.allCases {
    let standard = GlyphRingGeometry(diameter: 22, strokeWidth: preset.thickness)
    for diameter in [18.0, 21, 24, 70] {
      let scaled = GlyphRingGeometry(
        diameter: diameter, strokeWidth: preset.thickness * diameter / GlyphLayout.referenceDiameter
      )
      #expect(abs(scaled.radius / diameter - standard.radius / 22) < 0.000_001)
      #expect(abs(scaled.dotDiameter / diameter - standard.dotDiameter / 22) < 0.000_001)
      for index in 0..<GlyphRingGeometry.dotCount {
        #expect(
          abs(scaled.dotOffset(at: index).x / diameter - standard.dotOffset(at: index).x / 22)
            < 0.000_001)
        #expect(
          abs(scaled.dotOffset(at: index).y / diameter - standard.dotOffset(at: index).y / 22)
            < 0.000_001)
      }
    }
  }
}

@Test func networkStatusGlyphNeverUsesAFullStrengthSymbolForMissingSignal() {
  #expect(
    GlyphCenter.networkStatus(connection: .unknown, wifiPowered: nil, signal: nil)
      == .symbol("questionmark"))
  #expect(
    GlyphCenter.networkStatus(connection: .wifi, wifiPowered: true, signal: nil)
      == .symbol("questionmark"))
  #expect(
    GlyphCenter.networkStatus(connection: .wifi, wifiPowered: true, signal: .weak)
      == .symbol("wifi", variableValue: 1.0 / 3))
  #expect(
    GlyphCenter.networkStatus(connection: .wifi, wifiPowered: true, signal: .fair)
      == .symbol("wifi", variableValue: 2.0 / 3))
  #expect(
    GlyphCenter.networkStatus(connection: .wifi, wifiPowered: true, signal: .strong)
      == .symbol("wifi", variableValue: 1))
  #expect(
    GlyphCenter.networkStatus(connection: .offline, wifiPowered: true, signal: nil)
      == .symbol("wifi.exclamationmark"))
  #expect(
    GlyphCenter.networkStatus(connection: .offline, wifiPowered: false, signal: nil)
      == .symbol("wifi.slash"))
  #expect(
    GlyphCenter.networkStatus(connection: .connecting, wifiPowered: true, signal: nil)
      == .symbol("ellipsis"))
  for connection in [ConnectionState.wired, .other] {
    #expect(
      GlyphCenter.networkStatus(connection: connection, wifiPowered: false, signal: nil)
        == .symbol("network"))
  }
}

@Test func glyphFractionsClampFiniteValuesAndKeepInvalidValuesUnavailable() {
  #expect(GlyphPresentation.percentage(1) == 100)
  #expect(GlyphPresentation.percentage(2) == 100)
  #expect(GlyphPresentation.percentage(-1) == 0)
  #expect(GlyphPresentation.percentage(.nan) == nil)
  #expect(GlyphPresentation.percentage(.infinity) == nil)
  let presentation = GlyphPresentation(ring: .infinity, bar: .nan, center: .percentage(nil))
  #expect(presentation.ring == nil && presentation.bar == nil)
}
