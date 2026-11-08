import Foundation

public actor DeviceEventSource: DeviceEventObserving {
  private struct Observation: Sendable {
    let id: UUID
    let continuation: AsyncStream<Void>.Continuation
    var shared: [any DeviceEventRegistration]
    var audio: [any DeviceEventRegistration] = []
    var output: AudioOutputIdentity?
    var outputUptime: TimeInterval = -1
  }
  private let backend: any DeviceEventRegistering
  private var observation: Observation?
  public private(set) var failures: [DeviceEventFailure] = []
  private let maximumFailures = 32

  public init(workspaceCenter: NotificationCenter, defaultCenter: NotificationCenter = .default) {
    backend = NativeDeviceEventRegistrar(
      workspaceCenter: workspaceCenter, defaultCenter: defaultCenter)
  }
  init(backend: any DeviceEventRegistering) { self.backend = backend }

  public func start() -> DeviceEventObservation {
    let id = UUID()
    let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    guard !Task.isCancelled else {
      continuation.finish()
      return DeviceEventObservation(id: id, events: stream)
    }
    if let current = observation { stop(observationID: current.id) }
    continuation.onTermination = { [weak self] _ in
      Task { await self?.stop(observationID: id) }
    }
    let shared = register(DeviceEventChannel.shared, continuation: continuation)
    guard !Task.isCancelled else {
      continuation.finish()
      cancel(shared)
      return DeviceEventObservation(id: id, events: stream)
    }
    observation = Observation(id: id, continuation: continuation, shared: shared)
    return DeviceEventObservation(id: id, events: stream)
  }
  public func observeAudioOutput(
    _ output: AudioOutputIdentity?, at uptime: TimeInterval, observationID: UUID
  ) {
    guard !Task.isCancelled, uptime.isFinite, uptime >= 0,
      var current = observation, current.id == observationID, uptime > current.outputUptime
    else { return }
    if current.output != output {
      cancel(current.audio)
      current.audio = []
      current.output = output
      if let output, output.objectID != 0, !output.uniqueID.isEmpty {
        current.audio = register(
          DeviceEventChannel.audio(for: output.objectID), continuation: current.continuation)
      }
      if Task.isCancelled {
        cancel(current.audio)
        current.audio = []
        current.output = nil
        observation = current
        return
      }
    }
    current.outputUptime = uptime
    observation = current
  }
  public func stop(observationID: UUID) {
    guard let current = observation, current.id == observationID else { return }
    observation = nil
    current.continuation.finish()
    cancel(current.audio + current.shared)
  }
  private func register(
    _ channels: [DeviceEventChannel], continuation: AsyncStream<Void>.Continuation
  ) -> [any DeviceEventRegistration] {
    channels.compactMap { channel in
      guard !Task.isCancelled else { return nil }
      do {
        return try backend.register(channel) { continuation.yield(()) }
      } catch let failure as DeviceEventFailure {
        record(failure)
      } catch {
        record(
          DeviceEventFailure(
            channel: String(describing: channel), operation: "register", status: -1))
      }
      return nil
    }
  }
  private func cancel(_ registrations: [any DeviceEventRegistration]) {
    for registration in registrations {
      if let failure = registration.cancel() { record(failure) }
    }
  }
  private func record(_ failure: DeviceEventFailure) {
    guard !failures.contains(failure) else { return }
    failures.append(failure)
    if failures.count > maximumFailures { failures.removeFirst(failures.count - maximumFailures) }
  }
  deinit {
    observation?.continuation.finish()
    for registration in (observation?.audio ?? []) + (observation?.shared ?? []) {
      _ = registration.cancel()
    }
  }
}
