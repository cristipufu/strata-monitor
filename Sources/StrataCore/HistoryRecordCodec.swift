import Foundation

enum HistoryCodecError: Error, Equatable {
  case truncated
  case malformed
}

enum HistoryRecordKind: UInt8 {
  case system = 1
  case processDefinition = 2
  case processBucket = 3
  case episode = 4
}

/// A history file is an 8-byte header followed by records framed as
/// `length (UInt32) | CRC-32 (UInt32) | kind (UInt8) | payload`, little-endian,
/// where the length and checksum cover the kind and payload.
enum HistoryFileFormat {
  static let header: [UInt8] = Array("SBHS".utf8) + [1, 0, 0, 0]
  static let frameOverhead = 8
  static let maximumRecordLength = 1 << 20

  struct Scan {
    var validLength: Int
    var skippedRecords: Int
  }

  static func hasHeader(_ bytes: UnsafeRawBufferPointer) -> Bool {
    bytes.count >= header.count && zip(bytes, header).allSatisfy { $0 == $1 }
  }

  static func frame(_ kind: HistoryRecordKind, _ payload: HistoryByteWriter) -> [UInt8] {
    var body = [kind.rawValue]
    body.append(contentsOf: payload.bytes)
    var frame = HistoryByteWriter()
    frame.write(UInt32(body.count))
    frame.write(body.withUnsafeBytes(CRC32.checksum))
    return frame.bytes + body
  }

  /// Visits every intact record after the header. A record whose checksum fails
  /// is skipped; a frame that cannot be complete ends the scan, and everything
  /// from it on is the torn tail a crash can leave behind.
  static func scan(
    _ bytes: UnsafeRawBufferPointer, visit: (UInt8, UnsafeRawBufferPointer) -> Void
  ) -> Scan {
    var offset = header.count
    var skipped = 0
    while bytes.count - offset >= frameOverhead {
      let length = Int(UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self)))
      let checksum = UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self))
      let bodyStart = offset + frameOverhead
      guard length >= 1, length <= maximumRecordLength, length <= bytes.count - bodyStart else { break }
      let body = UnsafeRawBufferPointer(rebasing: bytes[bodyStart..<bodyStart + length])
      if CRC32.checksum(body) == checksum {
        visit(body[0], UnsafeRawBufferPointer(rebasing: body.dropFirst()))
      } else {
        skipped += 1
      }
      offset = bodyStart + length
    }
    return Scan(validLength: min(offset, bytes.count), skippedRecords: skipped)
  }
}

enum HistoryRecordCodec {
  // A presence mask keeps unmeasured values out of a system record: bits 0–8
  // follow `HistoryMetric`, then uptime, memory pressure and thermal pressure.
  private static let uptimeBit: UInt16 = 1 << 9
  private static let memoryPressureBit: UInt16 = 1 << 10
  private static let thermalBit: UInt16 = 1 << 11

  static func encode(_ point: HistorySystemPoint) -> [UInt8] {
    var mask: UInt16 = 0
    var values = HistoryByteWriter()
    if let uptime = point.uptime, uptime.isFinite {
      mask |= uptimeBit
      values.write(uptime)
    }
    for metric in HistoryMetric.all {
      guard let value = SummaryAccumulator.storable(point[metric]) else { continue }
      mask |= 1 << metric.rawValue
      values.write(value)
    }
    if let pressure = point.memoryPressure {
      mask |= memoryPressureBit
      values.write(pressure.rawValue)
    }
    if let thermal = point.thermal {
      mask |= thermalBit
      values.write(thermal.rawValue)
    }
    var payload = HistoryByteWriter()
    payload.write(point.time.timeIntervalSinceReferenceDate)
    payload.write(mask)
    payload.append(values)
    return HistoryFileFormat.frame(.system, payload)
  }

  static func decodeSystem(_ payload: UnsafeRawBufferPointer) throws -> HistorySystemPoint {
    var reader = HistoryByteReader(payload)
    let time = try reader.readDouble()
    let mask = try reader.read(UInt16.self)
    guard time.isFinite else { throw HistoryCodecError.malformed }
    var point = HistorySystemPoint(time: Date(timeIntervalSinceReferenceDate: time))
    if mask & uptimeBit != 0 { point.uptime = try reader.readDouble() }
    for metric in HistoryMetric.all where mask & (1 << metric.rawValue) != 0 {
      point[metric] = Double(try reader.readFloat())
    }
    if mask & memoryPressureBit != 0 { point.memoryPressure = HistoryPressure(rawValue: try reader.read(UInt8.self)) }
    if mask & thermalBit != 0 { point.thermal = HistoryPressure(rawValue: try reader.read(UInt8.self)) }
    return point
  }

  static func encodeDefinition(index: UInt32, label: HistoryProcessLabel) -> [UInt8] {
    var payload = HistoryByteWriter()
    payload.writeVarint(UInt64(index))
    payload.write(label)
    return HistoryFileFormat.frame(.processDefinition, payload)
  }

  static func decodeDefinition(_ payload: UnsafeRawBufferPointer) throws -> (UInt32, HistoryProcessLabel) {
    var reader = HistoryByteReader(payload)
    guard let index = UInt32(exactly: try reader.readVarint()) else { throw HistoryCodecError.malformed }
    return (index, try reader.readLabel())
  }

  /// Entries refer to processes by the per-file index of their definition record.
  static func encode(_ bucket: HistoryProcessBucket, indices: [ProcessIdentity: UInt32]) -> [UInt8] {
    let entries = bucket.entries.compactMap { entry in indices[entry.identity].map { (entry, $0) } }
    var payload = HistoryByteWriter()
    payload.write(bucket.time.timeIntervalSinceReferenceDate)
    payload.write(Float(bucket.duration))
    payload.writeVarint(UInt64(entries.count))
    for (entry, index) in entries {
      payload.writeVarint(UInt64(index))
      payload.writeVarint(UInt64(entry.sampleCount))
      let present = HistoryProcessMetric.all.filter { !entry.values[$0.rawValue].isNaN }
      payload.write(present.reduce(UInt8(0)) { $0 | 1 << $1.rawValue })
      for metric in present { payload.write(entry.values[metric.rawValue]) }
    }
    return HistoryFileFormat.frame(.processBucket, payload)
  }

  static func decodeBucket(
    _ payload: UnsafeRawBufferPointer, definitions: [UInt32: HistoryProcessLabel]
  ) throws -> HistoryProcessBucket {
    var reader = HistoryByteReader(payload)
    let start = try reader.readDouble()
    let duration = Double(try reader.readFloat())
    guard start.isFinite, duration.isFinite, duration > 0 else { throw HistoryCodecError.malformed }
    let count = try reader.readVarint()
    var entries: [HistoryProcessEntry] = []
    // Every entry takes at least a byte, so a larger count is damage, not data.
    for _ in 0..<min(count, UInt64(payload.count)) {
      let index = try reader.readVarint()
      let sampleCount = try reader.readVarint()
      let mask = try reader.read(UInt8.self)
      var values = ProcessValues(repeating: .nan)
      for metric in HistoryProcessMetric.all where mask & (1 << metric.rawValue) != 0 {
        values[metric.rawValue] = try reader.readFloat()
      }
      guard let key = UInt32(exactly: index), let label = definitions[key] else { continue }
      entries.append(
        HistoryProcessEntry(
          identity: label.identity, name: label.name, project: label.project,
          sampleCount: Int(clamping: sampleCount), values: values))
    }
    return HistoryProcessBucket(
      time: Date(timeIntervalSinceReferenceDate: start), duration: duration, entries: entries)
  }

  static func encode(_ episode: Episode) -> [UInt8] {
    var payload = HistoryByteWriter()
    payload.write(episode.kind.rawValue)
    payload.write(UInt8(episode.process == nil ? 0 : 1) | UInt8(episode.end == nil ? 0 : 2))
    if let process = episode.process { payload.write(process) }
    payload.write(episode.start.timeIntervalSinceReferenceDate)
    if let end = episode.end { payload.write(end.timeIntervalSinceReferenceDate) }
    payload.write(episode.lastObserved.timeIntervalSinceReferenceDate)
    payload.write(episode.peak)
    payload.write(episode.average)
    return HistoryFileFormat.frame(.episode, payload)
  }

  static func decodeEpisode(_ payload: UnsafeRawBufferPointer) throws -> Episode {
    var reader = HistoryByteReader(payload)
    guard let kind = EpisodeKind(rawValue: try reader.read(UInt8.self)) else { throw HistoryCodecError.malformed }
    let flags = try reader.read(UInt8.self)
    let process = try flags & 1 != 0 ? reader.readLabel() : nil
    let start = try reader.readDate()
    let end = try flags & 2 != 0 ? reader.readDate() : nil
    let lastObserved = try reader.readDate()
    let peak = try reader.readDouble()
    let average = try reader.readDouble()
    // Values shown as numbers must be finite; a damaged record is skipped like any other.
    guard peak.isFinite, average.isFinite else { throw HistoryCodecError.malformed }
    return Episode(
      kind: kind, process: process, start: start, end: end, lastObserved: lastObserved,
      peak: peak, average: average)
  }
}

struct HistoryByteWriter {
  private(set) var bytes: [UInt8] = []

  mutating func write<T: FixedWidthInteger>(_ value: T) {
    withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) }
  }

  mutating func write(_ value: Float) { write(value.bitPattern) }
  mutating func write(_ value: Double) { write(value.bitPattern) }
  mutating func append(_ other: HistoryByteWriter) { bytes.append(contentsOf: other.bytes) }

  mutating func writeVarint(_ value: UInt64) {
    var remaining = value
    while remaining >= 0x80 {
      bytes.append(UInt8(truncatingIfNeeded: remaining) | 0x80)
      remaining >>= 7
    }
    bytes.append(UInt8(remaining))
  }

  /// Texts are cut at a character boundary to fit a one-byte length.
  mutating func writeText(_ text: String) {
    var length = 0
    for scalar in text.unicodeScalars {
      let size = UTF8.width(scalar)
      guard length + size <= Int(UInt8.max) else { break }
      length += size
    }
    write(UInt8(length))
    bytes.append(contentsOf: text.utf8.prefix(length))
  }

  mutating func write(_ label: HistoryProcessLabel) {
    write(UInt32(bitPattern: label.identity.pid))
    writeVarint(label.identity.startSeconds)
    writeVarint(label.identity.startMicroseconds)
    write(UInt8(label.project == nil ? 0 : 1))
    writeText(label.name)
    if let project = label.project { writeText(project) }
  }
}

struct HistoryByteReader {
  private let bytes: UnsafeRawBufferPointer
  private var offset = 0

  init(_ bytes: UnsafeRawBufferPointer) { self.bytes = bytes }

  mutating func read<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
    let size = MemoryLayout<T>.size
    guard bytes.count - offset >= size else { throw HistoryCodecError.truncated }
    defer { offset += size }
    return T(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: T.self))
  }

  mutating func readFloat() throws -> Float { Float(bitPattern: try read(UInt32.self)) }
  mutating func readDouble() throws -> Double { Double(bitPattern: try read(UInt64.self)) }

  mutating func readDate() throws -> Date {
    let seconds = try readDouble()
    guard seconds.isFinite else { throw HistoryCodecError.malformed }
    return Date(timeIntervalSinceReferenceDate: seconds)
  }

  mutating func readVarint() throws -> UInt64 {
    var value: UInt64 = 0
    for shift in stride(from: 0, to: 64, by: 7) {
      let byte = try read(UInt8.self)
      value |= UInt64(byte & 0x7F) << shift
      if byte & 0x80 == 0 { return value }
    }
    throw HistoryCodecError.malformed
  }

  mutating func readText() throws -> String {
    let length = Int(try read(UInt8.self))
    guard bytes.count - offset >= length else { throw HistoryCodecError.truncated }
    defer { offset += length }
    return String(decoding: UnsafeRawBufferPointer(rebasing: bytes[offset..<offset + length]), as: UTF8.self)
  }

  mutating func readLabel() throws -> HistoryProcessLabel {
    let pid = Int32(bitPattern: try read(UInt32.self))
    let identity = ProcessIdentity(
      pid: pid, startSeconds: try readVarint(), startMicroseconds: try readVarint())
    let hasProject = try read(UInt8.self) != 0
    let name = try readText()
    let project = try hasProject ? readText() : nil
    return HistoryProcessLabel(identity: identity, name: name, project: project)
  }
}

enum CRC32 {
  private static let table: [UInt32] = (0..<256).map { index in
    (0..<8).reduce(UInt32(index)) { crc, _ in crc & 1 != 0 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1 }
  }

  static func checksum(_ bytes: UnsafeRawBufferPointer) -> UInt32 {
    table.withUnsafeBufferPointer { table in
      ~bytes.reduce(~UInt32(0)) { crc, byte in table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
    }
  }
}
