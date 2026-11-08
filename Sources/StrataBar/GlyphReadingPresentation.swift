import AppKit
import StrataCore

extension AppModel {
  var glyphPresentation: GlyphPresentation {
    GlyphPresentation(
      ring: fraction(for: profile.ring), bar: fraction(for: profile.bar),
      center: glyphCenter, ringTone: glyphRingTone, badge: glyphBatteryBadge,
      accessibilityLabel: "Strata Monitor. \(accessibilityStatus)")
  }
  var glyphCenter: GlyphCenter {
    if let moment { return .symbol(moment.symbol) }
    switch profile.center {
    case .cpu, .gpu, .memory, .battery, .disk: return .percent(fraction(for: profile.center))
    case .sound:
      return devices?.audio.muted == true
        ? .symbol("speaker.slash.fill") : .percent(fraction(for: .sound))
    case .network:
      let recent = sample?.network.flatMap { _ in NetworkRate.recentAverage(of: history.points) }
      switch NetworkActivity(recent ?? sample?.network) {
      case .unavailable: return .symbol("questionmark")
      case .idle: return .symbol("arrow.up.arrow.down", subdued: true)
      case .receiving: return .symbol("arrow.down")
      case .sending: return .symbol("arrow.up")
      case .bidirectional: return .symbol("arrow.up.arrow.down")
      }
    case .wifi:
      return .networkStatus(
        connection: connection, wifiPowered: devices?.wifi.powered, signal: signalStrength)
    case .bluetooth:
      guard let snapshot = bluetooth.snapshot, snapshot.access == .allowed,
        snapshot.powered != nil, snapshot.issue == nil
      else { return .symbol("questionmark") }
      if snapshot.powered == false { return .symbol("bolt.horizontal") }
      guard let count = snapshot.connectedCount else { return .symbol("questionmark") }
      return .count(count, symbol: "wave.3.right")
    case .display: return .count(NSScreen.screens.count, symbol: "display")
    case .overview: return .symbol(profile.center.symbol)
    }
  }
  private var glyphBatteryBadge: GlyphBatteryBadge? {
    guard profile.ring == .battery, let battery = devices?.battery else { return nil }
    let percentage =
      profile.showsBatteryPercent ? GlyphPresentation.percentage(battery.fraction) : nil
    guard percentage != nil || battery.charging == true || battery.externalPower == true else {
      return nil
    }
    return GlyphBatteryBadge(
      percentage: percentage, charging: battery.charging == true,
      externalPower: battery.externalPower == true)
  }
  private var glyphRingTone: GlyphRingTone {
    guard profile.ring == .battery, profile.accent == .automatic,
      let fraction = GlyphPresentation.unitInterval(devices?.battery?.fraction)
    else { return .accent }
    switch fraction {
    case ...0.15: return .red
    case ...0.30: return .orange
    case ...0.50: return .yellow
    default: return .green
    }
  }
}
