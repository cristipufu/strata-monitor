import Foundation
import Testing
@testable import StrataBar

@MainActor
struct ApplicationUpdatesTests {
  @Test func unavailableUpdaterDoesNotCheckOrChangeSettings() {
    let updates = ApplicationUpdates()
    updates.checkNow()
    updates.setAutomaticChecks(true)
    updates.setAutomaticDownloads(true)
    #expect(!updates.isAvailable)
    #expect(!updates.canCheck)
    #expect(!updates.automaticallyChecks)
    #expect(!updates.automaticallyDownloads)
  }

  @Test func productionConfigurationRequiresBundleKeyAndSecureFeed() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    func bundle(named name: String, key: String, feed: String) throws -> Bundle {
      let application = directory.appending(path: name)
      let contents = application.appending(path: "Contents")
      try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
      let info = ["CFBundleIdentifier": "dev.stratabar.tests.\(UUID().uuidString)",
                  "SUPublicEDKey": key, "SUFeedURL": feed]
      try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        .write(to: contents.appending(path: "Info.plist"))
      return try #require(Bundle(url: application))
    }
    let key = Data(repeating: 1, count: 32).base64EncodedString()
    let feed = "https://github.com/cristipufu/strata-monitor/releases/latest/download/appcast.xml"
    let configured = try bundle(named: "Valid.app", key: key, feed: feed)
    #expect(ApplicationUpdates.isConfigured(in: configured))
    #expect(!ApplicationUpdates.configured(in: configured, isPreview: true).isAvailable)
    #expect(!ApplicationUpdates.isConfigured(in: try bundle(named: "Missing.app", key: "", feed: feed)))
    #expect(!ApplicationUpdates.isConfigured(in: try bundle(named: "HTTP.app", key: key,
      feed: "http://github.com/feed.xml")))
    #expect(!ApplicationUpdates.isConfigured(in: try bundle(named: "Command.bundle", key: key, feed: feed)))
  }
}
