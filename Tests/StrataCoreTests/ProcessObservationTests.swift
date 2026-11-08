import Foundation
import StrataCore
import Testing

private func observedProcess(
  _ pid: Int32, parent: Int32 = 1, start: UInt64 = 1,
  cpu: Double? = 25, memory: UInt64? = 100
) -> ProcessSample {
  ProcessSample(
    id: ProcessIdentity(pid: pid, startSeconds: start, startMicroseconds: 0),
    parentPID: parent, userID: 501, name: "Worker \(pid)", path: "/tmp/worker",
    cpuTimeNanoseconds: nil, cpuPercent: cpu, residentBytes: nil, footprintBytes: memory,
    threads: nil)
}
private func observedSample(_ time: Double, _ processes: [ProcessSample], scanned: Bool = true)
  -> SystemSample
{
  SystemSample(
    uptime: time, cpu: nil, cores: [], memory: nil, network: nil, interfaces: [],
    processes: processes,
    processScan: scanned ? ScanSummary() : nil)
}

@Test func processHistoryStartsAtSelectionAndDoesNotAttachToReusedPID() {
  var history = ObservedProcessHistory()
  let original = observedProcess(10)
  history.track(original.id, at: 20)
  history.append(observedSample(19, [original]))
  history.append(observedSample(20, [original]))
  history.append(observedSample(21, [], scanned: false))
  history.append(observedSample(22, [observedProcess(10, start: 2)]))
  #expect(history.points.map(\.uptime) == [20, 22])
  #expect(history.points.first?.cpu == 0.25)
  #expect(history.points.last?.present == false)
  #expect(history.points.last?.footprint == nil)
  history.track(original.id, at: 23)
  #expect(history.points.count == 2)
  history.track(observedProcess(20).id, at: 23)
  #expect(history.points.isEmpty)
  history.track(nil, at: 24)
  history.append(observedSample(25, [original]))
  #expect(history.points.isEmpty)
}

@Test func processHistoryRejectsInvalidRatesAndBoundsBothTimeAndCount() {
  var history = ObservedProcessHistory()
  let process = observedProcess(10, cpu: .nan)
  history.track(process.id, at: 0)
  history.append(observedSample(.nan, [process]))
  for index in 0..<500 { history.append(observedSample(Double(index) / 100, [process])) }
  #expect(history.points.count == 240)
  #expect(history.points.allSatisfy { $0.cpu == nil })
  history.append(observedSample(70, [process]))
  history.append(observedSample(69, [process]))
  #expect(history.points.count == 1)
  #expect(history.points.first?.uptime == 70)
}

@Test func processFamiliesPartitionNestedChildrenWithoutDoubleCounting() throws {
  let root = observedProcess(10, cpu: 20, memory: 200)
  let child = observedProcess(20, parent: 10, cpu: 30, memory: 300)
  let grandchild = observedProcess(30, parent: 20, cpu: nil, memory: nil)
  let separate = observedProcess(40)
  let families = ProcessFamilies([grandchild, child, root, separate, child])
  #expect(families.roots.count == 2)
  #expect(families.roots.flatMap(\.members).count == 4)
  let family = try #require(families.subtree(of: root.id))
  #expect(family.members.count == 3)
  #expect(family.cpuPercent == 50 && family.footprintBytes == 500)
  #expect(family.hasMissingCPU && family.hasMissingMemory)
  #expect(families.parent(of: grandchild.id)?.id == child.id)
  #expect(families.directChildren(of: root.id).map(\.id) == [child.id])
}

@Test func processFamilyCyclesAndReusedParentsCannotInventDescendants() throws {
  let a = observedProcess(10, parent: 20)
  let b = observedProcess(20, parent: 10)
  let staleChild = observedProcess(30, parent: 40, start: 1)
  let reusedParent = observedProcess(40, start: 2)
  let families = ProcessFamilies([b, a, staleChild, reusedParent])
  #expect(families.roots.count == 3)
  #expect(families.roots.flatMap(\.members).count == 4)
  #expect(families.parent(of: a.id) == nil)
  #expect(families.parent(of: b.id)?.id == a.id)
  #expect(families.parent(of: staleChild.id) == nil)
  let overflow = ProcessFamilies([
    observedProcess(50, memory: .max), observedProcess(60, parent: 50, memory: 1),
  ])
  let family = try #require(overflow.roots.first)
  #expect(family.footprintBytes == nil)
  #expect(family.hasMissingMemory)
}
