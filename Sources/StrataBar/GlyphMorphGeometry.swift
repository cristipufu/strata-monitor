import Foundation

struct GlyphMorphGeometry {
  static let extensionWidth: CGFloat = 36
  let ring: GlyphRingGeometry
  let compactWidth: Double
  let ringCenterOffset: Double
  let progress: Double
  var expandedWidth: Double { compactWidth + Self.extensionWidth }
  var slotWidth: Double { expandedWidth / 3 }
  var compactCenter: Double { -compactWidth / 2 + ring.diameter * ringCenterOffset }
  var sourceOpacity: Double { 1 - phase(from: 0.12, to: 0.78) }
  var controlsOpacity: Double { phase(from: 0.22, to: 0.85) }
  var badgeOpacity: Double { 1 - phase(from: 0, to: 0.45) }
  var centerOffset: CGPoint {
    CGPoint(x: slotOffset(0) * progress, y: -ring.diameter * 0.025 * (1 - progress))
  }

  func slotOffset(_ index: Int) -> Double {
    -slotWidth * (Double(index) + 0.5) - compactCenter
  }

  func ringPoint(at fraction: Double) -> CGPoint {
    let angle =
      Double.pi / 2 + 2 * Double.pi
      * (GlyphRingGeometry.startFraction + GlyphRingGeometry.sweepFraction * fraction)
    let compact = CGPoint(x: cos(angle) * ring.radius, y: sin(angle) * ring.radius)
    let line = CGPoint(x: slotOffset(1) + (fraction - 0.5) * ring.diameter * 0.7, y: 0)
    return interpolate(compact, line)
  }

  func dotOffset(at index: Int) -> CGPoint {
    let lane = Double(index % 2) - 0.5
    let endpoint = index < 2 ? -1.0 : 1.0
    let target = CGPoint(
      x: slotOffset(2) + lane * ring.diameter * 0.2,
      y: endpoint * ring.diameter * 0.2)
    return interpolate(ring.dotOffset(at: index), target)
  }

  private func interpolate(_ start: CGPoint, _ end: CGPoint) -> CGPoint {
    CGPoint(x: start.x + (end.x - start.x) * progress, y: start.y + (end.y - start.y) * progress)
  }

  private func phase(from start: Double, to end: Double) -> Double {
    let value = min(1, max(0, (progress - start) / (end - start)))
    return value * value * (3 - 2 * value)
  }
}
