import Foundation

public struct PowerReading: Codable, Equatable, Sendable {
  // What the Mac consumes, whether it comes from the adapter or the battery.
  public var systemWatts: Double?
  // What arrives from the adapter, including any power used to charge the battery.
  public var inputWatts: Double?
  public var inputVolts: Double?
  public var inputAmps: Double?
  public var adapterWatts: Double?
  public var adapterName: String?
  public var batteryInstalled: Bool?
  // Negative while the battery discharges, positive while it charges.
  public var batteryWatts: Double?
  public var batteryVolts: Double?
  public var batteryAmps: Double?
  public var batteryTemperatureCelsius: Double?
  public var batteryCycleCount: Int?
  public var onExternalPower: Bool?
  public var isCharging: Bool?

  public init(
    systemWatts: Double? = nil, inputWatts: Double? = nil, inputVolts: Double? = nil,
    inputAmps: Double? = nil, adapterWatts: Double? = nil, adapterName: String? = nil,
    batteryInstalled: Bool? = nil, batteryWatts: Double? = nil, batteryVolts: Double? = nil,
    batteryAmps: Double? = nil, batteryTemperatureCelsius: Double? = nil,
    batteryCycleCount: Int? = nil, onExternalPower: Bool? = nil, isCharging: Bool? = nil
  ) {
    self.systemWatts = systemWatts
    self.inputWatts = inputWatts
    self.inputVolts = inputVolts
    self.inputAmps = inputAmps
    self.adapterWatts = adapterWatts
    self.adapterName = adapterName
    self.batteryInstalled = batteryInstalled
    self.batteryWatts = batteryWatts
    self.batteryVolts = batteryVolts
    self.batteryAmps = batteryAmps
    self.batteryTemperatureCelsius = batteryTemperatureCelsius
    self.batteryCycleCount = batteryCycleCount
    self.onExternalPower = onExternalPower
    self.isCharging = isCharging
  }
}
