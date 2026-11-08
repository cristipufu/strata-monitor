import AppKit
import CSystem
import Foundation
import Synchronization
import Testing

@testable import StrataSystem

@Test func nativeDeviceWorkspaceNotificationsCancelExactlyOnceAcrossConcurrentCallers() async throws
{
  let workspace = NotificationCenter()
  let backend = NativeDeviceEventRegistrar(
    workspaceCenter: workspace, defaultCenter: NotificationCenter())
  let count = Mutex(0)
  let registration = try backend.register(.volumeMounted) { count.withLock { $0 += 1 } }
  workspace.post(name: NSWorkspace.didMountNotification, object: nil)
  #expect(count.withLock { $0 } == 1)
  await withTaskGroup(of: Void.self) { group in
    for _ in 0..<32 { group.addTask { #expect(registration.cancel() == nil) } }
  }
  workspace.post(name: NSWorkspace.didMountNotification, object: nil)
  #expect(count.withLock { $0 } == 1)
}

@Test func nativeDeviceEventsRepeatedlyRegisterAndReleaseWithoutChangingHardware() async {
  let source = DeviceEventSource(
    workspaceCenter: NotificationCenter(), defaultCenter: NotificationCenter())
  let hardware = NativeAudioHardware()
  for _ in 0..<20 {
    let observation = await source.start()
    if case .device(let id) = hardware.defaultOutput(),
      let output = hardware.describeOutput(id)?.identity
    {
      await source.observeAudioOutput(
        output, at: ProcessInfo.processInfo.systemUptime, observationID: observation.id)
    }
    await source.stop(observationID: observation.id)
    var events = observation.events.makeAsyncIterator()
    // A final buffered wake-up is harmless; stop must close the bounded stream.
    _ = await events.next()
    let end: Void? = await events.next()
    #expect(end == nil)
  }
  let failures = await source.failures
  #expect(!failures.contains { $0.operation == "remove" })
}

private final class NotificationProbeState: Sendable {
  struct State: Sendable {
    var callbacks = 0
    var released = false
  }
  let value = Mutex(State())
}
private final class NotificationProbe: Sendable {
  let state: NotificationProbeState
  init(state: NotificationProbeState) { self.state = state }
  func receive() { state.value.withLock { $0.callbacks += 1 } }
  deinit { state.value.withLock { $0.released = true } }
}
private func registerPrivateDeviceNotification(
  _ name: String, state: NotificationProbeState, token: inout Int32
) -> UInt32 {
  let probe = NotificationProbe(state: state)
  return sb_observe_dispatch_notification(name, { probe.receive() }, &token)
}
private func postPrivateDeviceNotification(_ name: String) async throws {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/notifyutil")
  process.arguments = ["-p", name]
  let status = try await withCheckedThrowingContinuation {
    (continuation: CheckedContinuation<Int32, Error>) in
    process.terminationHandler = { process in
      continuation.resume(returning: process.terminationStatus)
    }
    do { try process.run() } catch {
      process.terminationHandler = nil
      continuation.resume(throwing: error)
    }
  }
  #expect(status == 0)
}
@Test func nativeDeviceNotificationBridgeOwnsAndReleasesItsEscapingCallback() async throws {
  let name = "dev.strata.bar.tests.\(UUID().uuidString)"
  let state = NotificationProbeState()
  var token: Int32 = 0
  let status = registerPrivateDeviceNotification(name, state: state, token: &token)
  try #require(status == 0)
  var active = true
  defer { if active { _ = sb_cancel_dispatch_notification(token) } }
  #expect(!state.value.withLock { $0.released })
  try await postPrivateDeviceNotification(name)
  let clock = ContinuousClock()
  let deliveryTimeout = Duration.seconds(10)
  let deadline = clock.now + deliveryTimeout
  while state.value.withLock({ $0.callbacks }) == 0 && clock.now < deadline {
    try await Task.sleep(for: .milliseconds(5))
  }
  try #require(state.value.withLock { $0.callbacks } == 1)
  let canceled = sb_cancel_dispatch_notification(token)
  active = false
  #expect(canceled == 0)
  let releaseDeadline = clock.now + deliveryTimeout
  while !state.value.withLock({ $0.released }) && clock.now < releaseDeadline {
    try await Task.sleep(for: .milliseconds(5))
  }
  #expect(state.value.withLock { $0.released })
  try await postPrivateDeviceNotification(name)
  try await Task.sleep(for: .milliseconds(30))
  #expect(state.value.withLock { $0.callbacks } == 1)
}

@Test func nativeDeviceNotificationBridgeRejectsMissingInputsWithoutReturningAnActiveToken() {
  var token: Int32 = 123
  #expect(sb_observe_dispatch_notification(nil, {}, &token) != 0 && token == -1)
  token = 123
  #expect(sb_observe_dispatch_notification("", {}, &token) != 0 && token == -1)
  token = 123
  #expect(
    sb_observe_dispatch_notification("dev.strata.bar.tests.invalid", nil, &token) != 0
      && token == -1)
  #expect(sb_observe_dispatch_notification("dev.strata.bar.tests.invalid", {}, nil) != 0)
  #expect(sb_cancel_dispatch_notification(-1) != 0)
}
