import AppKit

@MainActor
final class FloatingPanel: NSPanel, MenuBarPanelHosting {
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
    // The rounded content owns its edge; the borderless window must not add a rectangular shadow.
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
