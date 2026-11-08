import StrataCore
import SwiftUI

/// Rendering consumes an immutable presentation; it never reads hardware or starts monitoring.
struct GlyphDrawing: View, Animatable {
  let profile: Profile
  let presentation: GlyphPresentation
  let diameter: CGFloat
  var reveal: Double = 1
  nonisolated var unfolding: Double = 0
  var layoutWidth: CGFloat?
  nonisolated var animatableData: Double {
    get { unfolding }
    set { unfolding = newValue }
  }
  var contrast: ColorSchemeContrast = .standard
  // Animating a glyph re-lays out every view in its window on each frame, so glyphs inside
  // large windows show readings without motion.
  var animatesReadings = true
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var scale: Double { diameter / GlyphLayout.referenceDiameter }
  private var geometry: GlyphRingGeometry {
    GlyphRingGeometry(diameter: diameter, strokeWidth: profile.ringThickness * scale)
  }
  private var progress: Double { min(1, max(0, unfolding)) }
  private var fades: Bool { profile.unfoldStyle == .fade }
  // Fade swaps the compact and unfolded layouts at the midpoint while the glyph is invisible,
  // instead of moving the ring's parts into place.
  private var morph: GlyphMorphGeometry {
    GlyphMorphGeometry(
      ring: geometry, compactWidth: compactWidth,
      ringCenterOffset: GlyphLayout.ringCenterOffset(for: profile),
      progress: fades ? (progress < 0.5 ? 0 : 1) : progress)
  }
  private var fadeOpacity: Double { fades ? abs(1 - 2 * progress) : 1 }
  private var fillAnimation: (Double) -> Animation? {
    { duration in
      profile.fillMotion == .snap || reduceMotion || !animatesReadings
        ? nil : .easeInOut(duration: duration)
    }
  }
  private var readingAnimation: Animation? {
    reduceMotion || !animatesReadings ? nil : .easeInOut(duration: MotionPolicy.readingChange)
  }
  private var compactWidth: CGFloat {
    max(GlyphLayout.statusItemWidth(for: profile), diameter * GlyphLayout.widthRatio(for: profile))
  }
  private var drawingWidth: CGFloat {
    layoutWidth ?? compactWidth + GlyphMorphGeometry.extensionWidth * morph.progress
  }
  private var ringPosition: CGFloat { drawingWidth / 2 + morph.compactCenter }
  private var track: Color { .primary.opacity(contrast == .increased ? 0.4 : 0.16) }
  private var ringColor: Color {
    switch presentation.ringTone {
    case .accent: Design.accent(profile.accent)
    case .green: Design.mint
    case .yellow: Design.yellow
    case .orange: Design.orange
    case .red: .red
    }
  }
  var body: some View {
    ZStack {
      ZStack {
        ring.frame(width: diameter, height: diameter).opacity(morph.sourceOpacity)
          .animation(fillAnimation(MotionPolicy.ringFill), value: presentation.ring)
        center.scaleEffect(1 + 0.16 * morph.progress).frame(
          width: diameter, height: diameter, alignment: .center
        )
        .offset(x: morph.centerOffset.x, y: morph.centerOffset.y).opacity(reveal)
        .animation(readingAnimation, value: presentation.center)
        bar.opacity(morph.sourceOpacity)
          .animation(fillAnimation(MotionPolicy.barFill), value: presentation.bar)
        expandedReading(profile.ring, fraction: presentation.ring)
          .foregroundStyle(ringColor).offset(x: morph.slotOffset(1))
          .opacity(morph.controlsOpacity)
          .animation(fillAnimation(MotionPolicy.ringFill), value: presentation.ring)
        expandedReading(profile.bar, fraction: presentation.bar)
          .offset(x: morph.slotOffset(2)).opacity(morph.controlsOpacity)
          .animation(fillAnimation(MotionPolicy.barFill), value: presentation.bar)
      }.frame(width: diameter, height: diameter)
        .offset(x: ringPosition)
      if let badge = presentation.badge {
        batteryBadge(badge)
          .offset(x: drawingWidth / 2 - compactWidth / 2)
          .opacity(reveal * morph.badgeOpacity)
          .animation(readingAnimation, value: presentation.badge)
      }
    }
    .frame(width: drawingWidth, height: diameter)
    .opacity(fadeOpacity)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(presentation.accessibilityLabel)
  }
  private var ring: some View {
    ZStack {
      if profile.showsTracks {
        arc(fraction: reveal).stroke(track, style: ringStroke)
      }
      arc(fraction: (presentation.ring ?? 0) * reveal)
        .stroke(fill(ringColor), style: ringStroke)
        .opacity(presentation.ring == nil ? 0 : 1)
    }
  }
  private var ringStroke: StrokeStyle {
    StrokeStyle(
      lineWidth: profile.ringThickness * scale, lineCap: .round,
      dash: profile.fillStyle == .segmented ? [scale, 2.5 * scale] : [])
  }
  private func arc(fraction: Double) -> some Shape {
    GlyphMorphArc(
      geometry: morph, fraction: fraction)
  }
  private var bar: some View {
    ZStack {
      ForEach(0..<GlyphRingGeometry.dotCount, id: \.self) { index in
        let level = min(
          1, max(0, (presentation.bar ?? 0) * Double(GlyphRingGeometry.dotCount) - Double(index)))
        Circle().fill(fill(Design.accent(profile.accent)))
          .frame(width: geometry.dotDiameter, height: geometry.dotDiameter)
          .opacity(
            (profile.showsTracks ? dotTrackOpacity + (1 - dotTrackOpacity) * level : level) * reveal
          )
          .offset(x: morph.dotOffset(at: index).x, y: morph.dotOffset(at: index).y)
      }
    }
  }
  private var dotTrackOpacity: Double { contrast == .increased ? 0.45 : 0.22 }
  private func fill(_ color: Color) -> AnyShapeStyle {
    if profile.fillStyle == .gradient {
      return AnyShapeStyle(
        LinearGradient(
          colors: [color.opacity(0.45), color], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
    return AnyShapeStyle(color)
  }
  @ViewBuilder private var center: some View {
    switch presentation.center {
    case .percentage(let percentage):
      Text(percentage.map(String.init) ?? "—")
        .font(.system(size: diameter * 0.40, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .contentTransition(reduceMotion ? .identity : .opacity)
    case .count(let count, let symbol):
      HStack(spacing: diameter * 0.035) {
        Image(systemName: symbol).font(.system(size: diameter * 0.22, weight: .semibold))
          .swapsWithoutAnimation()
        Text("\(count)").font(.system(size: diameter * 0.30, weight: .semibold, design: .rounded))
          .monospacedDigit().contentTransition(reduceMotion ? .identity : .opacity)
      }.frame(maxWidth: diameter * 0.72).minimumScaleFactor(0.7)
    case .symbol(let name, let variableValue, let subdued):
      Image(systemName: name, variableValue: variableValue)
        .resizable().scaledToFit()
        .fontWeight(.semibold)
        .swapsWithoutAnimation()
        .frame(width: diameter * 0.60, height: diameter * 0.48, alignment: .center)
        .opacity(subdued ? 0.45 : 1)
    }
  }
  private func expandedReading(_ reading: Reading, fraction: Double?) -> some View {
    let symbol = expandedSymbol(for: reading, fraction: fraction)
    return Image(systemName: symbol)
      .font(.system(size: diameter * 0.65, weight: .medium))
      .swapsWithoutAnimation()
      .frame(width: morph.slotWidth, height: diameter)
  }

  private func expandedSymbol(for reading: Reading, fraction: Double?) -> String {
    if reading == .battery {
      if presentation.badge?.charging == true { return "battery.100percent.bolt" }
      guard let fraction else { return "questionmark" }
      let quarter = Int((fraction * 4).rounded()) * 25
      return "battery.\(quarter)percent"
    }
    if reading == .sound, fraction == 0 { return "speaker.slash" }
    return reading.symbol
  }

  private func batteryBadge(_ badge: GlyphBatteryBadge) -> some View {
    VStack(spacing: diameter * 0.015) {
      if let percentage = badge.percentage {
        Text("\(percentage)")
          .font(.system(size: diameter * 0.29, weight: .bold, design: .rounded))
          .monospacedDigit().contentTransition(reduceMotion ? .identity : .opacity)
      }
      if badge.charging {
        Image(systemName: "bolt.fill").font(.system(size: diameter * 0.44, weight: .semibold))
          .foregroundStyle(ringColor)
      } else if badge.externalPower {
        Image(systemName: "powerplug.fill").font(.system(size: diameter * 0.44, weight: .semibold))
          .foregroundStyle(ringColor)
      }
    }.offset(x: diameter * GlyphLayout.badgeCenterOffset(for: profile))
  }
}

private struct GlyphMorphArc: Shape {
  let geometry: GlyphMorphGeometry
  var fraction: Double
  var animatableData: Double {
    get { fraction }
    set { fraction = newValue }
  }

  func path(in rect: CGRect) -> Path {
    let samples = 96
    return Path { path in
      for step in 0...samples {
        let point = geometry.ringPoint(
          at: min(1, max(0, fraction)) * Double(step) / Double(samples))
        let positioned = CGPoint(x: rect.midX + point.x, y: rect.midY + point.y)
        if step == 0 { path.move(to: positioned) } else { path.addLine(to: positioned) }
      }
    }
  }
}

extension View {
  // Animating an SF Symbol swap renders it on the GPU, which holds about 130 MB of surfaces
  // while it runs; symbols that stay on screen change at once instead.
  func swapsWithoutAnimation() -> some View { transaction { $0.animation = nil } }
}
