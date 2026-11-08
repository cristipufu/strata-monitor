import Foundation

public enum HistoryStoreError: Error, Equatable, Sendable {
  /// The directory or a file in it is a link, another user's or not a regular file.
  case unsafeLocation
  case anotherWriterIsActive
  case notOpen
  case fileSystem(operation: String, code: Int)
}

/// A UTC calendar day; each has its own history file named `YYYY-MM-DD.history`.
struct HistoryDay: Hashable, Comparable, Sendable {
  private static let fileExtension = ".history"
  private static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
  }()

  let start: Date

  init(containing date: Date) {
    start = Self.calendar.startOfDay(for: date)
  }

  init?(fileName: String) {
    guard fileName.hasSuffix(Self.fileExtension) else { return nil }
    let parts = fileName.dropLast(Self.fileExtension.count).split(separator: "-")
    guard parts.count == 3, parts.allSatisfy({ $0.allSatisfy(\.isASCII) }) else { return nil }
    let numbers = parts.compactMap { Int($0) }
    guard numbers.count == 3,
      let start = Self.calendar.date(from: DateComponents(year: numbers[0], month: numbers[1], day: numbers[2]))
    else { return nil }
    self.start = start
    guard self.fileName == fileName else { return nil }
  }

  var end: Date { Self.calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400) }

  var fileName: String {
    let parts = Self.calendar.dateComponents([.year, .month, .day], from: start)
    return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
      + Self.fileExtension
  }

  static func < (lhs: Self, rhs: Self) -> Bool { lhs.start < rhs.start }
}

/// File access for the history directory: owner-only permissions, no symbolic
/// links followed and nothing but regular files opened.
enum HistoryDirectory {
  /// Far above a day of readings; a larger file is refused rather than read in part.
  static let maximumFileBytes = 64 << 20
  private static let lockName = "writer.lock"

  static func prepare(_ directory: URL) throws {
    do {
      try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    } catch {
      throw HistoryStoreError.fileSystem(operation: "create directory", code: (error as NSError).code)
    }
    let path = withoutTrailingSlash(directory.path(percentEncoded: false))
    var status = stat()
    guard lstat(path, &status) == 0, status.st_mode & S_IFMT == S_IFDIR, status.st_uid == geteuid() else {
      throw HistoryStoreError.unsafeLocation
    }
    if status.st_mode & 0o777 != 0o700, chmod(path, 0o700) != 0 {
      throw HistoryStoreError.fileSystem(operation: "chmod", code: Int(errno))
    }
  }

  /// A trailing slash makes `lstat` resolve a symbolic link instead of reporting it.
  private static func withoutTrailingSlash(_ path: String) -> String {
    path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
  }

  /// Holding an exclusive lock keeps a second running copy from writing the same files.
  static func lock(_ directory: URL) throws -> FileHandle {
    let handle = try regularFile(directory.appending(path: lockName), flags: O_RDWR | O_CREAT)
    guard flock(handle.fileDescriptor, LOCK_EX | LOCK_NB) == 0 else {
      throw errno == EWOULDBLOCK
        ? HistoryStoreError.anotherWriterIsActive : HistoryStoreError.fileSystem(operation: "lock", code: Int(errno))
    }
    return handle
  }

  static func dayFiles(in directory: URL) throws -> [(day: HistoryDay, url: URL)] {
    let names: [String]
    do {
      names = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
    } catch {
      throw HistoryStoreError.fileSystem(operation: "list", code: (error as NSError).code)
    }
    return names.compactMap { name in
      HistoryDay(fileName: name).map { ($0, directory.appending(path: name)) }
    }.sorted { $0.day < $1.day }
  }

  static func contents(of url: URL) throws -> Data {
    let handle = try regularFile(url, flags: O_RDONLY)
    var status = stat()
    guard fstat(handle.fileDescriptor, &status) == 0 else {
      throw HistoryStoreError.fileSystem(operation: "stat", code: Int(errno))
    }
    guard status.st_size <= maximumFileBytes else {
      throw HistoryStoreError.fileSystem(operation: "read", code: Int(EFBIG))
    }
    do {
      return try handle.readToEnd() ?? Data()
    } catch {
      throw HistoryStoreError.fileSystem(operation: "read", code: (error as NSError).code)
    }
  }

  static func appendingHandle(_ url: URL) throws -> FileHandle {
    try regularFile(url, flags: O_WRONLY | O_CREAT | O_APPEND)
  }

  static func remove(_ url: URL) throws {
    guard unlink(url.path(percentEncoded: false)) == 0 || errno == ENOENT else {
      throw HistoryStoreError.fileSystem(operation: "remove", code: Int(errno))
    }
  }

  /// Opening without blocking keeps a FIFO planted under a history name from
  /// stalling the store; it is then rejected as not a regular file.
  private static func regularFile(_ url: URL, flags: Int32) throws -> FileHandle {
    let descriptor = open(
      url.path(percentEncoded: false), flags | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, mode_t(0o600))
    guard descriptor >= 0 else { throw HistoryStoreError.fileSystem(operation: "open", code: Int(errno)) }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    var status = stat()
    guard fstat(descriptor, &status) == 0, status.st_mode & S_IFMT == S_IFREG, status.st_uid == geteuid() else {
      throw HistoryStoreError.unsafeLocation
    }
    if status.st_mode & 0o777 != 0o600, fchmod(descriptor, 0o600) != 0 {
      throw HistoryStoreError.fileSystem(operation: "chmod", code: Int(errno))
    }
    return handle
  }
}

/// The append side of one day's file. Definitions give each process a small
/// per-file index so interval records do not repeat names every minute.
struct HistoryFileWriter {
  let day: HistoryDay
  private let handle: FileHandle
  private(set) var length: Int
  private(set) var indices: [ProcessIdentity: UInt32]
  private var nextIndex: UInt32
  private static let maximumDefinitions: UInt32 = 1 << 24

  /// Opens the day's file, discarding a torn tail and adopting its definitions.
  init(day: HistoryDay, directory: URL) throws {
    let url = directory.appending(path: day.fileName)
    handle = try HistoryDirectory.appendingHandle(url)
    let existing = try HistoryDirectory.contents(of: url)
    var definitions: [ProcessIdentity: UInt32] = [:]
    let validLength = existing.withUnsafeBytes { bytes -> Int in
      guard HistoryFileFormat.hasHeader(bytes) else { return 0 }
      return HistoryFileFormat.scan(bytes) { kind, payload in
        // A day names far fewer processes; a larger index can only come from a damaged file.
        guard kind == HistoryRecordKind.processDefinition.rawValue,
          let (index, label) = try? HistoryRecordCodec.decodeDefinition(payload),
          index < Self.maximumDefinitions
        else { return }
        definitions[label.identity] = index
      }.validLength
    }
    self.day = day
    indices = definitions
    nextIndex = (definitions.values.max() ?? 0) + (definitions.isEmpty ? 0 : 1)
    length = validLength
    if validLength != existing.count { try truncate(to: validLength) }
    if validLength == 0 { try append(HistoryFileFormat.header) }
  }

  /// Definition records for processes in `bucket` that this file has not named yet.
  mutating func definitions(for bucket: HistoryProcessBucket) -> [UInt8] {
    var bytes: [UInt8] = []
    for entry in bucket.entries where indices[entry.identity] == nil {
      guard nextIndex < Self.maximumDefinitions else { break }
      indices[entry.identity] = nextIndex
      bytes += HistoryRecordCodec.encodeDefinition(
        index: nextIndex, label: HistoryProcessLabel(identity: entry.identity, name: entry.name, project: entry.project))
      nextIndex += 1
    }
    return bytes
  }

  /// A failed write is cut back off so the next record starts on a frame boundary.
  mutating func append(_ bytes: [UInt8]) throws {
    do {
      try handle.write(contentsOf: bytes)
      length += bytes.count
    } catch {
      try? truncate(to: length)
      throw HistoryStoreError.fileSystem(operation: "write", code: (error as NSError).code)
    }
  }

  private func truncate(to length: Int) throws {
    do {
      try handle.truncate(atOffset: UInt64(length))
    } catch {
      throw HistoryStoreError.fileSystem(operation: "truncate", code: (error as NSError).code)
    }
  }
}

/// Rebuilds history and episodes from files, oldest first.
struct HistoryReplay {
  private(set) var history: TieredHistory
  private(set) var episodes: [Episode.ID: Episode] = [:]
  private(set) var systemPoints = 0
  private(set) var processBuckets = 0
  private(set) var skippedRecords = 0
  private(set) var damagedBytes = 0
  private(set) var unreadableFiles = 0
  private let cutoff: Date

  init(configuration: HistoryConfiguration, cutoff: Date) {
    history = TieredHistory(configuration: configuration)
    self.cutoff = cutoff
  }

  mutating func replay(_ url: URL) {
    guard let data = try? HistoryDirectory.contents(of: url) else {
      unreadableFiles += 1
      return
    }
    data.withUnsafeBytes { bytes in
      guard HistoryFileFormat.hasHeader(bytes) else {
        damagedBytes += bytes.count
        return
      }
      var definitions: [UInt32: HistoryProcessLabel] = [:]
      let scan = HistoryFileFormat.scan(bytes) { kind, payload in
        replay(kind: kind, payload: payload, definitions: &definitions)
      }
      skippedRecords += scan.skippedRecords
      damagedBytes += bytes.count - scan.validLength
    }
  }

  private mutating func replay(
    kind: UInt8, payload: UnsafeRawBufferPointer, definitions: inout [UInt32: HistoryProcessLabel]
  ) {
    do {
      switch HistoryRecordKind(rawValue: kind) {
      case .system:
        let point = try HistoryRecordCodec.decodeSystem(payload)
        if point.time >= cutoff, history.append(point).isAccepted { systemPoints += 1 }
      case .processDefinition:
        let (index, label) = try HistoryRecordCodec.decodeDefinition(payload)
        definitions[index] = label
      case .processBucket:
        let bucket = try HistoryRecordCodec.decodeBucket(payload, definitions: definitions)
        if bucket.time >= cutoff, history.restore(bucket) { processBuckets += 1 }
      case .episode:
        let episode = try HistoryRecordCodec.decodeEpisode(payload)
        if (episode.end ?? episode.lastObserved) >= cutoff { episodes[episode.id] = episode }
      case nil:
        return
      }
    } catch {
      skippedRecords += 1
    }
  }
}
