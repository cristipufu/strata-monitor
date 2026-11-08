import StrataCore
import SwiftUI

struct StrataGlyph: View {
  @ObservedObject var model: AppModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorSchemeContrast) private var contrast
  @State private var hasEntered = false
  var size: CGFloat?
  var animatesEntrance = false
  var fitsMenuBar = false
  var unfolding: Double = 0
  var animatesReadings = true

  private var entranceProgress: Double {
    hasEntered || !animatesEntrance || !model.preferences.launchAnimationEnabled || reduceMotion
      ? 1 : 0
  }
  var body: some View {
    Group {
      if fitsMenuBar {
        GeometryReader { geometry in
          drawing(
            diameter: GlyphLayout.diameter(
              for: model.profile,
              available: CGSize(
                width: GlyphLayout.statusItemWidth(for: model.profile),
                height: geometry.size.height)), layoutWidth: geometry.size.width
          )
          .frame(width: geometry.size.width, height: geometry.size.height)
        }
      } else {
        drawing(diameter: size ?? model.profile.iconSize)
      }
    }
    .task {
      guard !hasEntered else { return }
      withAnimation(reduceMotion ? nil : .easeOut(duration: MotionPolicy.launchDraw)) {
        hasEntered = true
      }
    }
  }
  private func drawing(diameter: CGFloat, layoutWidth: CGFloat? = nil) -> some View {
    GlyphDrawing(
      profile: model.profile, presentation: model.glyphPresentation, diameter: diameter,
      reveal: entranceProgress, unfolding: unfolding, layoutWidth: layoutWidth, contrast: contrast,
      animatesReadings: animatesReadings)
  }
}
