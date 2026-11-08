import Combine
import Foundation
import StrataSystem

@MainActor final class WiFiController: ObservableObject {
  @Published private(set) var report: WiFiScanReport?
  @Published private(set) var isScanning = false
  @Published private(set) var joiningNetworkID: UUID?
  @Published private(set) var joiningNetworkName: String?
  @Published private(set) var errorMessage: String?
  @Published private(set) var connectionAttemptFinished: UUID?
  private let service: any WiFiNetworking
  private let uptime: @MainActor () -> TimeInterval
  private var isRunning = false
  private var isVisible = false
  private var scanID: UUID?
  private var operationID = UUID()
  private var scanTask: Task<Void, Never>?
  private var joinTask: Task<Void, Never>?
  init(
    service: any WiFiNetworking = WiFiService(),
    uptime: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
  ) {
    self.service = service
    self.uptime = uptime
  }
  var hasCurrentResults: Bool { report?.isCurrent(at: uptime()) == true }
  func start() { isRunning = true }
  func setVisible(_ visible: Bool) {
    guard isVisible != visible else { return }
    isVisible = visible
    if visible && report != nil && !hasCurrentResults { discardScan() }
    if !visible && isScanning { cancelScan() }
  }
  func scan() {
    guard isRunning, isVisible, !isScanning, joiningNetworkID == nil else { return }
    discardScan()
    let identifier = UUID()
    scanID = identifier
    isScanning = true
    errorMessage = nil
    let service = service
    scanTask = Task { [weak self] in
      defer { self?.finishScan(identifier) }
      do {
        try Task.checkCancellation()
        let next = try await service.scan(requestID: identifier)
        try Task.checkCancellation()
        guard self?.scanID == identifier, self?.isVisible == true else { return }
        self?.report = next
      } catch {
        guard !Task.isCancelled, self?.scanID == identifier else { return }
        self?.errorMessage = error.localizedDescription
      }
    }
  }
  func cancelScan() {
    scanTask?.cancel()
    scanTask = nil
    isScanning = false
    report = nil
    if joiningNetworkID == nil { discardScan() }
  }
  func join(_ networkID: UUID) {
    guard isRunning, isVisible, !isScanning, joiningNetworkID == nil,
      hasCurrentResults, let report, report.id == scanID,
      let network = report.networks.first(where: { $0.id == networkID }),
      network.joinCapability.permitsDirectJoin
    else { return }
    joiningNetworkID = networkID
    joiningNetworkName = network.name
    errorMessage = nil
    let identifier = UUID()
    operationID = identifier
    let service = service
    let selectedScanID = report.id
    joinTask = Task { [weak self] in
      defer { self?.finishJoin(identifier) }
      do {
        try Task.checkCancellation()
        try await service.join(networkID: networkID, scanID: selectedScanID)
      } catch {
        guard !Task.isCancelled else { return }
        self?.errorMessage = error.localizedDescription
      }
    }
  }
  func dismissError() { errorMessage = nil }
  func stop() {
    isRunning = false
    operationID = UUID()
    joinTask?.cancel()
    joinTask = nil
    joiningNetworkID = nil
    joiningNetworkName = nil
    cancelScan()
    errorMessage = nil
    connectionAttemptFinished = nil
  }
  private func finishScan(_ identifier: UUID) {
    guard scanID == identifier else { return }
    scanTask = nil
    isScanning = false
  }
  private func finishJoin(_ identifier: UUID) {
    guard operationID == identifier else { return }
    joiningNetworkID = nil
    joiningNetworkName = nil
    joinTask = nil
    if isRunning && !Task.isCancelled { connectionAttemptFinished = identifier }
    if !isVisible { discardScan() }
  }
  private func discardScan() {
    guard let identifier = scanID else { return }
    scanID = nil
    report = nil
    let service = service
    Task { await service.discard(scanID: identifier) }
  }
  isolated deinit {
    scanTask?.cancel()
    joinTask?.cancel()
    if let identifier = scanID {
      let service = service
      Task { await service.discard(scanID: identifier) }
    }
  }
}
