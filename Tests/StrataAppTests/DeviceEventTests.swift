import Foundation
import Testing

@testable import StrataBar
@testable import StrataSystem

private actor EventDevices: DeviceControlling {
  private var pending: [Int: CheckedContinuation<DeviceSnapshot, Never>] = [:]
  private(set) var reads = 0
  func sample() async -> DeviceSnapshot {
    reads += 1
    let index = reads
    return await withCheckedContinuation { pending[index] = $0 }
  }
  func finish(_ index: Int, muted: Bool = false, uptime: Double? = nil) {
    pending.removeValue(forKey: index)?.resume(
      returning: DeviceSnapshot(
        battery: .absent,
        audio: AudioState(
          outputs: [
            AudioOutput(
              objectID: 42, name: "Speaker", isDefault: true, uniqueID: "StrataAudioFixture")
          ],
          volume: 0.5, muted: muted, canSetVolume: true, canSetMute: true),
        wifi: WiFiState(powered: false, ssid: nil, rssi: nil, interface: nil), volumes: [],
        lowPowerMode: false,
        observationUptime: uptime ?? Double(index)))
  }
  func setVolume(_ value: Double, on output: AudioOutputIdentity) {}
  func setMuted(_ muted: Bool, on output: AudioOutputIdentity) {}
  func selectOutput(_ output: AudioOutputIdentity) {}
  func setWiFiPower(_ powered: Bool) {}
}

private actor EventSourceFixture: DeviceEventObserving {
  private var continuations: [UUID: AsyncStream<Void>.Continuation] = [:]
  private var pending:
    [UUID: (DeviceEventObservation, CheckedContinuation<DeviceEventObservation, Never>)] = [:]
  private let delaysStart: Bool
  private(set) var starts: [UUID] = []
  private(set) var stops: [UUID] = []
  private(set) var boundOutputs: [AudioOutputIdentity?] = []
  init(delaysStart: Bool = false) { self.delaysStart = delaysStart }
  func start() async -> DeviceEventObservation {
    let id = UUID()
    let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    continuations[id] = continuation
    starts.append(id)
    let observation = DeviceEventObservation(id: id, events: stream)
    if delaysStart {
      return await withCheckedContinuation { pending[id] = (observation, $0) }
    }
    return observation
  }
  func finishStart(_ id: UUID) {
    guard let (observation, continuation) = pending.removeValue(forKey: id) else { return }
    continuation.resume(returning: observation)
  }
  func observeAudioOutput(
    _ output: AudioOutputIdentity?, at uptime: TimeInterval, observationID: UUID
  ) {
    if continuations[observationID] != nil && !Task.isCancelled { boundOutputs.append(output) }
  }
  func stop(observationID: UUID) {
    stops.append(observationID)
    continuations.removeValue(forKey: observationID)?.finish()
  }
  func emit(count: Int = 1, observationID: UUID? = nil) {
    guard let id = observationID ?? starts.last, let continuation = continuations[id] else {
      return
    }
    for _ in 0..<count { continuation.yield(()) }
  }
}

@Test @MainActor
func deviceEventRefreshCoalescesBurstsAndRetainsOneTrailingRefreshDuringCollection() async throws {
  let devices = EventDevices()
  var deliveries: [Double] = []
  let refresh = DeviceEventRefresh(collector: devices, coalescingDelay: .milliseconds(30)) {
    deliveries.append($0.observationUptime)
  }
  defer { refresh.stop() }
  for _ in 0..<1_000 { refresh.request() }
  try await waitUntil { await devices.reads == 1 }
  for _ in 0..<1_000 { refresh.request() }
  #expect(await devices.reads == 1)
  await devices.finish(1)
  try await waitUntil { await devices.reads == 2 }
  await devices.finish(2)
  try await waitUntil { deliveries.count == 2 }
  try await Task.sleep(for: .milliseconds(100))
  #expect(await devices.reads == 2)
  #expect(deliveries == [1, 2])
}

@Test @MainActor func deviceEventRefreshStopRejectsLateSamplesAndPendingTimers() async throws {
  let devices = EventDevices()
  var deliveries = 0
  let refresh = DeviceEventRefresh(collector: devices, coalescingDelay: .milliseconds(10)) { _ in
    deliveries += 1
  }
  refresh.request()
  try await waitUntil { await devices.reads == 1 }
  refresh.stop()
  refresh.request()
  await devices.finish(1)
  try await Task.sleep(for: .milliseconds(30))
  #expect(deliveries == 0)
  #expect(await devices.reads == 1)
  let pending = DeviceEventRefresh(collector: devices) { _ in deliveries += 1 }
  pending.request()
  pending.stop()
  try await Task.sleep(for: .milliseconds(150))
  #expect(await devices.reads == 1)
}

@Test @MainActor func deviceEventRefreshDoesNotRetainItsOwnerAcrossCollection() async throws {
  let devices = EventDevices()
  var refresh: DeviceEventRefresh? = DeviceEventRefresh(collector: devices, coalescingDelay: .zero)
  { _ in Issue.record("A released owner cannot deliver") }
  weak let owner = refresh
  refresh?.request()
  try await waitUntil { await devices.reads == 1 }
  refresh = nil
  #expect(owner == nil)
  await devices.finish(1)
}

@Test @MainActor func deviceEventsRefreshTheModelAndMomentsWithoutWaitingForThePollingFallback()
  async throws
{
  let sampler = GatedSampler()
  let devices = EventDevices()
  let events = EventSourceFixture()
  let model = AppModel(
    collector: sampler, deviceCollector: devices, deviceEvents: events, persistsPreferences: false)
  model.start()
  defer { model.stop() }
  try await waitUntil { await sampler.requests.count == 1 }
  await sampler.complete()
  try await waitUntil { await devices.reads == 1 }
  await devices.finish(1)
  try await waitUntil { model.devices != nil }
  try await waitUntil { await events.boundOutputs.contains(audioOutputFixture) }
  await events.emit(count: 1_000)
  try await waitUntil { await devices.reads == 2 }
  await devices.finish(2, muted: true)
  try await waitUntil { model.moment?.title == "Muted" }
  #expect(model.devices?.audio.muted == true)
  model.stop()
  try await waitUntil { await events.stops.count == 1 }
  await events.emit(count: 10)
  try await Task.sleep(for: .milliseconds(150))
  #expect(await devices.reads == 2)
}

@Test @MainActor func stoppedDeviceEventStartupCannotCloseANewerObservationWhenItFinishesLate()
  async throws
{
  let sampler = GatedSampler()
  let devices = EventDevices()
  let events = EventSourceFixture(delaysStart: true)
  let model = AppModel(
    collector: sampler, deviceCollector: devices, deviceEvents: events, persistsPreferences: false)
  model.start()
  try await waitUntil { await events.starts.count == 1 }
  try await waitUntil { await sampler.requests.count == 1 }
  try await waitUntil { await devices.reads == 1 }
  await sampler.complete()
  model.stop()
  await devices.finish(1)
  model.start()
  try await waitUntil { await events.starts.count == 2 }
  let ids = await events.starts
  await events.finishStart(ids[1])
  await events.finishStart(ids[0])
  try await waitUntil { await events.stops.contains(ids[0]) }
  #expect(!(await events.stops.contains(ids[1])))
  model.stop()
  try await waitUntil { await events.stops.contains(ids[1]) }
  await sampler.complete()
  await devices.finish(2)
}

@Test @MainActor func deviceEventObservationDoesNotRetainItsAppModelWhileWaiting() async throws {
  let sampler = GatedSampler()
  let devices = EventDevices()
  let events = EventSourceFixture()
  var model: AppModel? = AppModel(
    collector: sampler, deviceCollector: devices, deviceEvents: events, persistsPreferences: false)
  weak let owner = model
  model?.start()
  try await waitUntil { await events.starts.count == 1 }
  try await waitUntil { await sampler.requests.count == 1 }
  try await waitUntil { await devices.reads == 1 }
  model = nil
  #expect(owner == nil)
  try await waitUntil { await events.stops.count == 1 }
  await sampler.complete()
  await devices.finish(1)
}

private actor UnavailableDeviceEvents: DeviceEventObserving {
  func start() -> DeviceEventObservation {
    let (stream, continuation) = AsyncStream<Void>.makeStream()
    continuation.finish()
    return DeviceEventObservation(id: UUID(), events: stream)
  }
  func observeAudioOutput(
    _ output: AudioOutputIdentity?, at uptime: TimeInterval, observationID: UUID
  ) {}
  func stop(observationID: UUID) {}
}

@Test @MainActor func deviceEventsEndingDoesNotStopTheRealSixSecondPollingFallback() async throws {
  let sampler = GatedSampler()
  let devices = EventDevices()
  let model = AppModel(
    collector: sampler, deviceCollector: devices, deviceEvents: UnavailableDeviceEvents(),
    persistsPreferences: false)
  model.start()
  defer { model.stop() }
  try await waitUntil { await sampler.requests.count == 1 }
  await sampler.complete()
  try await waitUntil { await devices.reads == 1 }
  await devices.finish(1)
  try await waitUntil { model.devices != nil }
  try await Task.sleep(for: .milliseconds(6_200))
  try await waitUntil { await devices.reads == 2 }
  await devices.finish(2)
  try await waitUntil { model.devices?.observationUptime == 2 }
  model.stop()
  await sampler.complete()
}
