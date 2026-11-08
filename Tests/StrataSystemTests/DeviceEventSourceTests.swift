import Foundation
import Synchronization
import Testing

@testable import StrataSystem

private final class EventRegistrarFixture: DeviceEventRegistering, Sendable {
  struct Entry: Sendable {
    let channel: DeviceEventChannel
    let changed: @Sendable () -> Void
    var canceled = false
  }
  struct State: Sendable {
    var entries: [Entry] = []
    var failedChannels: Set<DeviceEventChannel> = []
    var cancelOnChannels: Set<DeviceEventChannel> = []
    var failsRemoval = false
  }
  let state = Mutex(State())
  let cancelsDuringFirstRegistration: Bool
  init(cancelsDuringFirstRegistration: Bool = false) {
    self.cancelsDuringFirstRegistration = cancelsDuringFirstRegistration
  }
  var entries: [Entry] { state.withLock { $0.entries } }
  var activeChannels: [DeviceEventChannel] { entries.filter { !$0.canceled }.map(\.channel) }
  func register(_ channel: DeviceEventChannel, change: @escaping @Sendable () -> Void) throws
    -> any DeviceEventRegistration
  {
    let (index, cancelCurrentTask) = try state.withLock { state in
      if state.failedChannels.contains(channel) {
        throw DeviceEventFailure(
          channel: String(describing: channel), operation: "register", status: -77)
      }
      state.entries.append(Entry(channel: channel, changed: change))
      return (state.entries.count - 1, state.cancelOnChannels.remove(channel) != nil)
    }
    if cancelCurrentTask || (cancelsDuringFirstRegistration && index == 0) {
      withUnsafeCurrentTask { $0?.cancel() }
    }
    return Registration(owner: self, index: index)
  }
  func fire(_ index: Int) { entries[index].changed() }
  private func cancel(_ index: Int) -> DeviceEventFailure? {
    state.withLock { state in
      guard !state.entries[index].canceled else { return nil }
      state.entries[index].canceled = true
      return state.failsRemoval
        ? DeviceEventFailure(
          channel: String(describing: state.entries[index].channel), operation: "remove",
          status: -78) : nil
    }
  }
  private final class Registration: DeviceEventRegistration, Sendable {
    let owner: EventRegistrarFixture
    let index: Int
    init(owner: EventRegistrarFixture, index: Int) {
      self.owner = owner
      self.index = index
    }
    func cancel() -> DeviceEventFailure? { owner.cancel(index) }
    deinit { _ = cancel() }
  }
}

@Test func deviceEventsHaveOneBoundedStreamAndScopeLateCleanupToTheOldObservation() async {
  let backend = EventRegistrarFixture()
  let source = DeviceEventSource(backend: backend)
  let first = await source.start()
  #expect(Set(backend.activeChannels) == Set(DeviceEventChannel.shared))
  let second = await source.start()
  await source.stop(observationID: first.id)
  #expect(backend.activeChannels.count == DeviceEventChannel.shared.count)
  backend.fire(0)
  var oldEvents = first.events.makeAsyncIterator()
  let old: Void? = await oldEvents.next()
  #expect(old == nil)
  let index = backend.entries.count - 1
  for _ in 0..<1_000 { backend.fire(index) }
  await source.stop(observationID: second.id)
  var events = second.events.makeAsyncIterator()
  let one: Void? = await events.next()
  let end: Void? = await events.next()
  #expect(one != nil && end == nil)
  #expect(backend.activeChannels.isEmpty)
}

@Test func deviceEventAudioBindingsRejectStaleSnapshotsAndRebindReusedObjectIDs() async {
  let backend = EventRegistrarFixture()
  let source = DeviceEventSource(backend: backend)
  let observation = await source.start()
  let first = AudioOutputIdentity(objectID: 10, uniqueID: "Speaker")
  let other = AudioOutputIdentity(objectID: 20, uniqueID: "Headphones")
  await source.observeAudioOutput(first, at: 10, observationID: observation.id)
  #expect(
    Set(backend.activeChannels)
      == Set(DeviceEventChannel.shared + DeviceEventChannel.audio(for: 10)))
  let originalCount = backend.entries.count
  await source.observeAudioOutput(first, at: 30, observationID: observation.id)
  await source.observeAudioOutput(other, at: 20, observationID: observation.id)
  #expect(backend.entries.count == originalCount)
  await source.observeAudioOutput(
    AudioOutputIdentity(objectID: 10, uniqueID: "Replacement"), at: 40,
    observationID: observation.id)
  #expect(backend.entries.count == originalCount + 4)
  #expect(backend.entries[originalCount - 4..<originalCount].allSatisfy { $0.canceled })
  await source.observeAudioOutput(nil, at: 50, observationID: observation.id)
  #expect(Set(backend.activeChannels) == Set(DeviceEventChannel.shared))
  await source.stop(observationID: observation.id)
}

@Test func deviceEventBindingsRequireCurrentObservationAndValidCollectionTime() async {
  let backend = EventRegistrarFixture()
  let source = DeviceEventSource(backend: backend)
  let old = await source.start()
  let current = await source.start()
  let output = AudioOutputIdentity(objectID: 10, uniqueID: "Speaker")
  await source.observeAudioOutput(output, at: 10, observationID: old.id)
  for uptime in [Double.nan, .infinity, -1] {
    await source.observeAudioOutput(output, at: uptime, observationID: current.id)
  }
  #expect(Set(backend.activeChannels) == Set(DeviceEventChannel.shared))
  await source.stop(observationID: current.id)
}

@Test func deviceEventRegistrationFailuresKeepOtherChannelsUsableAndReportTeardownFailure() async {
  let backend = EventRegistrarFixture()
  backend.state.withLock {
    $0.failedChannels = [.power, .audioVolume(10)]
    $0.failsRemoval = true
  }
  let source = DeviceEventSource(backend: backend)
  let observation = await source.start()
  await source.observeAudioOutput(
    AudioOutputIdentity(objectID: 10, uniqueID: "Speaker"), at: 10, observationID: observation.id)
  #expect(backend.activeChannels.count == DeviceEventChannel.shared.count + 2)
  let failures = await source.failures
  #expect(failures.count == 2 && failures.allSatisfy { $0.operation == "register" })
  backend.fire(0)
  var events = observation.events.makeAsyncIterator()
  let event: Void? = await events.next()
  #expect(event != nil)
  await source.stop(observationID: observation.id)
  #expect(await source.failures.contains { $0.operation == "remove" })
}

@Test @MainActor func canceledDeviceEventStartupCannotStopTheCurrentObservation() async {
  let backend = EventRegistrarFixture()
  let source = DeviceEventSource(backend: backend)
  let current = await source.start()
  let canceled = Task { @MainActor in await source.start() }
  canceled.cancel()
  let obsolete = await canceled.value
  await source.stop(observationID: obsolete.id)
  #expect(
    backend.entries.count == DeviceEventChannel.shared.count && !backend.activeChannels.isEmpty)
  await source.stop(observationID: current.id)
}

@Test func deviceEventCancellationDuringRegistrationReleasesPartialResources() async {
  let backend = EventRegistrarFixture(cancelsDuringFirstRegistration: true)
  let source = DeviceEventSource(backend: backend)
  let task = Task { await source.start() }
  let canceled = await task.value
  #expect(backend.entries.count == 1 && backend.activeChannels.isEmpty)
  var events = canceled.events.makeAsyncIterator()
  let end: Void? = await events.next()
  #expect(end == nil)
}

@Test func deviceEventOwnerReleaseRemovesItsNativeRegistrations() async throws {
  let backend = EventRegistrarFixture()
  var source: DeviceEventSource? = DeviceEventSource(backend: backend)
  let started = await source?.start()
  let observation = try #require(started)
  weak let owner = source
  source = nil
  #expect(owner == nil && backend.activeChannels.isEmpty)
  var events = observation.events.makeAsyncIterator()
  let end: Void? = await events.next()
  #expect(end == nil)
}

@Test func deviceEventCanceledPartialAudioBindingCanRecoverForTheSameSnapshot() async {
  let backend = EventRegistrarFixture()
  let source = DeviceEventSource(backend: backend)
  let observation = await source.start()
  backend.state.withLock { $0.cancelOnChannels = [.audioVolume(10)] }
  let output = AudioOutputIdentity(objectID: 10, uniqueID: "Speaker")
  let canceled = Task {
    await source.observeAudioOutput(output, at: 10, observationID: observation.id)
  }
  await canceled.value
  #expect(Set(backend.activeChannels) == Set(DeviceEventChannel.shared))
  await source.observeAudioOutput(output, at: 10, observationID: observation.id)
  #expect(
    Set(backend.activeChannels)
      == Set(DeviceEventChannel.shared + DeviceEventChannel.audio(for: 10)))
  await source.stop(observationID: observation.id)
}

@Test func deviceEventDiagnosticsRemainBoundedAcrossManyUnsupportedOutputs() async {
  let backend = EventRegistrarFixture()
  let source = DeviceEventSource(backend: backend)
  let observation = await source.start()
  for id in 1...40 {
    _ = backend.state.withLock { $0.failedChannels.insert(.audioVolume(UInt32(id))) }
    await source.observeAudioOutput(
      AudioOutputIdentity(objectID: UInt32(id), uniqueID: "Output"), at: Double(id),
      observationID: observation.id)
  }
  #expect(await source.failures.count == 32)
  await source.stop(observationID: observation.id)
}
