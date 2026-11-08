import Foundation
import SwiftUI

@MainActor
final class ApplicationLanguage: ObservableObject {
  @Published private(set) var selection: String
  @Published private(set) var needsRestart = false
  let languages: [String]
  private let defaults: UserDefaults?

  init(defaults: UserDefaults?, domainName: String = ApplicationPreferences.bundleIdentifier,
       localizations: [String] = Bundle.main.localizations) {
    self.defaults = defaults
    languages = Array(Set(localizations).subtracting(["Base"])).sorted {
      if $0 == "en" || $1 == "en" { return $0 == "en" && $1 != "en" }
      return Self.name($0).localizedCaseInsensitiveCompare(Self.name($1)) == .orderedAscending
    }
    let savedLanguages = defaults?.persistentDomain(forName: domainName)?["AppleLanguages"] as? [String]
    let saved = savedLanguages?.first ?? ""
    selection = languages.contains(saved) ? saved : ""
  }

  func select(_ code: String) {
    guard let defaults, code != selection, code.isEmpty || languages.contains(code) else { return }
    if code.isEmpty { defaults.removeObject(forKey: "AppleLanguages") }
    else { defaults.set([code], forKey: "AppleLanguages") }
    selection = code
    needsRestart = true
  }

  static func name(_ code: String) -> String {
    Locale(identifier: code).localizedString(forIdentifier: code) ?? code
  }
}

struct LanguageSection: View {
  @ObservedObject var language: ApplicationLanguage

  var body: some View {
    Section("Language") {
      Picker("Language", selection: Binding(get: { language.selection }, set: { language.select($0) })) {
        Text("System Default").tag("")
        ForEach(language.languages, id: \.self) { code in
          Text(verbatim: ApplicationLanguage.name(code)).tag(code)
        }
      }
      if language.needsRestart {
        Text("Quit and reopen Strata Monitor to apply the new language.").footnoteStyle()
      }
    }
  }
}
