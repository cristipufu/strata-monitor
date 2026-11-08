import Foundation
import IOKit
import IOKit.ps
import StrataCore
import Testing

@testable import StrataSystem

// Immutable fixture data, never mutated after creation.
private struct SmartBatteryFixture: SmartBatteryRegistryReading, @unchecked Sendable {
  let values: [String: Any]?
  func properties() -> [String: Any]? { values }
}

private final class PowerSourcesFixture: PowerSourceFallbackReading, @unchecked Sendable {
  let values: PowerSourceSnapshot?
  let adapter: [String: Any]?
  private(set) var snapshotQueries = 0
  private(set) var adapterQueries = 0
  init(_ values: PowerSourceSnapshot? = nil, adapter: [String: Any]? = nil) {
    self.values = values
    self.adapter = adapter
  }
  func snapshot() -> PowerSourceSnapshot? {
    snapshotQueries += 1
    return values
  }
  func adapterDetails() -> [String: Any]? {
    adapterQueries += 1
    return adapter
  }
}

private var adapterOnFullBattery: [String: Any] {
  [
    "PowerTelemetryData": [
      "SystemPowerIn": 59_462, "SystemVoltageIn": 19_960, "SystemCurrentIn": 2_980,
      "SystemLoad": 59_462, "BatteryPower": 0,
    ],
    "AdapterDetails": [
      "Watts": 94, "Name": "96W USB-C Power Adapter", "Description": "pd charger",
    ],
    "BatteryInstalled": true, "Voltage": 12_870, "InstantAmperage": 0, "Amperage": 0,
    "Temperature": 3_070, "CycleCount": 114, "ExternalConnected": true, "IsCharging": false,
  ]
}

private func smartBattery(_ changes: [String: Any?]) -> [String: Any] {
  var properties = adapterOnFullBattery
  for (key, value) in changes { properties[key] = value }
  return properties
}

private func telemetry(_ changes: [String: Any?]) -> [String: Any] {
  var values = adapterOnFullBattery["PowerTelemetryData"] as? [String: Any] ?? [:]
  for (key, value) in changes { values[key] = value }
  return values
}

private func internalBattery(_ fields: [String: Any] = [:]) -> [String: Any] {
  [kIOPSTypeKey: kIOPSInternalBatteryType, kIOPSIsPresentKey: true].merging(fields) { $1 }
}

private func read(_ battery: [String: Any]?, _ sources: PowerSourcesFixture = PowerSourcesFixture())
  -> PowerReading
{
  PowerTelemetryReader(registry: SmartBatteryFixture(values: battery), fallback: sources).read()
}

@Test func adapterPowerWithAFullBatteryReadsEverythingFromTheRegistry() {
  let sources = PowerSourcesFixture()
  let reading = read(adapterOnFullBattery, sources)
  #expect(reading.systemWatts == 59.462 && reading.inputWatts == 59.462)
  #expect(reading.inputVolts == 19.96 && reading.inputAmps == 2.98)
  #expect(reading.adapterWatts == 94 && reading.adapterName == "96W USB-C Power Adapter")
  #expect(reading.batteryInstalled == true && reading.batteryVolts == 12.87)
  #expect(reading.batteryAmps == 0 && reading.batteryWatts == 0)
  #expect(reading.batteryTemperatureCelsius == 30.7 && reading.batteryCycleCount == 114)
  #expect(reading.onExternalPower == true && reading.isCharging == false)
  #expect(sources.snapshotQueries == 0 && sources.adapterQueries == 0)
}

@Test func dischargingBatteryReportsNegativeWattsAndNoStaleAdapter() throws {
  let reading = read(
    smartBattery([
      "PowerTelemetryData": telemetry(["SystemPowerIn": 0, "SystemLoad": 14_100]),
      "InstantAmperage": -1_100, "Amperage": -1_000, "Voltage": 12_000,
      "ExternalConnected": false,
    ]))
  #expect(reading.onExternalPower == false && reading.isCharging == false)
  #expect(reading.batteryAmps == -1.1)
  let watts = try #require(reading.batteryWatts)
  #expect(abs(watts - -13.2) < 1e-9)
  #expect(reading.systemWatts == 14.1)
  #expect(reading.adapterWatts == nil && reading.adapterName == nil)
}

@Test func chargingBatteryReportsPositiveWatts() {
  let reading = read(
    smartBattery([
      "InstantAmperage": 2_500, "Voltage": 12_000, "IsCharging": true,
      "PowerTelemetryData": telemetry(["SystemPowerIn": 60_000, "SystemLoad": 30_000]),
    ]))
  #expect(reading.batteryWatts == 30 && reading.isCharging == true)
  #expect(reading.systemWatts == 30 && reading.inputWatts == 60)
}

@Test func desktopWithoutABatteryReportsNoBatteryValues() {
  let sources = PowerSourcesFixture(
    PowerSourceSnapshot(providingType: kIOPSACPowerValue, descriptions: []))
  let reading = read(nil, sources)
  #expect(reading.batteryInstalled == false && reading.onExternalPower == true)
  #expect(reading.batteryWatts == nil && reading.batteryVolts == nil && reading.batteryAmps == nil)
  #expect(reading.batteryTemperatureCelsius == nil && reading.batteryCycleCount == nil)
  #expect(reading.isCharging == nil && reading.systemWatts == nil)
  #expect(reading.adapterWatts == nil && reading.adapterName == nil)
}

@Test func desktopTelemetryStillReportsSystemPower() {
  let reading = read([
    "PowerTelemetryData": ["SystemPowerIn": 31_000], "BatteryInstalled": false,
    "ExternalConnected": true, "Voltage": 12_000, "InstantAmperage": 100, "IsCharging": false,
  ])
  #expect(reading.batteryInstalled == false && reading.systemWatts == 31)
  #expect(reading.batteryWatts == nil && reading.batteryVolts == nil && reading.isCharging == nil)
}

@Test func missingRegistryAndPowerSourcesLeaveEveryReadingUnavailable() {
  #expect(read(nil) == PowerReading())
  #expect(read([:]) == PowerReading())
}

@Test func missingTelemetryKeysAreUnavailableNeverZero() {
  let reading = read(
    smartBattery([
      "PowerTelemetryData": nil, "AdapterDetails": nil, "InstantAmperage": nil,
      "Amperage": nil, "Temperature": nil, "CycleCount": nil,
    ]))
  #expect(reading.systemWatts == nil && reading.inputWatts == nil && reading.inputVolts == nil)
  #expect(reading.adapterWatts == nil && reading.adapterName == nil)
  #expect(reading.batteryAmps == nil && reading.batteryWatts == nil)
  #expect(reading.batteryTemperatureCelsius == nil && reading.batteryCycleCount == nil)
  #expect(reading.batteryVolts == 12.87 && reading.onExternalPower == true)
}

@Test func garbageTypesAreRejectedRatherThanCoerced() {
  let reading = read([
    "PowerTelemetryData": ["SystemLoad": "59 W", "SystemPowerIn": true, "SystemVoltageIn": 1.5],
    "AdapterDetails": ["Watts": "94", "Name": 7, "Description": ""],
    "BatteryInstalled": 1, "Voltage": "12870", "InstantAmperage": Double.nan,
    "Amperage": [1], "Temperature": false, "CycleCount": 1.5, "ExternalConnected": "Yes",
    "IsCharging": 0,
  ])
  #expect(reading == PowerReading())
}

@Test func negativeAndOverflowingValuesAreRejected() {
  let reading = read(
    smartBattery([
      "PowerTelemetryData": telemetry([
        "SystemLoad": -5, "SystemPowerIn": Int64.max, "SystemVoltageIn": -19_960,
        "SystemCurrentIn": UInt64.max, "BatteryPower": Int64.min,
      ]),
      "AdapterDetails": ["Watts": -94, "Name": "Adapter"],
      "Voltage": -12_870, "InstantAmperage": 900_000, "Amperage": -1_000_000,
      "Temperature": 1_000_000, "CycleCount": -1,
    ]))
  #expect(reading.systemWatts == nil && reading.inputWatts == nil)
  #expect(reading.inputVolts == nil && reading.inputAmps == nil)
  #expect(reading.adapterWatts == nil && reading.adapterName == "Adapter")
  #expect(reading.batteryVolts == nil && reading.batteryAmps == nil && reading.batteryWatts == nil)
  #expect(reading.batteryTemperatureCelsius == nil && reading.batteryCycleCount == nil)
}

@Test func amperageFallsBackFromInstantToAverage() {
  let reading = read(smartBattery(["InstantAmperage": "bad", "Amperage": -2_000]))
  #expect(reading.batteryAmps == -2)
}

@Test func batteryPowerIsUsedOnlyWhenItsDirectionIsKnown() {
  func batteryWatts(_ state: [String: Any?]) -> Double? {
    let withoutCurrent: [String: Any?] = [
      "InstantAmperage": nil, "Amperage": nil,
      "PowerTelemetryData": telemetry(["BatteryPower": 8_000, "SystemLoad": nil]),
    ]
    return read(smartBattery(withoutCurrent.merging(state) { $1 })).batteryWatts
  }
  #expect(batteryWatts(["ExternalConnected": false]) == -8)
  #expect(batteryWatts(["IsCharging": true]) == 8)
  #expect(batteryWatts([:]) == nil)
}

@Test func powerSourcesFillOnlyWhatTheRegistryLacks() {
  let sources = PowerSourcesFixture(
    PowerSourceSnapshot(
      providingType: kIOPSBatteryPowerValue,
      descriptions: [
        internalBattery([
          kIOPSIsChargingKey: false, kIOPSCurrentKey: -1_500, kIOPSVoltageKey: 11_000,
          kIOPSTemperatureKey: 31,
        ])
      ]),
    adapter: ["Watts": 30, "Name": "Ignored on battery"])
  let reading = read(nil, sources)
  #expect(reading.onExternalPower == false && reading.batteryInstalled == true)
  #expect(reading.isCharging == false && reading.batteryAmps == -1.5 && reading.batteryVolts == 11)
  #expect(reading.batteryTemperatureCelsius == 31 && reading.batteryWatts == -16.5)
  #expect(reading.systemWatts == 16.5)
  #expect(reading.adapterWatts == nil && sources.adapterQueries == 0)
  let registryWins = read(smartBattery(["Temperature": nil]), sources)
  #expect(registryWins.onExternalPower == true && registryWins.batteryAmps == 0)
  #expect(registryWins.batteryTemperatureCelsius == 31)
}

@Test func adapterDetailsFillMissingAdapterFields() {
  let sources = PowerSourcesFixture(
    PowerSourceSnapshot(providingType: kIOPSACPowerValue, descriptions: []),
    adapter: ["Watts": 140, "Description": "pd charger"])
  let reading = read(smartBattery(["AdapterDetails": ["Watts": 0]]), sources)
  #expect(reading.adapterWatts == 140 && reading.adapterName == "pd charger")
}

@Test func ambiguousOrUnreadableBatteriesAreNotAttachedToTheMac() {
  let two = PowerSourcesFixture(
    PowerSourceSnapshot(
      providingType: kIOPSACPowerValue,
      descriptions: [internalBattery([kIOPSCurrentKey: 1]), internalBattery([kIOPSCurrentKey: 2])])
  )
  let ambiguous = read(nil, two)
  #expect(ambiguous.batteryInstalled == true && ambiguous.batteryAmps == nil)
  let unreadable = PowerSourcesFixture(
    PowerSourceSnapshot(
      providingType: "UPS Power",
      descriptions: [[kIOPSTypeKey: kIOPSInternalBatteryType, kIOPSIsPresentKey: "yes"]]))
  let unknown = read(nil, unreadable)
  #expect(unknown.batteryInstalled == nil && unknown.onExternalPower == nil)
}

extension SystemIntegrationTests {
  @Test func livePowerTelemetryIsPlausibleOrUnavailable() {
    let reading = PowerTelemetryReader().read()
    if let watts = reading.systemWatts { #expect((0...1_000).contains(watts)) }
    if let watts = reading.adapterWatts { #expect(watts > 0 && watts <= 1_000) }
    if let watts = reading.batteryWatts { #expect(abs(watts) <= 5_000) }
    if let celsius = reading.batteryTemperatureCelsius { #expect((-50...150).contains(celsius)) }
    if reading.batteryInstalled == false { #expect(reading.batteryWatts == nil) }
  }

  @Test func repeatedPowerTelemetryReadsBalanceRegistrySendRights() {
    let service = IOServiceGetMatchingService(
      kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    guard service != 0 else { return }  // Desktop Macs have no smart battery.
    defer { IOObjectRelease(service) }
    let reader = PowerTelemetryReader()
    _ = reader.read()
    var before: mach_port_urefs_t = 0
    var after: mach_port_urefs_t = 0
    #expect(
      mach_port_get_refs(mach_task_self_, service, mach_port_right_t(MACH_PORT_RIGHT_SEND), &before)
        == KERN_SUCCESS)
    for _ in 0..<200 { _ = reader.read() }
    #expect(
      mach_port_get_refs(mach_task_self_, service, mach_port_right_t(MACH_PORT_RIGHT_SEND), &after)
        == KERN_SUCCESS)
    #expect(before == after)
  }
}
