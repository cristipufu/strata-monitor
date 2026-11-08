import Foundation
import StrataCore
import Testing

@testable import StrataSystem

/// Shaped like `ps -ax -o pid=,ppid=,uid=,time=,rss=,state=,comm=` on macOS 26.
private let processTableFixture = """
      1     0     0 183:06.42  24480 Ss   /sbin/launchd
    526     1     0 2892:14.22  61168 Ss   /usr/libexec/logd
    588     1    88   0:41.07  92304 Ss   /System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer
  65700 65690   501   1:02.50 182016 S    /Applications/Example Browser.app/Contents/Frameworks/Example Browser Helper (Renderer).app/Contents/MacOS/Example Browser Helper (Renderer)
  34730 34723   501   0:07.49 845968 U    /usr/bin/swift-build
  40589 40586   501   0:00.00   1216 SN   evil\\012  999 1 0 0:00.00 100 R fake
  38678 96544   501   0:00.00      0 ?E   (Python)
  18000     1   501   0:00.01      0 Z    (zombie)
  18001     1   501   0:03.00   2048 T    /bin/sleep
  18002     1   501   0:00.10   4096 I    /usr/bin/idle-tool
  18003  1800   501   9:59.99  10240 R+   /usr/bin/yes
  71362     1    -2   0:00.21   3120 Ss   /usr/libexec/nobody-daemon

  garbage line
  18004     1   501   0:00.00   1024
  18005     1   501   1:75.00   1024 S    /bin/bad-seconds
     -6     1   501   0:00.00   1024 S    /bin/negative
  18010     1 -99999999999 0:00.00 1024 S    /bin/bad-uid
  18006     1   501   0:00.00     -4 S    /bin/negative-rss
  18007     1   501   0:00.00   1024 S    \r
  18008     1   501   0:00.00   1024 S    /bin/tail-after-crlf\r
  18009
"""

@Suite struct ProcessTableParserTests {
  private let table = ProcessTableParser.parse(Data(processTableFixture.utf8))

  @Test func parsesEveryWellFormedRowAndCountsTheRest() {
    #expect(
      table.records.map(\.pid) == [
        1, 526, 588, 65700, 34730, 40589, 38678, 18000, 18001, 18002, 18003, 71362, 18008,
      ])
    #expect(table.skippedLines == 8)
  }

  @Test func readsFixedColumnsThenTheWholeCommand() throws {
    let browser = try #require(table.records.first { $0.pid == 65700 })
    #expect(browser.parentPID == 65690 && browser.userID == 501)
    #expect(browser.residentBytes == 182_016 * 1024)
    #expect(browser.cpuTimeNanoseconds == 62_500_000_000)
    #expect(browser.command.hasSuffix("MacOS/Example Browser Helper (Renderer)"))
    #expect(browser.command.hasPrefix("/Applications/Example Browser.app/"))
  }

  @Test func escapedLineBreaksStayInsideTheirOwnCommand() throws {
    let escaped = try #require(table.records.first { $0.pid == 40589 })
    #expect(escaped.command == "evil\\012  999 1 0 0:00.00 100 R fake")
    #expect(!table.records.contains { $0.pid == 999 })
  }

  @Test func negativeUIDsAreTheUnsignedAccountsPsPrintsSigned() throws {
    let nobody = try #require(table.records.first { $0.pid == 71362 })
    #expect(nobody.userID == 4_294_967_294)
  }

  @Test func longRunningCPUTimeKeepsAccumulatingMinutes() throws {
    let logd = try #require(table.records.first { $0.pid == 526 })
    #expect(logd.cpuTimeNanoseconds == (2892 * 60 + 14) * 1_000_000_000 + 220_000_000)
  }

  @Test func stateLettersMapToRunStates() {
    let states = Dictionary(uniqueKeysWithValues: table.records.map { ($0.pid, $0.state) })
    #expect(states[1] == .running)
    #expect(states[34730] == .running)
    #expect(states[18002] == .running)
    #expect(states[18003] == .running)
    #expect(states[18001] == .stopped)
    #expect(states[18000] == .zombie)
    #expect(states[38678] == .some(nil))
  }

  @Test(arguments: [
    ("0:00.00", 0), ("0:05.5", 5_500_000_000), ("12:34.56", 754_560_000_000),
    ("1:02:03", 3_723_000_000_000), ("2-01:00:00", 176_400_000_000_000),
    ("0:01.123456789", 1_123_456_789), ("7:00", 420_000_000_000),
  ] as [(String, UInt64)])
  func cpuTimeFormatsBecomeNanoseconds(_ text: String, _ expected: UInt64) {
    #expect(CPUTimeField.nanoseconds(Substring(text)) == expected)
  }

  @Test(arguments: [
    "", "1", ":00", "1:", "1:60.00", "1:2:3:4", "1:60:00", "a:00", "1:00.", "1:00.1234567890",
    "-1:00", "x-1:00:00", "1:0a", "+1:00", "99999999999999999999:00", "307445734561825861:00",
    "213503982336-00:00:00",
  ])
  func malformedOrOverflowingCPUTimesAreRejected(_ text: String) {
    #expect(CPUTimeField.nanoseconds(Substring(text)) == nil)
  }

  @Test func hugeOutputIsParsedLinearlyWithoutRecordsFromGarbage() {
    var lines: [String] = []
    for pid in 1...20_000 {
      lines.append("\(pid) 1 501 0:01.00 16 S /bin/tool \(pid)")
      lines.append(String(repeating: "#", count: pid % 97))
    }
    let parsed = ProcessTableParser.parse(Data(lines.joined(separator: "\n").utf8))
    #expect(parsed.records.count == 20_000)
    #expect(parsed.records.last?.command == "/bin/tool 20000")
    #expect(parsed.skippedLines == lines.count - 20_000 - (1...20_000).filter { $0 % 97 == 0 }.count)
  }

  @Test func invalidUTF8NeverStopsParsing() {
    var data = Data("    5     1   501   0:00.10   16 S    /bin/".utf8)
    data.append(contentsOf: [0xFF, 0xFE])
    data.append(Data("\n    6     1   501   0:00.10   16 S    /bin/ok\n".utf8))
    #expect(ProcessTableParser.parse(data).records.map(\.pid) == [5, 6])
  }
}

@Suite struct ProcessTableReaderTests {
  @Test func readerAsksForTheProcessTableOnly() async throws {
    let tool = ScriptedSystemTool(.processTable, output: processTableFixture)
    let table = try await ProcessTableReader(tool: tool).read()
    #expect(table.records.count == 13)
    #expect(tool.invocations == [.processTable])
  }

  @Test(arguments: ["", "\n\n", "garbage\nmore garbage\n"])
  func outputWithoutAnyProcessIsUnrecognizedRatherThanEmpty(_ output: String) async {
    await #expect(throws: SystemToolError.unrecognizedOutput) {
      try await ProcessTableReader(tool: ScriptedSystemTool(.processTable, output: output)).read()
    }
  }

  @Test func toolFailuresReachTheCaller() async {
    let tool = ScriptedSystemTool([.processTable: .failure(.timedOut)])
    await #expect(throws: SystemToolError.timedOut) { try await ProcessTableReader(tool: tool).read() }
  }
}
