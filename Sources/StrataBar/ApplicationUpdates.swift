import Combine
import Foundation
import Sparkle
import SwiftUI

@MainActor
final class ApplicationUpdates: ObservableObject {
  @Published private(set) var canCheck = false
  @Published private(set) var automaticallyChecks = false
  @Published private(set) var automaticallyDownloads = false
  private let controller: SPUStandardUpdaterController?

  init(controller: SPUStandardUpdaterController? = nil) {
    self.controller = controller
    guard let updater = controller?.updater else { return }
    updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
    updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automaticallyChecks)
    updater.publisher(for: \.automaticallyDownloadsUpdates).assign(to: &$automaticallyDownloads)
  }

  static func configured(in bundle: Bundle, isPreview: Bool) -> ApplicationUpdates {
    guard !isPreview, isConfigured(in: bundle) else { return ApplicationUpdates() }
    return ApplicationUpdates(controller: SPUStandardUpdaterController(
      startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil))
  }

  static func isConfigured(in bundle: Bundle) -> Bool {
    guard bundle.bundleURL.pathExtension == "app",
      let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
      Data(base64Encoded: key)?.count == 32,
      let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
      let url = URL(string: feed), url.scheme == "https", url.host == "github.com"
    else { return false }
    return true
  }

  var isAvailable: Bool { controller != nil }
  func checkNow() { controller?.checkForUpdates(nil) }
  func setAutomaticChecks(_ enabled: Bool) {
    controller?.updater.automaticallyChecksForUpdates = enabled
  }
  func setAutomaticDownloads(_ enabled: Bool) {
    controller?.updater.automaticallyDownloadsUpdates = enabled
  }
}

struct UpdatesSection: View {
  @ObservedObject var updates: ApplicationUpdates

  var body: some View {
    Section("Updates") {
      if updates.isAvailable {
        Toggle("Check for updates automatically", isOn: Binding(
          get: { updates.automaticallyChecks }, set: { updates.setAutomaticChecks($0) }))
        Toggle("Download and install updates automatically", isOn: Binding(
          get: { updates.automaticallyDownloads }, set: { updates.setAutomaticDownloads($0) }))
          .disabled(!updates.automaticallyChecks)
        Text("Checks GitHub once a day when enabled. Signed updates install when Strata Monitor quits.")
          .footnoteStyle()
        Button("Check for Updates…", action: updates.checkNow).disabled(!updates.canCheck)
      } else {
        Text("Updates are available in copies installed from a release.").footnoteStyle()
      }
    }
  }
}
