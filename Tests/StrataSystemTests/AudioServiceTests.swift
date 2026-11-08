import Foundation
import Testing

@testable import StrataSystem

private enum AudioWrite: Equatable {
  case volume(Double, UInt32)
  case mute(Bool, UInt32)
  case output(UInt32)
}
private final class AudioHardwareFixture: AudioHardware {
  let original = AudioOutputIdentity(objectID: 10, uniqueID: "OriginalSpeaker")
  let alternative = AudioOutputIdentity(objectID: 20, uniqueID: "Headphones")
  var ids: [UInt32]? = [10, 20]
  var selected: UInt32? = 10
  var descriptions: [UInt32: AudioOutput] = [
    10: AudioOutput(objectID: 10, name: "Speaker", isDefault: false, uniqueID: "OriginalSpeaker"),
    20: AudioOutput(objectID: 20, name: "Headphones", isDefault: false, uniqueID: "Headphones"),
  ]
  var readings = AudioControls(volume: 0.5, muted: false, canSetVolume: true, canSetMute: true)
  var duringControls: (() -> Void)?
  var failsWrites = false
  private(set) var writes: [AudioWrite] = []
  private(set) var descriptionsRead = 0
  func deviceIDs() -> [UInt32]? { ids }
  func defaultOutput() -> AudioOutputSelection {
    guard let selected else { return .unavailable }
    return selected == 0 ? .none : .device(selected)
  }
  func describeOutput(_ id: UInt32) -> AudioOutput? {
    descriptionsRead += 1
    return descriptions[id]
  }
  func controls(for id: UInt32) -> AudioControls {
    let result = readings
    duringControls?()
    return result
  }
  func setVolume(_ value: Double, on id: UInt32) throws { try write(.volume(value, id)) }
  func setMuted(_ muted: Bool, on id: UInt32) throws { try write(.mute(muted, id)) }
  func selectOutput(_ id: UInt32) throws { try write(.output(id)) }
  private func write(_ write: AudioWrite) throws {
    if failsWrites { throw DeviceError.operationFailed("Fixture audio change", -1) }
    writes.append(write)
  }
}

@Test func audioOutputRowsChangeIdentityForReplacementHardwareWhileNamesAndSelectionCanChange()
  throws
{
  let hardware = AudioHardwareFixture()
  let original = try #require(hardware.descriptions[10])
  var replacement = original
  replacement.uniqueID = "Replacement"
  #expect(replacement.id != original.id && replacement.identity != original.identity)
  var selected = original
  selected.isDefault = true
  #expect(selected.id == original.id)
  let renamed = AudioOutput(
    objectID: 10, name: "New name", isDefault: false, uniqueID: "OriginalSpeaker")
  #expect(renamed.id == original.id)
  var unidentified = original
  unidentified.uniqueID = nil
  #expect(unidentified.identity == nil && unidentified.id != original.id)
}

@Test func audioMutationsRemainBoundToTheObservedOutput() throws {
  let hardware = AudioHardwareFixture()
  let service = AudioService(hardware: hardware)
  let snapshot = service.snapshot()
  let selected = try #require(snapshot.outputIdentity)
  #expect(selected == hardware.original)
  try service.setVolume(0.25, on: selected)
  try service.setMuted(true, on: selected)
  try service.selectOutput(hardware.alternative)
  #expect(hardware.writes == [.volume(0.25, 10), .mute(true, 10), .output(20)])
}

@Test func audioDefaultChangesNeverRedirectAVolumeOrMuteCommand() {
  let hardware = AudioHardwareFixture()
  let service = AudioService(hardware: hardware)
  hardware.selected = hardware.alternative.objectID
  #expect(throws: DeviceError.self) { try service.setVolume(1, on: hardware.original) }
  #expect(throws: DeviceError.self) { try service.setMuted(true, on: hardware.original) }
  #expect(hardware.writes.isEmpty)
}

@Test func audioNumericIDReuseAndDisconnectionCannotSelectOrControlAReplacement() {
  let hardware = AudioHardwareFixture()
  let service = AudioService(hardware: hardware)
  hardware.descriptions[10]?.uniqueID = "Replacement"
  #expect(throws: DeviceError.self) { try service.setVolume(1, on: hardware.original) }
  #expect(throws: DeviceError.self) { try service.setMuted(true, on: hardware.original) }
  #expect(throws: DeviceError.self) { try service.selectOutput(hardware.original) }
  hardware.descriptions.removeValue(forKey: 20)
  #expect(throws: DeviceError.self) { try service.selectOutput(hardware.alternative) }
  #expect(hardware.writes.isEmpty)
}

@Test(arguments: [false, true]) func audioRevalidatesAfterQueryingControlCapabilities(
  _ reuseID: Bool
) {
  let hardware = AudioHardwareFixture()
  let service = AudioService(hardware: hardware)
  hardware.duringControls = { [weak hardware] in
    guard let hardware else { return }
    if reuseID {
      hardware.descriptions[10]?.uniqueID = "Replacement"
    } else {
      hardware.selected = 20
    }
  }
  #expect(throws: DeviceError.self) { try service.setVolume(0.75, on: hardware.original) }
  #expect(hardware.writes.isEmpty)
}

@Test func audioUnsupportedControlsAndNativeErrorsAreReportedWithoutFallback() {
  let hardware = AudioHardwareFixture()
  let service = AudioService(hardware: hardware)
  hardware.readings = AudioControls(volume: nil, muted: nil, canSetVolume: false, canSetMute: false)
  #expect(throws: DeviceError.self) { try service.setVolume(0.75, on: hardware.original) }
  #expect(throws: DeviceError.self) { try service.setMuted(true, on: hardware.original) }
  hardware.failsWrites = true
  #expect(throws: DeviceError.self) { try service.selectOutput(hardware.alternative) }
  hardware.readings = AudioControls(volume: 0.5, muted: false, canSetVolume: true, canSetMute: true)
  #expect(throws: DeviceError.self) { try service.setVolume(0.75, on: hardware.original) }
  #expect(throws: DeviceError.self) { try service.setMuted(true, on: hardware.original) }
  #expect(hardware.writes.isEmpty)
}

@Test func audioVolumeInputsMustBeFiniteAndAreBoundedBeforeWriting() throws {
  let hardware = AudioHardwareFixture()
  let service = AudioService(hardware: hardware)
  for value in [Double.nan, .infinity, -.infinity] {
    #expect(throws: DeviceError.self) { try service.setVolume(value, on: hardware.original) }
  }
  #expect(hardware.descriptionsRead == 0)
  try service.setVolume(-1, on: hardware.original)
  try service.setVolume(2, on: hardware.original)
  #expect(hardware.writes == [.volume(0, 10), .volume(1, 10)])
}

@Test @MainActor func canceledAudioCommandsDoNotQueryOrWriteHardware() async {
  let hardware = AudioHardwareFixture()
  let service = AudioService(hardware: hardware)
  for command in 0..<3 {
    let task = Task { @MainActor in
      switch command {
      case 0: try service.setVolume(1, on: hardware.original)
      case 1: try service.setMuted(true, on: hardware.original)
      default: try service.selectOutput(hardware.alternative)
      }
    }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
  }
  #expect(hardware.writes.isEmpty && hardware.descriptionsRead == 0)
}

@Test func audioEnumerationFailureAndMissingIdentityCannotEnableControlsOrInventAnOutputEvent() {
  let hardware = AudioHardwareFixture()
  let service = AudioService(hardware: hardware)
  hardware.ids = nil
  let failed = service.snapshot()
  #expect(failed.volume == nil && failed.muted == nil && !failed.canSetVolume && !failed.canSetMute)
  #expect(failed.observedOutputName == nil && failed.issue != nil)
  hardware.ids = [10]
  hardware.descriptions[10]?.uniqueID = nil
  let unidentified = service.snapshot()
  #expect(
    unidentified.outputIdentity == nil && !unidentified.canSetVolume && !unidentified.canSetMute)
  #expect(unidentified.volume == nil && unidentified.issue != nil)
  #expect(unidentified.observedOutputName == "Speaker")
}

@Test(arguments: [false, true]) func audioSnapshotCannotCombineAnOldVolumeWithANewDefault(
  _ reuseID: Bool
) {
  let hardware = AudioHardwareFixture()
  let service = AudioService(hardware: hardware)
  hardware.duringControls = { [weak hardware] in
    guard let hardware else { return }
    if reuseID {
      hardware.descriptions[10]?.uniqueID = "Replacement"
    } else {
      hardware.selected = 20
    }
  }
  let snapshot = service.snapshot()
  #expect(snapshot.outputIdentity == nil && snapshot.observedOutputName == nil)
  #expect(
    snapshot.volume == nil && snapshot.muted == nil && !snapshot.canSetVolume
      && !snapshot.canSetMute)
  #expect(snapshot.outputs.allSatisfy { !$0.isDefault })
}

@Test func audioMissingAndInvalidControlsStayUnavailableInsteadOfBecomingZero() {
  let hardware = AudioHardwareFixture()
  let service = AudioService(hardware: hardware)
  for volume in [Double?.none, Double.nan, Double.infinity, -0.1, 1.1] {
    hardware.readings = AudioControls(
      volume: volume, muted: nil, canSetVolume: true, canSetMute: true)
    let snapshot = service.snapshot()
    #expect(
      snapshot.volume == nil && snapshot.muted == nil && !snapshot.canSetVolume
        && !snapshot.canSetMute)
    #expect(snapshot.issue != nil && snapshot.outputIdentity == hardware.original)
  }
  hardware.selected = 0
  let empty = service.snapshot()
  #expect(empty.outputIdentity == nil && empty.observedOutputName == "No output device")
  #expect(!empty.canSetVolume && !empty.canSetMute)
  hardware.selected = nil
  let failed = service.snapshot()
  #expect(failed.outputIdentity == nil && failed.observedOutputName == nil && failed.issue != nil)
}

@Test func nativeAudioObservationRepeatedlyReadsOwnedStringsWithoutChangingHardware() {
  let service = AudioService()
  for _ in 0..<100 {
    let snapshot = service.snapshot()
    #expect(Set(snapshot.outputs.map(\.id)).count == snapshot.outputs.count)
    for output in snapshot.outputs { #expect(output.objectID != 0 && !output.name.isEmpty) }
    if let volume = snapshot.volume { #expect(volume.isFinite && (0...1).contains(volume)) }
    if snapshot.canSetVolume || snapshot.canSetMute { #expect(snapshot.outputIdentity != nil) }
  }
}
