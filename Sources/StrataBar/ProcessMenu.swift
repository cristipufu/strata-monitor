import AppKit
import StrataCore

// The Process menu acts on the Explorer's selected process; its items are enabled only while
// the Explorer is the key window and Strata Monitor may act on that process.
@MainActor final class ProcessMenu: NSObject, NSMenuItemValidation {
  private let model: AppModel
  private let navigation: ExplorerNavigation
  private let isExplorerKey: @MainActor () -> Bool
  private static let backspace = String(UnicodeScalar(UInt8(NSBackspaceCharacter)))

  init(
    model: AppModel, navigation: ExplorerNavigation,
    isExplorerKey: @escaping @MainActor () -> Bool
  ) {
    self.model = model
    self.navigation = navigation
    self.isExplorerKey = isExplorerKey
  }

  func makeMenu() -> NSMenu {
    let menu = NSMenu(title: String(localized: "Process"))
    add(String(localized: "Find"), #selector(find), "f", to: menu)
    add(String(localized: "Show Inspector"), #selector(toggleInspector), "i", to: menu)
    menu.addItem(.separator())
    add(String(localized: "Pause"), #selector(togglePause), "p", modifiers: [.command, .option], to: menu)
    add(String(localized: "Quit Process…"), #selector(quitProcess), "q", modifiers: [.command, .option], to: menu)
    add(String(localized: "Terminate…"), #selector(terminate), Self.backspace, to: menu)
    add(String(localized: "Force Quit…"), #selector(forceQuit), Self.backspace, modifiers: [.command, .option], to: menu)
    return menu
  }

  private func add(
    _ title: String, _ action: Selector, _ key: String,
    modifiers: NSEvent.ModifierFlags = .command, to menu: NSMenu
  ) {
    let item = menu.addItem(
      withTitle: title, action: action,
      keyEquivalent: key)
    item.keyEquivalentModifierMask = modifiers
    item.target = self
  }

  private var selected: ProcessSample? {
    navigation.identity.flatMap { identity in model.processes.first { $0.id == identity } }
  }

  func validateMenuItem(_ item: NSMenuItem) -> Bool {
    guard isExplorerKey() else { return false }
    switch item.action {
    case #selector(find): return true
    case #selector(toggleInspector):
      item.title =
        navigation.showsInspector
        ? String(localized: "Hide Inspector") : String(localized: "Show Inspector")
      return true
    case #selector(togglePause):
      let resumes = selected?.runState == .stopped
      item.title = resumes ? String(localized: "Resume") : String(localized: "Pause")
      return allows(resumes ? .resume : .pause)
    case #selector(quitProcess):
      return !model.processActions.isBusy
        && selected.map(model.processActions.canQuitApplication) == true
    case #selector(terminate): return allows(.terminate)
    case #selector(forceQuit): return allows(.forceQuit)
    default: return false
    }
  }

  private func allows(_ signal: ProcessSignal) -> Bool {
    guard !model.processActions.isBusy, let process = selected else { return false }
    return ProcessActionPolicy.allows(
      signal, for: process, currentPID: ProcessInfo.processInfo.processIdentifier,
      currentUser: getuid())
  }

  @objc private func find() { navigation.requestSearchFocus() }
  @objc private func toggleInspector() { navigation.showsInspector.toggle() }
  @objc private func togglePause() {
    guard let process = selected else { return }
    model.processActions.request(process, signal: process.runState == .stopped ? .resume : .pause)
  }
  @objc private func quitProcess() {
    guard let process = selected else { return }
    model.processActions.requestApplicationQuit(process)
  }
  @objc private func terminate() {
    guard let process = selected else { return }
    model.processActions.request(process, signal: .terminate)
  }
  @objc private func forceQuit() {
    guard let process = selected else { return }
    model.processActions.request(process, signal: .forceQuit)
  }
}
