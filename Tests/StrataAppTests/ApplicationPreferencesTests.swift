import Foundation
import StrataCore
import Testing

@testable import StrataBar

@Test func changingBundleIdentityPreservesProfilesThemeAndOnlyOwnedWindowPositions() throws {
  let sourceName = "StrataBar.Migration.Source.\(UUID())"
  let targetName = "StrataBar.Migration.Target.\(UUID())"
  let source = try #require(UserDefaults(suiteName: sourceName))
  let target = try #require(UserDefaults(suiteName: targetName))
  defer {
    source.removePersistentDomain(forName: sourceName)
    target.removePersistentDomain(forName: targetName)
  }
  var preferences = Preferences()
  preferences.appearance = .dark
  preferences.hasCompletedWelcome = true
  preferences.profiles[0].iconSize = 21
  preferences.selectProfile(preferences.profiles[0].id)
  let data = try JSONEncoder().encode(preferences)
  source.set(data, forKey: ApplicationPreferences.key)
  source.set(284, forKey: "NSStatusItem Preferred Position dev.strata.bar.indicator")
  source.set("100 100 1000 700", forKey: "NSWindow Frame StrataBar.Explorer")
  source.set(false, forKey: "NSStatusItem Visible Item-0")
  ApplicationPreferences.migrate(from: source, to: target)
  let restored = Preferences.decode(target.data(forKey: ApplicationPreferences.key))
  #expect(restored.appearance == .dark && restored.hasCompletedWelcome)
  #expect(
    restored.activeProfile.iconSize == 21
      && restored.activeProfile.id == preferences.activeProfile.id)
  #expect(
    target.integer(
      forKey: "NSStatusItem Preferred Position \(ApplicationPreferences.statusItemName)") == 284)
  #expect(target.string(forKey: "NSWindow Frame StrataBar.Explorer") == "100 100 1000 700")
  #expect(target.object(forKey: "NSStatusItem Visible Item-0") == nil)
  #expect(source.data(forKey: ApplicationPreferences.key) == data)
}

@Test func existingPreferencesInTheNewBundleDomainAreNeverOverwritten() throws {
  let sourceName = "StrataBar.Migration.Source.\(UUID())"
  let targetName = "StrataBar.Migration.Target.\(UUID())"
  let source = try #require(UserDefaults(suiteName: sourceName))
  let target = try #require(UserDefaults(suiteName: targetName))
  defer {
    source.removePersistentDomain(forName: sourceName)
    target.removePersistentDomain(forName: targetName)
  }
  var old = Preferences()
  old.appearance = .light
  var current = Preferences()
  current.appearance = .dark
  source.set(try JSONEncoder().encode(old), forKey: ApplicationPreferences.key)
  let data = try JSONEncoder().encode(current)
  target.set(data, forKey: ApplicationPreferences.key)
  let positionKey = "NSStatusItem Preferred Position \(ApplicationPreferences.statusItemName)"
  source.set(200, forKey: "NSStatusItem Preferred Position dev.strata.bar.indicator")
  target.set(500, forKey: positionKey)
  ApplicationPreferences.migrate(from: source, to: target)
  #expect(target.data(forKey: ApplicationPreferences.key) == data)
  #expect(target.integer(forKey: positionKey) == 500)
}

@Test func malformedLegacyPreferencesAndPositionsAreNotImported() throws {
  let sourceName = "StrataBar.Migration.Source.\(UUID())"
  let targetName = "StrataBar.Migration.Target.\(UUID())"
  let source = try #require(UserDefaults(suiteName: sourceName))
  let target = try #require(UserDefaults(suiteName: targetName))
  defer {
    source.removePersistentDomain(forName: sourceName)
    target.removePersistentDomain(forName: targetName)
  }
  source.set(Data("invalid".utf8), forKey: ApplicationPreferences.key)
  source.set(-10, forKey: "NSStatusItem Preferred Position dev.strata.bar.indicator")
  ApplicationPreferences.migrate(from: source, to: target)
  #expect(target.object(forKey: ApplicationPreferences.key) == nil)
  #expect(
    target.object(
      forKey: "NSStatusItem Preferred Position \(ApplicationPreferences.statusItemName)") == nil)
}
