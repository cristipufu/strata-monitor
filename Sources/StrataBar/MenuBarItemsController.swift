import AppKit
import Combine

@MainActor final class MenuBarItemsController: ObservableObject {
  @Published private(set) var menuInteraction: MenuBarInteraction?
  private let divider: (any MenuBarDividerHosting)?
  private let menuSession: MenuBarMenuSession
  private var running = false
  private var unfolded = false

  init(divider: (any MenuBarDividerHosting)?, menuSession: MenuBarMenuSession = MenuBarMenuSession())
  {
    self.divider = divider
    self.menuSession = menuSession
  }

  func start() {
    running = true
    synchronizeVisibility()
  }

  func attach(indicator: NSButton?, autosaveName: String?) {
    divider?.attach(indicator: indicator, autosaveName: autosaveName)
    synchronizeVisibility()
  }

  func setUnfolded(_ unfolded: Bool) {
    guard self.unfolded != unfolded else { return }
    self.unfolded = unfolded
    synchronizeVisibility()
  }

  func beginMenu(at pointerX: CGFloat, barBottom: CGFloat) {
    guard running else { return }
    let interaction = MenuBarInteraction(pointerX: pointerX, barBottom: barBottom)
    menuInteraction = interaction
    menuSession.observe(interaction) { [weak self] id in self?.endMenu(id) }
    synchronizeVisibility()
  }

  func stop() {
    running = false
    menuSession.stop()
    menuInteraction = nil
    divider?.stop()
  }

  private func endMenu(_ id: UUID) {
    guard menuInteraction?.id == id else { return }
    menuInteraction = nil
    synchronizeVisibility()
  }

  private func synchronizeVisibility() {
    guard running else { return }
    divider?.setRevealed(unfolded || menuInteraction != nil)
  }
}
