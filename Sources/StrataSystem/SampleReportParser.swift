import Foundation
import StrataCore

/// Reads the report `/usr/bin/sample` writes: a `Process:` header, a call graph
/// whose thread roots are indented by exactly four spaces, and a "Sort by top of
/// stack" section of `symbol  (in binary)  count` lines.
enum SampleReportParser {
  static func parse(_ text: String) -> SampleReport? {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    guard let process = lines.lazy.compactMap(processHeader).first else { return nil }
    return SampleReport(
      pid: process.pid, processName: process.name,
      topFrames: section(titled: "Sort by top of stack", in: lines).compactMap(frame),
      totalSamples: section(titled: "Call graph:", in: lines).compactMap(threadSampleCount)
        .reduce(0, clampedSum),
      rawText: text)
  }

  static func processHeader(_ line: Substring) -> (name: String, pid: Int32)? {
    guard line.hasPrefix("Process:") else { return nil }
    let value = line.dropFirst("Process:".count).trimmingCharacters(in: .whitespaces)
    guard value.hasSuffix("]"), let open = value.range(of: " [", options: .backwards),
      let pid = Int32(value[open.upperBound..<value.index(before: value.endIndex)]), pid > 0
    else { return nil }
    return (String(value[..<open.lowerBound]), pid)
  }

  static func frame(_ line: Substring) -> SampleFrame? {
    let entry = line.trimmingCharacters(in: .whitespaces)
    guard let gap = entry.lastIndex(where: \.isWhitespace),
      let count = Int(entry[entry.index(after: gap)...]), count > 0
    else { return nil }
    let location = entry[..<gap].trimmingCharacters(in: .whitespaces)
    guard let marker = location.range(of: "(in ", options: .backwards) else {
      return location.isEmpty ? nil : SampleFrame(symbol: location, binary: nil, count: count)
    }
    let symbol = location[..<marker.lowerBound].trimmingCharacters(in: .whitespaces)
    let binary = location[marker.upperBound...].prefix { $0 != ")" }
    guard !symbol.isEmpty else { return nil }
    return SampleFrame(symbol: symbol, binary: binary.isEmpty ? nil : String(binary), count: count)
  }

  static func threadSampleCount(_ line: Substring) -> Int? {
    guard line.hasPrefix("    ") else { return nil }
    let root = line.dropFirst(4)
    let digits = root.prefix { $0.isASCII && $0.isNumber }
    guard !digits.isEmpty, root.dropFirst(digits.count).hasPrefix(" Thread_") else { return nil }
    return Int(digits)
  }

  private static func section(titled title: String, in lines: [Substring]) -> ArraySlice<Substring> {
    guard let heading = lines.firstIndex(where: { $0.hasPrefix(title) }) else { return [] }
    let body = lines[(heading + 1)...]
    let end = body.firstIndex { $0.allSatisfy(\.isWhitespace) } ?? body.endIndex
    return body[..<end]
  }

  private static func clampedSum(_ total: Int, _ count: Int) -> Int {
    let (sum, overflow) = total.addingReportingOverflow(count)
    return overflow ? .max : sum
  }
}
