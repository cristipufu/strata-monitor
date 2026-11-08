import Foundation
import XCTest

/// Native AppKit interactions need XCTest's Cocoa run-loop host. Record their
/// boundaries separately so an early successful process exit cannot pass CI.
class CocoaTestCase: XCTestCase {
  private static let events = CocoaTestEvents()
  override func setUp() {
    super.setUp()
    Self.events.record("testStarted", name: name)
  }
  override func tearDown() {
    Self.events.record("testEnded", name: name)
    super.tearDown()
  }
}

private final class CocoaTestEvents: @unchecked Sendable {
  private let lock = NSLock()
  func record(_ kind: String, name: String) {
    guard let path = ProcessInfo.processInfo.environment["STRATA_XCTEST_EVENTS_PATH"] else {
      return
    }
    lock.lock()
    defer { lock.unlock() }
    do {
      var data = try JSONSerialization.data(withJSONObject: [
        "kind": "nativeEvent", "payload": ["kind": kind, "testID": name],
      ])
      data.append(10)
      let file = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
      defer { try? file.close() }
      try file.seekToEnd()
      try file.write(contentsOf: data)
    } catch { XCTFail("Could not record native test execution: \(error.localizedDescription)") }
  }
}
