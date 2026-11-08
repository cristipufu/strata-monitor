import Foundation
import Testing

@testable import StrataSystem

@Suite struct AccessoryBatteryFlowTests {
  @Test func accessoryBatteryNoCandidatesDoesNotConnectOrInventAnyReadings() throws {
    var scenario = BatteryScenario()
    scenario.start([])
    let report = try #require(scenario.report)
    #expect(report.devices.isEmpty && report.totalCandidates == 0)
    #expect(scenario.connections.isEmpty)
  }

  @Test(arguments: [0, 58, 100]) func accessoryBatteryPercentIsAnExactObservedByte(_ percent: UInt8)
    throws
  {
    var scenario = BatteryScenario()
    scenario.start([scenario.device])
    scenario.connected(services: [UUID()])
    scenario.readLevel(Data([percent]))
    #expect(scenario.report == nil)
    #expect(scenario.flow.phase == .closing)
    scenario.send(.disconnected(scenario.device.id))
    let result = try #require(scenario.report?.devices.first)
    #expect(result.id == scenario.device.id)
    #expect(result.levels.count == 1 && result.levels.first?.percent == Int(percent))
    #expect(result.issue == nil && result.levels.first?.issue == nil)
  }

  @Test(arguments: [nil, Data(), Data([255]), Data([101]), Data([20, 30])])
  func accessoryBatteryMalformedValuesRemainUnavailable(_ bytes: Data?) throws {
    var scenario = BatteryScenario()
    scenario.start([scenario.device])
    scenario.connected(services: [UUID()])
    scenario.readLevel(bytes)
    scenario.send(.disconnected(scenario.device.id))
    let level = try #require(scenario.report?.devices.first?.levels.first)
    #expect(level.percent == nil && level.issue != nil)
  }

  @Test func accessoryBatteryMultipleInstancesRemainSeparateAndPreserveReportedOrder() throws {
    var scenario = BatteryScenario()
    scenario.start([scenario.device])
    scenario.connected(services: [UUID(), UUID()])
    scenario.readLevel(Data([82]))
    scenario.readLevel(Data([19]))
    scenario.send(.disconnected(scenario.device.id))
    let levels = try #require(scenario.report?.devices.first?.levels)
    #expect(levels.map(\.id) == [1, 2])
    #expect(levels.compactMap(\.percent) == [82, 19])
  }

  @Test func accessoryBatterySameNameAccessoriesHaveIndependentIdentities() throws {
    var scenario = BatteryScenario()
    let second = BatteryCandidate(id: UUID(), name: scenario.device.name)
    scenario.start([second, scenario.device])
    for percent in [UInt8(82), UInt8(19)] {
      let current = try #require(scenario.flow.activeDevice)
      scenario.connected(services: [UUID()])
      scenario.readLevel(Data([percent]))
      scenario.send(.disconnected(current))
    }
    let devices = try #require(scenario.report?.devices)
    #expect(Set(devices.map(\.id)) == [scenario.device.id, second.id])
    #expect(devices.map(\.name) == [scenario.device.name, scenario.device.name])
    #expect(devices.compactMap { $0.levels.first?.percent } == [82, 19])
  }

  @Test(arguments: [BatteryRadioState.denied, .off, .unsupported])
  func accessoryBatteryUnavailableRadioNeverConnects(_ state: BatteryRadioState) {
    var scenario = BatteryScenario()
    scenario.send(.begin)
    scenario.send(.radio(state))
    #expect(scenario.failure != nil && scenario.connections.isEmpty)
    #expect(scenario.flow.phase == .finished)
  }

  @Test func accessoryBatteryRevocationAndCancelWaitForOwnedConnectionRelease() throws {
    for event in [BatteryReadEvent.cancel, .radio(.denied), .radio(.off), .radio(.waiting)] {
      var scenario = BatteryScenario()
      scenario.start([scenario.device])
      scenario.send(event)
      #expect(scenario.flow.phase == .closing && scenario.failure == nil)
      scenario.send(.connected(scenario.device.id))
      #expect(scenario.flow.phase == .closing)
      scenario.send(.disconnected(scenario.device.id))
      #expect(scenario.failure != nil && scenario.report == nil)
      #expect(scenario.send(.disconnected(scenario.device.id)).isEmpty)
    }
  }

  @Test func accessoryBatteryUnrelatedAndLateCallbacksCannotSupplyAReading() throws {
    var scenario = BatteryScenario()
    scenario.start([scenario.device])
    #expect(scenario.send(.connected(UUID())).isEmpty)
    scenario.connected(services: [UUID()])
    guard case .characteristics(let service) = scenario.flow.phase else {
      Issue.record("Expected a battery service")
      return
    }
    #expect(scenario.send(.characteristics(scenario.device.id, UUID(), [], nil)).isEmpty)
    let characteristic = UUID()
    scenario.send(
      .characteristics(
        scenario.device.id, service, [BatteryCharacteristic(id: characteristic, readable: true)],
        nil))
    #expect(scenario.send(.value(UUID(), characteristic, Data([99]), nil)).isEmpty)
    #expect(scenario.send(.value(scenario.device.id, UUID(), Data([99]), nil)).isEmpty)
    scenario.send(.value(scenario.device.id, characteristic, Data([33]), nil))
    #expect(scenario.send(.value(scenario.device.id, characteristic, Data([99]), nil)).isEmpty)
    scenario.send(.disconnected(scenario.device.id))
    #expect(scenario.report?.devices.first?.levels.first?.percent == 33)
  }

  @Test func accessoryBatteryUnreadableAndAmbiguousCharacteristicsDoNotChooseAnArbitraryValue()
    throws
  {
    for count in [0, 1, 2] {
      var scenario = BatteryScenario()
      scenario.start([scenario.device])
      let service = UUID()
      scenario.connected(services: [service])
      scenario.send(
        .characteristics(
          scenario.device.id, service,
          (0..<count).map { _ in BatteryCharacteristic(id: UUID(), readable: false) }, nil))
      scenario.send(.disconnected(scenario.device.id))
      #expect(scenario.report?.devices.first?.levels.first?.percent == nil)
      #expect(scenario.report?.devices.first?.levels.first?.issue != nil)
    }
  }

  @Test func accessoryBatteryReadErrorsDoNotEraseOtherBatteryInstances() throws {
    var scenario = BatteryScenario()
    scenario.start([scenario.device])
    scenario.connected(services: [UUID(), UUID()])
    scenario.readLevel(Data([100]), error: "Controlled read failure")
    scenario.readLevel(Data([24]))
    scenario.send(.disconnected(scenario.device.id))
    let levels = try #require(scenario.report?.devices.first?.levels)
    #expect(levels[0].percent == nil && levels[0].issue == "Controlled read failure")
    #expect(levels[1].percent == 24 && levels[1].issue == nil)
  }

  @Test func accessoryBatteryDuplicateDeviceIdentitiesAreRejectedBeforeConnecting() {
    var scenario = BatteryScenario()
    scenario.start([scenario.device, scenario.device])
    #expect(scenario.failure != nil && scenario.connections.isEmpty)
  }

  @Test func accessoryBatteryServiceLimitsAndInvalidationCloseTheOwnedConnection() throws {
    for services in [[], Array(repeating: UUID(), count: 2), (0..<9).map { _ in UUID() }] {
      var scenario = BatteryScenario()
      scenario.start([scenario.device])
      scenario.connected(services: services)
      #expect(scenario.flow.phase == .closing)
      scenario.send(.disconnected(scenario.device.id))
      #expect(scenario.report?.devices.first?.issue != nil)
    }
    var scenario = BatteryScenario()
    scenario.start([scenario.device])
    scenario.connected(services: [UUID()])
    scenario.send(.servicesChanged(scenario.device.id))
    #expect(scenario.flow.phase == .closing)
    scenario.send(.disconnected(scenario.device.id))
    #expect(scenario.report?.devices.first?.levels.isEmpty == true)
    #expect(scenario.report?.devices.first?.issue != nil)
  }

  @Test func accessoryBatteryDeviceBoundIsExplicitInTheReport() throws {
    var scenario = BatteryScenario()
    scenario.start((0..<17).map { BatteryCandidate(id: UUID(), name: "Accessory \($0)") })
    while let id = scenario.flow.activeDevice {
      scenario.send(.connectionFailed(id, "Controlled connection failure"))
      scenario.send(.disconnected(id))
    }
    let report = try #require(scenario.report)
    #expect(scenario.connections.count == 16 && report.devices.count == 16)
    #expect(report.totalCandidates == 17 && report.issue != nil)
  }

  @Test func accessoryBatteryDeadlinesRejectPrematureAndObsoleteTimers() throws {
    var scenario = BatteryScenario()
    scenario.send(.begin)
    let initial = try #require(scenario.flow.watchdogID)
    #expect(scenario.send(.timedOut(initial)).isEmpty)
    scenario.send(.radio(.ready))
    scenario.send(.candidates([scenario.device]))
    #expect(scenario.send(.timedOut(initial), at: 5).isEmpty)
    #expect(scenario.flow.phase == .connecting)
    let timeout = try #require(scenario.flow.watchdogID)
    scenario.send(.timedOut(timeout), at: 8)
    #expect(scenario.flow.phase == .closing && scenario.report == nil)
    scenario.send(.disconnected(scenario.device.id), at: 8.1)
    #expect(scenario.report?.devices.first?.issue != nil)
  }

  @Test func accessoryBatteryLateResponseCannotExtendItsDeadline() throws {
    var scenario = BatteryScenario()
    scenario.start([scenario.device])
    scenario.send(.connected(scenario.device.id), at: 8.1)
    #expect(scenario.flow.phase == .closing)
    #expect(!scenario.commands.contains { if case .discoverServices = $0 { true } else { false } })
  }

  @Test func accessoryBatteryUnconfirmedReleaseStopsFurtherConnections() throws {
    var scenario = BatteryScenario()
    scenario.start([scenario.device, BatteryCandidate(id: UUID(), name: "Other")])
    let id = try #require(scenario.flow.activeDevice)
    scenario.send(.connectionFailed(id, "Controlled failure"))
    let timeout = try #require(scenario.flow.watchdogID)
    scenario.send(.timedOut(timeout), at: 2)
    #expect(scenario.report?.issue != nil)
    #expect(scenario.connections.count == 1)
    #expect(scenario.report?.devices.allSatisfy { $0.levels.isEmpty && $0.issue != nil } == true)
  }

  @Test func accessoryBatteryWholeSessionLimitMarksUnreadDevicesExplicitly() throws {
    var scenario = BatteryScenario()
    scenario.start((0..<16).map { BatteryCandidate(id: UUID(), name: "Accessory \($0)") })
    for index in 1...6 {
      let id = try #require(scenario.flow.activeDevice)
      scenario.send(.connectionFailed(id, "Controlled failure"), at: Double(index * 7))
      scenario.send(.disconnected(id))
    }
    let current = try #require(scenario.flow.activeDevice)
    scenario.send(.connected(current), at: 45)
    #expect(scenario.flow.phase == .closing)
    scenario.send(.disconnected(current))
    #expect(scenario.report?.devices.count == 16 && scenario.report?.issue != nil)
    #expect(scenario.connections.count == 7)
  }

  @Test func accessoryBatteryNativeDeniedSessionCompletesWithoutCreatingARadioManager() async throws
  {
    for _ in 0..<20 {
      let session = NativeAccessoryBatterySession(isAuthorized: { false })
      await #expect(throws: AccessoryBatteryError.self) { try await session.read() }
    }
  }

  @Test func accessoryBatteryAlreadyCanceledNativeRequestDoesNotStart() async throws {
    let operation = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await NativeAccessoryBatterySession(isAuthorized: { false }).read()
    }
    await #expect(throws: CancellationError.self) { try await operation.value }
  }

  @Test func accessoryBatteryRadioTimeoutIsFiniteAndCancelBeforeStartIsTerminal() throws {
    var scenario = BatteryScenario()
    scenario.send(.begin)
    let token = try #require(scenario.flow.watchdogID)
    scenario.send(.timedOut(token), at: 5)
    #expect(scenario.failure != nil && scenario.connections.isEmpty)
    var canceled = BatteryScenario()
    canceled.send(.cancel)
    #expect(canceled.failure != nil)
    #expect(canceled.send(.begin).isEmpty)
  }

  @Test func accessoryBatteryCanceledConnectionFailureConfirmsReleaseWithoutAnotherWait() throws {
    var scenario = BatteryScenario()
    scenario.start([scenario.device])
    scenario.send(.cancel)
    scenario.send(.connectionFailed(scenario.device.id, "Connection canceled"))
    #expect(scenario.flow.phase == .finished && scenario.failure != nil)
    #expect(scenario.report == nil)
  }

  @Test func accessoryBatteryCancellationDiscardsPartialResultsAndPendingReadReplies() throws {
    var scenario = BatteryScenario()
    scenario.start([scenario.device])
    let services = [UUID(), UUID()]
    scenario.connected(services: services)
    scenario.readLevel(Data([82]))
    let characteristic = UUID()
    scenario.send(
      .characteristics(
        scenario.device.id, services[1],
        [BatteryCharacteristic(id: characteristic, readable: true)], nil))
    scenario.send(.cancel)
    scenario.send(.value(scenario.device.id, characteristic, Data([100]), nil))
    scenario.send(.disconnected(scenario.device.id))
    #expect(scenario.failure == .canceled && scenario.report == nil)
  }

  @Test func accessoryBatteryUnexpectedDisconnectLabelsThePartialObservation() throws {
    var scenario = BatteryScenario()
    scenario.start([scenario.device])
    scenario.connected(services: [UUID(), UUID()])
    scenario.readLevel(Data([82]))
    scenario.send(.disconnected(scenario.device.id))
    let observation = try #require(scenario.report?.devices.first)
    #expect(observation.levels.count == 1 && observation.levels.first?.percent == 82)
    #expect(observation.issue != nil)
  }
}

private struct BatteryScenario {
  let device = BatteryCandidate(id: UUID(), name: "Headphones")
  var flow = AccessoryBatteryFlow()
  var now: TimeInterval = 0
  var commands: [BatteryReadCommand] = []
  var connections: [UUID] {
    commands.compactMap { if case .connect(let id) = $0 { id } else { nil } }
  }
  var report: AccessoryBatteryReport? {
    commands.compactMap { if case .finish(.success(let report)) = $0 { report } else { nil } }.last
  }
  var failure: AccessoryBatteryError? {
    commands.compactMap { if case .finish(.failure(let error)) = $0 { error } else { nil } }.last
  }
  @discardableResult mutating func send(_ event: BatteryReadEvent, at time: TimeInterval? = nil)
    -> [BatteryReadCommand]
  {
    if let time { now = time }
    let next = flow.receive(event, at: now)
    commands += next
    return next
  }
  mutating func start(_ candidates: [BatteryCandidate]) {
    send(.begin)
    send(.radio(.ready))
    send(.candidates(candidates))
  }
  mutating func connected(services: [UUID]) {
    guard let id = flow.activeDevice else {
      Issue.record("Expected a connected accessory")
      return
    }
    send(.connected(id))
    send(.services(id, services, nil))
  }
  mutating func readLevel(_ data: Data?, error: String? = nil) {
    guard let id = flow.activeDevice, case .characteristics(let service) = flow.phase else {
      Issue.record("Expected a readable battery service")
      return
    }
    let characteristic = UUID()
    send(
      .characteristics(
        id, service, [BatteryCharacteristic(id: characteristic, readable: true)], nil))
    send(.value(id, characteristic, data, error))
  }
}
