import Foundation
import StrataCore

enum GlyphLayout {
  static let referenceDiameter = 22.0
  /// Reserve the battery badge even while not charging, so events never move adjacent items.
  static func widthRatio(for profile: Profile) -> Double {
    guard profile.ring == .battery else { return 1.1 }
    return profile.showsBatteryPercent ? 1.8 : 1.7
  }
  static func ringCenterOffset(for profile: Profile) -> Double {
    guard profile.ring == .battery else { return 0 }
    return profile.showsBatteryPercent ? -0.28 : -0.30
  }
  static func badgeCenterOffset(for profile: Profile) -> Double {
    profile.showsBatteryPercent ? 0.57 : 0.55
  }
  static func statusItemWidth(for profile: Profile) -> Double {
    max(36, ceil(profile.iconSize * widthRatio(for: profile) + 4))
  }
  static func diameter(for profile: Profile, available: CGSize) -> Double {
    guard available.width.isFinite, available.height.isFinite,
      available.width > 0, available.height > 2
    else { return 0 }
    // These are actual point sizes. Settings only offers sizes that fit the
    // native 24-point status button, so larger choices never shrink the glyph.
    return max(
      0, min(profile.iconSize, available.height, available.width / widthRatio(for: profile)))
  }
}

struct GlyphRingGeometry {
  private static let openingDegrees = 110.0
  static let startFraction = openingDegrees / 720
  static let sweepFraction = 1 - openingDegrees / 360
  static let dotCount = 4
  let diameter: Double
  let strokeWidth: Double
  var dotDiameter: Double { diameter * 0.10 }
  var pathInset: Double { max(strokeWidth, dotDiameter) / 2 }
  var radius: Double { max(0, diameter / 2 - pathInset) }
  func dotOffset(at index: Int) -> CGPoint {
    let opening = 2 * Double.pi * (1 - Self.sweepFraction)
    let angle =
      Double.pi / 2 + opening / 2 - opening * Double(index + 1) / Double(Self.dotCount + 1)
    return CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
  }
}
