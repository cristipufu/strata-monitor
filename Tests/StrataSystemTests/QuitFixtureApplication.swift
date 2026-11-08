import AppKit
import CSystem
import Foundation
import StrataCore
import Testing

@testable import StrataSystem

private final class TestBundleAnchor: NSObject {}

@MainActor struct QuitFixtureApplication {
  let application: NSRunningApplication
  let process: ProcessSample
  let directory: URL
  let marker: URL
  private let token: SBActionToken
  static func launch(veto: Bool) async throws -> QuitFixtureApplication {
    _ = NSApplication.shared
    let binary = Bundle(for: TestBundleAnchor.self).bundleURL.deletingLastPathComponent()
      .appendingPathComponent("StrataQuitFixture")
    try #require(FileManager.default.isExecutableFile(atPath: binary.path))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "StrataQuit-\(UUID())", isDirectory: true)
    let bundle = directory.appendingPathComponent("Fixture.app", isDirectory: true)
    let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
    let executables = contents.appendingPathComponent("MacOS", isDirectory: true)
    try FileManager.default.createDirectory(at: executables, withIntermediateDirectories: true)
    do {
      try FileManager.default.copyItem(
        at: binary, to: executables.appendingPathComponent("StrataQuitFixture"))
      let info: [String: Any] = [
        "CFBundleIdentifier": "dev.strata.tests.quit.\(UUID().uuidString.lowercased())",
        "CFBundleExecutable": "StrataQuitFixture",
        "CFBundleName": "Strata Quit Test", "CFBundlePackageType": "APPL", "LSBackgroundOnly": true,
      ]
      try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(
        to: contents.appendingPathComponent("Info.plist"))
      let marker = directory.appendingPathComponent("requested.txt")
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.activates = false
      configuration.addsToRecentItems = false
      configuration.createsNewApplicationInstance = true
      configuration.promptsUserIfNeeded = false
      configuration.arguments = [marker.path] + (veto ? ["--veto"] : [])
      let application = try await NSWorkspace.shared.openApplication(
        at: bundle, configuration: configuration)
      do {
        let sample = await SystemCollector().sample(includeProcesses: true)
        let process = try #require(
          sample.processes.first { $0.id.pid == application.processIdentifier })
        var token = SBActionToken()
        try #require(
          sb_prepare_signal(
            process.id.pid, process.id.startSeconds, process.id.startMicroseconds, &token) == 0)
        return QuitFixtureApplication(
          application: application, process: process, directory: directory, marker: marker,
          token: token)
      } catch {
        application.forceTerminate()
        throw error
      }
    } catch {
      try? FileManager.default.removeItem(at: directory)
      throw error
    }
  }
  func cleanUp() {
    var token = token
    _ = sb_send_signal(&token, SIGKILL)
    try? FileManager.default.removeItem(at: directory)
  }
  func waitForQuitRequest() async throws {
    let clock = ContinuousClock()
    let deadline = ContinuousClock.now + .seconds(4)
    while !FileManager.default.fileExists(atPath: marker.path), clock.now < deadline {
      try await Task.sleep(for: .milliseconds(10))
    }
    try #require(FileManager.default.fileExists(atPath: marker.path))
  }
}
