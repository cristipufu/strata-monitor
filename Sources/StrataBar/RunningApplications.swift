import AppKit
import Combine

// The pids of regular applications, kept current from workspace launch and quit notices instead
// of being listed again on every view update.
@MainActor final class RunningApplications: ObservableObject {
  @Published private(set) var processIdentifiers: Set<Int32> = []
  private var subscriptions: Set<AnyCancellable> = []

  init(workspace: NSWorkspace = .shared) {
    refresh(workspace)
    let center = workspace.notificationCenter
    for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
      center.publisher(for: name).receive(on: DispatchQueue.main)
        .sink { [weak self] _ in MainActor.assumeIsolated { self?.refresh(workspace) } }
        .store(in: &subscriptions)
    }
  }

  private func refresh(_ workspace: NSWorkspace) {
    let pids = Set(
      workspace.runningApplications.filter { $0.activationPolicy == .regular }.map(\.processIdentifier))
    if pids != processIdentifiers { processIdentifiers = pids }
  }
}
