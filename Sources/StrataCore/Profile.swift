import Foundation

public enum Accent: String, CaseIterable, Codable, Sendable {
  case automatic, monochrome, blue, mint, teal, violet, pink, orange, red
}
public enum FillStyle: String, CaseIterable, Codable, Sendable {
  case continuous, segmented, gradient
}
public enum FillMotion: String, CaseIterable, Codable, Sendable { case grow, snap }
public enum UnfoldStyle: String, CaseIterable, Codable, Sendable { case morph, fade }
public enum Appearance: String, CaseIterable, Codable, Sendable { case system, light, dark }

public struct Profile: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public var name: String
  public var ring: Reading
  public var center: Reading
  public var bar: Reading
  public var accent: Accent
  public var fillStyle: FillStyle
  public var fillMotion: FillMotion
  public var unfoldStyle: UnfoldStyle
  public var showsTracks: Bool
  public var showsBatteryPercent: Bool
  public var ringThickness: Double
  public var iconSize: Double
  public static let iconSizeRange: ClosedRange<Double> = 18...24
  public static let scalarReadings: [Reading] = [.cpu, .gpu, .memory, .disk, .network, .battery, .sound]

  public init(name: String, ring: Reading = .cpu, center: Reading = .wifi, bar: Reading = .network)
  {
    id = UUID()
    self.name = name
    self.ring = ring
    self.center = center
    self.bar = bar
    accent = .automatic
    fillStyle = .continuous
    fillMotion = .grow
    unfoldStyle = .morph
    showsTracks = true
    showsBatteryPercent = false
    ringThickness = RingThicknessPreset.regular.thickness
    iconSize = 22
  }
  public mutating func validate() {
    name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
    if name.isEmpty { name = String(localized: "Untitled") }
    if !Self.scalarReadings.contains(ring) { ring = .cpu }
    if !Self.scalarReadings.contains(bar) { bar = .network }
    if center == .overview { center = .wifi }
    ringThickness = RingThicknessPreset.nearest(to: ringThickness).thickness
    iconSize =
      iconSize.isFinite
      ? min(Self.iconSizeRange.upperBound, max(Self.iconSizeRange.lowerBound, iconSize)) : 22
  }
  public static var defaults: [Profile] {
    [
      Profile(name: String(localized: "Everyday"), ring: .battery), Profile(name: String(localized: "Desktop")),
      Profile(name: String(localized: "Performance"), ring: .cpu, center: .memory, bar: .network),
    ]
  }
}

public enum UpdateSpeed: String, CaseIterable, Codable, Sendable {
  case fast, normal, relaxed
  public var interval: Duration {
    switch self {
    case .fast: .seconds(1)
    case .normal: .seconds(2)
    case .relaxed: .seconds(5)
    }
  }
  public var seconds: Int {
    switch self {
    case .fast: 1
    case .normal: 2
    case .relaxed: 5
    }
  }
}

public enum HistoryKeeping: String, CaseIterable, Codable, Sendable {
  case off, day, week
  public var retention: HistoryRetention? {
    switch self {
    case .off: nil
    case .day: .day
    case .week: .week
    }
  }
}

public struct Preferences: Codable, Sendable {
  public var version = 1
  public var profiles = Profile.defaults
  public var selectedProfile: UUID
  public var hoverOpensPage = false
  public var momentsEnabled = true
  public var launchAnimationEnabled = true
  public var appearance: Appearance = .system
  public var hasCompletedWelcome = false
  public var hasSelectedInitialPreset = false
  public var updateSpeed = UpdateSpeed.normal
  public var historyKeeping = HistoryKeeping.day
  public init() { selectedProfile = profiles[1].id }
  private enum CodingKeys: String, CodingKey {
    case version, profiles, selectedProfile, hoverOpensPage, momentsEnabled, appearance
    case hasCompletedWelcome, hasSelectedInitialPreset, launchAnimationEnabled, updateSpeed
    case historyKeeping
  }
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    version = try values.decode(Int.self, forKey: .version)
    profiles = try values.decode([Profile].self, forKey: .profiles)
    selectedProfile = try values.decode(UUID.self, forKey: .selectedProfile)
    hoverOpensPage = try values.decode(Bool.self, forKey: .hoverOpensPage)
    momentsEnabled = try values.decode(Bool.self, forKey: .momentsEnabled)
    launchAnimationEnabled =
      try values.decodeIfPresent(Bool.self, forKey: .launchAnimationEnabled) ?? true
    appearance = try values.decode(Appearance.self, forKey: .appearance)
    hasCompletedWelcome = try values.decode(Bool.self, forKey: .hasCompletedWelcome)
    // Existing saved profiles predate the bootstrap marker and must retain their selection.
    hasSelectedInitialPreset =
      try values.decodeIfPresent(Bool.self, forKey: .hasSelectedInitialPreset) ?? true
    updateSpeed = try values.decodeIfPresent(UpdateSpeed.self, forKey: .updateSpeed) ?? .normal
    historyKeeping =
      try values.decodeIfPresent(HistoryKeeping.self, forKey: .historyKeeping) ?? .day
  }
  public mutating func selectProfile(_ identity: UUID) {
    guard profiles.contains(where: { $0.id == identity }) else { return }
    selectedProfile = identity
    hasSelectedInitialPreset = true
  }
  public mutating func selectInitialPreset(hasBattery: Bool) {
    guard let preset = profiles.first(where: { $0.ring == (hasBattery ? .battery : .cpu) }) else {
      return
    }
    selectProfile(preset.id)
  }
  public var activeProfile: Profile {
    profiles.first { $0.id == selectedProfile } ?? profiles.first ?? Profile(name: String(localized: "Desktop"))
  }
  public mutating func validate() {
    if profiles.isEmpty { profiles = Profile.defaults }
    profiles = Array(profiles.prefix(20))
    var ids = Set<UUID>()
    profiles = profiles.filter { ids.insert($0.id).inserted }
    for index in profiles.indices { profiles[index].validate() }
    if !profiles.contains(where: { $0.id == selectedProfile }) { selectedProfile = profiles[0].id }
  }
  public static func decode(_ data: Data?) -> Preferences {
    guard let data, data.count <= 128_000,
      var decoded = try? JSONDecoder().decode(Preferences.self, from: data), decoded.version == 1
    else {
      return Preferences()
    }
    decoded.validate()
    return decoded
  }
}
