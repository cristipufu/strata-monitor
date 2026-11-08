import StrataCore
import Testing

private let editor = ProcessIdentity(pid: 300, startSeconds: 1_000, startMicroseconds: 5)
private let compiler = ProcessIdentity(pid: 301, startSeconds: 1_001, startMicroseconds: 0)
private let reusedEditorPID = ProcessIdentity(pid: 300, startSeconds: 2_000, startMicroseconds: 0)

private func cpu(_ time: Double, _ counters: [ProcessIdentity: UInt64])
  -> ProcessCounterSnapshot<UInt64>
{
  ProcessCounterSnapshot(capturedAt: time, counters: counters)
}

private func network(_ time: Double, _ counters: [ProcessIdentity: (UInt64, UInt64)])
  -> ProcessCounterSnapshot<NetworkByteCounts>
{
  ProcessCounterSnapshot(
    capturedAt: time,
    counters: counters.mapValues { NetworkByteCounts(bytesIn: $0.0, bytesOut: $0.1) })
}

@Test func cpuPercentIsCPUTimeOverWallTimePerCore() {
  let earlier = cpu(10, [editor: 1_000_000_000, compiler: 0])
  let later = cpu(14, [editor: 3_000_000_000, compiler: 12_000_000_000])
  let percentages = ProcessCPUUsage.percentages(from: earlier, to: later)
  #expect(percentages[editor] == 50)
  #expect(percentages[compiler] == 300)
}

@Test func reusedPIDNeverInheritsThePreviousOwnersCPUTime() {
  let earlier = cpu(10, [editor: 9_000_000_000])
  let later = cpu(12, [reusedEditorPID: 1_000_000_000])
  #expect(ProcessCPUUsage.percentages(from: earlier, to: later).isEmpty)
}

@Test func cpuTimeThatWentBackwardsHasNoRate() {
  let earlier = cpu(10, [editor: 5_000_000_000, compiler: 1])
  let later = cpu(12, [editor: 4_000_000_000, compiler: 1])
  #expect(ProcessCPUUsage.percentages(from: earlier, to: later) == [compiler: 0])
}

@Test(arguments: [10.0, 9, .nan, .infinity])
func intervalsThatAreNotForwardHaveNoRates(_ laterTime: Double) {
  let earlier = cpu(10, [editor: 1])
  let later = cpu(laterTime, [editor: 2])
  #expect(ProcessCPUUsage.percentages(from: earlier, to: later).isEmpty)
}

@Test func processesSeenOnceHaveNoRate() {
  let earlier = cpu(10, [editor: 1])
  let later = cpu(12, [editor: 1, compiler: 50])
  #expect(ProcessCPUUsage.percentages(from: earlier, to: later).keys.sorted { $0.pid < $1.pid } == [editor])
}

@Test func pidKeyedCountersJoinOnlyWithTheirOwnIdentity() {
  let snapshot = ProcessCounterSnapshot<UInt64>(
    capturedAt: 1, countersByPID: [300: 7, 301: 8, 302: 9],
    identities: [300: editor, 301: reusedEditorPID])
  #expect(snapshot.counters == [editor: 7])
}

@Test func networkRatesFollowBothDirections() throws {
  let earlier = network(20, [editor: (1_000, 500)])
  let later = network(22, [editor: (5_000, 700)])
  let rate = try #require(NetworkUsageRates.rates(from: earlier, to: later)[editor])
  #expect(rate.received == 2_000 && rate.sent == 100)
}

@Test(arguments: [(UInt64(900), UInt64(700)), (5_000, 400), (0, 0)])
func networkCounterResetsHaveNoRate(_ bytesIn: UInt64, _ bytesOut: UInt64) {
  let earlier = network(20, [editor: (1_000, 500)])
  let later = network(22, [editor: (bytesIn, bytesOut)])
  #expect(NetworkUsageRates.rates(from: earlier, to: later).isEmpty)
}

@Test func networkRatesNeverPairAReusedPID() {
  let earlier = network(20, [editor: (1_000, 500)])
  let later = network(22, [reusedEditorPID: (9_000, 9_000), compiler: (1, 1)])
  #expect(NetworkUsageRates.rates(from: earlier, to: later).isEmpty)
}
