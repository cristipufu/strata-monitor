import Foundation
import StrataCore
import Testing

@Test func unavailableMemoryFieldsDoNotBecomeZeroAndTotalsDoNotOverflow() {
  let memory = MemorySample(
    total: 100, active: .max, wired: .max, compressed: .max,
    cached: 0, free: 0, swap: nil, pressure: .unavailable)
  #expect(memory.swap == nil)
  #expect(memory.used == 100 && memory.fraction == 1)
}

@Test func datagramPortOwnershipIsDifferentFromTCPListening() {
  let owner = ProcessIdentity(pid: 1, startSeconds: 1, startMicroseconds: 1)
  let udp = ProcessResource(
    owner: owner, processName: "DNS", descriptor: 7, kind: .udp,
    localAddress: "::1", remoteAddress: "2001:db8::1", localPort: 53, remotePort: 9000,
    state: "Connected datagram")
  #expect(udp.ownsLocalPort && !udp.isListener)
  #expect(udp.endpoint == "[::1]:53")
  #expect(udp.remoteEndpoint == "[2001:db8::1]:9000")
  #expect(ExplorerQuery("port:53").matches(udp))
}

@Test func partialScanReasonsSurviveAggregationAndExport() throws {
  var first = ScanSummary()
  first.restricted = true
  var second = ScanSummary()
  second.failed = true
  second.failureMessage = "The query failed"
  second.unreadableHandles = 2
  first.merge(second)
  #expect(!first.isComplete)
  #expect(first.restricted && first.failed && first.unreadableHandles == 2)
  #expect(first.explanation == "The query failed")
  let report = ResourceReport(resources: [], summary: first)
  let restored = try JSONDecoder().decode(ResourceReport.self, from: JSONEncoder().encode(report))
  #expect(restored.summary.failed && restored.summary.restricted)
}
