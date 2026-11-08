import Foundation
import StrataCore
import StrataSystem

// Keeps readings on disk so the panel can chart hours, the Explorer can list what happened, and
// sustained heavy processes become alerts. The store's actor does the file work off the main actor.
@MainActor final class HistoryRecorder: ObservableObject {
  @Published private(set) var episodes: [Episode] = []
  @Published private(set) var diagnosis: DiagnosisReport?
  @Published private(set) var issue: String?
  // Two process readings per one-minute history bucket keep idle scanning rare.
  static let processInterval: TimeInterval = 30
  static let diagnosisWindow: TimeInterval = 600
  private let directory: URL
  private let now: @Sendable () -> Date
  private var store: HistoryStore?
  private var keeping = HistoryKeeping.off
  private var lastProcessRecord: Date?
  private var openTask: Task<Void, Never>?
  private var writeFailed = false

  init(directory: URL, now: @escaping @Sendable () -> Date = { Date() }) {
    self.directory = directory
    self.now = now
  }

  static var defaultDirectory: URL {
    URL.applicationSupportDirectory.appending(path: "Strata Bar/History", directoryHint: .isDirectory)
  }

  var isRecording: Bool { store != nil }
  // History needs process readings this often even when no view shows processes.
  var wantsProcesses: Bool {
    guard isRecording else { return false }
    return lastProcessRecord.map { now().timeIntervalSince($0) >= Self.processInterval - 0.5 } ?? true
  }

  func apply(_ next: HistoryKeeping) {
    guard next != keeping else { return }
    keeping = next
    openTask?.cancel()
    guard let retention = next.retention else {
      let closing = store
      store = nil
      episodes = []
      diagnosis = nil
      issue = nil
      openTask = Task { await closing?.close() }
      return
    }
    let configuration = HistoryConfiguration(retention: retention)
    let existing = store
    let opening = existing ?? HistoryStore(directory: directory, configuration: configuration)
    store = opening
    openTask = Task {
      do {
        // A retention change during the first load may have cancelled it; open in that case.
        let isOpen = await opening.isOpen
        _ = try await existing == nil || !isOpen ? opening.open() : opening.apply(configuration)
        guard !Task.isCancelled else { return }
        issue = nil
        episodes = await opening.episodes
      } catch {
        guard !Task.isCancelled else { return }
        // Readings stay in memory for this session when the folder can't be used.
        issue = error.localizedDescription
      }
    }
  }

  func record(
    _ sample: SystemSample, systemWatts: Double?, networkUsage: [ProcessIdentity: NetworkRate],
    diagnoses: Bool
  ) async -> [EpisodeChange] {
    // Loading the files replaces what is in memory, so readings wait until it has finished.
    await openTask?.value
    guard let store else { return [] }
    let time = now()
    let point = HistorySystemPoint(sample, time: time, systemWatts: systemWatts)
    // A failed scan is no reading at all, not every process ending; frequent scans while views
    // are open are recorded only as often as idle history would read them.
    let scanned = sample.processScan.map { !$0.failed } == true && wantsProcesses
    let processes = !scanned ? nil : sample.processes.map { process in
      HistoryProcessPoint(
        process, project: process.project,
        networkBytesPerSecond: networkUsage[process.id].map { $0.received + $0.sent })
    }
    if processes != nil { lastProcessRecord = time }
    // Read before recording, so the diagnosis counts the current reading once.
    let recent =
      diagnoses ? await store.points(in: time.addingTimeInterval(-Self.diagnosisWindow)...time) : []
    let result = await store.record(system: point, processes: processes)
    guard self.store === store else { return [] }
    if !result.episodeChanges.isEmpty { episodes = await store.episodes }
    // A failed write is reported until a later write succeeds; a folder that could not be
    // opened stays reported, since nothing is written then.
    if let error = result.persistenceError {
      issue = error.localizedDescription
      writeFailed = true
    } else if writeFailed, await store.isOpen {
      issue = nil
      writeFailed = false
    }
    if diagnoses {
      diagnosis = DiagnosisEngine.diagnose(
        DiagnosisInput(
          current: point, processes: processes ?? [], recent: recent,
          logicalCores: sample.cores.isEmpty ? nil : sample.cores.count))
    }
    return result.episodeChanges
  }

  // For demo data only: earlier readings, oldest first. Live readings wait until they are
  // recorded, since history accepts readings in time order only.
  func seed(_ points: [HistorySystemPoint]) {
    let opening = openTask
    openTask = Task {
      await opening?.value
      guard let store else { return }
      for point in points { _ = await store.record(system: point) }
    }
  }

  func points(last interval: TimeInterval, maximumCount: Int = 360) async -> [HistorySummaryPoint] {
    guard let store else { return [] }
    let time = now()
    return await store.points(in: time.addingTimeInterval(-interval)...time, maximumCount: maximumCount)
  }

  func clear() async {
    guard let store else { return }
    do {
      try await store.clear()
      episodes = []
      diagnosis = nil
      issue = nil
    } catch {
      issue = error.localizedDescription
    }
  }

  func stop() {
    openTask?.cancel()
    let closing = store
    store = nil
    diagnosis = nil
    Task { await closing?.close() }
  }
}
