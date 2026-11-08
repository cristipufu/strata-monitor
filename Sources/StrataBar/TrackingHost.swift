import AppKit
import StrataCore
import SwiftUI

@MainActor
final class TrackingHost<Content: View>: NSHostingView<Content> {
  private var tracking: NSTrackingArea?
  private let event: (PresentationEvent) -> Void
  private let contextMenu: (() -> NSMenu?)?
  private let usesSwiftUIControls: Bool
  init(
    rootView: Content, event: @escaping (PresentationEvent) -> Void,
    contextMenu: (() -> NSMenu?)? = nil, usesSwiftUIControls: Bool = false
  ) {
    self.event = event
    self.contextMenu = contextMenu
    self.usesSwiftUIControls = usesSwiftUIControls
    super.init(rootView: rootView)
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
    layer?.isOpaque = false
    layerContentsPlacement = .right
  }
  @available(*, unavailable) required init(rootView: Content) { fatalError() }
  @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
  func reserveCanvasWidth(_ width: CGFloat) {
    guard width > frame.width else { return }
    let right = frame.maxX
    MenuBarLayoutTransaction.perform {
      setFrameSize(CGSize(width: width, height: frame.height))
      setFrameOrigin(CGPoint(x: right - width, y: frame.minY))
    }
  }
  override func resize(withOldSuperviewSize oldSize: NSSize) {
    MenuBarLayoutTransaction.perform { super.resize(withOldSuperviewSize: oldSize) }
  }
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    guard tracking == nil else { return }
    let area = NSTrackingArea(
      rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
    addTrackingArea(area)
    tracking = area
  }
  override func mouseEntered(with event: NSEvent) { self.event(.entered(.indicator)) }
  override func mouseExited(with event: NSEvent) { self.event(.exited(.indicator)) }
  override func mouseDown(with event: NSEvent) {
    if usesSwiftUIControls { super.mouseDown(with: event) } else { self.event(.click) }
  }
  override func menu(for event: NSEvent) -> NSMenu? { contextMenu?() }
  override func rightMouseDown(with event: NSEvent) {
    if let menu = menu(for: event) { NSMenu.popUpContextMenu(menu, with: event, for: self) }
  }
  override func hitTest(_ point: NSPoint) -> NSView? {
    usesSwiftUIControls ? super.hitTest(point) : bounds.contains(point) ? self : nil
  }
  override func accessibilityPerformPress() -> Bool {
    event(.click)
    return true
  }
}
