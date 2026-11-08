import AppKit
import Foundation
import StrataCore
import Testing

@testable import StrataBar

@Test @MainActor func processMenuActsOnlyFromTheExplorerAndOnASelectedProcess() throws {
  let model = AppModel(
    defaults: try #require(UserDefaults(suiteName: "StrataBar.Tests.\(UUID())")),
    collector: GatedSampler(), persistsPreferences: false)
  let navigation = ExplorerNavigation()
  let explorer = KeyWindowState()
  let controller = ProcessMenu(model: model, navigation: navigation) { explorer.isKey }
  let menu = controller.makeMenu()
  func enabled() -> [String] {
    menu.items.filter { !$0.isSeparatorItem && controller.validateMenuItem($0) }.map(\.title)
  }
  #expect(enabled().isEmpty)
  explorer.isKey = true
  #expect(enabled() == ["Find", "Hide Inspector"], "Without a selection nothing can be signaled")
  let request = navigation.searchFocusRequest
  let find = try #require(menu.items.first { $0.title == "Find" })
  _ = find.target?.perform(find.action, with: find)
  #expect(navigation.searchFocusRequest != request)
}

@MainActor private final class KeyWindowState {
  var isKey = false
}
