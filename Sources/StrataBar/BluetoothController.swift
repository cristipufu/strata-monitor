import Combine
import Foundation
import StrataSystem

enum BluetoothDemand: Hashable { case page, indicator }

@MainActor final class BluetoothController: ObservableObject {
  @Published private(set) var snapshot: BluetoothSnapshot? {
    didSet { updateBatteryAvailability() }
  }
  @Published private(set) var busyDeviceID: String? {
    didSet { updateBatteryAvailability() }
  }
  @Published private(set) var errorMessage: String?
  let batteries: AccessoryBatteryController
  private var batteryChanges: AnyCancellable?
  private let service: any BluetoothManaging
  private let observationInterval: Duration
  private let accessRequest: any BluetoothAccessRequesting
  private var demands: Set<BluetoothDemand> = []
  private var isRunning = false
  private var observationTask: Task<Void, Never>?
  private var operationTask: Task<Void, Never>?
  private var operationID = UUID()
  init(
    service: any BluetoothManaging = BluetoothCollector(),
    observationInterval: Duration = .seconds(6),
    accessRequest: any BluetoothAccessRequesting = BluetoothAccessRequest(),
    batteryReader: any AccessoryBatteryReading = AccessoryBatteryReader()
  ) {
    self.service = service
    self.observationInterval = observationInterval
    self.accessRequest = accessRequest
    batteries = AccessoryBatteryController(reader: batteryReader)
    batteryChanges = batteries.objectWillChange.sink { [weak self] in self?.objectWillChange.send()
    }
  }
  func setDemand(_ demand: BluetoothDemand, active: Bool) {
    let previous = demands
    if active { demands.insert(demand) } else { demands.remove(demand) }
    if !demands.contains(.page) { accessRequest.stop() }
    batteries.setVisible(isRunning && demands.contains(.page))
    if previous != demands { restartObservation() }
  }
  func start() {
    guard !isRunning else { return }
    isRunning = true
    batteries.setVisible(demands.contains(.page))
    restartObservation()
  }
  func stop() {
    isRunning = false
    batteries.stop()
    accessRequest.stop()
    operationID = UUID()
    observationTask?.cancel()
    observationTask = nil
    operationTask?.cancel()
    operationTask = nil
    busyDeviceID = nil
    snapshot = nil
    errorMessage = nil
  }
  func refresh() { restartObservation() }
  func requestAccess() {
    guard isRunning, demands.contains(.page), snapshot?.access == .notDetermined else { return }
    accessRequest.request { [weak self] in
      guard let self, self.isRunning, self.demands.contains(.page) else { return }
      self.refresh()
    }
  }
  func dismissError() { errorMessage = nil }
  func setConnected(_ connected: Bool, deviceID: String) {
    guard isRunning, demands.contains(.page), busyDeviceID == nil, !batteries.isReading,
      snapshot?.access == .allowed, snapshot?.powered == true,
      snapshot?.issue == nil,
      snapshot?.devices.contains(where: { $0.id == deviceID }) == true
    else { return }
    observationTask?.cancel()
    observationTask = nil
    errorMessage = nil
    busyDeviceID = deviceID
    let identifier = UUID()
    operationID = identifier
    let service = service
    operationTask = Task { [weak self] in
      defer { self?.finishOperation(identifier) }
      do {
        try Task.checkCancellation()
        try await service.setConnected(connected, deviceID: deviceID)
      } catch {
        guard !Task.isCancelled else { return }
        self?.errorMessage = error.localizedDescription
      }
    }
  }
  private func finishOperation(_ identifier: UUID) {
    guard operationID == identifier else { return }
    busyDeviceID = nil
    operationTask = nil
    restartObservation()
  }
  private func updateBatteryAvailability() {
    batteries.update(snapshot, blockedByConnection: !isRunning || busyDeviceID != nil)
  }
  private func restartObservation() {
    observationTask?.cancel()
    observationTask = nil
    guard isRunning, !demands.isEmpty else {
      if snapshot != nil { snapshot = nil }
      return
    }
    guard busyDeviceID == nil else { return }
    let service = service
    let interval = observationInterval
    observationTask = Task { [weak self] in
      while !Task.isCancelled && self != nil {
        let next = await service.snapshot()
        guard !Task.isCancelled else { return }
        self?.snapshot = next
        do { try await Task.sleep(for: interval) } catch { return }
      }
    }
  }
  isolated deinit {
    batteries.stop()
    observationTask?.cancel()
    operationTask?.cancel()
    accessRequest.stop()
  }
}
