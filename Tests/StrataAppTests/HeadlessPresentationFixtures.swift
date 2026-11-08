import AppKit

@testable import StrataBar

@MainActor final class HeadlessPanel: MenuBarPanelHosting {
  var isVisible = false
  var isKeyWindow = false
  var canBecomeKey: Bool { acceptsKeyboard }
  var acceptsKeyboard = false
  var ignoresMouseEvents = false
  var title = ""
  var frame = CGRect.zero
  var contentView: NSView?
  var onEscape: (() -> Void)?
  var onInteraction: (() -> Void)?
  func orderFrontRegardless() { isVisible = true }
  func orderOut(_ sender: Any?) {
    isVisible = false
    isKeyWindow = false
  }
  func makeKey() { isKeyWindow = acceptsKeyboard }
  func resignKey() { isKeyWindow = false }
  func setFrame(_ frame: NSRect, display: Bool) { self.frame = frame }
  func animateFrame(_ frame: NSRect, duration: TimeInterval) { self.frame = frame }
}

@MainActor final class HeadlessStatusItem: MenuBarStatusItemHosting {
  let button: NSButton? = NSButton(frame: NSRect(x: 0, y: 0, width: 36, height: 24))
  var length: CGFloat = 36
  var autosaveName: String?
  var isVisible = false
  private(set) var removed = false
  var onRemove: ((String?) -> Void)?
  func remove() {
    onRemove?(autosaveName)
    removed = true
  }
}

@MainActor final class HeadlessMenuBarEvents: MenuBarEventMonitoring {
  private(set) var activeMonitors: Set<UUID> = []
  func global(_ events: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> Void) -> Any? {
    register()
  }
  func local(_ events: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> NSEvent?) -> Any? {
    register()
  }
  func remove(_ monitor: Any) {
    if let id = monitor as? UUID { activeMonitors.remove(id) }
  }
  private func register() -> UUID {
    let id = UUID()
    activeMonitors.insert(id)
    return id
  }
}
