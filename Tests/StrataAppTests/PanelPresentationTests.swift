import AppKit
import StrataCore
import Testing

@testable import StrataBar

@Test @MainActor func reversingAFoldCancelsItsObsoleteWindowDismissal() async throws {
  let window = HeadlessPanel()
  var hides = 0
  let presentation = PanelPresentation(window: window) { hides += 1 }
  presentation.setVisible(true, style: .morph, reducedMotion: true)
  try await waitUntil { presentation.presented }
  presentation.setVisible(false, style: .morph, reducedMotion: true)
  #expect(!presentation.presented && window.isVisible)
  presentation.setVisible(true, style: .fade, reducedMotion: true)
  try await waitUntil { presentation.presented }
  try await Task.sleep(for: .milliseconds(150))
  #expect(window.isVisible && hides == 0 && presentation.style == .fade)
  presentation.setVisible(false, style: .fade, reducedMotion: true)
  try await waitUntil { !window.isVisible }
  #expect(hides == 1)
  presentation.stop()
}

@Test @MainActor func stoppedPanelCannotPublishItsQueuedOpening() async {
  let window = HeadlessPanel()
  let presentation = PanelPresentation(window: window) {
    Issue.record("Stopping is not a completed fold")
  }
  presentation.setVisible(true, style: .morph, reducedMotion: false)
  presentation.stop()
  for _ in 0..<10 { await Task.yield() }
  #expect(!window.isVisible && !presentation.presented)
}

@Test @MainActor func aHiddenPanelReleasesItsContentUntilItOpensAgain() async throws {
  let window = HeadlessPanel()
  let presentation = PanelPresentation(window: window) {}
  #expect(!presentation.hostsContent)
  presentation.setVisible(true, style: .morph, reducedMotion: true)
  #expect(presentation.hostsContent)
  try await waitUntil { presentation.presented }
  presentation.setVisible(false, style: .morph, reducedMotion: true)
  #expect(presentation.hostsContent, "The fold still shows the content fading out")
  try await waitUntil { !window.isVisible }
  #expect(!presentation.hostsContent)
  presentation.setVisible(true, style: .morph, reducedMotion: true)
  #expect(presentation.hostsContent)
  presentation.stop()
  #expect(!presentation.hostsContent)
}
