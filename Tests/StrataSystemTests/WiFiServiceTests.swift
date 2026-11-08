import Foundation
import Synchronization
import Testing

@testable import StrataSystem

private func wifiCandidate(
  name: String? = "Cafe", ssid: Data? = Data("Cafe".utf8), bssid: String? = "00:11:22:33:44:55",
  rssi: Int = -45, security: Set<WiFiSecurityMode> = [.none], administrator: Bool? = false,
  adHoc: Bool = false
) -> WiFiScanCandidate {
  WiFiScanCandidate(
    id: UUID(), interfaceName: "en0", name: name, ssid: ssid, bssid: bssid,
    rssi: rssi, securityModes: security, administratorRequired: administrator, adHoc: adHoc)
}
private final class WiFiBackendFixture: WiFiBackend, Sendable {
  struct State: Sendable {
    var candidates = [wifiCandidate()]
    var joinedIDs: [UUID] = []
    var failsScan = false
    var now: TimeInterval = 10
  }
  private let state = Mutex(State())
  func configure(_ change: (inout State) -> Void) { state.withLock { change(&$0) } }
  func read() -> State { state.withLock { $0 } }
  func scan() throws -> [WiFiScanCandidate] {
    try state.withLock {
      if $0.failsScan { throw DeviceError.unavailable("Fixture scan failed") }
      return $0.candidates
    }
  }
  func join(_ candidate: WiFiScanCandidate) { state.withLock { $0.joinedIDs.append(candidate.id) } }
}

@Test func wifiScanSeparatesSecurityAndRawSSIDWhileChoosingTheStrongestCompatibleResult()
  async throws
{
  let backend = WiFiBackendFixture()
  backend.configure {
    $0.candidates = [
      wifiCandidate(rssi: -70), wifiCandidate(rssi: -30),
      wifiCandidate(security: [.wpa2Personal]), wifiCandidate(ssid: Data("Other bytes".utf8)),
      wifiCandidate(name: nil),
    ]
  }
  let scanner = WiFiService(backend: backend)
  let request = UUID()
  let report = try await scanner.scan(requestID: request)
  #expect(report.id == request && report.networks.count == 3 && report.unavailableNames == 1)
  #expect(report.networks.first?.rssi == -30)
  #expect(report.networks.filter { $0.isProtected == true }.count == 1)
  #expect(report.networks.allSatisfy { $0.name == "Cafe" })
}

@Test(arguments: WiFiSecurityMode.allCases.filter { $0 != .none })
func wifiProtectedUnknownAndTransitionSecurityCannotBecomeADirectOpenJoin(
  _ security: WiFiSecurityMode
) {
  #expect(!wifiCandidate(security: [security]).joinCapability.permitsDirectJoin)
  #expect(!wifiCandidate(security: [.none, security]).joinCapability.permitsDirectJoin)
}

@Test func wifiOpenJoinRequiresAVisibleIdentityAndOrdinaryInfrastructurePolicy() {
  #expect(wifiCandidate().joinCapability.permitsDirectJoin)
  let unavailable = [
    wifiCandidate(ssid: nil), wifiCandidate(ssid: Data()),
    wifiCandidate(ssid: Data(repeating: 1, count: 33)), wifiCandidate(bssid: nil),
    wifiCandidate(administrator: true), wifiCandidate(administrator: nil),
    wifiCandidate(adHoc: true),
    wifiCandidate(security: []),
  ]
  #expect(unavailable.allSatisfy { !$0.joinCapability.permitsDirectJoin })
  #expect(wifiCandidate(security: []).presentation?.isProtected == nil)
  #expect(wifiCandidate(security: [.unknown]).presentation?.isProtected == nil)
  #expect(wifiCandidate(security: [.oweTransition]).presentation?.isProtected == nil)
  #expect(wifiCandidate(security: [.none, .wpa2Personal]).presentation?.isProtected == nil)
}

@Test func wifiScanLeasesRejectExpiryReplacedResultsAndObsoleteCleanup() async throws {
  let backend = WiFiBackendFixture()
  let scanner = WiFiService(backend: backend, uptime: { backend.read().now })
  let first = try await scanner.scan(requestID: UUID())
  let firstID = try #require(first.networks.first?.id)
  backend.configure { $0.now = 71 }
  do {
    try await scanner.join(networkID: firstID, scanID: first.id)
    Issue.record("Expired scans must not join")
  } catch { #expect(error is DeviceError) }
  let second = try await scanner.scan(requestID: UUID())
  await scanner.discard(scanID: first.id)
  let secondID = try #require(second.networks.first?.id)
  try await scanner.join(networkID: secondID, scanID: second.id)
  do {
    try await scanner.join(networkID: firstID, scanID: first.id)
    Issue.record("Old scan IDs must not join")
  } catch { #expect(error is DeviceError) }
  await scanner.discard(scanID: second.id)
  do {
    try await scanner.join(networkID: secondID, scanID: second.id)
    Issue.record("Discarded scans must not join")
  } catch { #expect(error is DeviceError) }
  #expect(backend.read().joinedIDs == [secondID])
}

@Test func wifiFailedOrCanceledScanCannotReuseAnOlderSelection() async throws {
  let backend = WiFiBackendFixture()
  let scanner = WiFiService(backend: backend)
  let old = try await scanner.scan(requestID: UUID())
  backend.configure { $0.failsScan = true }
  do {
    _ = try await scanner.scan(requestID: UUID())
    Issue.record("A failed scan must be reported")
  } catch { #expect(error is DeviceError) }
  let oldID = try #require(old.networks.first?.id)
  do {
    try await scanner.join(networkID: oldID, scanID: old.id)
    Issue.record("A failed replacement invalidates old results")
  } catch { #expect(error is DeviceError) }
  let canceled = Task {
    withUnsafeCurrentTask { $0?.cancel() }
    try await scanner.join(networkID: oldID, scanID: old.id)
  }
  do {
    try await canceled.value
    Issue.record("Canceled joins must not reach the backend")
  } catch { #expect(error is CancellationError) }
  #expect(backend.read().joinedIDs.isEmpty)
}

@Test func wifiUnsupportedNetworkSelectionsCannotBypassTheServicePolicy() async throws {
  for candidate in [
    wifiCandidate(security: [.wpa2Personal]), wifiCandidate(security: [.owe]),
    wifiCandidate(administrator: true), wifiCandidate(bssid: nil),
  ] {
    let backend = WiFiBackendFixture()
    backend.configure { $0.candidates = [candidate] }
    let service = WiFiService(backend: backend)
    let report = try await service.scan(requestID: UUID())
    do {
      try await service.join(networkID: candidate.id, scanID: report.id)
      Issue.record("Unsupported selections must not reach association")
    } catch { #expect(error is DeviceError) }
    #expect(backend.read().joinedIDs.isEmpty)
  }
}

@Test(arguments: [9.0, Double.nan, Double.infinity])
func wifiBackwardsOrUnusableClocksCannotAuthorizeAnOldResult(_ now: Double) async throws {
  let backend = WiFiBackendFixture()
  let service = WiFiService(backend: backend, uptime: { backend.read().now })
  let report = try await service.scan(requestID: UUID())
  let network = try #require(report.networks.first?.id)
  backend.configure { $0.now = now }
  do {
    try await service.join(networkID: network, scanID: report.id)
    Issue.record("An unusable clock must not authorize a selection")
  } catch { #expect(error is DeviceError) }
  #expect(backend.read().joinedIDs.isEmpty)
}
