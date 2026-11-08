import AppKit
import OSLog

@MainActor protocol MenuBarDividerHosting: AnyObject {
  func attach(indicator: NSButton?, autosaveName: String?)
  func setRevealed(_ revealed: Bool)
  func stop()
}

// One empty status item sits just left of the ring. Stretching it pushes every item to its
// left beyond the display edge; collapsing it brings them back in place.
@MainActor final class NativeMenuBarDivider: MenuBarDividerHosting {
  static let autosaveName = "dev.stratabar.app.divider"
  private static let logger = Logger(subsystem: "dev.stratabar.app", category: "MenuBarItems")
  // A measurable width lets placement be confirmed before anything is hidden.
  private static let placementWidth: CGFloat = 1
  private static let revealedWidth: CGFloat = 0
  private static let placementReads = 12
  private static let placementReadInterval: Duration = .milliseconds(80)
  private let defaults: UserDefaults
  private weak var indicator: NSButton?
  private var indicatorAutosaveName: String?
  private var item: NSStatusItem?
  private var revealed = true
  private var placementConfirmed = false
  private var placementTask: Task<Void, Never>?
  private var screenChangeObserver: NSObjectProtocol?

  init(defaults: UserDefaults) {
    self.defaults = defaults
  }

  func attach(indicator: NSButton?, autosaveName: String?) {
    stop()
    self.indicator = indicator
    indicatorAutosaveName = autosaveName
  }

  func setRevealed(_ revealed: Bool) {
    self.revealed = revealed
    guard indicator?.window != nil else {
      removeItem()
      return
    }
    installIfNeeded()
    if placementConfirmed { applyLength() } else { confirmPlacement() }
  }

  func stop() {
    removeItem()
  }

  private func applyLength() {
    guard let item else { return }
    let length = revealed ? Self.revealedWidth : hidingWidth
    if item.length != length { item.length = length }
  }

  private var hidingWidth: CGFloat {
    let widest = NSScreen.screens.map(\.frame.width).max() ?? 1600
    return min(5000, widest + 256)
  }

  private struct Placement: Equatable {
    let ring: CGRect
    let divider: CGRect
  }

  private var safePlacement: Placement? {
    guard let indicator, let ringWindow = indicator.window, let screen = ringWindow.screen,
      let button = item?.button, let dividerWindow = button.window
    else { return nil }
    let ring = ringWindow.convertToScreen(indicator.convert(indicator.bounds, to: nil))
    let divider = dividerWindow.convertToScreen(button.convert(button.bounds, to: nil))
    let region = screen.auxiliaryTopRightArea ?? screen.frame
    guard region.contains(ring), divider.maxX <= ring.minX, abs(divider.midY - ring.midY) <= 2
    else { return nil }
    return Placement(ring: ring, divider: divider)
  }

  private func confirmPlacement() {
    guard placementTask == nil, let item else { return }
    item.length = Self.placementWidth
    placementTask = Task { [weak self] in
      var previous: Placement?
      for _ in 0..<Self.placementReads {
        do { try await Task.sleep(for: Self.placementReadInterval) } catch { return }
        guard let self, !Task.isCancelled, self.item != nil else { return }
        let current = self.safePlacement
        if let current, current == previous {
          self.placementTask = nil
          self.placementConfirmed = true
          self.applyLength()
          return
        }
        previous = current
      }
      self?.placementTask = nil
      Self.logger.notice("Menu bar items stay visible until Strata Monitor is to their right")
    }
  }

  private func revalidatePlacement() {
    guard item != nil else { return }
    placementTask?.cancel()
    placementTask = nil
    placementConfirmed = false
    confirmPlacement()
  }

  private func installIfNeeded() {
    guard item == nil else { return }
    seedPosition()
    let item = NSStatusBar.system.statusItem(withLength: Self.placementWidth)
    item.autosaveName = Self.autosaveName
    if let button = item.button {
      button.title = ""
      // A stretched button must not draw its hover highlight across the menu bar.
      button.isTransparent = true
      button.isEnabled = false
      button.setAccessibilityElement(false)
    }
    self.item = item
    screenChangeObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in self?.revalidatePlacement() }
    }
  }

  private func seedPosition() {
    let key = Self.positionKey(Self.autosaveName)
    guard defaults.object(forKey: key) == nil, let indicatorAutosaveName,
      let value = defaults.object(forKey: Self.positionKey(indicatorAutosaveName)) as? NSNumber,
      value.doubleValue.isFinite, value.doubleValue >= 0
    else { return }
    // Larger preferred positions sit further left, so this lands immediately left of the ring.
    defaults.set(value.doubleValue + 1, forKey: key)
  }

  private static func positionKey(_ autosaveName: String) -> String {
    "NSStatusItem Preferred Position \(autosaveName)"
  }

  private func removeItem() {
    if let screenChangeObserver { NotificationCenter.default.removeObserver(screenChangeObserver) }
    screenChangeObserver = nil
    placementTask?.cancel()
    placementTask = nil
    placementConfirmed = false
    guard let item else { return }
    self.item = nil
    let names = [Self.autosaveName] + [indicatorAutosaveName].compactMap { $0 }
    StatusItemPositions.preserve(names, in: defaults) {
      // Detach autosave before AppKit schedules removal, which would clear the saved position.
      item.autosaveName = nil
      // Control Center keeps a removed item that is still stretched off screen, and that
      // leftover would hide the menu bar after Strata Monitor quits.
      item.length = Self.placementWidth
      NSStatusBar.system.removeStatusItem(item)
    }
  }

  isolated deinit { removeItem() }
}
