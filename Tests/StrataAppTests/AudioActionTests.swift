import Foundation
import StrataCore
import Testing

@testable import StrataBar
@testable import StrataSystem

@Test func volumeEditingCommitsOnceToTheOutputWhereItBegan() {
  var editing = VolumeEditingSession()
  editing.begin(on: audioOutputFixture)
  #expect(editing.isEditing)
  #expect(editing.finish(currentOutput: audioOutputFixture, isVisible: true) == audioOutputFixture)
  #expect(
    !editing.isEditing && editing.finish(currentOutput: audioOutputFixture, isVisible: true) == nil)
}

@Test func volumeEditingRejectsChangedMissingAndReusedOutputs() {
  let changed = AudioOutputIdentity(objectID: 7, uniqueID: "Other")
  let reused = AudioOutputIdentity(objectID: audioOutputFixture.objectID, uniqueID: "Other")
  let reconnected = AudioOutputIdentity(objectID: 7, uniqueID: audioOutputFixture.uniqueID)
  var editing = VolumeEditingSession()
  for output in [changed, reused, reconnected, nil] {
    editing.begin(on: audioOutputFixture)
    #expect(editing.finish(currentOutput: output, isVisible: true) == nil && !editing.isEditing)
  }
}

@Test func volumeEditingCannotCommitAfterPageClosureOrOutputChangeCancelsIt() {
  var editing = VolumeEditingSession()
  editing.begin(on: audioOutputFixture)
  editing.cancel()
  #expect(editing.finish(currentOutput: audioOutputFixture, isVisible: true) == nil)
  editing.begin(on: nil)
  #expect(!editing.isEditing && editing.finish(currentOutput: nil, isVisible: true) == nil)
  editing.begin(on: audioOutputFixture)
  #expect(editing.finish(currentOutput: audioOutputFixture, isVisible: true) == audioOutputFixture)
}

private enum SoundPageInterruption: CaseIterable, Sendable {
  case dismissed, navigated, stopped
}

@Test(arguments: SoundPageInterruption.allCases) @MainActor
private func volumeEditingRequiresTheSoundPageToBeActuallyVisibleAtCommit(
  _ reason: SoundPageInterruption
) {
  let model = AppModel(persistsPreferences: false)
  defer { model.stop() }
  var editing = VolumeEditingSession()
  model.page = .sound
  model.setDemand("explorer", active: true)
  #expect(!model.isReadingPageVisible(.sound))
  model.setDemand("popover", active: true)
  #expect(model.isReadingPageVisible(.sound))
  editing.begin(on: audioOutputFixture)
  switch reason {
  case .dismissed: model.setDemand("popover", active: false)
  case .navigated: model.page = .cpu
  case .stopped: model.stop()
  }
  #expect(
    editing.finish(
      currentOutput: audioOutputFixture, isVisible: model.isReadingPageVisible(.sound)) == nil)
  #expect(!editing.isEditing)
}

private enum AudioCommand: Equatable {
  case volume(Double, AudioOutputIdentity)
  case mute(Bool, AudioOutputIdentity)
  case output(AudioOutputIdentity)
}
private actor AudioActionsFixture: DeviceControlling {
  private var pending: [Int: CheckedContinuation<Void, Error>] = [:]
  private(set) var commands: [AudioCommand] = []
  private(set) var reads = 0
  func sample() -> DeviceSnapshot {
    reads += 1
    return DeviceSnapshot(
      battery: .absent,
      audio: AudioState(
        outputs: [
          AudioOutput(
            objectID: 42, name: "Speaker", isDefault: true, uniqueID: "StrataAudioFixture")
        ],
        volume: 0.5, muted: false, canSetVolume: true, canSetMute: true),
      wifi: WiFiState(powered: false, ssid: nil, rssi: nil, interface: nil), volumes: [],
      lowPowerMode: false)
  }
  func setVolume(_ value: Double, on output: AudioOutputIdentity) async throws {
    try await request(.volume(value, output))
  }
  func setMuted(_ muted: Bool, on output: AudioOutputIdentity) async throws {
    try await request(.mute(muted, output))
  }
  func selectOutput(_ output: AudioOutputIdentity) async throws {
    try await request(.output(output))
  }
  func setWiFiPower(_ powered: Bool) throws { throw DeviceError.unavailable("No Wi-Fi") }
  func finish(_ index: Int, fails: Bool = false) {
    if fails {
      pending.removeValue(forKey: index)?.resume(
        throwing: DeviceError.unavailable("Output changed"))
    } else {
      pending.removeValue(forKey: index)?.resume()
    }
  }
  private func request(_ command: AudioCommand) async throws {
    commands.append(command)
    let index = commands.count
    try await withCheckedThrowingContinuation { pending[index] = $0 }
  }
}

@Test @MainActor func audioActionsForwardTheExplicitlyObservedTarget() async throws {
  let devices = AudioActionsFixture()
  let model = AppModel(deviceCollector: devices, persistsPreferences: false)
  defer { model.stop() }
  let other = AudioOutputIdentity(objectID: 99, uniqueID: "Headphones")
  model.setVolume(0.25, on: audioOutputFixture)
  try await waitUntil { await devices.commands.count == 1 }
  model.setMuted(true, on: audioOutputFixture)
  try await waitUntil { await devices.commands.count == 2 }
  model.selectOutput(other)
  try await waitUntil { await devices.commands.count == 3 }
  #expect(
    await devices.commands == [
      .volume(0.25, audioOutputFixture), .mute(true, audioOutputFixture), .output(other),
    ])
  for index in 1...3 { await devices.finish(index) }
  try await waitUntil { await devices.reads == 3 }
  #expect(model.errorMessage == nil)
}

@Test @MainActor func anAudioActionDoesNotRetainItsOwnerOrPublishAfterDeallocation() async throws {
  let devices = AudioActionsFixture()
  var model: AppModel? = AppModel(deviceCollector: devices, persistsPreferences: false)
  weak let owner = model
  model?.setVolume(0.25, on: audioOutputFixture)
  try await waitUntil { await devices.commands.count == 1 }
  model = nil
  #expect(owner == nil)
  await devices.finish(1, fails: true)
  for _ in 0..<10 { await Task.yield() }
  #expect(await devices.reads == 0)
}

@Test @MainActor func failedAudioActionsRefreshTheCurrentOutputWhileStoppedActionsStayCanceled()
  async throws
{
  let devices = AudioActionsFixture()
  let model = AppModel(deviceCollector: devices, persistsPreferences: false)
  defer { model.stop() }
  model.setVolume(0.25, on: audioOutputFixture)
  try await waitUntil { await devices.commands.count == 1 }
  await devices.finish(1, fails: true)
  try await waitUntil { model.devices?.audio.outputIdentity == audioOutputFixture }
  #expect(model.errorMessage == "Output changed")
  #expect(await devices.reads == 1)
  model.setMuted(true, on: audioOutputFixture)
  try await waitUntil { await devices.commands.count == 2 }
  model.errorMessage = nil
  model.stop()
  await devices.finish(2, fails: true)
  for _ in 0..<10 { await Task.yield() }
  #expect(model.errorMessage == nil)
  #expect(await devices.reads == 1)
}
