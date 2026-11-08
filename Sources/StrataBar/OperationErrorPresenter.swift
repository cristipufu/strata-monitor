import AppKit
import Combine

/// One presentation owner prevents retained, hidden SwiftUI windows from each
/// opening an alert for the same operation. Errors without a visible key owner
/// remain available in the inline banner instead of activating the app.
@MainActor
final class OperationErrorPresenter {
  private let model: AppModel
  private let owner: @MainActor () -> NSWindow?
  private let makeAlert: @MainActor () -> NSAlert
  private var subscription: AnyCancellable?
  private var alert: NSAlert?
  private var active = true

  init(
    model: AppModel, owner: @escaping @MainActor () -> NSWindow?,
    makeAlert: @escaping @MainActor () -> NSAlert = { NSAlert() }
  ) {
    self.model = model
    self.owner = owner
    self.makeAlert = makeAlert
    subscription = model.$errorMessage.compactMap { $0 }.sink { [weak self] message in
      Task { @MainActor [weak self] in self?.present(message) }
    }
  }
  private func present(_ message: String) {
    guard active else { return }
    if let alert {
      alert.informativeText = message
      return
    }
    guard let window = owner(), window.isVisible else { return }
    let alert = makeAlert()
    alert.messageText = String(localized: "Unable to complete action")
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.addButton(withTitle: String(localized: "OK"))
    self.alert = alert
    alert.beginSheetModal(for: window) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.active else { return }
        self.alert = nil
        self.model.errorMessage = nil
      }
    }
  }
  func stop() {
    active = false
    subscription?.cancel()
    subscription = nil
    if let window = alert?.window, let parent = window.sheetParent {
      parent.endSheet(window, returnCode: .abort)
    }
    alert = nil
  }
}
