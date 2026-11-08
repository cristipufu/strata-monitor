import Foundation
import StrataSystem

/// One event refresh may collect at a time. Events during collection request one trailing refresh.
@MainActor final class DeviceEventRefresh {
  private let collector: any DeviceControlling
  private let coalescingDelay: Duration
  private let deliver: @MainActor (DeviceSnapshot) -> Void
  private var revision: UInt64 = 0
  private var task: Task<Void, Never>?
  private var stopped = false
  init(
    collector: any DeviceControlling, coalescingDelay: Duration = .milliseconds(100),
    deliver: @escaping @MainActor (DeviceSnapshot) -> Void
  ) {
    self.collector = collector
    self.coalescingDelay = coalescingDelay
    self.deliver = deliver
  }
  func request() {
    guard !stopped else { return }
    revision &+= 1
    guard task == nil else { return }
    let collector = collector
    let delay = coalescingDelay
    task = Task { [weak self] in
      defer { self?.task = nil }
      while !Task.isCancelled {
        do { try await Task.sleep(for: delay) } catch { return }
        guard let revision = self?.revision else { return }
        let snapshot = await collector.sample()
        guard !Task.isCancelled, self?.stopped == false else { return }
        self?.deliver(snapshot)
        if self?.revision == revision { return }
      }
    }
  }
  func stop() {
    stopped = true
    task?.cancel()
    task = nil
  }
  isolated deinit { task?.cancel() }
}
