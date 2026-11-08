import Combine
import Foundation
import StrataSystem

@MainActor final class AccessoryBatteryController: ObservableObject {
  @Published private(set) var report: AccessoryBatteryReport?
  @Published private(set) var isReading = false
  @Published private(set) var isCanceling = false
  @Published private(set) var errorMessage: String?
  @Published private(set) var isAvailable = false
  private let reader: any AccessoryBatteryReading
  private var isVisible = false
  private var operationID = UUID()
  private var task: Task<Void, Never>?
  init(reader: any AccessoryBatteryReading = AccessoryBatteryReader()) { self.reader = reader }
  var canRead: Bool { isVisible && isAvailable && !isReading }
  func setVisible(_ visible: Bool) {
    isVisible = visible
    if !visible { cancel() }
  }
  func update(_ snapshot: BluetoothSnapshot?, blockedByConnection: Bool) {
    isAvailable =
      snapshot?.access == .allowed && snapshot?.powered == true
      && snapshot?.issue == nil && !blockedByConnection
    if !isAvailable { cancel() }
    if let snapshot, snapshot.access != .allowed || snapshot.powered == false { report = nil }
  }
  func read() {
    guard canRead else { return }
    let identifier = UUID()
    operationID = identifier
    isReading = true
    errorMessage = nil
    report = nil
    let reader = reader
    task = Task { [weak self] in
      defer { self?.finish(identifier) }
      do {
        try Task.checkCancellation()
        let next = try await reader.read()
        try Task.checkCancellation()
        guard self?.operationID == identifier else { return }
        self?.report = next
      } catch {
        guard !Task.isCancelled, self?.operationID == identifier else { return }
        self?.errorMessage = error.localizedDescription
      }
    }
  }
  func cancel() {
    if task != nil { isCanceling = true }
    task?.cancel()
    errorMessage = nil
  }
  func stop() {
    isVisible = false
    isAvailable = false
    cancel()
    report = nil
  }
  func dismissError() { errorMessage = nil }
  private func finish(_ identifier: UUID) {
    guard operationID == identifier else { return }
    isReading = false
    isCanceling = false
    task = nil
  }
  isolated deinit { task?.cancel() }
}
