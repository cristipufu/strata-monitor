import AppKit
import CoreGraphics
import StrataCore

@MainActor final class WorkspaceLifecycleMonitor {
  private let center: NotificationCenter
  private let suspend: @MainActor () -> Void
  private let resume: @MainActor () -> Void
  private var policy: MonitoringAvailability
  private var observers: [NSObjectProtocol] = []
  private var active = true
  init(
    center: NotificationCenter = NSWorkspace.shared.notificationCenter,
    isConsoleSession: Bool = WorkspaceLifecycleMonitor.isConsoleSession,
    suspend: @escaping @MainActor () -> Void, resume: @escaping @MainActor () -> Void
  ) {
    self.center = center
    self.suspend = suspend
    self.resume = resume
    policy = MonitoringAvailability(isConsoleSession: isConsoleSession)
    let events: [(Notification.Name, WorkspaceAvailabilityEvent)] = [
      (NSWorkspace.willSleepNotification, .systemWillSleep),
      (NSWorkspace.didWakeNotification, .systemDidWake),
      (NSWorkspace.screensDidSleepNotification, .screensDidSleep),
      (NSWorkspace.screensDidWakeNotification, .screensDidWake),
      (NSWorkspace.sessionDidResignActiveNotification, .sessionResigned),
      (NSWorkspace.sessionDidBecomeActiveNotification, .sessionBecameActive),
    ]
    for (name, event) in events {
      observers.append(
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
          MainActor.assumeIsolated { self?.receive(event) }
        })
    }
    if !policy.isAvailable { suspend() }
  }
  private static var isConsoleSession: Bool {
    (CGSessionCopyCurrentDictionary() as? [String: Any])?[kCGSessionOnConsoleKey as String] as? Bool
      ?? false
  }
  private func receive(_ event: WorkspaceAvailabilityEvent) {
    guard active else { return }
    switch policy.receive(event) {
    case .suspend: suspend()
    case .resume: resume()
    case nil: break
    }
  }
  func stop() {
    active = false
    for observer in observers { center.removeObserver(observer) }
    observers.removeAll()
  }
  isolated deinit { for observer in observers { center.removeObserver(observer) } }
}
