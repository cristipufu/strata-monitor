import Foundation

enum AudioOutputSelection: Equatable {
  case unavailable, none
  case device(UInt32)
}

struct AudioControls {
  let volume: Double?
  let muted: Bool?
  let canSetVolume: Bool
  let canSetMute: Bool
}

/// All native access is synchronous and confined to the owning device collector.
protocol AudioHardware {
  func deviceIDs() -> [UInt32]?
  func defaultOutput() -> AudioOutputSelection
  func describeOutput(_ id: UInt32) -> AudioOutput?
  func controls(for id: UInt32) -> AudioControls
  func setVolume(_ value: Double, on id: UInt32) throws
  func setMuted(_ muted: Bool, on id: UInt32) throws
  func selectOutput(_ id: UInt32) throws
}
