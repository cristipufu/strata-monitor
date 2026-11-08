import Foundation
import IOKit.ps
import Testing

@testable import StrataSystem

@Test func batteryChargeScaleCannotBeMisreportedAsHealthCapacity() {
  let reader = BatteryHealthReader()
  #expect(
    reader.maximumCapacityFraction(from: [kIOPSMaxCapacityKey: 100, kIOPSDesignCapacityKey: 6249])
      == nil)
  #expect(
    reader.maximumCapacityFraction(from: [
      kIOPSNominalCapacityKey: 5400, kIOPSDesignCapacityKey: 6000,
    ]) == 0.9)
  #expect(
    reader.maximumCapacityFraction(from: [kIOPSNominalCapacityKey: 5400, kIOPSDesignCapacityKey: 0])
      == nil)
  #expect(
    reader.maximumCapacityFraction(from: [
      kIOPSNominalCapacityKey: Double.nan, kIOPSDesignCapacityKey: 6000,
    ]) == nil)
  #expect(reader.maximumCapacityFraction(from: [:]) == nil)
}
