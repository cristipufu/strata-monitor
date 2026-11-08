import Foundation
import StrataCore
import Testing

@testable import StrataSystem

/// Shaped like `nettop -P -L 1 -x -n -J bytes_in,bytes_out` on macOS 26.
private let nettopFixture = """
  ,bytes_in,bytes_out,
  launchd.1,0,0,
  mDNSResponder.648,113848177,17558837,
  Example Brows H.65700,182582,183757,
  com.example.age.845,7744,5796,
  kernel_task.0,10,20,

  odd,name.71,5,6,
  no-pid-suffix,1,2,
  empty-suffix.,1,2,
  negative.-4,1,2,
  letters.12a,1,2,
  not-a-number.77,many,2,
  short-row.78,1
  overflow.79,99999999999999999999,1,
  spoof.648,1,1,
  """

@Suite struct NetworkUsageParserTests {
  @Test func rowsAreKeyedByThePIDSuffix() throws {
    let usage = try NetworkUsageParser.parse(Data(nettopFixture.utf8))
    #expect(usage.countsByPID[1] == NetworkByteCounts(bytesIn: 0, bytesOut: 0))
    #expect(usage.countsByPID[65700] == NetworkByteCounts(bytesIn: 182_582, bytesOut: 183_757))
    #expect(usage.countsByPID[845] == NetworkByteCounts(bytesIn: 7744, bytesOut: 5796))
    #expect(usage.countsByPID[0] == NetworkByteCounts(bytesIn: 10, bytesOut: 20))
  }

  @Test func namesWithCommasStillFindTheirValues() throws {
    let usage = try NetworkUsageParser.parse(Data(nettopFixture.utf8))
    #expect(usage.countsByPID[71] == NetworkByteCounts(bytesIn: 5, bytesOut: 6))
  }

  @Test func malformedAndDuplicatedRowsAreDroppedAndCounted() throws {
    let usage = try NetworkUsageParser.parse(Data(nettopFixture.utf8))
    #expect(usage.countsByPID[648] == nil)
    #expect(Set(usage.countsByPID.keys) == [1, 65700, 845, 0, 71])
    #expect(usage.skippedRows == 9)
  }

  @Test func columnsFollowTheHeaderOrder() throws {
    let reordered = ",bytes_out,rx_dupe,bytes_in,\nnode.42,700,3,100,\n"
    let usage = try NetworkUsageParser.parse(Data(reordered.utf8))
    #expect(usage.countsByPID == [42: NetworkByteCounts(bytesIn: 100, bytesOut: 700)])
  }

  @Test func headerAloneMeansNoSockets() throws {
    let usage = try NetworkUsageParser.parse(Data(",bytes_in,bytes_out,\n".utf8))
    #expect(usage.countsByPID.isEmpty && usage.skippedRows == 0)
  }

  @Test(arguments: [
    "", "\n", "launchd.1,0,0,\n", "name,bytes_in,bytes_out,\nx.1,0,0,\n", ",bytes_in,\nx.1,0,\n",
  ])
  func outputWithoutTheExpectedHeaderIsUnrecognized(_ output: String) {
    #expect(throws: SystemToolError.unrecognizedOutput) {
      try NetworkUsageParser.parse(Data(output.utf8))
    }
  }

  @Test func manyRowsParseWithoutLimits() throws {
    let rows = (1...50_000).map { "proc.\($0),\($0),\($0 * 2)," }
    let output = ([",bytes_in,bytes_out,"] + rows).joined(separator: "\n")
    let usage = try NetworkUsageParser.parse(Data(output.utf8))
    #expect(usage.countsByPID.count == 50_000)
    #expect(usage.countsByPID[50_000] == NetworkByteCounts(bytesIn: 50_000, bytesOut: 100_000))
  }
}

@Suite struct NetworkUsageReaderTests {
  @Test func readerAsksForNetworkUsageOnly() async throws {
    let tool = ScriptedSystemTool(.networkUsage, output: nettopFixture)
    let usage = try await NetworkUsageReader(tool: tool).read()
    #expect(usage.countsByPID.count == 5)
    #expect(tool.invocations == [.networkUsage])
  }

  @Test func toolFailuresReachTheCaller() async {
    let tool = ScriptedSystemTool([.networkUsage: .failure(.outputLimitExceeded(limit: 8))])
    await #expect(throws: SystemToolError.outputLimitExceeded(limit: 8)) {
      try await NetworkUsageReader(tool: tool).read()
    }
  }
}

private final class ScriptedNetworkUsage: NetworkUsageReading, @unchecked Sendable {
  private let lock = NSLock()
  private var readings: [ProcessNetworkUsage?]
  init(_ readings: [ProcessNetworkUsage?]) { self.readings = readings }
  func read() async throws -> ProcessNetworkUsage {
    let next = lock.withLock { readings.isEmpty ? nil : readings.removeFirst() }
    guard let next else { throw SystemToolError.unrecognizedOutput }
    return next
  }
}

@Test func networkUsageBecomesRatesPerProcessAndRestartsAfterAFailure() async throws {
  let identity = ProcessIdentity(pid: 30, startSeconds: 1, startMicroseconds: 0)
  func usage(_ bytesIn: UInt64) -> ProcessNetworkUsage {
    ProcessNetworkUsage(
      countsByPID: [30: NetworkByteCounts(bytesIn: bytesIn, bytesOut: 0)], skippedRows: 0)
  }
  let clock = NetworkClock()
  let collector = NetworkUsageCollector(
    reader: ScriptedNetworkUsage([usage(1_000), usage(9_000), nil, usage(20_000)]),
    refreshInterval: 4, uptime: { clock.now })
  #expect(await collector.sample(of: [identity]) == .measuring, "The first reading is a baseline")
  clock.now += 2
  #expect(await collector.sample(of: [identity]) == .measuring, "Within the interval nothing launches")
  clock.now += 2
  #expect(await collector.sample(of: [identity]).rates[identity]?.received == 2_000)
  clock.now += 4
  #expect(await collector.sample(of: [identity]) == .unavailable, "A failure is not shown as quiet")
  clock.now += 4
  #expect(await collector.sample(of: [identity]) == .measuring, "A failure drops the old baseline")
}

private final class NetworkClock: @unchecked Sendable {
  var now: TimeInterval = 10
}
