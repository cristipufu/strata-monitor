import Foundation
import StrataCore

enum GlyphCenter: Equatable {
  case percentage(Int?)
  case count(Int, symbol: String)
  case symbol(String, variableValue: Double? = nil, subdued: Bool = false)
  static func percent(_ fraction: Double?) -> GlyphCenter {
    .percentage(GlyphPresentation.percentage(fraction))
  }
  static func networkStatus(
    connection: ConnectionState, wifiPowered: Bool?, signal: SignalStrength?
  ) -> GlyphCenter {
    if connection == .wired || connection == .other { return .symbol("network") }
    if wifiPowered == false { return .symbol("wifi.slash") }
    switch connection {
    case .offline: return .symbol("wifi.exclamationmark")
    case .connecting: return .symbol("ellipsis")
    case .unknown: return .symbol("questionmark")
    case .wifi:
      guard let signal else { return .symbol("questionmark") }
      return .symbol("wifi", variableValue: signal.fraction)
    case .wired, .other: return .symbol("network")
    }
  }
}
enum GlyphRingTone: Equatable, Sendable { case accent, green, yellow, orange, red }
struct GlyphBatteryBadge: Equatable {
  let percentage: Int?
  let charging: Bool
  var externalPower = false
}
struct GlyphPresentation: Equatable {
  let ring: Double?
  let bar: Double?
  let center: GlyphCenter
  let ringTone: GlyphRingTone
  let badge: GlyphBatteryBadge?
  let accessibilityLabel: String
  init(
    ring: Double?, bar: Double?, center: GlyphCenter, ringTone: GlyphRingTone = .accent,
    badge: GlyphBatteryBadge? = nil, accessibilityLabel: String = "Strata Monitor"
  ) {
    self.ring = Self.unitInterval(ring)
    self.bar = Self.unitInterval(bar)
    self.center = center
    self.ringTone = ringTone
    self.badge = badge
    self.accessibilityLabel = accessibilityLabel
  }
  static func unitInterval(_ value: Double?) -> Double? {
    value.flatMap { $0.isFinite ? min(1, max(0, $0)) : nil }
  }
  static func percentage(_ fraction: Double?) -> Int? {
    unitInterval(fraction).map { Int(($0 * 100).rounded()) }
  }
}
