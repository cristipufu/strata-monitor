import AppKit
import Combine
import StrataCore
import StrataSystem
import UniformTypeIdentifiers

@MainActor
final class SnapshotExportController: ObservableObject {
  @Published private(set) var isBusy = false
  private let writer = SnapshotWriter()
  private var panel: NSSavePanel?
  private var task: Task<Void, Never>?
  private var request: UUID?

  func present(
    _ snapshot: InspectionExport, in window: NSWindow?, reportError: @escaping (String) -> Void
  ) {
    guard !isBusy, let window, window.isVisible else { return }
    let request = UUID()
    self.request = request
    isBusy = true
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.json]
    panel.nameFieldStringValue = "Strata Monitor \(snapshot.scope.rawValue).json"
    panel.prompt = "Export"
    self.panel = panel
    panel.beginSheetModal(for: window) { [weak self, weak panel] response in
      guard let self, self.request == request else { return }
      let destination = panel?.url
      self.panel = nil
      guard response == .OK, let url = destination else {
        self.finish(request)
        return
      }
      self.task = Task { [weak self] in
        guard let self else { return }
        defer { self.finish(request) }
        do { try await self.writer.write(snapshot, to: url) } catch is CancellationError {} catch {
          if !Task.isCancelled { reportError(error.localizedDescription) }
        }
      }
    }
  }
  func stop() {
    request = nil
    panel?.cancel(nil)
    panel = nil
    task?.cancel()
    task = nil
    isBusy = false
  }
  private func finish(_ request: UUID) {
    guard self.request == request else { return }
    self.request = nil
    task = nil
    isBusy = false
  }
}
