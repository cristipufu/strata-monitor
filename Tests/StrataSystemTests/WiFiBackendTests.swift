import Foundation
import Testing

@testable import StrataSystem

private final class AccessPointFixture: WiFiAccessPoint, Sendable {
  let name: String? = "Cafe"
  let ssid: Data?
  let bssid: String?
  let rssi = -45
  let securityModes: Set<WiFiSecurityMode>
  let adHoc: Bool
  init(
    ssid: Data? = Data("Cafe".utf8), bssid: String? = "00:11:22:33:44:55",
    security: Set<WiFiSecurityMode> = [.none], adHoc: Bool = false
  ) {
    self.ssid = ssid
    self.bssid = bssid
    securityModes = security
    self.adHoc = adHoc
  }
}
private final class WiFiInterfaceFixture: WiFiInterfaceHandle, @unchecked Sendable {
  enum Outcome { case selected, wrongSSID, protected, failure }
  struct State {
    var name: String? = "en0"
    var powered = true
    var administrator: Bool? = false
    var points: [AccessPointFixture] = [AccessPointFixture()]
    var scannedSSIDs: [Data?] = []
    var associations = 0
    var associatedSSID: Data?
    var unprotected = true
    var outcome: Outcome = .selected
    var requireAdministratorAfterScan = false
    var cancelDuringFilteredScan = false
  }
  private let lock = NSLock()
  private var state = State()
  func configure(_ change: (inout State) -> Void) { lock.withLock { change(&state) } }
  func read() -> State { lock.withLock { state } }
  var name: String? { read().name }
  var powered: Bool { read().powered }
  var administratorRequired: Bool? { read().administrator }
  var associatedSSID: Data? { read().associatedSSID }
  var associatedWithUnprotectedNetwork: Bool { read().unprotected }
  func scan(ssid: Data?) -> [any WiFiAccessPoint] {
    let observed = lock.withLock {
      state.scannedSSIDs.append(ssid)
      if ssid != nil && state.requireAdministratorAfterScan { state.administrator = true }
      return state
    }
    if ssid != nil && observed.cancelDuringFilteredScan { withUnsafeCurrentTask { $0?.cancel() } }
    return observed.points
  }
  func associate(_ network: any WiFiAccessPoint) throws {
    let ssid = network.ssid
    try lock.withLock {
      state.associations += 1
      switch state.outcome {
      case .selected: state.associatedSSID = ssid
      case .wrongSSID: state.associatedSSID = Data("Other".utf8)
      case .protected:
        state.associatedSSID = ssid
        state.unprotected = false
      case .failure: throw DeviceError.unavailable("Fixture association failed")
      }
    }
  }
}
private final class WiFiDirectoryFixture: WiFiInterfaceFinding, @unchecked Sendable {
  let handle = WiFiInterfaceFixture()
  private let lock = NSLock()
  private var requested: [String?] = []
  var names: [String?] { lock.withLock { requested } }
  func interface(named name: String?) -> (any WiFiInterfaceHandle)? {
    lock.withLock { requested.append(name) }
    return handle
  }
}

@Test func wifiAssociationBindsTheObservedInterfaceAndRevalidatesTheAccessPoint() throws {
  let directory = WiFiDirectoryFixture()
  let backend = NativeWiFiBackend(interfaces: directory)
  let original = try #require(backend.scan().first)
  try backend.join(original)
  #expect(directory.names == [nil, "en0"])
  #expect(directory.handle.read().scannedSSIDs == [nil, Data("Cafe".utf8)])
  #expect(directory.handle.read().associations == 1)
}

private enum AccessPointChange: CaseIterable {
  case missing, sameNameOtherAccessPoint, security, rawSSID, adHoc
}
@Test(arguments: AccessPointChange.allCases)
private func wifiChangedAccessPointsCannotReachAssociation(_ change: AccessPointChange) throws {
  let directory = WiFiDirectoryFixture()
  let backend = NativeWiFiBackend(interfaces: directory)
  let original = try #require(backend.scan().first)
  directory.handle.configure {
    switch change {
    case .missing: $0.points = []
    case .sameNameOtherAccessPoint: $0.points = [AccessPointFixture(bssid: "00:11:22:33:44:66")]
    case .security: $0.points = [AccessPointFixture(security: [.wpa2Personal])]
    case .rawSSID: $0.points = [AccessPointFixture(ssid: Data("Different bytes".utf8))]
    case .adHoc: $0.points = [AccessPointFixture(adHoc: true)]
    }
  }
  #expect(throws: DeviceError.self) { try backend.join(original) }
  #expect(directory.handle.read().associations == 0)
}

@Test func wifiAdministrativePolicyAndAdapterChangesPreventAssociation() throws {
  let directory = WiFiDirectoryFixture()
  let backend = NativeWiFiBackend(interfaces: directory)
  let original = try #require(backend.scan().first)
  directory.handle.configure { $0.administrator = true }
  #expect(throws: DeviceError.self) { try backend.join(original) }
  directory.handle.configure { $0.administrator = nil }
  #expect(throws: DeviceError.self) { try backend.join(original) }
  directory.handle.configure {
    $0.administrator = false
    $0.name = "en7"
  }
  #expect(throws: DeviceError.self) { try backend.join(original) }
  directory.handle.configure {
    $0.name = "en0"
    $0.powered = false
  }
  #expect(throws: DeviceError.self) { try backend.join(original) }
  #expect(
    directory.handle.read().associations == 0 && directory.handle.read().scannedSSIDs.count == 1)
}

@Test func wifiRechecksAdministrativePolicyAfterTheFreshScan() throws {
  let directory = WiFiDirectoryFixture()
  let backend = NativeWiFiBackend(interfaces: directory)
  let original = try #require(backend.scan().first)
  directory.handle.configure { $0.requireAdministratorAfterScan = true }
  #expect(throws: DeviceError.self) { try backend.join(original) }
  #expect(directory.handle.read().associations == 0)
}

@Test func wifiCancellationDuringRevalidationPreventsAConnection() async throws {
  let directory = WiFiDirectoryFixture()
  let backend = NativeWiFiBackend(interfaces: directory)
  let original = try #require(backend.scan().first)
  directory.handle.configure { $0.cancelDuringFilteredScan = true }
  let request = Task { try backend.join(original) }
  do {
    try await request.value
    Issue.record("Canceled revalidation must not associate")
  } catch { #expect(error is CancellationError) }
  #expect(directory.handle.read().associations == 0)
}

@Test func wifiAssociationFailureOrUnexpectedFinalStateDoesNotPretendSuccessOrRetry() throws {
  for outcome in [WiFiInterfaceFixture.Outcome.failure, .wrongSSID, .protected] {
    let directory = WiFiDirectoryFixture()
    let backend = NativeWiFiBackend(interfaces: directory)
    let original = try #require(backend.scan().first)
    directory.handle.configure { $0.outcome = outcome }
    #expect(throws: DeviceError.self) { try backend.join(original) }
    #expect(directory.handle.read().associations == 1)
  }
}
