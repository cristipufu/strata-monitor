import Foundation
import StrataCore

/// Parses nettop's per-process CSV. Columns are located through the header row,
/// since nettop does not promise their order. Names are truncated and end with
/// `.<pid>`; a name may itself contain commas, so value columns are counted from
/// the end of the row.
enum NetworkUsageParser {
  static func parse(_ data: Data) throws -> ProcessNetworkUsage {
    let lines = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline)
      .filter { !$0.allSatisfy(\.isWhitespace) }
    guard let header = lines.first, let columns = NetworkUsageColumns(header: header) else {
      throw SystemToolError.unrecognizedOutput
    }
    var counts: [Int32: NetworkByteCounts] = [:]
    var rowsPerPID: [Int32: Int] = [:]
    var skipped = 0
    for line in lines.dropFirst() {
      guard let (pid, row) = columns.row(line) else {
        skipped += 1
        continue
      }
      counts[pid] = row
      rowsPerPID[pid, default: 0] += 1
    }
    // nettop prints one row per process; a repeated PID means a process name
    // contained a line break, so none of its rows is trusted.
    for (pid, rows) in rowsPerPID where rows > 1 {
      counts[pid] = nil
      skipped += rows
    }
    return ProcessNetworkUsage(countsByPID: counts, skippedRows: skipped)
  }
}

private struct NetworkUsageColumns {
  let count: Int
  let bytesIn: Int
  let bytesOut: Int

  init?(header: Substring) {
    let names = header.split(separator: ",", omittingEmptySubsequences: false)
    guard names.first?.isEmpty == true, let bytesIn = names.firstIndex(of: "bytes_in"),
      let bytesOut = names.firstIndex(of: "bytes_out")
    else { return nil }
    count = names.count
    self.bytesIn = bytesIn
    self.bytesOut = bytesOut
  }

  func row(_ line: Substring) -> (pid: Int32, counts: NetworkByteCounts)? {
    let fields = line.split(separator: ",", omittingEmptySubsequences: false)
    guard fields.count >= count else { return nil }
    let nameEnd = fields.count - count
    guard let pid = Self.pid(endingName: fields[nameEnd]),
      let bytesIn = UInt64(fields[nameEnd + bytesIn]),
      let bytesOut = UInt64(fields[nameEnd + bytesOut])
    else { return nil }
    return (pid, NetworkByteCounts(bytesIn: bytesIn, bytesOut: bytesOut))
  }

  private static func pid(endingName field: Substring) -> Int32? {
    guard let dot = field.lastIndex(of: ".") else { return nil }
    let digits = field[field.index(after: dot)...]
    guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
    return Int32(digits)
  }
}
