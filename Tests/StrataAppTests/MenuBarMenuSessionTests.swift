import Foundation
import Testing

@testable import StrataBar

private actor MenuSessionProbe {
  private var answers: [Bool]
  private let holdFirst: Bool
  private var pending: CheckedContinuation<Bool, Never>?
  private(set) var reads = 0
  private(set) var queries: [CGPoint] = []
  init(_ answers: [Bool], holdFirst: Bool = false) {
    self.answers = answers
    self.holdFirst = holdFirst
  }
  func hasMenu(at pointerX: CGFloat = 0, below barBottom: CGFloat = 0) async -> Bool {
    reads += 1
    queries.append(CGPoint(x: pointerX, y: barBottom))
    if reads == 1 && holdFirst { return await withCheckedContinuation { pending = $0 } }
    return answers.isEmpty ? false : answers.removeFirst()
  }
  func finishHeldRead() {
    pending?.resume(returning: true)
    pending = nil
  }
}

private func menuInteraction() -> MenuBarInteraction {
  MenuBarInteraction(pointerX: 600, barBottom: 33)
}

@Test @MainActor func menuSessionWaitsForThePopupToCloseBeforeEndingItsReveal() async throws {
  let probe = MenuSessionProbe([false, true, true, false])
  let session = MenuBarMenuSession(hasMenu: { x, bottom in await probe.hasMenu(at: x, below: bottom) })
  let interaction = menuInteraction()
  var ended: [UUID] = []
  session.observe(interaction) { ended.append($0) }
  try await waitUntil { await probe.reads >= 3 }
  #expect(ended.isEmpty)
  try await waitUntil { ended == [interaction.id] }
  #expect(await probe.queries.allSatisfy { $0 == CGPoint(x: 600, y: 33) })
  session.stop()
}

@Test @MainActor func aStoppedMenuSessionRejectsALateReadWithoutRetainingItsOwner() async throws {
  let probe = MenuSessionProbe([], holdFirst: true)
  var session: MenuBarMenuSession? = MenuBarMenuSession(hasMenu: { _, _ in await probe.hasMenu() })
  let released = { [weak session] in session == nil }
  var endings = 0
  session?.observe(menuInteraction()) { _ in endings += 1 }
  try await waitUntil { await probe.reads == 1 }
  session?.stop()
  session = nil
  #expect(released())
  await probe.finishHeldRead()
  await Task.yield()
  #expect(endings == 0)
}

@Test @MainActor func aSupersededMenuSessionCannotEndTheNewInteraction() async throws {
  let oldProbe = MenuSessionProbe([], holdFirst: true)
  let session = MenuBarMenuSession(hasMenu: { _, _ in await oldProbe.hasMenu() })
  let old = menuInteraction()
  var ended: [UUID] = []
  session.observe(old) { ended.append($0) }
  try await waitUntil { await oldProbe.reads == 1 }
  let current = menuInteraction()
  session.observe(current) { ended.append($0) }
  await oldProbe.finishHeldRead()
  try await waitUntil { ended == [current.id] }
  #expect(!ended.contains(old.id))
  session.stop()
}
