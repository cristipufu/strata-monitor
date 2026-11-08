import Foundation

public actor WiFiService: WiFiNetworking {
  private struct Group: Hashable {
    let ssid: Data?
    let name: String?
    let security: Set<WiFiSecurityMode>
    let adHoc: Bool
  }
  private let backend: any WiFiBackend
  private let uptime: @Sendable () -> TimeInterval
  private var scanID: UUID?
  private var scannedAt: TimeInterval?
  private var candidates: [UUID: WiFiScanCandidate] = [:]
  public init() {
    backend = NativeWiFiBackend()
    uptime = { ProcessInfo.processInfo.systemUptime }
  }
  init(
    backend: any WiFiBackend,
    uptime: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
  ) {
    self.backend = backend
    self.uptime = uptime
  }
  public func scan(requestID: UUID) throws -> WiFiScanReport {
    try Task.checkCancellation()
    scanID = requestID
    scannedAt = nil
    candidates = [:]
    let observed = try backend.scan()
    try Task.checkCancellation()
    var groups: [Group: WiFiScanCandidate] = [:]
    for candidate in observed where candidate.presentation != nil {
      let group = Group(
        ssid: candidate.ssid, name: candidate.name, security: candidate.securityModes,
        adHoc: candidate.adHoc)
      if let previous = groups[group], previous.rssi >= candidate.rssi { continue }
      groups[group] = candidate
    }
    candidates = Dictionary(uniqueKeysWithValues: groups.values.map { ($0.id, $0) })
    let observationUptime = uptime()
    scannedAt = observationUptime
    let networks = candidates.values.compactMap(\.presentation).sorted {
      if $0.rssi != $1.rssi { return $0.rssi > $1.rssi }
      if $0.name != $1.name {
        return $0.name.localizedStandardCompare($1.name) == .orderedAscending
      }
      return $0.securityLabel < $1.securityLabel
    }
    return WiFiScanReport(
      id: requestID, networks: networks,
      unavailableNames: observed.filter { $0.presentation == nil }.count,
      observationUptime: observationUptime)
  }
  public func join(networkID: UUID, scanID: UUID) throws {
    try Task.checkCancellation()
    let now = uptime()
    guard self.scanID == scanID, let scannedAt,
      WiFiScanPolicy.isCurrent(observationUptime: scannedAt, now: now),
      let candidate = candidates[networkID]
    else {
      throw DeviceError.unavailable(
        String(localized: "This network selection expired. Refresh nearby networks before joining."))
    }
    switch candidate.joinCapability {
    case .unprotectedNetwork: break
    case .systemSettings(let restriction):
      throw DeviceError.unavailable(restriction.explanation)
    }
    try Task.checkCancellation()
    try backend.join(candidate)
  }
  public func discard(scanID: UUID) {
    guard self.scanID == scanID else { return }
    self.scanID = nil
    scannedAt = nil
    candidates = [:]
  }
}
