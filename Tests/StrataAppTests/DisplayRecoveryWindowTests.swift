import AppKit
import XCTest

@testable import StrataBar
@testable import StrataSystem

@MainActor private final class HeadlessRecoveryWindow: DisplayRecoveryHosting {
  var isVisible = false
  var title = ""
  var placements = 0
  var shouldClose: @MainActor () -> Bool = { true }
  func show() { isVisible = true }
  func hide() { isVisible = false }
  func placeOnVisibleDisplay() { placements += 1 }
  func requestClose() { if shouldClose() { hide() } }
  func stop() { hide() }
}

final class DisplayRecoveryWindowTests: CocoaTestCase {
  @MainActor func testRecoveryPresentationSurvivesPageClosureAndClosingRequestsRevert() throws {
    let service = GatedDisplays()
    let controller = DisplayController(service: service)
    var activations = 0
    let window = HeadlessRecoveryWindow()
    let presentation = DisplayRecoveryWindow(
      controller: controller,
      makeWindow: { _, shouldClose in
        window.shouldClose = shouldClose
        return window
      },
      activateApplication: { activations += 1 })
    defer { presentation.stop() }
    let operation = Task {
      controller.setVisible(true)
      await waitForAsync { await service.reads == 1 }
      await service.finishCatalog(1)
      await waitForAsync { controller.canPreview }
      controller.preview(.mode(service.identity, service.mode))
      await waitForAsync { await service.previews == 1 }
      await service.finishPreview()
    }
    defer { operation.cancel() }
    waitFor { presentation.visibleWindow != nil }
    XCTAssertNotNil(presentation.visibleWindow)
    XCTAssertTrue(window.title == "Keep Display Settings")
    controller.setVisible(false)
    XCTAssertTrue(window.isVisible && activations == 1)
    NotificationCenter.default.post(
      name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
    XCTAssertEqual(window.placements, 2)
    window.requestClose()
    waitFor { presentation.visibleWindow == nil }
    XCTAssertTrue(controller.trial == nil)
  }
  @MainActor private func waitFor(_ condition: () -> Bool) {
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(3)
    while !condition(), clock.now < deadline {
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
    }
    XCTAssertTrue(condition())
  }
  @MainActor private func waitForAsync(_ condition: () async -> Bool) async {
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(3)
    while !(await condition()), clock.now < deadline, !Task.isCancelled {
      try? await Task.sleep(for: .milliseconds(5))
    }
    let result = await condition()
    XCTAssertTrue(result)
  }
}
