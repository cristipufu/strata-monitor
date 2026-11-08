import Foundation
import Synchronization
import Testing

@testable import StrataCore

private final class HistoryTestClock: Sendable {
  private let date: Mutex<Date>

  init(_ date: Date) { self.date = Mutex(date) }

  var now: Date { date.withLock { $0 } }
  func set(_ value: Date) { date.withLock { $0 = value } }
}

private func withHistoryDirectory(_ body: (URL) async throws -> Void) async throws {
  let parent = FileManager.default.temporaryDirectory.appending(
    path: "StrataHistoryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
  defer { try? FileManager.default.removeItem(at: parent) }
  try await body(parent.appending(path: "History", directoryHint: .isDirectory))
}

private func dayFile(_ directory: URL, containing time: Date) -> URL {
  directory.appending(path: HistoryDay(containing: time).fileName)
}

private func permissions(_ url: URL) throws -> Int {
  try #require(FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.posixPermissions] as? Int)
}

private func reading(_ second: Double, cpu: Double = 0.5) -> HistorySystemPoint {
  HistorySystemPoint(time: historyTime(second), uptime: second, cpu: cpu, memoryPressure: .normal, thermal: .normal)
}

@Test func historyAndASyntheticBurnersEpisodeSurviveARestart() async throws {
  try await withHistoryDirectory { directory in
    let clock = HistoryTestClock(historyTime(0))
    let store = HistoryStore(directory: directory, now: { clock.now })
    #expect(try await store.open().files == 0)
    for second in stride(from: 0.0, through: 900, by: 2) {
      clock.set(historyTime(second))
      let burner = historyProcess(42, name: "burner", cpu: second < 400 ? 300 : 5, footprint: 1 << 20)
      let processes = second.truncatingRemainder(dividingBy: 10) == 0 ? [burner, historyProcess(2, cpu: 3)] : nil
      let result = await store.record(system: reading(second, cpu: second / 1_000), processes: processes)
      #expect(result.persistenceError == nil)
    }
    let before = await store.history
    let episodes = await store.episodes
    await store.close()
    #expect(episodes.map(\.kind) == [.cpu])
    #expect(episodes.first?.end == historyTime(400))

    let reopened = HistoryStore(directory: directory, now: { clock.now })
    let summary = try await reopened.open()
    let after = await reopened.history
    #expect(summary.systemPoints == 451)
    #expect(summary.processBuckets == 15)
    #expect(summary.episodes == 1)
    #expect(summary.damagedBytes == 0)
    for start in [0.0, 600, 899] {
      let range = historyTime(start)...historyTime(900)
      #expect(after.points(in: range) == before.points(in: range))
      #expect(after.processBuckets(in: range) == before.processBuckets(in: range))
    }
    #expect(await reopened.episodes == episodes)
    await reopened.close()
  }
}

@Test func aTornLastRecordIsDiscardedAndAppendingContinues() async throws {
  try await withHistoryDirectory { directory in
    let store = HistoryStore(directory: directory, now: { historyTime(100) })
    try await store.open()
    for second in stride(from: 0.0, to: 60, by: 2) { _ = await store.record(system: reading(second)) }
    await store.close()
    let file = dayFile(directory, containing: historyTime(0))
    let handle = try FileHandle(forWritingTo: file)
    let length = try handle.seekToEnd()
    try handle.truncate(atOffset: length - 5)
    try handle.close()

    let damaged = try await store.open()
    #expect(damaged.systemPoints == 29)
    #expect(damaged.damagedBytes > 0)
    #expect(await store.record(system: reading(60)).persistenceError == nil)
    await store.close()

    let repaired = try await store.open()
    #expect(repaired.systemPoints == 30)
    #expect(repaired.damagedBytes == 0)
    #expect(repaired.skippedRecords == 0)
  }
}

@Test func aDamagedRecordIsSkippedAndTheRestLoads() async throws {
  try await withHistoryDirectory { directory in
    let store = HistoryStore(directory: directory, now: { historyTime(100) })
    try await store.open()
    for second in stride(from: 0.0, to: 20, by: 2) { _ = await store.record(system: reading(second)) }
    await store.close()
    let file = dayFile(directory, containing: historyTime(0))
    var bytes = try Data(contentsOf: file)
    bytes[bytes.count / 2] ^= 0xFF
    try bytes.write(to: file)

    let summary = try await store.open()
    #expect(summary.systemPoints == 9)
    #expect(summary.skippedRecords == 1)
  }
}

@Test func aFileWithoutAHeaderIsIgnoredAndThenReplaced() async throws {
  try await withHistoryDirectory { directory in
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let garbage = Data("not a history file".utf8)
    try garbage.write(to: dayFile(directory, containing: historyTime(0)))
    let store = HistoryStore(directory: directory, now: { historyTime(100) })
    let summary = try await store.open()
    #expect(summary.systemPoints == 0)
    #expect(summary.damagedBytes == garbage.count)
    #expect(await store.record(system: reading(10)).persistenceError == nil)
    #expect(try await store.open().systemPoints == 1)
  }
}

@Test func aCancelledOpenLoadsNothingAndReleasesTheDirectory() async throws {
  try await withHistoryDirectory { directory in
    let writer = HistoryStore(directory: directory, now: { historyTime(100) })
    try await writer.open()
    _ = await writer.record(system: reading(10))
    await writer.close()

    let store = HistoryStore(directory: directory, now: { historyTime(100) })
    let cancelled = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await store.open()
    }
    await #expect(throws: CancellationError.self) { try await cancelled.value }
    #expect(await !store.isOpen)
    #expect(await store.history.footprint.systemPoints == 0)
    #expect(try await store.open().systemPoints == 1)
  }
}

@Test func retentionRemovesExpiredDaysAndSkipsExpiredReadings() async throws {
  try await withHistoryDirectory { directory in
    let clock = HistoryTestClock(historyTime(3_600))
    let store = HistoryStore(directory: directory, now: { clock.now })
    try await store.open()
    _ = await store.record(system: reading(3_600))
    clock.set(historyTime(90_000))
    _ = await store.record(system: reading(90_000))
    await store.close()

    clock.set(historyTime(86_400 + 7_200))
    let nextMorning = try await store.open()
    #expect(nextMorning.files == 2)
    #expect(nextMorning.systemPoints == 1)
    await store.close()

    let weekly = HistoryStore(directory: directory, configuration: HistoryConfiguration(retention: .week), now: { clock.now })
    #expect(try await weekly.open().systemPoints == 2)
    await weekly.close()

    clock.set(historyTime(2 * 86_400 + 100))
    let twoDaysLater = try await store.open()
    #expect(twoDaysLater.files == 1)
    #expect(twoDaysLater.systemPoints == 1)
    #expect(!FileManager.default.fileExists(atPath: dayFile(directory, containing: historyTime(0)).path(percentEncoded: false)))
  }
}

@Test func startingANewDayRemovesExpiredFiles() async throws {
  try await withHistoryDirectory { directory in
    let clock = HistoryTestClock(historyTime(10))
    let store = HistoryStore(directory: directory, now: { clock.now })
    try await store.open()
    _ = await store.record(system: reading(10))
    clock.set(historyTime(2 * 86_400 + 10))
    #expect(await store.record(system: reading(2 * 86_400 + 10)).persistenceError == nil)
    let names = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
    #expect(names.filter { $0.hasSuffix(".history") } == [HistoryDay(containing: historyTime(2 * 86_400)).fileName])
  }
}

@Test func changingRetentionReloadsWithTheNewTiers() async throws {
  try await withHistoryDirectory { directory in
    let store = HistoryStore(directory: directory, now: { historyTime(700) })
    try await store.open()
    for second in stride(from: 0.0, through: 700, by: 2) { _ = await store.record(system: reading(second)) }
    let summary = try await store.apply(HistoryConfiguration(retention: .week))
    #expect(summary.systemPoints == 351)
    #expect(await store.configuration.systemTiers.count == 4)
    let week = await store.points(in: historyTime(-6 * 86_400)...historyTime(700))
    #expect(week.map(\.duration) == [300, 300, 300])
  }
}

@Test func clearingHistoryRemovesFilesAndMemory() async throws {
  try await withHistoryDirectory { directory in
    let store = HistoryStore(directory: directory, now: { historyTime(500) })
    try await store.open()
    for second in stride(from: 0.0, through: 400, by: 2) {
      _ = await store.record(system: reading(second), processes: [historyProcess(1, cpu: 400)])
    }
    #expect(await !store.episodes.isEmpty)
    try await store.clear()
    #expect(try HistoryDirectory.dayFiles(in: directory).isEmpty)
    #expect(await store.history.footprint.systemPoints == 0)
    #expect(await store.episodes.isEmpty)
    #expect(await store.record(system: reading(450)).persistenceError == nil)
    #expect(try await store.open().systemPoints == 1)
  }
}

@Test func filesAreReadableOnlyByTheirOwner() async throws {
  try await withHistoryDirectory { directory in
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
    let store = HistoryStore(directory: directory, now: { historyTime(10) })
    try await store.open()
    _ = await store.record(system: reading(0))
    #expect(try permissions(directory) == 0o700)
    #expect(try permissions(dayFile(directory, containing: historyTime(0))) == 0o600)
    #expect(try permissions(directory.appending(path: "writer.lock")) == 0o600)
  }
}

@Test func onlyOneStoreWritesADirectoryAtATime() async throws {
  try await withHistoryDirectory { directory in
    let first = HistoryStore(directory: directory)
    let second = HistoryStore(directory: directory)
    try await first.open()
    await #expect(throws: HistoryStoreError.anotherWriterIsActive) { try await second.open() }
    await first.close()
    try await second.open()
    #expect(await second.isOpen)
  }
}

@Test func readingsAreKeptInMemoryWhenTheStoreIsNotOpen() async {
  let store = HistoryStore(directory: FileManager.default.temporaryDirectory.appending(path: "never-created-\(UUID())"))
  let result = await store.record(system: reading(0))
  #expect(result.persistenceError == .notOpen)
  #expect(await store.points(in: historyTime(0)...historyTime(1)).count == 1)
}

@Test func aSymbolicLinkIsNotAcceptedAsTheHistoryDirectory() async throws {
  try await withHistoryDirectory { directory in
    let target = directory.deletingLastPathComponent().appending(path: "Elsewhere")
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: target)
    let store = HistoryStore(directory: directory)
    await #expect(throws: HistoryStoreError.unsafeLocation) { try await store.open() }
  }
}

@Test func plantedLinksAndPipesAreSkippedAndNeverWritten() async throws {
  try await withHistoryDirectory { directory in
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let elsewhere = directory.deletingLastPathComponent().appending(path: "elsewhere.history")
    try Data().write(to: elsewhere)
    try FileManager.default.createSymbolicLink(
      at: dayFile(directory, containing: historyTime(0)), withDestinationURL: elsewhere)
    #expect(mkfifo(dayFile(directory, containing: historyTime(-10)).path(percentEncoded: false), 0o600) == 0)
    let store = HistoryStore(directory: directory, now: { historyTime(100) })
    let summary = try await store.open()
    #expect(summary.files == 2)
    #expect(summary.unreadableFiles == 2)
    let result = await store.record(system: reading(200))
    #expect(result.persistenceError == .fileSystem(operation: "open", code: Int(ELOOP)))
    #expect(try Data(contentsOf: elsewhere).isEmpty)
  }
}

@Test func writeFailuresAreReportedWithoutLosingReadings() async throws {
  try await withHistoryDirectory { directory in
    let store = HistoryStore(directory: directory, now: { historyTime(10) })
    try await store.open()
    #expect(await store.record(system: reading(0)).persistenceError == nil)
    let path = directory.path(percentEncoded: false)
    #expect(chmod(path, 0o500) == 0)
    defer { chmod(path, 0o700) }
    let failed = await store.record(system: reading(86_400))
    #expect(failed.persistenceError == .fileSystem(operation: "open", code: Int(EACCES)))
    #expect(await store.history.latestTime == historyTime(86_400))
    #expect(chmod(path, 0o700) == 0)
    #expect(await store.record(system: reading(86_402)).persistenceError == nil)
  }
}

@Test func filesHoldProcessNamesButNotPaths() async throws {
  try await withHistoryDirectory { directory in
    let store = HistoryStore(directory: directory, now: { historyTime(100) })
    try await store.open()
    let process = HistoryProcessPoint(
      identity: historyIdentity(3), name: "/Users/someone/bin/tool", project: "/Users/someone/Developer/secret-project",
      cpuPercent: 50)
    _ = await store.record(system: reading(0), processes: [process])
    _ = await store.record(system: reading(60), processes: [process])
    let contents = try Data(contentsOf: dayFile(directory, containing: historyTime(0)))
    #expect(contents.range(of: Data("tool".utf8)) != nil)
    #expect(contents.range(of: Data("secret-project".utf8)) != nil)
    #expect(contents.range(of: Data("/Users".utf8)) == nil)
  }
}

/// Runs on the store's executor so a day of readings costs no actor hops.
private func recordSimulatedDay(on store: isolated HistoryStore, clock: HistoryTestClock) {
  for second in stride(from: 0.0, to: 86_400, by: 2) {
    clock.set(historyTime(second))
    let processes = second.truncatingRemainder(dividingBy: 60) == 0 ? simulatedProcesses(at: second) : nil
    let point = HistorySystemPoint(
      time: historyTime(second), uptime: second, cpu: 0.3, memoryUsedFraction: 0.6, memoryPressure: .normal,
      swapBytes: 1e9, networkInBytesPerSecond: 1e5, networkOutBytesPerSecond: 1e4, diskReadBytesPerSecond: 1e6,
      diskWriteBytesPerSecond: 1e6, gpu: 0.1, systemWatts: 8, thermal: .normal)
    _ = store.record(system: point, processes: processes)
  }
}

@Test func aSimulatedDayFitsInFiveMegabytesAndLoadsBack() async throws {
  try await withHistoryDirectory { directory in
    let clock = HistoryTestClock(historyTime(0))
    let store = HistoryStore(directory: directory, now: { clock.now })
    try await store.open()
    await recordSimulatedDay(on: store, clock: clock)
    await store.close()
    let size = try #require(
      FileManager.default.attributesOfItem(
        atPath: dayFile(directory, containing: historyTime(0)).path(percentEncoded: false))[.size] as? Int)
    #expect(size <= 5_000_000)
    let summary = try await store.open()
    #expect(summary.systemPoints == 43_200)
    #expect(summary.processBuckets == 1_439)
  }
}
