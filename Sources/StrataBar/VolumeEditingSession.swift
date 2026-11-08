import StrataSystem

struct VolumeEditingSession {
  private var output: AudioOutputIdentity?
  var isEditing: Bool { output != nil }
  mutating func begin(on output: AudioOutputIdentity?) { self.output = output }
  mutating func finish(currentOutput: AudioOutputIdentity?, isVisible: Bool) -> AudioOutputIdentity?
  {
    defer { cancel() }
    guard isVisible, let output, output == currentOutput else { return nil }
    return output
  }
  mutating func cancel() { output = nil }
}
