import Foundation
import IOKit
import IOKit.ps
import StrataCore

protocol SmartBatteryRegistryReading: Sendable {
  // Nil when the registry has no smart battery entry, as on desktop Macs.
  func properties() -> [String: Any]?
}

struct PowerSourceSnapshot {
  let providingType: String?
  let descriptions: [[String: Any]]
}

protocol PowerSourceFallbackReading: Sendable {
  func snapshot() -> PowerSourceSnapshot?
  func adapterDetails() -> [String: Any]?
}

public struct PowerTelemetryReader: Sendable {
  private let registry: any SmartBatteryRegistryReading
  private let fallback: any PowerSourceFallbackReading

  public init() {
    self.init(registry: NativeSmartBatteryRegistry(), fallback: NativePowerSourceFallback())
  }

  init(registry: any SmartBatteryRegistryReading, fallback: any PowerSourceFallbackReading) {
    self.registry = registry
    self.fallback = fallback
  }

  public func read() -> PowerReading {
    var values = registry.properties().map(PowerValues.init(smartBattery:)) ?? PowerValues()
    if values.lacksPowerSourceFields, let snapshot = fallback.snapshot() {
      values.fill(from: snapshot)
    }
    if values.lacksAdapterFields, let adapter = fallback.adapterDetails() {
      values.fillAdapter(from: adapter)
    }
    return values.reading
  }
}

private enum SmartBatteryKey {
  static let telemetry = "PowerTelemetryData"
  static let adapter = "AdapterDetails"
  static let installed = "BatteryInstalled"
  static let voltage = "Voltage"
  static let instantAmperage = "InstantAmperage"
  static let amperage = "Amperage"
  static let temperature = "Temperature"
  static let cycleCount = "CycleCount"
  static let externalConnected = "ExternalConnected"
  static let charging = "IsCharging"
  static let all = [
    telemetry, adapter, installed, voltage, instantAmperage, amperage, temperature, cycleCount,
    externalConnected, charging,
  ]
}

private enum Plausible {
  static let watts = 0.0...1_000
  static let signedWatts = -1_000.0...1_000
  static let inputVolts = 0.0...100
  static let inputAmps = 0.0...50
  static let batteryVolts = 1.0...100
  static let batteryAmps = -50.0...50
  static let celsius = -50.0...150
  static let cycles = 0...1_000_000
}

private struct PowerValues {
  private var base = PowerReading()
  private var systemLoadWatts: Double?
  // The telemetry does not say which way this flows, so its sign is never trusted.
  private var batteryPowerMagnitude: Double?

  init() {}

  init(smartBattery properties: [String: Any]) {
    let telemetry = properties[SmartBatteryKey.telemetry] as? [String: Any] ?? [:]
    systemLoadWatts = Self.milli(telemetry["SystemLoad"], within: Plausible.watts)
    batteryPowerMagnitude = Self.milli(telemetry["BatteryPower"], within: Plausible.signedWatts)
      .map(abs)
    base.inputWatts = Self.milli(telemetry["SystemPowerIn"], within: Plausible.watts)
    base.inputVolts = Self.milli(telemetry["SystemVoltageIn"], within: Plausible.inputVolts)
    base.inputAmps = Self.milli(telemetry["SystemCurrentIn"], within: Plausible.inputAmps)
    fillAdapter(from: properties[SmartBatteryKey.adapter] as? [String: Any] ?? [:])
    base.batteryInstalled = PowerSourceValue.boolean(properties[SmartBatteryKey.installed])
    base.batteryVolts = Self.milli(
      properties[SmartBatteryKey.voltage], within: Plausible.batteryVolts)
    base.batteryAmps =
      Self.milli(properties[SmartBatteryKey.instantAmperage], within: Plausible.batteryAmps)
      ?? Self.milli(properties[SmartBatteryKey.amperage], within: Plausible.batteryAmps)
    base.batteryTemperatureCelsius = Self.celsius(
      properties[SmartBatteryKey.temperature], perDegree: 100)
    base.batteryCycleCount = PowerSourceValue.integer(properties[SmartBatteryKey.cycleCount])
      .flatMap { Plausible.cycles.contains($0) ? $0 : nil }
    base.onExternalPower = PowerSourceValue.boolean(properties[SmartBatteryKey.externalConnected])
    base.isCharging = PowerSourceValue.boolean(properties[SmartBatteryKey.charging])
  }

  var lacksPowerSourceFields: Bool {
    guard base.onExternalPower != nil, base.batteryInstalled != nil else { return true }
    guard base.batteryInstalled == true else { return false }
    return base.isCharging == nil || base.batteryAmps == nil || base.batteryVolts == nil
      || base.batteryTemperatureCelsius == nil
  }

  var lacksAdapterFields: Bool {
    base.onExternalPower != false && (base.adapterWatts == nil || base.adapterName == nil)
  }

  mutating func fill(from snapshot: PowerSourceSnapshot) {
    base.onExternalPower = base.onExternalPower ?? Self.externalPower(snapshot.providingType)
    let batteries = snapshot.descriptions.filter {
      $0[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
    }
    let presence = batteries.map { PowerSourceValue.boolean($0[kIOPSIsPresentKey]) }
    let installed = batteries.indices.filter { presence[$0] == true }.map { batteries[$0] }
    base.batteryInstalled =
      base.batteryInstalled ?? (installed.isEmpty ? (presence.contains(nil) ? nil : false) : true)
    // Never attach one of several batteries' values to the Mac as a whole.
    guard installed.count == 1, base.batteryInstalled == true else { return }
    fillBattery(from: installed[0])
  }

  mutating func fillAdapter(from details: [String: Any]) {
    base.adapterWatts = base.adapterWatts ?? Self.adapterWatts(details)
    base.adapterName = base.adapterName ?? Self.adapterName(details)
  }

  var reading: PowerReading {
    var result = base.batteryInstalled == false ? Self.withoutBattery(base) : base
    result.batteryWatts = batteryWatts(result)
    result.systemWatts = systemLoadWatts ?? Self.derivedSystemWatts(result)
    if result.onExternalPower == false {
      result.adapterWatts = nil
      result.adapterName = nil
    }
    return result
  }

  private mutating func fillBattery(from description: [String: Any]) {
    base.isCharging = base.isCharging ?? PowerSourceValue.boolean(description[kIOPSIsChargingKey])
    base.batteryAmps =
      base.batteryAmps ?? Self.milli(description[kIOPSCurrentKey], within: Plausible.batteryAmps)
    base.batteryVolts =
      base.batteryVolts ?? Self.milli(description[kIOPSVoltageKey], within: Plausible.batteryVolts)
    base.batteryTemperatureCelsius =
      base.batteryTemperatureCelsius ?? Self.celsius(description[kIOPSTemperatureKey], perDegree: 1)
  }

  private func batteryWatts(_ reading: PowerReading) -> Double? {
    guard reading.batteryInstalled != false else { return nil }
    if let volts = reading.batteryVolts, let amps = reading.batteryAmps { return volts * amps }
    guard let magnitude = batteryPowerMagnitude else { return nil }
    if magnitude == 0 { return 0 }
    if reading.onExternalPower == false { return -magnitude }
    return reading.isCharging == true ? magnitude : nil
  }

  private static func derivedSystemWatts(_ reading: PowerReading) -> Double? {
    if let input = reading.inputWatts {
      if reading.batteryInstalled == false { return input }
      // Whatever arrives and does not go into the battery is used by the Mac.
      return reading.batteryWatts.map { max(0, input - $0) }
    }
    guard reading.onExternalPower == false, let battery = reading.batteryWatts, battery <= 0
    else { return nil }
    return -battery
  }

  private static func withoutBattery(_ reading: PowerReading) -> PowerReading {
    var result = reading
    result.batteryVolts = nil
    result.batteryAmps = nil
    result.batteryTemperatureCelsius = nil
    result.batteryCycleCount = nil
    result.isCharging = nil
    return result
  }

  private static func externalPower(_ providingType: String?) -> Bool? {
    switch providingType {
    case kIOPSACPowerValue: true
    case kIOPSBatteryPowerValue: false
    default: nil
    }
  }

  private static func adapterWatts(_ details: [String: Any]) -> Double? {
    guard let watts = PowerSourceValue.integer(details[kIOPSPowerAdapterWattsKey]), watts > 0
    else { return nil }
    return scaled(watts, by: 1, within: Plausible.watts)
  }

  private static func adapterName(_ details: [String: Any]) -> String? {
    for key in ["Name", "Description"] {
      if let name = details[key] as? String, !name.isEmpty { return name }
    }
    return nil
  }

  private static func celsius(_ value: Any?, perDegree: Double) -> Double? {
    PowerSourceValue.integer(value).flatMap { scaled($0, by: perDegree, within: Plausible.celsius) }
  }

  private static func milli(_ value: Any?, within range: ClosedRange<Double>) -> Double? {
    PowerSourceValue.integer(value).flatMap { scaled($0, by: 1_000, within: range) }
  }

  private static func scaled(_ value: Int, by divisor: Double, within range: ClosedRange<Double>)
    -> Double?
  {
    let scaled = Double(value) / divisor
    return range.contains(scaled) ? scaled : nil
  }
}

struct NativeSmartBatteryRegistry: SmartBatteryRegistryReading {
  func properties() -> [String: Any]? {
    let service = IOServiceGetMatchingService(
      kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    guard service != IO_OBJECT_NULL else { return nil }
    defer { IOObjectRelease(service) }
    var properties: [String: Any] = [:]
    for key in SmartBatteryKey.all {
      properties[key] =
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
        .takeRetainedValue()
    }
    return properties
  }
}

struct NativePowerSourceFallback: PowerSourceFallbackReading {
  func snapshot() -> PowerSourceSnapshot? {
    guard let information = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let sources = IOPSCopyPowerSourcesList(information)?.takeRetainedValue() as? [CFTypeRef]
    else { return nil }
    let providingType = IOPSGetProvidingPowerSourceType(information)?.takeUnretainedValue()
    return PowerSourceSnapshot(
      providingType: providingType as String?,
      descriptions: sources.compactMap {
        IOPSGetPowerSourceDescription(information, $0)?.takeUnretainedValue() as? [String: Any]
      })
  }

  func adapterDetails() -> [String: Any]? {
    IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any]
  }
}
