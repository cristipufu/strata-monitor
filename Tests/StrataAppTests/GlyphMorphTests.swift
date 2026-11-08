import AppKit
import StrataCore
import SwiftUI
import Testing

@testable import StrataBar

@Test func unfoldedControlsConsumeTheEntireRingAndDots() {
  let ring = GlyphRingGeometry(diameter: 22, strokeWidth: 2)
  let closed = GlyphMorphGeometry(ring: ring, compactWidth: 42, ringCenterOffset: -0.3, progress: 0)
  let open = GlyphMorphGeometry(ring: ring, compactWidth: 42, ringCenterOffset: -0.3, progress: 1)
  #expect(closed.sourceOpacity == 1 && closed.controlsOpacity == 0)
  #expect(open.sourceOpacity == 0 && open.controlsOpacity == 1 && open.badgeOpacity == 0)
  for index in 0..<GlyphRingGeometry.dotCount {
    #expect(closed.dotOffset(at: index) == ring.dotOffset(at: index))
  }
}

@Test func everyMorphFrameKeepsTheGlyphAndControlsInsideTheirReservedSpace() {
  for diameter in [18.0, 22, 24] {
    for reading in [Reading.battery, .cpu] {
      var profile = Profile(name: "Morph", ring: reading)
      profile.iconSize = diameter
      let compact = GlyphLayout.statusItemWidth(for: profile)
      let ring = GlyphRingGeometry(diameter: diameter, strokeWidth: 2 * diameter / 22)
      for step in 0...100 {
        let morph = GlyphMorphGeometry(
          ring: ring, compactWidth: compact,
          ringCenterOffset: GlyphLayout.ringCenterOffset(for: profile), progress: Double(step) / 100
        )
        let origin = morph.expandedWidth + morph.compactCenter
        let points =
          (0...32).map { morph.ringPoint(at: Double($0) / 32) }
          + (0..<GlyphRingGeometry.dotCount).map { morph.dotOffset(at: $0) }
        for point in points {
          #expect(origin + point.x >= ring.pathInset)
          #expect(origin + point.x <= morph.expandedWidth - ring.pathInset)
          #expect(abs(point.y) <= ring.radius + 0.0001)
        }
        for slot in 0..<3 {
          let x = origin + morph.slotOffset(slot)
          #expect(x >= morph.slotWidth / 2 && x <= morph.expandedWidth - morph.slotWidth / 2)
        }
      }
    }
  }
}

@Test @MainActor func expandedRenderingContainsNoResidualRingDotsOrTracks() throws {
  var profile = Profile(name: "Morph", ring: .cpu)
  let first = try rasterizeGlyph(profile, ring: 1, bar: 1, unfolding: 1)
  profile.ringThickness = 3
  profile.showsTracks = false
  let second = try rasterizeGlyph(profile, ring: 0.15, bar: 0, unfolding: 1)
  #expect(first == second)
  #expect(try rasterizeGlyph(profile, ring: 1, bar: 1, unfolding: 0) != first)
}

@MainActor private func rasterizeGlyph(
  _ profile: Profile, ring: Double, bar: Double, unfolding: Double
) throws -> Data {
  let drawing = GlyphDrawing(
    profile: profile,
    presentation: GlyphPresentation(
      ring: ring, bar: bar, center: .symbol("wifi", variableValue: 1)),
    diameter: profile.iconSize, unfolding: unfolding, layoutWidth: 80
  )
  .frame(width: 80, height: 24).foregroundStyle(.white).background(.black)
  .environment(\.colorScheme, .dark)
  let renderer = ImageRenderer(content: drawing)
  renderer.scale = 2
  return try #require(renderer.cgImage?.dataProvider?.data) as Data
}

@Test @MainActor func reservingNativeSpaceDoesNotMoveOrResizeTheCompactIndicator() throws {
  let model = AppModel(persistsPreferences: false)
  model.preferences.launchAnimationEnabled = false
  defer { model.stop() }
  let motion = MenuBarMotion(applyWidth: { _ in }, didFold: {})
  let compact = GlyphLayout.statusItemWidth(for: model.profile)
  func render(width: CGFloat) throws -> Data {
    let view = MenuBarView(model: model, motion: motion, open: {}, openReading: { _ in })
      .frame(width: width, height: 24)
      .frame(width: 160, height: 40, alignment: .trailing)
      .foregroundStyle(.white).background(.black).environment(\.colorScheme, .dark)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    return try #require(renderer.cgImage?.dataProvider?.data) as Data
  }
  let closed = try render(width: compact)
  #expect(rendersAlike(try render(width: compact + GlyphMorphGeometry.extensionWidth), closed))
  #expect(rendersAlike(try render(width: 150), closed))
}

@Test @MainActor func aRetainedDrawingCanvasDoesNotStretchOrClipTheNextMoment() throws {
  let model = AppModel(persistsPreferences: false)
  model.preferences.launchAnimationEnabled = false
  defer { model.stop() }
  let motion = MenuBarMotion(applyWidth: { _ in }, didFold: {})
  func render(width: CGFloat) throws -> Data {
    let view = MenuBarView(model: model, motion: motion, open: {}, openReading: { _ in })
      .frame(width: width, height: 24)
      .frame(width: 300, height: 40, alignment: .trailing)
      .foregroundStyle(.white).background(.black).environment(\.colorScheme, .dark)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    return try #require(renderer.cgImage?.dataProvider?.data) as Data
  }
  for title in ["Power connected", "Muted"] {
    motion.present(
      expanded: false, moment: StatusMoment(symbol: "bolt.fill", title: title, priority: 1),
      compactWidth: 42, reducedMotion: true)
    #expect(rendersAlike(try render(width: motion.displayedMomentWidth), try render(width: 236)))
  }
}

// Symbol rasterization varies by a unit in a channel between renders; a moved or resized glyph
// changes many pixels by far more.
private func rendersAlike(_ lhs: Data, _ rhs: Data, tolerance: UInt8 = 3) -> Bool {
  lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { max($0, $1) - min($0, $1) <= tolerance }
}
