import AppKit
import Foundation
import Testing

@testable import StrataBar

@MainActor private final class VisibleTestWindow: NSWindow {
  override var isVisible: Bool { true }
}

@MainActor private final class RecordingAlert: NSAlert {
  var presentations = 0
  var completion: ((NSApplication.ModalResponse) -> Void)?
  override func beginSheetModal(
    for sheetWindow: NSWindow,
    completionHandler handler: ((NSApplication.ModalResponse) -> Void)? = nil
  ) {
    presentations += 1
    completion = handler
  }
}

@Test @MainActor func oneOperationOwnerCoalescesErrorsIntoOneAlert() async throws {
  _ = NSApplication.shared
  let model = AppModel(defaults: try #require(UserDefaults(suiteName: "StrataBar.Tests.\(UUID())")))
  let window = VisibleTestWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
  let alert = RecordingAlert()
  let presenter = OperationErrorPresenter(model: model, owner: { window }, makeAlert: { alert })
  model.errorMessage = "First failure"
  try await waitUntil { alert.presentations == 1 }
  model.errorMessage = "Latest failure"
  try await waitUntil { alert.informativeText == "Latest failure" }
  #expect(alert.presentations == 1)
  alert.completion?(.alertFirstButtonReturn)
  #expect(model.errorMessage == nil)
  presenter.stop()
}

@Test @MainActor func hiddenOwnersDoNotOpenOrActivateAnErrorWindow() async throws {
  let model = AppModel(defaults: try #require(UserDefaults(suiteName: "StrataBar.Tests.\(UUID())")))
  var created = 0
  let presenter = OperationErrorPresenter(
    model: model, owner: { nil },
    makeAlert: {
      created += 1
      return NSAlert()
    })
  model.errorMessage = "Deferred failure"
  for _ in 0..<10 { await Task.yield() }
  #expect(created == 0 && model.errorMessage == "Deferred failure")
  presenter.stop()
  model.errorMessage = "After teardown"
  for _ in 0..<10 { await Task.yield() }
  #expect(created == 0)
}
