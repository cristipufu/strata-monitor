import Foundation
import IOKit.ps

protocol PowerSourceReading {
  /// Nil outer value is a failed query; nil entries are unreadable descriptions.
  func descriptions() -> [[String: Any]?]?
}
struct NativePowerSources: PowerSourceReading {
  func descriptions() -> [[String: Any]?]? {
    guard let information = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let sources = IOPSCopyPowerSourcesList(information)?.takeRetainedValue() as? [CFTypeRef]
    else { return nil }
    return sources.map {
      IOPSGetPowerSourceDescription(information, $0)?.takeUnretainedValue() as? [String: Any]
    }
  }
}

struct BatteryReader {
  private let sources: any PowerSourceReading
  private let health: any BatteryHealthReading
  init(
    sources: any PowerSourceReading = NativePowerSources(),
    health: any BatteryHealthReading = BatteryHealthReader()
  ) {
    self.sources = sources
    self.health = health
  }
  func snapshot() -> BatteryObservation {
    guard let descriptions = sources.descriptions() else { return .unavailable }
    var installed: [[String: Any]] = []
    var incomplete = false
    for description in descriptions {
      guard let description, let type = description[kIOPSTypeKey] as? String else {
        incomplete = true
        continue
      }
      if type == kIOPSUPSType { continue }
      guard type == kIOPSInternalBatteryType,
        let present = PowerSourceValue.boolean(description[kIOPSIsPresentKey])
      else {
        incomplete = true
        continue
      }
      if present { installed.append(description) }
    }
    guard !installed.isEmpty else { return incomplete ? .unavailable : .absent }
    guard installed.count == 1, !incomplete else { return .present(unavailableState) }
    return .present(reading(installed[0]))
  }
  private var unavailableState: BatteryState {
    BatteryState(
      fraction: nil, charging: nil, externalPower: nil, minutesRemaining: nil, health: nil)
  }
  private func reading(_ details: [String: Any]) -> BatteryState {
    let charging = PowerSourceValue.boolean(details[kIOPSIsChargingKey])
    let external: Bool?
    switch details[kIOPSPowerSourceStateKey] as? String {
    case kIOPSACPowerValue: external = true
    case kIOPSBatteryPowerValue: external = false
    default: external = nil
    }
    let minutes: Int?
    if charging == true {
      minutes = PowerSourceValue.integer(details[kIOPSTimeToFullChargeKey])
    } else if charging == false && external == false {
      minutes = PowerSourceValue.integer(details[kIOPSTimeToEmptyKey])
    } else {
      minutes = nil
    }
    return BatteryState(
      fraction: fraction(details), charging: charging, externalPower: external,
      minutesRemaining: minutes.flatMap { $0 >= 0 ? $0 : nil },
      health: details[kIOPSBatteryHealthKey] as? String, cycleCount: health.cycleCount(),
      maximumCapacityFraction: health.maximumCapacityFraction(from: details))
  }
  private func fraction(_ details: [String: Any]) -> Double? {
    guard let current = PowerSourceValue.integer(details[kIOPSCurrentCapacityKey]),
      let maximum = PowerSourceValue.integer(details[kIOPSMaxCapacityKey]),
      maximum > 0, current >= 0, current <= maximum
    else { return nil }
    return Double(current) / Double(maximum)
  }
}
