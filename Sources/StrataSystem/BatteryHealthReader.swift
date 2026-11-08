import Foundation
import IOKit
import IOKit.ps
import IOKit.pwr_mgt

protocol BatteryHealthReading {
  func cycleCount() -> Int?
  func maximumCapacityFraction(from details: [String: Any]) -> Double?
}

struct BatteryHealthReader: BatteryHealthReading {
  func cycleCount() -> Int? {
    var iterator: io_iterator_t = 0
    guard
      IOServiceGetMatchingServices(
        kIOMainPortDefault, IOServiceMatching("IOPMPowerSource"), &iterator) == KERN_SUCCESS
    else { return nil }
    defer { IOObjectRelease(iterator) }
    var counts: [Int] = []
    while true {
      let source = IOIteratorNext(iterator)
      guard source != 0 else { break }
      defer { IOObjectRelease(source) }
      guard PowerSourceValue.boolean(property(source, key: kIOPMPSBatteryInstalledKey)) == true,
        let cycles = PowerSourceValue.integer(property(source, key: kIOPMPSCycleCountKey)),
        cycles >= 0
      else { continue }
      counts.append(cycles)
      // Never arbitrarily attach one of several installed battery counters.
      if counts.count > 1 { return nil }
    }
    return counts.first
  }
  func maximumCapacityFraction(from details: [String: Any]) -> Double? {
    // IOPS Max Capacity is commonly just the 100% charge scale. It is not
    // battery health. Nominal/design capacities must both be exposed in the
    // same power-source description, whose capacity units are consistent.
    guard let nominal = PowerSourceValue.positiveNumber(details[kIOPSNominalCapacityKey]),
      let design = PowerSourceValue.positiveNumber(details[kIOPSDesignCapacityKey])
    else { return nil }
    let fraction = nominal / design
    return fraction.isFinite ? min(1, fraction) : nil
  }
  private func property(_ source: io_registry_entry_t, key: String) -> CFTypeRef? {
    IORegistryEntryCreateCFProperty(source, key as CFString, kCFAllocatorDefault, 0)?
      .takeRetainedValue()
  }
}
