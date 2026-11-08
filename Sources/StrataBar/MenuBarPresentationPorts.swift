import AppKit

@MainActor protocol PanelOrdering: AnyObject {
  var ignoresMouseEvents: Bool { get set }
  func orderFrontRegardless()
  func orderOut(_ sender: Any?)
}

extension NSWindow: PanelOrdering {}

@MainActor protocol MenuBarPanelHosting: PanelOrdering {
  var isVisible: Bool { get }
  var isKeyWindow: Bool { get }
  var canBecomeKey: Bool { get }
  var acceptsKeyboard: Bool { get set }
  var title: String { get set }
  var frame: CGRect { get }
  var contentView: NSView? { get set }
  var onEscape: (() -> Void)? { get set }
  var onInteraction: (() -> Void)? { get set }
  func makeKey()
  func resignKey()
  func setFrame(_ frame: NSRect, display: Bool)
  func animateFrame(_ frame: NSRect, duration: TimeInterval)
}

@MainActor protocol MenuBarStatusItemHosting: AnyObject {
  var button: NSButton? { get }
  var length: CGFloat { get set }
  var autosaveName: String? { get set }
  var isVisible: Bool { get set }
  func remove()
}

@MainActor final class NativeMenuBarStatusItem: MenuBarStatusItemHosting {
  private let item: NSStatusItem
  init() { item = NSStatusBar.system.statusItem(withLength: 36) }
  var button: NSButton? { item.button }
  var length: CGFloat {
    get { item.length }
    set { item.length = newValue }
  }
  var autosaveName: String? {
    get { item.autosaveName }
    set { item.autosaveName = newValue }
  }
  var isVisible: Bool {
    get { item.isVisible }
    set { item.isVisible = newValue }
  }
  func remove() { NSStatusBar.system.removeStatusItem(item) }
}

@MainActor protocol MenuBarEventMonitoring {
  func global(_ events: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> Void) -> Any?
  func local(_ events: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> NSEvent?) -> Any?
  func remove(_ monitor: Any)
}

struct NativeMenuBarEventMonitor: MenuBarEventMonitoring {
  func global(_ events: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> Void) -> Any? {
    NSEvent.addGlobalMonitorForEvents(matching: events, handler: handler)
  }
  func local(_ events: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> NSEvent?) -> Any? {
    NSEvent.addLocalMonitorForEvents(matching: events, handler: handler)
  }
  func remove(_ monitor: Any) { NSEvent.removeMonitor(monitor) }
}
