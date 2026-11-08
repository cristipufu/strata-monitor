import CoreWLAN
import Foundation
import IOKit.ps

public actor DeviceCollector {
  private let audio = AudioService()
  private let battery = BatteryReader()
  public init() {}

  public func sample() -> DeviceSnapshot {
    let observationUptime = ProcessInfo.processInfo.systemUptime
    let storage = volumes()
    return DeviceSnapshot(
      battery: battery.snapshot(), audio: audio.snapshot(), wifi: wifi(), volumes: storage.readings,
      lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
      mountedVolumeNamesByID: storage.names, observationUptime: observationUptime)
  }
  public func setVolume(_ value: Double, on output: AudioOutputIdentity) throws {
    try Task.checkCancellation()
    try audio.setVolume(value, on: output)
  }
  public func setMuted(_ muted: Bool, on output: AudioOutputIdentity) throws {
    try Task.checkCancellation()
    try audio.setMuted(muted, on: output)
  }
  public func selectOutput(_ output: AudioOutputIdentity) throws {
    try Task.checkCancellation()
    try audio.selectOutput(output)
  }

  public func setWiFiPower(_ powered: Bool) throws {
    try Task.checkCancellation()
    guard let interface = CWWiFiClient.shared().interface() else {
      throw DeviceError.unavailable(String(localized: "No Wi-Fi interface is available."))
    }
    guard interface.configuration()?.requireAdministratorForPower == false else {
      throw DeviceError.unavailable(
        String(localized: "Wi-Fi power changes require system authorization. Use System Settings."))
    }
    try interface.setPower(powered)
  }
  private func wifi() -> WiFiState {
    guard let interface = CWWiFiClient.shared().interface() else {
      return WiFiState(powered: false, ssid: nil, rssi: nil, interface: nil)
    }
    let rssi = interface.rssiValue()
    return WiFiState(
      powered: interface.powerOn(), ssid: interface.ssid(),
      rssi: rssi == 0 ? nil : rssi, interface: interface.interfaceName)
  }
  private func volumes() -> (readings: [VolumeState], names: [String: String]?) {
    let keys: Set<URLResourceKey> = [
      .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
      .volumeIsBrowsableKey, .volumeIsLocalKey,
    ]
    guard
      let urls =
        FileManager.default.mountedVolumeURLs(
          includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes])
    else { return ([], nil) }
    var names: [String: String] = [:]
    var complete = true
    let readings = urls.compactMap { url -> VolumeState? in
      guard let values = try? url.resourceValues(forKeys: keys), let local = values.volumeIsLocal
      else {
        complete = false
        return nil
      }
      guard local, values.volumeIsBrowsable != false else { return nil }
      names[url.path] = values.volumeName ?? url.lastPathComponent
      guard let total = values.volumeTotalCapacity,
        let available = values.volumeAvailableCapacity, total > 0, available >= 0
      else { return nil }
      return VolumeState(
        url: url, name: values.volumeName ?? url.lastPathComponent,
        total: UInt64(total), available: UInt64(available),
        fileSystem: FileSystemIdentityReader().identity(at: url))
    }
    return (readings, complete ? names : nil)
  }
}
