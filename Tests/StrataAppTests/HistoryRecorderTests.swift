import Foundation
import StrataCore
import Testing

@testable import StrataBar

private final class SteppingClock: @unchecked Sendable {
  private let lock = NSLock()
  private var current = Date(timeIntervalSince1970: 1_800_000_000)
  var now: Date { lock.withLock { current } }
  func advance(_ seconds: TimeInterval) { lock.withLock { current += seconds } }
}

private func reading(cpu: Double, processes: [ProcessSample] = []) -> SystemSample {
  SystemSample(
    uptime: 100, cpu: cpu, cores: [cpu], memory: nil, network: nil, interfaces: [],
    processes: processes, processScan: processes.isEmpty ? nil : ScanSummary())
}

@Test @MainActor func historyRecordsReadingsAndAsksForProcessesEveryInterval() async throws {
  let directory = FileManager.default.temporaryDirectory.appending(path: "StrataBar.History.\(UUID())")
  defer { try? FileManager.default.removeItem(at: directory) }
  let clock = SteppingClock()
  let recorder = HistoryRecorder(directory: directory, now: { clock.now })
  #expect(!recorder.isRecording && !recorder.wantsProcesses)
  recorder.apply(.day)
  #expect(recorder.isRecording && recorder.wantsProcesses)
  let worker = ProcessSample(
    id: ProcessIdentity(pid: 40, startSeconds: 1, startMicroseconds: 0), parentPID: 1, userID: 501,
    name: "worker", path: "", cpuTimeNanoseconds: nil, cpuPercent: 5, residentBytes: nil,
    footprintBytes: 1, threads: nil)
  _ = await recorder.record(
    reading(cpu: 0.4, processes: [worker]), systemWatts: 20, networkUsage: [:], diagnoses: true)
  #expect(!recorder.wantsProcesses, "Processes were just recorded")
  #expect(recorder.diagnosis?.isNothingUnusual == true)
  clock.advance(HistoryRecorder.processInterval)
  #expect(recorder.wantsProcesses)
  _ = await recorder.record(reading(cpu: 0.5), systemWatts: nil, networkUsage: [:], diagnoses: false)
  let points = await recorder.points(last: 3600)
  #expect(!points.isEmpty)
  #expect(FileManager.default.fileExists(atPath: directory.path))

  await recorder.clear()
  #expect(await recorder.points(last: 3600).isEmpty)
  recorder.apply(.off)
  #expect(!recorder.isRecording && !recorder.wantsProcesses)
}

@Test func heavyProcessesAreAnnouncedAtMostOnceAnHour() {
  let identity = ProcessIdentity(pid: 40, startSeconds: 1, startMicroseconds: 0)
  let label = HistoryProcessLabel(identity: identity, name: "bun", project: "culprit")
  func episode(at start: Date) -> Episode {
    Episode(
      kind: .cpu, process: label, start: start, end: nil, lastObserved: start, peak: 250,
      average: 200)
  }
  var detector = MomentDetector()
  let start = Date(timeIntervalSince1970: 1_800_000_000)
  #expect(detector.observe(episodeStart: episode(at: start))?.title == "bun · culprit at 250% CPU")
  #expect(detector.observe(episodeStart: episode(at: start + 600)) == nil)
  #expect(detector.observe(episodeStart: episode(at: start + 3700)) != nil)
}
