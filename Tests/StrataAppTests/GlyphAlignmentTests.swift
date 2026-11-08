import AppKit
import StrataCore
import SwiftUI
import Testing

@testable import StrataBar

@Test @MainActor func renderedWiFiInkStaysCenteredInsideTheRingAtEverySize() throws {
  for reading in [Reading.cpu, .battery] {
    for diameter in [18.0, 21, 24] {
      var profile = Profile(name: "Alignment", ring: reading)
      profile.iconSize = diameter
      profile.accent = .red
      let drawing = GlyphDrawing(
        profile: profile,
        presentation: GlyphPresentation(
          ring: 1, bar: 1, center: .symbol("wifi", variableValue: 1)),
        diameter: diameter
      )
      .foregroundStyle(.white).frame(width: 80, height: 40).background(.black)
      .environment(\.colorScheme, .dark)
      let renderer = ImageRenderer(content: drawing)
      renderer.scale = 2
      let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
      let ring = try #require(
        horizontalInkBounds(in: bitmap) {
          $0.redComponent > 0.7 && $0.greenComponent < 0.5 && $0.blueComponent < 0.5
        })
      let symbol = try #require(
        horizontalInkBounds(in: bitmap) {
          $0.redComponent > 0.8 && $0.greenComponent > 0.8 && $0.blueComponent > 0.8
        })
      // Allow rasterization rounding without accepting a one-pixel lateral shift.
      #expect(abs(symbol.midpoint - ring.midpoint) <= 0.5)
    }
  }
}

private struct HorizontalInkBounds {
  var minimum: Int
  var maximum: Int
  var midpoint: Double { Double(minimum + maximum) / 2 }
}

private func horizontalInkBounds(
  in bitmap: NSBitmapImageRep, matching predicate: (NSColor) -> Bool
) -> HorizontalInkBounds? {
  var bounds: HorizontalInkBounds?
  for y in 0..<bitmap.pixelsHigh {
    for x in 0..<bitmap.pixelsWide {
      guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
        predicate(color)
      else { continue }
      if let current = bounds {
        bounds = HorizontalInkBounds(
          minimum: min(current.minimum, x), maximum: max(current.maximum, x))
      } else {
        bounds = HorizontalInkBounds(minimum: x, maximum: x)
      }
    }
  }
  return bounds
}
