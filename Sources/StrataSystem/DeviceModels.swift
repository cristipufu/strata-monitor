import Foundation
import StrataCore

public struct BatteryState: Sendable {
  public let fraction: Double?
  public let charging: Bool?
  public let externalPower: Bool?
  public let minutesRemaining: Int?
  public let health: String?
  public var cycleCount: Int? = nil
  public var maximumCapacityFraction: Double? = nil
}

public enum BatteryObservation: Sendable {
  case unavailable, absent
  case present(BatteryState)
  public var isInstalled: Bool? {
    switch self {
    case .unavailable: nil
    case .absent: false
    case .present: true
    }
  }
  public var state: BatteryState? {
    if case .present(let state) = self { return state }
    return nil
  }
}

public struct AudioOutputIdentity: Equatable, Hashable, Sendable {
  public let objectID: UInt32
  public let uniqueID: String
  public init(objectID: UInt32, uniqueID: String) {
    self.objectID = objectID
    self.uniqueID = uniqueID
  }
}

public struct AudioOutput: Identifiable, Sendable {
  public struct ID: Hashable, Sendable {
    public let objectID: UInt32
    public let uniqueID: String?
  }
  public let objectID: UInt32
  public let name: String
  public var isDefault: Bool
  public var uniqueID: String? = nil
  public var id: ID { ID(objectID: objectID, uniqueID: uniqueID) }
  public var identity: AudioOutputIdentity? {
    guard objectID != 0, let uniqueID, !uniqueID.isEmpty else { return nil }
    return AudioOutputIdentity(objectID: objectID, uniqueID: uniqueID)
  }
}

public struct AudioState: Sendable {
  public let outputs: [AudioOutput]
  public let volume: Double?
  public let muted: Bool?
  public let canSetVolume: Bool
  public let canSetMute: Bool
  public var issue: String? = nil
  public var outputIdentity: AudioOutputIdentity? { outputs.first(where: \.isDefault)?.identity }
  public var outputName: String { outputs.first(where: \.isDefault)?.name ?? String(localized: "No output device") }
  public var observedOutputName: String? {
    outputs.first(where: \.isDefault)?.name ?? (issue == nil ? String(localized: "No output device") : nil)
  }
}

public struct WiFiState: Sendable {
  public let powered: Bool
  public let ssid: String?
  public let rssi: Int?
  public let interface: String?
}

public struct VolumeState: Identifiable, Sendable {
  public let url: URL
  public let name: String
  public let total: UInt64
  public let available: UInt64
  public var fileSystem: FileSystemIdentity? = nil
  public var id: URL { url }
  public var usedFraction: Double {
    total > 0 ? 1 - Double(min(available, total)) / Double(total) : 0
  }
}

public struct DeviceSnapshot: Sendable {
  /// Monotonic time at which collection began, used to reject an older result
  /// delivered after a newer action/refresh result.
  public let observationUptime: TimeInterval
  public let batteryObservation: BatteryObservation
  public var battery: BatteryState? { batteryObservation.state }
  public let audio: AudioState
  public let wifi: WiFiState
  public let volumes: [VolumeState]
  public let lowPowerMode: Bool
  public var mountedVolumeNamesByID: [String: String]? = nil
  public init(
    battery: BatteryObservation, audio: AudioState, wifi: WiFiState, volumes: [VolumeState],
    lowPowerMode: Bool, mountedVolumeNamesByID: [String: String]? = nil,
    observationUptime: TimeInterval = ProcessInfo.processInfo.systemUptime
  ) {
    self.observationUptime = observationUptime
    self.batteryObservation = battery
    self.audio = audio
    self.wifi = wifi
    self.volumes = volumes
    self.lowPowerMode = lowPowerMode
    self.mountedVolumeNamesByID = mountedVolumeNamesByID
  }
}

public enum DeviceError: LocalizedError, Sendable {
  case unavailable(String)
  case operationFailed(String, Int32)
  public var errorDescription: String? {
    switch self {
    case .unavailable(let message): message
    case .operationFailed(let action, let status):
      String(localized: "\(action) failed (\(String(status))). The device may have changed.")
    }
  }
}
