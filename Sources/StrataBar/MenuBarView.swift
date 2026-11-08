import StrataCore
import SwiftUI

struct MenuBarView: View {
  @ObservedObject var model: AppModel
  @ObservedObject var motion: MenuBarMotion
  let open: () -> Void
  let openReading: (Reading) -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    GeometryReader { geometry in
      let compact = GlyphLayout.statusItemWidth(for: model.profile)
      ZStack(alignment: .trailing) {
        StrataGlyph(
          model: model, animatesEntrance: true, fitsMenuBar: true,
          unfolding: motion.unfolding
        )
        .opacity(1 - motion.momentVisibility)
        .allowsHitTesting(false).accessibilityHidden(true)
        Button(action: open) { Color.clear.contentShape(Rectangle()) }
          .buttonStyle(.plain).frame(width: compact)
          .allowsHitTesting(motion.unfolding == 0 && motion.momentVisibility < 0.8)
          .accessibilityHidden(motion.unfolding > 0 || motion.momentVisibility > 0.8)
          .accessibilityLabel("Strata Monitor").accessibilityValue(model.accessibilityStatus)
        HStack(spacing: 0) {
          readingButton(model.profile.bar)
          readingButton(model.profile.ring)
          readingButton(model.profile.center)
        }.frame(width: compact + GlyphMorphGeometry.extensionWidth)
          .allowsHitTesting(motion.unfolding > 0 && motion.momentVisibility < 0.8)
          .accessibilityHidden(motion.unfolding == 0 || motion.momentVisibility > 0.8)
        if let moment = motion.displayedMoment {
          Button(action: open) {
            MomentPill(moment: moment)
              .frame(width: motion.displayedMomentWidth, height: geometry.size.height)
              .background(Capsule().fill(.primary.opacity(0.05)).padding(.vertical, 3))
              .contentShape(Capsule())
          }.buttonStyle(.plain).opacity(motion.momentVisibility)
            .offset(y: reduceMotion ? 0 : 4 * (1 - motion.momentVisibility))
            .allowsHitTesting(motion.momentVisibility > 0.8)
            .accessibilityHidden(motion.momentVisibility < 0.8)
            .accessibilityLabel(moment.title)
        }
      }.frame(width: geometry.size.width, height: geometry.size.height, alignment: .trailing)
        .clipped()
    }
  }
  private func readingButton(_ reading: Reading) -> some View {
    Button {
      openReading(reading)
    } label: {
      Color.clear.contentShape(Rectangle())
    }.buttonStyle(.plain)
      .help("\(reading.title) · \(model.accessibleValue(for: reading))")
      .accessibilityLabel(reading.title).accessibilityValue(model.accessibleValue(for: reading))
  }

}

struct MomentPill: View {
  let moment: StatusMoment
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    HStack(spacing: MomentLayout.spacing) {
      Image(systemName: moment.symbol)
        .font(.system(size: MomentLayout.symbolSize, weight: .semibold))
        .foregroundStyle(Design.mint)
        .swapsWithoutAnimation()
      Text(verbatim: moment.title)
        .font(.system(size: MomentLayout.titleSize, weight: .medium, design: .rounded))
        .lineLimit(1).contentTransition(reduceMotion ? .identity : .opacity)
      Spacer(minLength: 0)
      Circle().fill(Design.mint).frame(
        width: MomentLayout.dotDiameter, height: MomentLayout.dotDiameter)
    }
    .padding(.horizontal, MomentLayout.horizontalPadding)
  }
}

// The pill's width is reserved in the native status item before it draws, so the
// measurement and the view share one definition.
enum MomentLayout {
  static let horizontalPadding: CGFloat = 10
  static let spacing: CGFloat = 8
  static let dotDiameter: CGFloat = 4
  static let symbolSize: CGFloat = 12
  static let titleSize: CGFloat = 11

  static func width(for moment: StatusMoment) -> CGFloat {
    let title = (moment.title as NSString).size(withAttributes: [.font: titleFont]).width
    let symbol =
      NSImage(systemSymbolName: moment.symbol, accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: symbolSize, weight: .semibold))?.size.width
      ?? symbolSize
    // Gaps sit between symbol and title, title and spacer, and spacer and dot.
    return (2 * horizontalPadding + symbol + title + 3 * spacing + dotDiameter).rounded(.up)
  }

  private static var titleFont: NSFont {
    let regular = NSFont.systemFont(ofSize: titleSize, weight: .medium)
    return regular.fontDescriptor.withDesign(.rounded).flatMap {
      NSFont(descriptor: $0, size: titleSize)
    } ?? regular
  }
}
