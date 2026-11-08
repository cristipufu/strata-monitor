import AppKit
import Foundation
import Testing

@testable import StrataBar

@MainActor private final class DividerFixture: MenuBarDividerHosting {
  private(set) var reveals: [Bool] = []
  private(set) var stops = 0
  private(set) var autosaveName: String?
  func attach(indicator: NSButton?, autosaveName: String?) { self.autosaveName = autosaveName }
  func setRevealed(_ revealed: Bool) { reveals.append(revealed) }
  func stop() { stops += 1 }
}

private actor MenuProbe {
  private var answers: [Bool]
  private var held: CheckedContinuation<Bool, Never>?
  private let holdFirst: Bool
  private(set) var reads = 0
  init(_ answers: [Bool], holdFirst: Bool = false) {
    self.answers = answers
    self.holdFirst = holdFirst
  }
  func hasMenu() async -> Bool {
    reads += 1
    if reads == 1 && holdFirst { return await withCheckedContinuation { held = $0 } }
    return answers.isEmpty ? false : answers.removeFirst()
  }
  func release() {
    held?.resume(returning: true)
    held = nil
  }
}

@MainActor private func itemsController(
  _ divider: DividerFixture, probe: MenuProbe = MenuProbe([])
) -> MenuBarItemsController {
  MenuBarItemsController(
    divider: divider, menuSession: MenuBarMenuSession(hasMenu: { _, _ in await probe.hasMenu() }))
}

@Test @MainActor func menuBarItemsStayHiddenUntilTheRingUnfolds() {
  let divider = DividerFixture()
  let items = itemsController(divider)
  items.attach(indicator: nil, autosaveName: "indicator")
  items.setUnfolded(true)
  #expect(divider.reveals.isEmpty && divider.autosaveName == "indicator")
  items.start()
  #expect(divider.reveals == [true])
  items.setUnfolded(false)
  items.setUnfolded(false)
  #expect(divider.reveals == [true, false])
  items.stop()
}

@Test @MainActor func anOpenMenuKeepsItsItemsRevealedAfterTheRingFolds() async throws {
  let divider = DividerFixture()
  let probe = MenuProbe([true, true, false])
  let items = itemsController(divider, probe: probe)
  items.start()
  items.setUnfolded(true)
  items.beginMenu(at: 600, barBottom: 33)
  items.setUnfolded(false)
  #expect(divider.reveals.last == true && items.menuInteraction != nil)
  try await waitUntil { items.menuInteraction == nil }
  #expect(divider.reveals.last == false)
  items.stop()
}

@Test @MainActor func stoppingRemovesTheDividerAndIgnoresLateMenus() async throws {
  let divider = DividerFixture()
  let probe = MenuProbe([], holdFirst: true)
  let items = itemsController(divider, probe: probe)
  items.start()
  items.beginMenu(at: 600, barBottom: 33)
  try await waitUntil { await probe.reads == 1 }
  items.stop()
  let revealsAtStop = divider.reveals
  items.beginMenu(at: 600, barBottom: 33)
  await probe.release()
  try await Task.sleep(for: .milliseconds(150))
  #expect(divider.stops == 1 && items.menuInteraction == nil)
  #expect(divider.reveals == revealsAtStop)
}

@Test @MainActor func aDividerWithoutAPlacedIndicatorNeverHidesItemsOrSavesAPosition() throws {
  let suite = "MenuBarDividerTests.\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  defaults.set(209, forKey: "NSStatusItem Preferred Position indicator")
  let divider = NativeMenuBarDivider(defaults: defaults)
  divider.attach(indicator: NSButton(), autosaveName: "indicator")
  divider.setRevealed(false)
  divider.stop()
  #expect(
    defaults.object(forKey: "NSStatusItem Preferred Position \(NativeMenuBarDivider.autosaveName)")
      == nil)
}
