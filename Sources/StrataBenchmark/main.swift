import Darwin
import Foundation
import StrataCore
import StrataSystem

private struct Timing: Encodable, Sendable {
  let name: String
  let iterations: Int
  let medianMilliseconds: Double
  let p95Milliseconds: Double
  let maximumMilliseconds: Double
  let cpuMillisecondsPerIteration: Double
}
private struct CancellationMeasurement: Encodable, Sendable {
  let openDescriptors: Int
  let canceledDuringScan: Bool
  let millisecondsAfterCancellation: Double
}
private struct BenchmarkReport: Encodable {
  let capturedAt: Date
  let system: String
  let logicalCores: Int
  let scope =
    "Collection and listener lifecycle timing; excludes UI rendering, animation, and ordinary sampling intervals."
  let processCount: Int
  let bluetoothObservationScope: String
  let deviceEventRegistrationFailures: [DeviceEventFailure]
  let deviceEventObservationScope: String
  let timings: [Timing]
  let cancellation: CancellationMeasurement
}

@main private struct StrataBenchmark {
  static func main() async throws {
    let collector = SystemCollector()
    let inventory = await ProcessInventoryCollector().inventory()
    guard !inventory.summary.failed,
      let own = inventory.processes.first(where: { $0.id.pid == getpid() })
    else {
      throw CocoaError(.featureUnsupported)
    }
    let resources = ResourceCollector()
    let details = ProcessDetailsCollector()
    let bluetooth = BluetoothCollector()
    let devices = DeviceCollector()
    let displays = DisplayService()
    let deviceEvents = DeviceEventSource(workspaceCenter: NotificationCenter())
    let bluetoothBaseline = await bluetooth.snapshot()
    var timings: [Timing] = []
    timings.append(
      try await measure("aggregate", count: 30) {
        _ = await collector.sample(includeProcesses: false)
      })
    timings.append(
      try await measure("aggregate-and-processes", count: 30) {
        _ = await collector.sample(includeProcesses: true)
      })
    timings.append(
      try await measure("own-process-details", count: 10) { _ = try await details.inspect(own) })
    timings.append(
      try await measure("bluetooth-observation", count: 30) { _ = await bluetooth.snapshot() })
    timings.append(
      try await measure("device-observation", count: 30) { _ = await devices.sample() })
    timings.append(
      try await measure("display-catalog-read-only", count: 30) { _ = try await displays.catalog() }
    )
    let observedAudio = await devices.sample().audio.outputIdentity
    timings.append(
      try await measure("device-event-register-and-cancel", count: 30) {
        let observation = await deviceEvents.start()
        await deviceEvents.observeAudioOutput(
          observedAudio, at: ProcessInfo.processInfo.systemUptime, observationID: observation.id)
        await deviceEvents.stop(observationID: observation.id)
      })
    timings.append(
      try await measure("global-sockets", count: 3) {
        _ = try await resources.inspect(inventory.processes, socketsOnly: true)
      })
    timings.append(
      try await measure("global-resources", count: 3) {
        _ = try await resources.inspect(inventory.processes)
      })
    let report = BenchmarkReport(
      capturedAt: Date(), system: ProcessInfo.processInfo.operatingSystemVersionString,
      logicalCores: ProcessInfo.processInfo.activeProcessorCount,
      processCount: inventory.processes.count,
      bluetoothObservationScope: bluetoothBaseline.access == .allowed
        ? "Initially authorized: controller state, plus paired-device queries only when powered on. No connection changes."
        : "Authorization status only: device queries skipped. No access request or connection changes.",
      deviceEventRegistrationFailures: await deviceEvents.failures,
      deviceEventObservationScope: observedAudio == nil
        ? "Shared notifications only: no identified current audio output. No hardware changes."
        : "Shared notifications and identified output properties. No audio, power or display changes.",
      timings: timings, cancellation: try await cancellationMeasurement(own))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(report)
    if CommandLine.arguments.count == 2 {
      try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
    }
    print(String(decoding: data, as: UTF8.self))
  }
  private static func measure(
    _ name: String, count: Int, operation: @Sendable () async throws -> Void
  ) async throws -> Timing {
    // Warm framework initialization separately from steady collection work.
    try await operation()
    var milliseconds: [Double] = []
    let initialCPU = try cpuMilliseconds()
    for _ in 0..<count {
      let started = ProcessInfo.processInfo.systemUptime
      try await operation()
      milliseconds.append((ProcessInfo.processInfo.systemUptime - started) * 1000)
    }
    let cpu = try (cpuMilliseconds() - initialCPU) / Double(count)
    milliseconds.sort()
    return Timing(
      name: name, iterations: count, medianMilliseconds: milliseconds[count / 2],
      p95Milliseconds: milliseconds[min(count - 1, Int(ceil(Double(count) * 0.95)) - 1)],
      maximumMilliseconds: milliseconds[count - 1], cpuMillisecondsPerIteration: cpu)
  }
  private static func cpuMilliseconds() throws -> Double {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) * 1000
      + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1000
  }
  private static func cancellationMeasurement(_ own: ProcessSample) async throws
    -> CancellationMeasurement
  {
    var descriptors: [Int32] = []
    defer { for descriptor in descriptors { close(descriptor) } }
    for _ in 0..<4000 {
      let descriptor = open("/dev/null", O_RDONLY)
      guard descriptor >= 0 else { break }
      descriptors.append(descriptor)
    }
    let task = Task { try await ResourceCollector().inspect([own]) }
    try await Task.sleep(for: .milliseconds(2))
    let started = ProcessInfo.processInfo.systemUptime
    task.cancel()
    var canceled = false
    do { _ = try await task.value } catch is CancellationError { canceled = true }
    return CancellationMeasurement(
      openDescriptors: descriptors.count, canceledDuringScan: canceled,
      millisecondsAfterCancellation: (ProcessInfo.processInfo.systemUptime - started) * 1000)
  }
}
