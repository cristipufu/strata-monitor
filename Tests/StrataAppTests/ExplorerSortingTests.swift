import Foundation
import StrataCore
import Testing

@testable import StrataBar

@Test func processSortDescriptorsRoundTripAndStartInEachKeysNaturalDirection() {
  for key in ProcessSort.allCases {
    let order = ProcessOrder(key)
    #expect(ProcessOrder(order.descriptor) == order)
    let textual: Set<ProcessSort> = [.name, .path, .pid, .user, .state, .kind]
    #expect(order.ascending == textual.contains(key), "Measurements and start times start highest")
  }
  #expect(ProcessOrder(NSSortDescriptor(key: "unknown", ascending: true)) == nil)
  #expect(ProcessOrder(NSSortDescriptor(key: nil, ascending: true)) == nil)
}

@Test func theClickedHeaderBecomesTheOrderAndUnknownDescriptorsLeaveItUnchanged() {
  var order = ProcessOrder(.name)
  order.descriptors = [
    NSSortDescriptor(key: ProcessSort.cpu.rawValue, ascending: true),
    ProcessOrder(.name).descriptor,
  ]
  #expect(order == ProcessOrder(.cpu, ascending: true))
  #expect(order.descriptors == [NSSortDescriptor(key: ProcessSort.cpu.rawValue, ascending: true)])
  order.descriptors = [ResourceOrder(.location).descriptor]
  order.descriptors = []
  #expect(order == ProcessOrder(.cpu, ascending: true))
}

@Test func reversingAMeasurementKeepsUnavailableProcessesLastAndTiesInPIDOrder() {
  let processes = [
    sortingProcess(5, cpu: .nan, footprint: nil), sortingProcess(30, cpu: 0, footprint: 300),
    sortingProcess(20, cpu: 80, footprint: 100), sortingProcess(10, cpu: 80, footprint: 200),
  ]
  func pids(_ order: ProcessOrder) -> [Int32] {
    processes.sorted(by: order.areInIncreasingOrder).map(\.id.pid)
  }
  #expect(pids(ProcessOrder(.cpu)) == [10, 20, 30, 5])
  #expect(pids(ProcessOrder(.cpu, ascending: true)) == [30, 10, 20, 5])
  #expect(pids(ProcessOrder(.memory)) == [30, 10, 20, 5])
  #expect(pids(ProcessOrder(.memory, ascending: true)) == [20, 10, 30, 5])
  #expect(pids(ProcessOrder(.pid, ascending: false)) == [30, 20, 10, 5])
  #expect(pids(ProcessOrder(.name)) == [5, 10, 20, 30])
}

@Test func familyRowsFollowTheChosenOrderAtEveryLevel() {
  let root = sortingProcess(10, parent: 1, cpu: 1, footprint: 100)
  let quiet = sortingProcess(20, parent: 10, cpu: 2, footprint: 100)
  let busy = sortingProcess(30, parent: 10, cpu: 50, footprint: 100)
  let separate = sortingProcess(40, parent: 1, cpu: 10, footprint: 100)
  let processes = [separate, busy, quiet, root]
  let descending = ProcessTreeSnapshot(families: ProcessFamilies(processes), query: "", order: ProcessOrder(.cpu))
  #expect(descending.rows.map(\.id.pid) == [10, 30, 40, 20])
  let ascending = ProcessTreeSnapshot(
    families: ProcessFamilies(processes), query: "", order: ProcessOrder(.cpu, ascending: true))
  #expect(ascending.rows.map(\.id.pid) == [20, 40, 30, 10])
}

@Test func leadingFamiliesRankByTheirTotalsAndSkipUnmeasuredOnes() {
  let shell = sortingProcess(10, parent: 1, cpu: 1, footprint: 100)
  let busyChild = sortingProcess(11, parent: 10, cpu: 90, footprint: 50)
  let single = sortingProcess(20, parent: 1, cpu: 60, footprint: 900)
  let unmeasured = sortingProcess(30, parent: 1, cpu: nil, footprint: nil)
  let roots = ProcessFamilies([unmeasured, single, busyChild, shell]).roots
  #expect(ProcessSort.cpu.ranked(roots).map(\.id.pid) == [10, 20])
  #expect(ProcessSort.memory.ranked(roots).map(\.id.pid) == [20, 10])
  #expect(ProcessSort.cpu.ranked(roots, limit: 1).map(\.id.pid) == [10])
  #expect(ProcessSort.memory.ranked(roots, limit: 1).map(\.id.pid) == [20])
}

@Test func aLimitedRankingKeepsTheSameLeadersAsAFullOne() {
  let processes = (0..<200).map { (index: Int) -> ProcessSample in
    let cpu = Double(index * 37 % 101)
    let footprint = UInt64(index * 53 % 97)
    return sortingProcess(Int32(100 + index), cpu: cpu, footprint: footprint)
  }
  let roots = ProcessFamilies(processes).roots
  for sort in [ProcessSort.cpu, .memory] {
    #expect(sort.ranked(roots, limit: 3).map(\.id) == Array(sort.ranked(roots).prefix(3)).map(\.id))
  }
}

@Test func resourceColumnsSortByTheirDisplayedValuesWithStableTies() {
  let resources = [
    sortingResource(pid: 30, name: "zsh", descriptor: 4, path: "/tmp/b"),
    sortingResource(pid: 10, name: "Finder", descriptor: 9, path: "/tmp/a"),
    sortingResource(
      pid: 10, name: "Finder", descriptor: 3, kind: .tcp, port: 8080, state: "Listening"),
  ]
  func descriptors(_ order: ResourceOrder) -> [Int32] {
    resources.sorted(by: order.areInIncreasingOrder).map(\.descriptor)
  }
  #expect(ResourceOrder(.process).ascending)
  #expect(descriptors(ResourceOrder(.process)) == [3, 9, 4])
  #expect(descriptors(ResourceOrder(.process, ascending: false)) == [4, 3, 9])
  #expect(descriptors(ResourceOrder(.pid, ascending: false)) == [4, 3, 9])
  #expect(descriptors(ResourceOrder(.kind)) == [9, 4, 3])
  #expect(descriptors(ResourceOrder(.state, ascending: false)) == [3, 9, 4])
  let files = resources.filter { $0.kind == .file }
  #expect(
    files.sorted(by: ResourceOrder(.location).areInIncreasingOrder).map(\.location) == [
      "/tmp/a", "/tmp/b",
    ])
}

@Test @MainActor func sortedRowsAreReusedUntilTheReportOrOrderChanges() {
  let counter = ComparisonCounter()
  let report = [3, 1, 2].map { CountedRow(value: $0, counter: counter) }
  let cache = SortedRowCache<CountedRow, ExplorerSortOrder<CountedSort>>()
  #expect(cache.rows(report, orderedBy: ExplorerSortOrder(.value)).map(\.value) == [1, 2, 3])
  let comparisons = counter.comparisons
  #expect(comparisons > 0)
  #expect(cache.rows(report, orderedBy: ExplorerSortOrder(.value)).map(\.value) == [1, 2, 3])
  #expect(counter.comparisons == comparisons)
  let replacement = [6, 4, 5].map { CountedRow(value: $0, counter: counter) }
  #expect(cache.rows(replacement, orderedBy: ExplorerSortOrder(.value)).map(\.value) == [4, 5, 6])
  #expect(
    cache.rows(replacement, orderedBy: ExplorerSortOrder(.value, ascending: false)).map(\.value)
      == [6, 5, 4])
}

private final class ComparisonCounter {
  var comparisons = 0
}

private struct CountedRow {
  let value: Int
  let counter: ComparisonCounter
}

private enum CountedSort: String, ExplorerSortKey {
  case value
  func compareValues(_ lhs: CountedRow, _ rhs: CountedRow) -> ComparisonResult {
    lhs.counter.comparisons += 1
    return ComparisonResult(comparing: lhs.value, to: rhs.value)
  }
  static func precedesWhenTied(_ lhs: CountedRow, _ rhs: CountedRow) -> Bool { false }
}

private func sortingProcess(
  _ pid: Int32, parent: Int32 = 1, cpu: Double?, footprint: UInt64?
) -> ProcessSample {
  ProcessSample(
    id: ProcessIdentity(pid: pid, startSeconds: 1, startMicroseconds: 0), parentPID: parent,
    userID: 501, name: "Process \(pid)", path: "", cpuTimeNanoseconds: nil, cpuPercent: cpu,
    residentBytes: nil, footprintBytes: footprint, threads: nil)
}

private func sortingResource(
  pid: Int32, name: String, descriptor: Int32, kind: ResourceKind = .file, path: String = "",
  port: UInt16 = 0, state: String = ""
) -> ProcessResource {
  ProcessResource(
    owner: ProcessIdentity(pid: pid, startSeconds: 1, startMicroseconds: 0), processName: name,
    descriptor: descriptor, kind: kind, path: path, localAddress: port > 0 ? "127.0.0.1" : "",
    localPort: port, state: state)
}
