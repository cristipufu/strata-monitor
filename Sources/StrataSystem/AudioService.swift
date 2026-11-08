import Foundation

struct AudioService {
  private let hardware: any AudioHardware
  init(hardware: any AudioHardware = NativeAudioHardware()) { self.hardware = hardware }

  func snapshot() -> AudioState {
    guard let ids = hardware.deviceIDs() else {
      return unavailable(outputs: [], issue: "Audio outputs are unavailable.")
    }
    let selected = hardware.defaultOutput()
    let outputs = ids.compactMap { id -> AudioOutput? in
      guard var output = hardware.describeOutput(id) else { return nil }
      output.isDefault = selected == .device(id)
      return output
    }
    guard selected != .unavailable else {
      return unavailable(outputs: outputs, issue: "The current audio output is unavailable.")
    }
    guard let output = outputs.first(where: \.isDefault) else {
      return unavailable(
        outputs: outputs,
        issue: selected == .none ? nil : "The audio output changed. Refreshing its controls.")
    }
    guard let identity = output.identity else {
      return unavailable(outputs: outputs, issue: "Controls are unavailable for this output.")
    }
    return readings(for: identity, outputs: outputs)
  }
  private func readings(for identity: AudioOutputIdentity, outputs: [AudioOutput]) -> AudioState {
    let controls = hardware.controls(for: identity.objectID)
    guard isCurrent(identity, requiresDefault: true) else {
      let deselected = outputs.map { output in
        var output = output
        output.isDefault = false
        return output
      }
      return unavailable(
        outputs: deselected, issue: "The audio output changed. Refreshing its controls.")
    }
    let volume = controls.volume.flatMap { $0.isFinite && (0...1).contains($0) ? $0 : nil }
    return AudioState(
      outputs: outputs, volume: volume, muted: controls.muted,
      canSetVolume: controls.canSetVolume && volume != nil,
      canSetMute: controls.canSetMute && controls.muted != nil,
      issue: (controls.canSetVolume && volume == nil)
        || (controls.canSetMute && controls.muted == nil)
        ? "Some output controls are unavailable." : nil)
  }
  func setVolume(_ value: Double, on output: AudioOutputIdentity) throws {
    guard value.isFinite else { throw DeviceError.unavailable("The volume value is unavailable.") }
    try changeControls(
      on: output, permits: { $0.canSetVolume },
      change: {
        try hardware.setVolume(min(1, max(0, value)), on: output.objectID)
      })
  }
  func setMuted(_ muted: Bool, on output: AudioOutputIdentity) throws {
    try changeControls(
      on: output, permits: { $0.canSetMute },
      change: {
        try hardware.setMuted(muted, on: output.objectID)
      })
  }
  func selectOutput(_ output: AudioOutputIdentity) throws {
    try Task.checkCancellation()
    try validate(output, requiresDefault: false)
    try Task.checkCancellation()
    try hardware.selectOutput(output.objectID)
  }
  private func changeControls(
    on output: AudioOutputIdentity, permits: (AudioControls) -> Bool, change: () throws -> Void
  ) throws {
    try Task.checkCancellation()
    try validate(output, requiresDefault: true)
    guard permits(hardware.controls(for: output.objectID)) else {
      throw DeviceError.unavailable("This output no longer supports that control.")
    }
    try Task.checkCancellation()
    try validate(output, requiresDefault: true)
    try change()
  }
  private func validate(_ output: AudioOutputIdentity, requiresDefault: Bool) throws {
    guard isCurrent(output, requiresDefault: requiresDefault) else {
      throw DeviceError.unavailable(
        "The audio output changed or disconnected. Try again with the current output.")
    }
  }
  private func isCurrent(_ output: AudioOutputIdentity, requiresDefault: Bool) -> Bool {
    guard output.objectID != 0, !output.uniqueID.isEmpty,
      hardware.describeOutput(output.objectID)?.identity == output
    else { return false }
    return !requiresDefault || hardware.defaultOutput() == .device(output.objectID)
  }
  private func unavailable(outputs: [AudioOutput], issue: String?) -> AudioState {
    AudioState(
      outputs: outputs, volume: nil, muted: nil, canSetVolume: false, canSetMute: false,
      issue: issue)
  }
}
