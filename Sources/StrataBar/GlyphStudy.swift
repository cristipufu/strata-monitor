import AppKit
import ImageIO
import StrataCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum GlyphStudyRenderer {
  static func write(to url: URL) throws {
    let renderer = ImageRenderer(content: GlyphStudy())
    renderer.scale = 2
    guard let image = renderer.cgImage,
      let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    else { throw CocoaError(.fileWriteUnknown) }
    try data.write(to: url, options: .atomic)
  }
}

/// Fixed illustrative readings render only the actual glyph views, with no collectors or windows.
private struct GlyphStudy: View {
  private let examples = GlyphStudyExample.examples
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Strata Monitor · Indicator study").font(.system(size: 24, weight: .semibold))
        Text("Illustrative readings · actual menu-bar bounds at 18 / 22 / 24 pt, then enlarged")
          .font(.system(size: 12)).foregroundStyle(.secondary)
        Text(
          "Glyph rendering only. Glass, motion, focus and physical display behavior require live review."
        )
        .font(.system(size: 11)).foregroundStyle(.secondary)
      }.padding(.bottom, 20)
      GlyphMorphStudy().padding(.bottom, 20)
      HStack(spacing: 0) {
        Text("Reading").frame(width: 150, alignment: .leading)
        ForEach(["Light", "Dark", "Increased contrast"], id: \.self) { label in
          Text(label).frame(width: 240)
        }
      }.font(.system(size: 11, weight: .semibold)).padding(.bottom, 8)
      ForEach(examples.indices, id: \.self) { index in
        HStack(spacing: 0) {
          Text(examples[index].label).font(.system(size: 11)).frame(width: 150, alignment: .leading)
          cell(examples[index], scheme: .light, contrast: .standard)
          cell(examples[index], scheme: .dark, contrast: .standard)
          cell(examples[index], scheme: .light, contrast: .increased)
        }
      }
    }.padding(24).background(Color.white).foregroundStyle(Color.black)
      .environment(\.colorScheme, .light)
  }
  private func cell(
    _ example: GlyphStudyExample, scheme: ColorScheme, contrast: ColorSchemeContrast
  ) -> some View {
    HStack(spacing: 10) {
      ForEach([18.0, 22, 24], id: \.self) { size in
        let profile = example.profile(size: size)
        let width = GlyphLayout.statusItemWidth(for: profile)
        GlyphDrawing(
          profile: profile, presentation: example.presentation,
          diameter: GlyphLayout.diameter(for: profile, available: CGSize(width: width, height: 24)),
          contrast: contrast
        )
        .frame(width: width, height: 24).clipped()
        .overlay(Rectangle().strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
      }
      GlyphDrawing(
        profile: example.profile(size: 22), presentation: example.presentation, diameter: 44,
        contrast: contrast)
    }.frame(width: 240, height: 66)
      .background(scheme == .dark ? Color(white: 0.08) : Color(white: 0.96))
      .foregroundStyle(scheme == .dark ? Color.white : Color.black)
      .environment(\.colorScheme, scheme)
  }
}

private struct GlyphStudyExample {
  let label: String
  let presentation: GlyphPresentation
  var battery = false
  var style: StrataCore.FillStyle = .continuous
  var accent: Accent = .automatic
  var tracks = true
  func profile(size: Double) -> Profile {
    var profile = Profile(name: "Study", ring: battery ? .battery : .cpu)
    profile.iconSize = size
    profile.fillStyle = style
    profile.accent = accent
    profile.showsTracks = tracks
    profile.showsBatteryPercent = presentation.badge?.percentage != nil
    return profile
  }
  static var examples: [Self] {
    [
      Self(
        label: "Battery · default",
        presentation: GlyphPresentation(
          ring: 0.83, bar: 0.6, center: .symbol("wifi", variableValue: 1), ringTone: .green),
        battery: true),
      Self(
        label: "Battery · AC · full",
        presentation: GlyphPresentation(
          ring: 1, bar: 0.6, center: .symbol("wifi", variableValue: 1), ringTone: .green,
          badge: GlyphBatteryBadge(percentage: nil, charging: false, externalPower: true)),
        battery: true),
      Self(
        label: "Battery · charging",
        presentation: GlyphPresentation(
          ring: 0.83, bar: 0.6, center: .symbol("wifi", variableValue: 1), ringTone: .green,
          badge: GlyphBatteryBadge(percentage: nil, charging: true)), battery: true),
      Self(
        label: "Battery · charging · 100",
        presentation: GlyphPresentation(
          ring: 1, bar: 0.6, center: .symbol("wifi", variableValue: 1), ringTone: .green,
          badge: GlyphBatteryBadge(percentage: 100, charging: true)), battery: true),
      Self(
        label: "Battery · low · 9",
        presentation: GlyphPresentation(
          ring: 0.09, bar: 0.1, center: .symbol("wifi", variableValue: 0.33), ringTone: .red,
          badge: GlyphBatteryBadge(percentage: 9, charging: false)), battery: true),
      Self(
        label: "Battery · 50",
        presentation: GlyphPresentation(
          ring: 0.5, bar: 0.7, center: .symbol("wifi", variableValue: 1), ringTone: .yellow,
          badge: GlyphBatteryBadge(percentage: 50, charging: false)), battery: true),
      Self(
        label: "Battery · 30",
        presentation: GlyphPresentation(
          ring: 0.3, bar: 0.7, center: .symbol("wifi", variableValue: 1), ringTone: .orange,
          badge: GlyphBatteryBadge(percentage: 30, charging: false)), battery: true),
      Self(
        label: "CPU · 100",
        presentation: GlyphPresentation(ring: 1, bar: 0.75, center: .percentage(100))),
      Self(
        label: "Memory · 64",
        presentation: GlyphPresentation(ring: 0.3, bar: 0.64, center: .percentage(64))),
      Self(
        label: "Sound · muted",
        presentation: GlyphPresentation(ring: 0.45, bar: 0, center: .symbol("speaker.slash.fill"))),
      Self(
        label: "Network · idle",
        presentation: GlyphPresentation(
          ring: 0.35, bar: 0, center: .symbol("arrow.up.arrow.down", subdued: true))),
      Self(
        label: "Network · receiving",
        presentation: GlyphPresentation(ring: 0.35, bar: 0.4, center: .symbol("arrow.down"))),
      Self(
        label: "Network · both",
        presentation: GlyphPresentation(
          ring: 0.35, bar: 0.65, center: .symbol("arrow.up.arrow.down"))),
      Self(
        label: "Unavailable",
        presentation: GlyphPresentation(ring: nil, bar: nil, center: .symbol("questionmark"))),
      Self(
        label: "Bluetooth · 2",
        presentation: GlyphPresentation(
          ring: 0.5, bar: 0.3, center: .count(2, symbol: "wave.3.right"))),
      Self(
        label: "Display · 1",
        presentation: GlyphPresentation(ring: 0.5, bar: 0.3, center: .count(1, symbol: "display"))),
      Self(
        label: "Segmented · violet",
        presentation: GlyphPresentation(ring: 0.82, bar: 0.7, center: .symbol("wifi")),
        style: .segmented, accent: .violet),
      Self(
        label: "Gradient · blue",
        presentation: GlyphPresentation(ring: 0.82, bar: 0.7, center: .symbol("wifi")),
        style: .gradient, accent: .blue),
      Self(
        label: "Monochrome · no tracks",
        presentation: GlyphPresentation(ring: 0.82, bar: 0.7, center: .percentage(82)),
        accent: .monochrome, tracks: false),
    ]
  }
}

private struct GlyphMorphStudy: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Hover morph · same geometry, sampled through the transition")
        .font(.system(size: 12, weight: .medium))
      ForEach([18.0, 22, 24], id: \.self) { size in
        HStack(spacing: 8) {
          Text("\(Int(size)) pt").font(.system(size: 11)).frame(width: 60)
          ForEach([0.0, 0.25, 0.5, 0.75, 1], id: \.self) { progress in
            let profile = GlyphStudyExample.examples[0].profile(size: size)
            GlyphDrawing(
              profile: profile, presentation: GlyphStudyExample.examples[0].presentation,
              diameter: size, unfolding: progress,
              layoutWidth: GlyphLayout.statusItemWidth(for: profile)
                + GlyphMorphGeometry.extensionWidth
            )
            .frame(
              width: GlyphLayout.statusItemWidth(for: profile) + GlyphMorphGeometry.extensionWidth,
              height: 24
            ).clipped()
            .frame(width: 150, height: 42, alignment: .trailing)
            .background(Color(white: 0.08)).foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
          }
        }
      }
    }
  }
}

// Looping GIFs for the README, drawn with the real glyph and moment views on a made-up menu bar.
@MainActor
enum MenuBarAnimation {
  private static let framesPerSecond = 30.0

  static func writeUnfold(to url: URL) throws {
    let unfolding = eased(steps: 12)
    let progress =
      hold(0, 30) + unfolding + hold(1, 60) + unfolding.reversed() + hold(0, 30)
    try write(progress.map { MenuBarUnfoldFrame(progress: $0) }, to: url)
  }

  // A moment each for power, sound, drives, a busy process, the network and the battery.
  static func writeMoments(to url: URL) throws {
    let moments = [
      StatusMoment(symbol: "powerplug.fill", title: "Power connected", priority: 2),
      StatusMoment(symbol: "headphones", title: "Studio Headphones", priority: 1),
      StatusMoment(symbol: "speaker.slash.fill", title: "Muted", priority: 1),
      StatusMoment(symbol: "externaldrive.badge.plus", title: "Archive mounted", priority: 1),
      StatusMoment(symbol: "flame", title: "Xcode at 340% CPU", priority: 2),
      StatusMoment(symbol: "wifi.exclamationmark", title: "Network unavailable", priority: 2),
      StatusMoment(symbol: "battery.25percent", title: "Battery is low", priority: 3),
    ]
    let appearing = eased(steps: 9)
    let visibility = appearing + hold(1, 42) + appearing.reversed() + hold(0, 12)
    let frames = moments.flatMap { moment in
      visibility.map { MenuBarMomentFrame(moment: moment, visibility: $0) }
    }
    try write(frames, to: url)
  }

  private static func write<Frame: View>(_ frames: [Frame], to url: URL) throws {
    guard
      let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.gif.identifier as CFString, frames.count, nil)
    else { throw CocoaError(.fileWriteUnknown) }
    CGImageDestinationSetProperties(
      destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for frame in frames {
      let renderer = ImageRenderer(content: frame)
      renderer.scale = 4
      guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
      CGImageDestinationAddImage(
        destination, image,
        [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / framesPerSecond]]
          as CFDictionary)
    }
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
  }

  private static func hold(_ value: Double, _ frames: Int) -> [Double] {
    Array(repeating: value, count: frames)
  }

  private static func eased(steps: Int) -> [Double] {
    (0...steps).map { step in
      let t = Double(step) / Double(steps)
      return t * t * (3 - 2 * t)
    }
  }
}

private struct DemoMenuBar<Item: View>: View {
  @ViewBuilder let item: Item
  var body: some View {
    HStack(spacing: 16) {
      Spacer(minLength: 0)
      item
      Image(systemName: "switch.2")
      Text("Mon 9:41")
    }
    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
    .padding(.horizontal, 14).frame(width: 360, height: 30)
    .background(
      LinearGradient(
        colors: [Color(red: 0.25, green: 0.2, blue: 0.4), Color(red: 0.18, green: 0.15, blue: 0.3)],
        startPoint: .leading, endPoint: .trailing))
    .environment(\.colorScheme, .dark)
  }
}

private struct MenuBarUnfoldFrame: View {
  let progress: Double
  private let example = GlyphStudyExample.examples[0]
  var body: some View {
    let profile = example.profile(size: 22)
    let compact = GlyphLayout.statusItemWidth(for: profile)
    let expanded = compact + GlyphMorphGeometry.extensionWidth
    DemoMenuBar {
      HStack(spacing: 16) {
        ForEach(["cloud", "music.note", "bolt.horizontal.circle"], id: \.self) {
          Image(systemName: $0)
        }
      }
      // Hidden items appear once the item is open, as they do in the menu bar.
      .opacity(max(0, (progress - 0.7) / 0.3))
      GlyphDrawing(
        profile: profile, presentation: example.presentation, diameter: 22, unfolding: progress,
        layoutWidth: expanded
      )
      .frame(width: expanded, height: 24, alignment: .trailing)
      .frame(width: compact + (expanded - compact) * progress, alignment: .trailing).clipped()
    }
  }
}

private struct MenuBarMomentFrame: View {
  let moment: StatusMoment
  let visibility: Double
  private let example = GlyphStudyExample.examples[0]
  var body: some View {
    let profile = example.profile(size: 22)
    let compact = GlyphLayout.statusItemWidth(for: profile)
    let full = MomentLayout.width(for: moment)
    DemoMenuBar {
      ZStack(alignment: .trailing) {
        GlyphDrawing(
          profile: profile, presentation: example.presentation, diameter: 22, layoutWidth: compact
        )
        .frame(width: compact, height: 24).opacity(1 - visibility)
        MomentPill(moment: moment).frame(width: full, height: 30)
          .opacity(visibility).offset(y: 4 * (1 - visibility))
      }
      .frame(width: compact + (full - compact) * visibility, height: 30, alignment: .trailing)
      .clipped()
    }
  }
}
