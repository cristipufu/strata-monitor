import Foundation
import StrataCore

/// Parses `ps -ax -o pid=,ppid=,uid=,time=,rss=,state=,comm=`. The command is the
/// last column and may contain spaces; ps escapes control characters in it, so
/// one line is always one process. Lines are split on UTF-8 bytes because
/// splitting by Character dominated the cost of a full table.
enum ProcessTableParser {
  private static let fixedColumns = 6

  static func parse(_ data: Data) -> ExternalProcessTable {
    var records: [ExternalProcessRecord] = []
    var skipped = 0
    let text = String(decoding: data, as: UTF8.self)
    for line in text.utf8.split(whereSeparator: TableText.isLineBreak)
    where !line.allSatisfy(TableText.isBlank) {
      if let record = record(from: Substring(line)) { records.append(record) } else { skipped += 1 }
    }
    return ExternalProcessTable(records: records, skippedLines: skipped)
  }

  /// ps prints UIDs as signed numbers, so nobody (4294967294) appears as -2.
  static func record(from line: Substring) -> ExternalProcessRecord? {
    let fields = line.utf8.split(
      maxSplits: fixedColumns, omittingEmptySubsequences: true, whereSeparator: TableText.isBlank
    ).map(Substring.init)
    guard fields.count == fixedColumns + 1,
      let pid = Int32(fields[0]), pid >= 0,
      let parentPID = Int32(fields[1]), parentPID >= 0,
      let userID = UInt32(fields[2]) ?? Int32(fields[2]).map(UInt32.init(bitPattern:)),
      let cpuTime = CPUTimeField.nanoseconds(fields[3]),
      let residentBytes = UInt64(fields[4]).flatMap(kilobytesToBytes),
      let stateLetter = fields[5].utf8.first
    else { return nil }
    let command = Substring(fields[6].utf8.drop(while: TableText.isBlank))
    guard !command.isEmpty else { return nil }
    return ExternalProcessRecord(
      pid: pid, parentPID: parentPID, userID: userID, cpuTimeNanoseconds: cpuTime,
      residentBytes: residentBytes, state: runState(stateLetter), command: String(command))
  }

  /// Runnable, sleeping, idle and waiting ("R", "S", "I", "U") all count as running,
  /// as they do for processes read from the kernel table.
  static func runState(_ letter: UInt8) -> ProcessRunState? {
    switch letter {
    case UInt8(ascii: "R"), UInt8(ascii: "S"), UInt8(ascii: "I"), UInt8(ascii: "U"): .running
    case UInt8(ascii: "T"): .stopped
    case UInt8(ascii: "Z"): .zombie
    default: nil
    }
  }

  private static func kilobytesToBytes(_ kilobytes: UInt64) -> UInt64? {
    let (bytes, overflow) = kilobytes.multipliedReportingOverflow(by: 1024)
    return overflow ? nil : bytes
  }
}

enum TableText {
  static func isLineBreak(_ byte: UInt8) -> Bool {
    byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r")
  }
  static func isBlank(_ byte: UInt8) -> Bool {
    byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t")
  }
  static func isDigit(_ byte: UInt8) -> Bool {
    (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
  }
}

/// ps prints CPU time as minutes:seconds.hundredths (`1386:57.76`) and never
/// rolls minutes into hours. Hours and days (`[d-]h:mm:ss`) are accepted too.
enum CPUTimeField {
  static func nanoseconds(_ text: Substring) -> UInt64? {
    let (dayText, clock) = splitDays(text)
    let (wholeText, fractionText) = splitFraction(clock)
    let fields = wholeText.utf8.split(separator: UInt8(ascii: ":"), omittingEmptySubsequences: false)
      .map(Substring.init)
    let parts = fields.compactMap(digits)
    guard (2...3).contains(fields.count), parts.count == fields.count,
      parts.dropFirst().allSatisfy({ $0 < 60 })
    else { return nil }
    var days: UInt64 = 0
    var fraction: UInt64 = 0
    if let dayText {
      guard let value = digits(dayText) else { return nil }
      days = value
    }
    if let fractionText {
      guard let value = fractionNanoseconds(fractionText) else { return nil }
      fraction = value
    }
    let hours = multiplyAdd(days, 24, parts.count == 3 ? parts[0] : 0)
    let seconds = parts.suffix(2).reduce(hours) { total, part in multiplyAdd(total, 60, part) }
    return multiplyAdd(seconds, 1_000_000_000, fraction)
  }

  private static func splitDays(_ text: Substring) -> (days: Substring?, clock: Substring) {
    guard let dash = text.utf8.firstIndex(of: UInt8(ascii: "-")) else { return (nil, text) }
    return (text[..<dash], text[text.utf8.index(after: dash)...])
  }
  private static func splitFraction(_ text: Substring) -> (whole: Substring, fraction: Substring?) {
    guard let dot = text.utf8.firstIndex(of: UInt8(ascii: ".")) else { return (text, nil) }
    return (text[..<dot], text[text.utf8.index(after: dot)...])
  }
  private static func digits(_ text: Substring) -> UInt64? {
    guard !text.isEmpty, text.utf8.allSatisfy(TableText.isDigit) else { return nil }
    return UInt64(text)
  }
  private static func fractionNanoseconds(_ text: Substring) -> UInt64? {
    guard (1...9).contains(text.utf8.count), let value = digits(text) else { return nil }
    return (text.utf8.count..<9).reduce(value) { scaled, _ in scaled * 10 }
  }
  private static func multiplyAdd(_ value: UInt64?, _ factor: UInt64, _ addend: UInt64) -> UInt64? {
    guard let value else { return nil }
    let (product, productOverflow) = value.multipliedReportingOverflow(by: factor)
    let (sum, sumOverflow) = product.addingReportingOverflow(addend)
    return productOverflow || sumOverflow ? nil : sum
  }
}
