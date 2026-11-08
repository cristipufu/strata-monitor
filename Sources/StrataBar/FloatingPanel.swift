import AppKit

@MainActor
final class FloatingPanel: NSPanel, MenuBarPanelHosting {
  static let contentInset: CGFloat = 12
  var acceptsKeyboard = false
  var onEscape: (() -> Void)?
  var onInteraction: (() -> Void)?
  override var canBecomeKey: Bool { acceptsKeyboard }
  override var canBecomeMain: Bool { false }
  init() {
    super.init(
      contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: false)
    isOpaque = false
    // Presentation owns opacity and scale. AppKit's implicit ordering
    // animation would compete with it and can run a nested event loop.
    animationBehavior = .none
    backgroundColor = .clear
    // Liquid Glass draws its own rounded edge and shadow. A second AppKit
    // shadow follows the rectangular hosting window and produces a visible box.
    hasShadow = false
    level = .statusBar
    hidesOnDeactivate = false
    isReleasedWhenClosed = false
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
  }
  override func cancelOperation(_ sender: Any?) { onEscape?() }
  override func sendEvent(_ event: NSEvent) {
    if event.type == .leftMouseDown { onInteraction?() }
    super.sendEvent(event)
  }
  func animateFrame(_ frame: NSRect, duration: TimeInterval) {
    NSAnimationContext.runAnimationGroup { context in
      context.duration = duration
      animator().setFrame(frame, display: true)
    }
  }
}
