import Foundation

public struct HistoryLoadSummary: Equatable, Sendable {
  public let files: Int
  public let systemPoints: Int
  public let processBuckets: Int
  public let episodes: Int
  public let skippedRecords: Int
  public let damagedBytes: Int
  public let unreadableFiles: Int
}

public struct HistoryRecordResult: Sendable {
  public let episodeChanges: [EpisodeChange]
  /// Set when the reading was kept in memory but could not be written to disk.
  public let persistenceError: HistoryStoreError?
}

/// The single writer of a history directory. It keeps the tiered history and
/// episodes in memory and appends every reading to the file for its UTC day.
/// Files hold process names and projects only, never arguments or paths.
public actor HistoryStore {
  public nonisolated let directory: URL
  public private(set) var configuration: HistoryConfiguration
  public private(set) var history: TieredHistory
  private let thresholds: EpisodeThresholds
  private let now: @Sendable () -> Date
  private var detector: EpisodeDetector
  private var lock: FileHandle?
  private var writer: HistoryFileWriter?

  public init(
    directory: URL, configuration: HistoryConfiguration = HistoryConfiguration(),
    thresholds: EpisodeThresholds = EpisodeThresholds(), now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.directory = directory
    self.configuration = configuration
    self.thresholds = thresholds
    self.now = now
    history = TieredHistory(configuration: configuration)
    detector = EpisodeDetector(thresholds: thresholds)
  }

  public var isOpen: Bool { lock != nil }
  public var episodes: [Episode] { detector.episodes }

  /// Takes ownership of the directory, removes expired files and loads the rest.
  /// Damaged records are skipped rather than failing the load; a load that fails
  /// or is cancelled releases the directory again.
  @discardableResult
  public func open() throws -> HistoryLoadSummary {
    if lock == nil {
      try HistoryDirectory.prepare(directory)
      lock = try HistoryDirectory.lock(directory)
    }
    do {
      return try reload()
    } catch {
      close()
      throw error
    }
  }

  public func close() {
    writer = nil
    lock = nil
  }

  /// Changing tiers or retention rebuilds memory from disk with the new shape.
  @discardableResult
  public func apply(_ configuration: HistoryConfiguration) throws -> HistoryLoadSummary {
    self.configuration = configuration
    guard isOpen else {
      history = TieredHistory(configuration: configuration)
      return HistoryLoadSummary(
        files: 0, systemPoints: 0, processBuckets: 0, episodes: 0, skippedRecords: 0, damagedBytes: 0,
        unreadableFiles: 0)
    }
    return try reload()
  }

  public func record(system point: HistorySystemPoint, processes: [HistoryProcessPoint]? = nil) -> HistoryRecordResult {
    let appended = history.append(point)
    guard appended.isAccepted else { return HistoryRecordResult(episodeChanges: [], persistenceError: nil) }
    var completed = appended.completedProcessBuckets
    var changes = detector.observe(system: point)
    if let processes {
      completed += history.append(processes: processes, at: point.time).completedProcessBuckets
      changes += detector.observe(processes: processes, at: point.time)
    }
    return HistoryRecordResult(
      episodeChanges: changes, persistenceError: persist(point, completed: completed, changes: changes))
  }

  public func points(
    in range: ClosedRange<Date>, resolution: TimeInterval = 0, maximumCount: Int = 360
  ) -> [HistorySummaryPoint] {
    history.points(in: range, resolution: resolution, maximumCount: maximumCount)
  }

  /// Deletes every history file and forgets everything in memory.
  public func clear() throws {
    writer = nil
    history.removeAll()
    detector.reset()
    guard isOpen else { return }
    for file in try HistoryDirectory.dayFiles(in: directory) { try HistoryDirectory.remove(file.url) }
  }

  public func prune() throws {
    let cutoff = now().addingTimeInterval(-configuration.retentionSpan)
    detector.removeEpisodes(endingBefore: cutoff)
    guard isOpen else { return }
    for file in try HistoryDirectory.dayFiles(in: directory) where file.day.end <= cutoff {
      if writer?.day == file.day { writer = nil }
      try HistoryDirectory.remove(file.url)
    }
  }

  private func reload() throws -> HistoryLoadSummary {
    writer = nil
    try prune()
    var replay = HistoryReplay(
      configuration: configuration, cutoff: now().addingTimeInterval(-configuration.retentionSpan))
    let files = try HistoryDirectory.dayFiles(in: directory)
    for file in files {
      try Task.checkCancellation()
      replay.replay(file.url)
    }
    history = replay.history
    detector = EpisodeDetector(thresholds: thresholds)
    detector.restore(Array(replay.episodes.values))
    return HistoryLoadSummary(
      files: files.count, systemPoints: replay.systemPoints, processBuckets: replay.processBuckets,
      episodes: detector.closedEpisodes.count, skippedRecords: replay.skippedRecords,
      damagedBytes: replay.damagedBytes, unreadableFiles: replay.unreadableFiles)
  }

  /// Each completed process interval also refreshes ongoing episodes on disk,
  /// so a crash loses at most a minute of an episode's progress.
  private func persist(
    _ point: HistorySystemPoint, completed: [HistoryProcessBucket], changes: [EpisodeChange]
  ) -> HistoryStoreError? {
    guard isOpen else { return .notOpen }
    do {
      var writer = try fileWriter(for: HistoryDay(containing: point.time))
      var bytes = HistoryRecordCodec.encode(point)
      for bucket in completed {
        bytes += writer.definitions(for: bucket)
        bytes += HistoryRecordCodec.encode(bucket, indices: writer.indices)
        for episode in detector.ongoingEpisodes { bytes += HistoryRecordCodec.encode(episode) }
      }
      for change in changes { bytes += HistoryRecordCodec.encode(change.episode) }
      try writer.append(bytes)
      self.writer = writer
      return nil
    } catch let error as HistoryStoreError {
      return error
    } catch {
      return .fileSystem(operation: "write", code: (error as NSError).code)
    }
  }

  private func fileWriter(for day: HistoryDay) throws -> HistoryFileWriter {
    if let writer, writer.day == day { return writer }
    if writer != nil { try prune() }
    writer = nil
    return try HistoryFileWriter(day: day, directory: directory)
  }
}
