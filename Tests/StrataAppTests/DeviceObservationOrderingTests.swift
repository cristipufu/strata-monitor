import Foundation
import StrataCore
import Testing

@testable import StrataBar
@testable import StrataSystem

private actor ReorderedDevices: DeviceControlling {
  private var pending: [Int: CheckedContinuation<DeviceSnapshot, Never>] = [:]
  private(set) var reads = 0
  func sample() async -> DeviceSnapshot {
    reads += 1
    let index = reads
    return await withCheckedContinuation { pending[index] = $0 }
  }
  func finish(_ index: Int, muted: Bool, uptime: TimeInterval) {
    pending.removeValue(forKey: index)?.resume(
      returning: DeviceSnapshot(
        battery: .absent,
        audio: AudioState(
          outputs: [], volume: 0.5, muted: muted, canSetVolume: true, canSetMute: true),
        wifi: WiFiState(powered: false, ssid: nil, rssi: nil, interface: nil), volumes: [],
        lowPowerMode: false, observationUptime: uptime))
  }
  func setMuted(_ muted: Bool, on output: AudioOutputIdentity) {}
  func setVolume(_ value: Double, on output: AudioOutputIdentity) {}
  func selectOutput(_ output: AudioOutputIdentity) {}
  func setWiFiPower(_ powered: Bool) {}
}

private actor RepeatingSystemSampler: SystemSampling {
  private(set) var reads = 0
  func reset() {}
  func sample(includeProcesses: Bool, includeGPU: Bool) -> SystemSample {
    reads += 1
    return SystemSample(
      uptime: Double(reads), cpu: 0.25, cores: [0.25], memory: nil,
      network: nil, interfaces: [], processes: [])
  }
}

@Test @MainActor func systemSamplingContinuesWhileDeviceCollectionIsWaiting() async throws {
  let sampler = RepeatingSystemSampler()
  let devices = ReorderedDevices()
  let model = AppModel(collector: sampler, deviceCollector: devices, persistsPreferences: false)
  model.start()
  try await waitUntil { await devices.reads == 1 }
  try await waitUntil { model.history.points.count >= 2 }
  #expect(await sampler.reads >= 2)
  model.stop()
  await devices.finish(1, muted: false, uptime: 10)
}

@Test @MainActor func monitoringTasksDoNotRetainAnOwnerWaitingOnCollectors() async throws {
  let sampler = GatedSampler()
  let devices = ReorderedDevices()
  var model: AppModel? = AppModel(
    collector: sampler, deviceCollector: devices, persistsPreferences: false)
  weak let owner = model
  model?.start()
  try await waitUntil {
    let systemReads = await sampler.requests.count
    let deviceReads = await devices.reads
    return systemReads == 1 && deviceReads == 1
  }
  model = nil
  #expect(owner == nil)
  await sampler.complete()
  await devices.finish(1, muted: false, uptime: 10)
}

@Test @MainActor func anOlderBackgroundDeviceReadingCannotUndoANewerControlResultOrInventAMoment()
  async throws
{
  let sampler = GatedSampler()
  let devices = ReorderedDevices()
  let model = AppModel(collector: sampler, deviceCollector: devices, persistsPreferences: false)
  model.start()
  defer { model.stop() }
  try await waitUntil { await sampler.requests.count == 1 }
  await sampler.complete()
  try await waitUntil { await devices.reads == 1 }
  model.setMuted(true, on: audioOutputFixture)
  try await waitUntil { await devices.reads == 2 }
  await devices.finish(2, muted: true, uptime: 20)
  try await waitUntil { model.devices?.audio.muted == true }
  await devices.finish(1, muted: false, uptime: 10)
  for _ in 0..<10 { await Task.yield() }
  #expect(model.devices?.audio.muted == true)
  #expect(model.moment == nil)
}
