import Foundation
import Testing

@testable import StrataCore

private func payload(of frame: [UInt8]) -> [UInt8] { Array(frame.dropFirst(HistoryFileFormat.frameOverhead + 1)) }

@Test func checksumMatchesTheStandardCheckValue() {
  let checksum = Array("123456789".utf8).withUnsafeBytes(CRC32.checksum)
  #expect(checksum == 0xCBF4_3926)
}

@Test func systemPointsRoundTripWithOnlyTheirMeasuredFields() throws {
  let full = HistorySystemPoint(
    time: historyTime(12.5), uptime: 3_600.25, cpu: 0.5, memoryUsedFraction: 0.75, memoryPressure: .elevated,
    swapBytes: 1_048_576, networkInBytesPerSecond: 1_024, networkOutBytesPerSecond: 512,
    diskReadBytesPerSecond: 2_048, diskWriteBytesPerSecond: 4_096, gpu: 0.25, systemWatts: 12.5, thermal: .critical)
  let sparse = HistorySystemPoint(time: historyTime(14), cpu: 0.125)
  for point in [full, sparse] {
    let decoded = try payload(of: HistoryRecordCodec.encode(point)).withUnsafeBytes(HistoryRecordCodec.decodeSystem)
    #expect(decoded == point)
  }
  #expect(HistoryRecordCodec.encode(sparse).count < HistoryRecordCodec.encode(full).count)
  #expect(HistoryRecordCodec.encode(full).count == 65)
}

@Test func processIntervalsReferToPerFileDefinitions() throws {
  let label = HistoryProcessLabel(identity: historyIdentity(4), name: "bun", project: "culprit")
  let entry = HistoryProcessEntry(
    identity: label.identity, name: "bun", project: "culprit", sampleCount: 6, cpuPercent: 42, footprintBytes: 2_048)
  let unknown = HistoryProcessEntry(identity: historyIdentity(5), name: "gone", project: nil, sampleCount: 1, cpuPercent: 1)
  let bucket = HistoryProcessBucket(time: historyTime(60), duration: 60, entries: [entry, unknown])
  let definition = payload(of: HistoryRecordCodec.encodeDefinition(index: 300, label: label))
  let (index, decodedLabel) = try definition.withUnsafeBytes(HistoryRecordCodec.decodeDefinition)
  #expect(index == 300)
  #expect(decodedLabel == label)
  let encoded = payload(of: HistoryRecordCodec.encode(bucket, indices: [label.identity: 300, unknown.identity: 301]))
  let decoded = try encoded.withUnsafeBytes { try HistoryRecordCodec.decodeBucket($0, definitions: [300: label]) }
  #expect(decoded == HistoryProcessBucket(time: historyTime(60), duration: 60, entries: [entry]))
}

@Test func episodesRoundTripWhetherOngoingOrEnded() throws {
  let process = Episode(
    kind: .memoryGrowth, process: HistoryProcessLabel(identity: historyIdentity(9), name: "Xcode", project: nil),
    start: historyTime(0), end: historyTime(600), lastObserved: historyTime(610), peak: 6e9, average: 3e9)
  let system = Episode(
    kind: .systemCPU, process: nil, start: historyTime(5), end: nil, lastObserved: historyTime(200), peak: 1,
    average: 0.95)
  for episode in [process, system] {
    let decoded = try payload(of: HistoryRecordCodec.encode(episode)).withUnsafeBytes(HistoryRecordCodec.decodeEpisode)
    #expect(decoded == episode)
  }
}

@Test func longNamesAreCutAtACharacterBoundary() throws {
  let name = String(repeating: "é", count: 200)
  var writer = HistoryByteWriter()
  writer.writeText(name)
  let decoded = try writer.bytes.withUnsafeBytes { bytes in
    var reader = HistoryByteReader(bytes)
    return try reader.readText()
  }
  #expect(decoded == String(repeating: "é", count: 127))
}

@Test func truncatedOrMalformedPayloadsAreRejected() {
  let frame = HistoryRecordCodec.encode(HistorySystemPoint(time: historyTime(0), cpu: 0.5))
  let cut = Array(payload(of: frame).dropLast())
  #expect(throws: HistoryCodecError.truncated) { try cut.withUnsafeBytes(HistoryRecordCodec.decodeSystem) }
  let overlong = [UInt8](repeating: 0xFF, count: 11)
  #expect(throws: HistoryCodecError.malformed) {
    try overlong.withUnsafeBytes { bytes in
      var reader = HistoryByteReader(bytes)
      return try reader.readVarint()
    }
  }
}

@Test func scanningSkipsDamagedRecordsAndStopsAtATornTail() {
  let records = (0..<3).map { HistoryRecordCodec.encode(HistorySystemPoint(time: historyTime(Double($0)), cpu: 0.5)) }
  var file = HistoryFileFormat.header + records.joined()
  file[HistoryFileFormat.header.count + records[0].count + 12] ^= 0xFF
  let complete = file.count
  file += Array(HistoryRecordCodec.encode(HistorySystemPoint(time: historyTime(9))).prefix(10))
  var visited = 0
  let scan = file.withUnsafeBytes { bytes in
    HistoryFileFormat.scan(bytes) { kind, _ in
      if kind == HistoryRecordKind.system.rawValue { visited += 1 }
    }
  }
  #expect(visited == 2)
  #expect(scan.skippedRecords == 1)
  #expect(scan.validLength == complete)
}

@Test func anEpisodeWithANonFiniteValueIsRejectedAsDamaged() throws {
  let damaged = Episode(
    kind: .cpu, process: HistoryProcessLabel(identity: historyIdentity(9), name: "x", project: nil),
    start: historyTime(0), end: nil, lastObserved: historyTime(10), peak: .nan, average: .infinity)
  let bytes = payload(of: HistoryRecordCodec.encode(damaged))
  #expect(throws: (any Error).self) { try bytes.withUnsafeBytes(HistoryRecordCodec.decodeEpisode) }
}
