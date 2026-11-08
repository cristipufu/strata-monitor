import Foundation
import Testing

@testable import StrataBar

@Test @MainActor func statusPositionsSurviveCascadingUpdatesDuringRemoval() throws {
  let suite = "StatusItemPositionsTests.\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let first = "NSStatusItem Preferred Position first"
  let second = "NSStatusItem Preferred Position second"
  let missing = "NSStatusItem Preferred Position new"
  defaults.set(40, forKey: first)
  defaults.set(62, forKey: second)
  StatusItemPositions.preserve(["first", "second", "new"], in: defaults) {
    defaults.removeObject(forKey: first)
    defaults.set(22, forKey: second)
    defaults.set(0, forKey: missing)
    defaults.set("keep", forKey: "unrelated")
  }
  #expect(defaults.integer(forKey: first) == 40)
  #expect(defaults.integer(forKey: second) == 62)
  #expect(defaults.object(forKey: missing) == nil)
  #expect(defaults.string(forKey: "unrelated") == "keep")
}

@Test @MainActor func statusPositionsAreRestoredWhenTeardownIsInterrupted() throws {
  let suite = "StatusItemPositionsTests.\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let key = "NSStatusItem Preferred Position indicator"
  defaults.set(120, forKey: key)
  #expect(throws: CancellationError.self) {
    try StatusItemPositions.preserve(["indicator"], in: defaults) {
      defaults.set(0, forKey: key)
      throw CancellationError()
    }
  }
  #expect(defaults.integer(forKey: key) == 120)
}
