import AppKit
import SwiftUI

@MainActor
final class PanelHostingView<Content: View>: NSHostingView<Content> {
  required init(rootView: Content) {
    super.init(rootView: rootView)
    sizingOptions = []
    wantsLayer = true
    clipsToBounds = true
    layer?.backgroundColor = NSColor.clear.cgColor
    layer?.isOpaque = false
    // Constrain the backing surface as well as SwiftUI's glass to the visible card.
    layer?.cornerRadius = Design.Radius.panel
    layer?.cornerCurve = .continuous
    layer?.masksToBounds = true
  }

  @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
}
