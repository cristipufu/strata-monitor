import CoreFoundation
import Foundation
import StrataCore

enum ApplicationPreferences {
  static let bundleIdentifier = "dev.stratabar.app"
  static let legacyBundleIdentifier = "dev.strata.bar"
  static let key = "StrataBar.preferences.v1"
  static let pausedProcessesKey = "StrataBar.pausedProcesses.v1"
  static let statusItemName = "dev.stratabar.app.indicator"
  private static let legacyStatusItemName = "dev.strata.bar.indicator"

  static func migrate(from legacy: UserDefaults, to current: UserDefaults) {
    migrateProfiles(from: legacy, to: current)
    let positionKey = "NSStatusItem Preferred Position \(statusItemName)"
    let oldPositionKey = "NSStatusItem Preferred Position \(legacyStatusItemName)"
    if current.object(forKey: positionKey) == nil,
      let position = legacy.object(forKey: oldPositionKey) as? NSNumber,
      CFGetTypeID(position) != CFBooleanGetTypeID(),
      position.doubleValue.isFinite, position.doubleValue >= 0
    {
      current.set(position, forKey: positionKey)
    }
    let frameKey = "NSWindow Frame StrataBar.Explorer"
    if current.object(forKey: frameKey) == nil,
      let frame = legacy.object(forKey: frameKey) as? String, frame.count <= 512
    {
      current.set(frame, forKey: frameKey)
    }
  }
  private static func migrateProfiles(from legacy: UserDefaults, to current: UserDefaults) {
    guard current.object(forKey: key) == nil, let data = legacy.data(forKey: key),
      data.count <= 128_000
    else { return }
    do {
      var preferences = try JSONDecoder().decode(Preferences.self, from: data)
      guard preferences.version == 1 else { return }
      preferences.validate()
      current.set(try JSONEncoder().encode(preferences), forKey: key)
    } catch {
      // An unreadable old profile must not prevent normal first-run defaults.
      return
    }
  }
}
