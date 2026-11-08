import Foundation

public struct DeviceEventObservation: Sendable {
  public let id: UUID
  public let events: AsyncStream<Void>
  public init(id: UUID, events: AsyncStream<Void>) {
    self.id = id
    self.events = events
  }
}

public protocol DeviceEventObserving: Sendable {
  func start() async -> DeviceEventObservation
  func observeAudioOutput(
    _ output: AudioOutputIdentity?, at uptime: TimeInterval, observationID: UUID) async
  func stop(observationID: UUID) async
}

public struct DeviceEventFailure: Error, Equatable, Sendable, Encodable {
  public let channel: String
  public let operation: String
  public let status: Int32
}

enum DeviceEventChannel: Hashable, Sendable {
  case power, lowPowerMode, volumeMounted, volumeUnmounted, volumeRenamed, displays
  case audioDevices, defaultAudioOutput
  case audioVolume(UInt32)
  case audioMute(UInt32)
  case audioName(UInt32)
  case audioIdentity(UInt32)
  static let shared: [Self] = [
    .power, .lowPowerMode, .volumeMounted, .volumeUnmounted, .volumeRenamed, .displays,
    .audioDevices, .defaultAudioOutput,
  ]
  static func audio(for objectID: UInt32) -> [Self] {
    [.audioVolume(objectID), .audioMute(objectID), .audioName(objectID), .audioIdentity(objectID)]
  }
}

protocol DeviceEventRegistration: Sendable {
  func cancel() -> DeviceEventFailure?
}
protocol DeviceEventRegistering: Sendable {
  func register(_ channel: DeviceEventChannel, change: @escaping @Sendable () -> Void) throws
    -> any DeviceEventRegistration
}
