import Combine
import Foundation
import StrataCore
import StrataSystem

@MainActor
final class ProcessActionController: ObservableObject {
  @Published private(set) var prepared: ProcessActionConfirmation?
  @Published private(set) var isBusy = false
  @Published private(set) var paused: PausedProcessLedger
  private let service: any ProcessControlling
  private let applicationQuit: any ApplicationQuitting
  private let reportError: @MainActor (String) -> Void
  private let savePaused: @MainActor (PausedProcessLedger) -> Void
  private var task: Task<Void, Never>?
  private var requestID = UUID()

  init(
    service: any ProcessControlling = ProcessControl(),
    applicationQuit: any ApplicationQuitting = ApplicationQuitService(),
    paused: PausedProcessLedger = PausedProcessLedger(),
    savePaused: @escaping @MainActor (PausedProcessLedger) -> Void = { _ in },
    reportError: @escaping @MainActor (String) -> Void
  ) {
    self.service = service
    self.applicationQuit = applicationQuit
    self.paused = paused
    self.savePaused = savePaused
    self.reportError = reportError
  }
  func request(_ process: ProcessSample, signal: ProcessSignal) {
    prepare(performsImmediately: !signal.needsConfirmation) { [service] in
      .signal(try await service.prepare(process, signal: signal))
    }
  }
  // Undoes every pause Strata Monitor made; processes that ended since are simply forgotten.
  func resumePausedProcesses() async {
    for identity in paused.identities {
      do {
        try await service.resumePaused(identity)
        update { $0.forget(identity) }
      } catch ProcessActionError.targetChanged {
        update { $0.forget(identity) }
      } catch {
        reportError(error.localizedDescription)
      }
    }
  }
  private func update(_ change: (inout PausedProcessLedger) -> Void) {
    var ledger = paused
    change(&ledger)
    guard ledger != paused else { return }
    paused = ledger
    savePaused(ledger)
  }
  func canQuitApplication(_ process: ProcessSample) -> Bool { applicationQuit.canQuit(process) }
  func requestApplicationQuit(_ process: ProcessSample) {
    prepare { [applicationQuit] in .applicationQuit(try await applicationQuit.prepare(process)) }
  }
  private func prepare(
    performsImmediately: Bool = false,
    _ operation: @escaping @MainActor () async throws -> ProcessActionConfirmation
  ) {
    stop()
    let identifier = UUID()
    requestID = identifier
    isBusy = true
    task = Task { [weak self] in
      guard let self else { return }
      defer { self.finish(identifier) }
      do {
        let action = try await operation()
        guard !Task.isCancelled else {
          await self.cancel(action)
          return
        }
        if performsImmediately {
          try await self.perform(action)
        } else {
          self.prepared = action
        }
      } catch { if !Task.isCancelled { self.reportError(error.localizedDescription) } }
    }
  }
  private func perform(_ action: ProcessActionConfirmation) async throws {
    switch action {
    case .signal(let action):
      try await service.perform(action)
      update { $0.record(action.signal, for: action.identity) }
    case .applicationQuit(let action): try await applicationQuit.perform(action)
    }
  }
  func confirm() {
    guard let action = prepared else { return }
    prepared = nil
    let identifier = UUID()
    requestID = identifier
    isBusy = true
    task = Task { [weak self] in
      guard let self else { return }
      defer { self.finish(identifier) }
      do {
        try await self.perform(action)
      } catch {
        if !Task.isCancelled { self.reportError(error.localizedDescription) }
      }
    }
  }
  func stop() {
    requestID = UUID()
    task?.cancel()
    task = nil
    if let action = prepared { Task { await cancel(action) } }
    prepared = nil
    isBusy = false
  }
  func dismissConfirmation() {
    guard let action = prepared else { return }
    prepared = nil
    Task { await cancel(action) }
  }
  private func cancel(_ action: ProcessActionConfirmation) async {
    switch action {
    case .signal(let action): await service.cancel(action.id)
    case .applicationQuit(let action): applicationQuit.cancel(action.id)
    }
  }
  private func finish(_ identifier: UUID) {
    guard requestID == identifier else { return }
    isBusy = false
    task = nil
  }
}
