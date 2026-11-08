import CoreAudio
import Foundation

struct NativeAudioHardware: AudioHardware {
  private let system = AudioObjectID(kAudioObjectSystemObject)
  private let maximumDeviceBytes: UInt32 = 64_000

  func defaultOutput() -> AudioOutputSelection {
    guard let id = read(system, kAudioHardwarePropertyDefaultOutputDevice, initial: UInt32(0))
    else { return .unavailable }
    return id == kAudioObjectUnknown ? .none : .device(id)
  }
  func deviceIDs() -> [UInt32]? {
    var property = address(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(system, &property, 0, nil, &size) == noErr,
      size < maximumDeviceBytes, Int(size) % MemoryLayout<UInt32>.stride == 0
    else { return nil }
    if size == 0 { return [] }
    let capacity = size
    var devices = [UInt32](repeating: 0, count: Int(capacity) / MemoryLayout<UInt32>.stride)
    let status = devices.withUnsafeMutableBytes { buffer in
      guard let destination = buffer.baseAddress else { return kAudioHardwareBadPropertySizeError }
      return AudioObjectGetPropertyData(system, &property, 0, nil, &size, destination)
    }
    guard status == noErr, size <= capacity, Int(size) % MemoryLayout<UInt32>.stride == 0 else {
      return nil
    }
    return Array(devices.prefix(Int(size) / MemoryLayout<UInt32>.stride))
  }
  func describeOutput(_ id: UInt32) -> AudioOutput? {
    guard id != kAudioObjectUnknown, hasOutput(id) else { return nil }
    return AudioOutput(
      objectID: id, name: copiedString(id, kAudioObjectPropertyName) ?? "Audio output",
      isDefault: false,
      uniqueID: copiedString(id, kAudioDevicePropertyDeviceUID))
  }
  func controls(for id: UInt32) -> AudioControls {
    let volume = read(
      id, kAudioDevicePropertyVolumeScalar, initial: Float32(0),
      scope: kAudioDevicePropertyScopeOutput)
    let muted = read(
      id, kAudioDevicePropertyMute, initial: UInt32(0), scope: kAudioDevicePropertyScopeOutput)
    return AudioControls(
      volume: volume.map(Double.init), muted: muted.map { $0 != 0 },
      canSetVolume: settable(id, kAudioDevicePropertyVolumeScalar),
      canSetMute: settable(id, kAudioDevicePropertyMute))
  }
  func setVolume(_ value: Double, on id: UInt32) throws {
    try write(
      id, kAudioDevicePropertyVolumeScalar, Float32(value), scope: kAudioDevicePropertyScopeOutput)
  }
  func setMuted(_ muted: Bool, on id: UInt32) throws {
    try write(
      id, kAudioDevicePropertyMute, UInt32(muted ? 1 : 0), scope: kAudioDevicePropertyScopeOutput)
  }
  func selectOutput(_ id: UInt32) throws {
    try write(system, kAudioHardwarePropertyDefaultOutputDevice, id)
  }
  private func hasOutput(_ id: UInt32) -> Bool {
    var property = address(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
    var size: UInt32 = 0
    return AudioObjectGetPropertyDataSize(id, &property, 0, nil, &size) == noErr && size > 0
  }
  private func settable(_ id: UInt32, _ selector: AudioObjectPropertySelector) -> Bool {
    var property = address(selector, scope: kAudioDevicePropertyScopeOutput)
    var allowed: DarwinBoolean = false
    return AudioObjectIsPropertySettable(id, &property, &allowed) == noErr && allowed.boolValue
  }
  private func address(
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
  ) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
  }
  /// This helper is private to fixed-size scalar properties, never reference-valued properties.
  private func read<T>(
    _ id: UInt32, _ selector: AudioObjectPropertySelector, initial: T,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
  ) -> T? {
    var property = address(selector, scope: scope)
    var value = initial
    var size = UInt32(MemoryLayout<T>.size)
    let status = withUnsafeMutablePointer(to: &value) {
      AudioObjectGetPropertyData(id, &property, 0, nil, &size, $0)
    }
    return status == noErr && size == MemoryLayout<T>.size ? value : nil
  }
  private func copiedString(_ id: UInt32, _ selector: AudioObjectPropertySelector) -> String? {
    var property = address(selector)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let status = withUnsafeMutablePointer(to: &value) {
      AudioObjectGetPropertyData(id, &property, 0, nil, &size, $0)
    }
    // Both supported string selectors return a +1 CFObject under the public SDK contract.
    let result = value?.takeRetainedValue()
    guard status == noErr, size == MemoryLayout<Unmanaged<CFString>?>.size else { return nil }
    return result.map { $0 as String }
  }
  private func write<T>(
    _ id: UInt32, _ selector: AudioObjectPropertySelector, _ value: T,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
  ) throws {
    var property = address(selector, scope: scope)
    var value = value
    let status = withUnsafePointer(to: &value) {
      AudioObjectSetPropertyData(id, &property, 0, nil, UInt32(MemoryLayout<T>.size), $0)
    }
    guard status == noErr else { throw DeviceError.operationFailed("Audio change", status) }
  }
}
