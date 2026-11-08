import AppKit

// In demo mode, a plain window behind everything Strata Monitor shows, so glass picks up a
// neutral tone instead of the desktop picture. It takes no clicks and leaves with the app.
@MainActor final class DemoBackdrop {
  private let window: NSWindow

  init(screen: NSScreen) {
    window = NSWindow(
      contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.level = .normal
    window.ignoresMouseEvents = true
    window.isReleasedWhenClosed = false
    window.collectionBehavior = [.canJoinAllSpaces, .stationary]
    window.backgroundColor = NSColor(name: nil) { appearance in
      appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(red: 0.11, green: 0.1, blue: 0.15, alpha: 1)
        : NSColor(red: 0.9, green: 0.89, blue: 0.94, alpha: 1)
    }
    window.orderFrontRegardless()
  }
}
