import Foundation
import Testing
@testable import StrataBar

@MainActor
struct ApplicationLanguageTests {
  @Test func selectionPersistsOnlySupportedLanguagesAndCanReturnToSystem() throws {
    let suite = "dev.stratabar.tests.language.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.register(defaults: ["AppleLanguages": ["ro"]])
    let language = ApplicationLanguage(defaults: defaults, domainName: suite, localizations: ["ro", "en", "Base", "ro"])
    #expect(language.languages == ["en", "ro"])
    #expect(language.selection.isEmpty)
    language.select("invalid")
    #expect(!language.needsRestart)
    #expect(defaults.persistentDomain(forName: suite)?["AppleLanguages"] == nil)
    language.select("ro")
    #expect(language.needsRestart)
    #expect(defaults.stringArray(forKey: "AppleLanguages") == ["ro"])
    #expect(ApplicationLanguage(defaults: defaults, domainName: suite, localizations: ["en", "ro"]).selection == "ro")
    language.select("")
    #expect(defaults.persistentDomain(forName: suite)?["AppleLanguages"] == nil)
  }

  @Test func previewDoesNotPersistOrRequestRestart() {
    let language = ApplicationLanguage(defaults: nil, localizations: ["en", "ja"])
    language.select("ja")
    #expect(language.selection.isEmpty)
    #expect(!language.needsRestart)
  }

  @Test func obsoleteSavedLanguageFallsBackToSystem() throws {
    let suite = "dev.stratabar.tests.language.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(["xx"], forKey: "AppleLanguages")
    #expect(ApplicationLanguage(defaults: defaults, domainName: suite, localizations: ["en"]).selection.isEmpty)
  }
}
