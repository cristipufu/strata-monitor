import StrataCore
import Testing

private func hierarchyProcess(_ pid: Int32, parent: Int32 = 1, start: UInt64 = 1) -> ProcessSample {
  ProcessSample(
    id: ProcessIdentity(pid: pid, startSeconds: start, startMicroseconds: 0), parentPID: parent,
    userID: 501,
    name: "Process \(pid)", path: "/fixture/\(pid)", cpuTimeNanoseconds: nil, residentBytes: nil,
    footprintBytes: nil, threads: nil)
}

@Test func hierarchySearchRetainsAncestorsButNotUnmatchedSiblings() {
  let root = hierarchyProcess(10)
  let child = hierarchyProcess(20, parent: 10)
  let descendant = hierarchyProcess(30, parent: 20)
  let sibling = hierarchyProcess(40, parent: 10)
  let separate = hierarchyProcess(50)
  let families = ProcessFamilies([separate, sibling, descendant, child, root])
  let filtered = ProcessHierarchy(families, query: ExplorerQuery("pid:30"))
  #expect(filtered.processes.map(\.id) == [root.id, child.id, descendant.id])
  #expect(filtered.matchingIdentities == [descendant.id])
  #expect(filtered.parentIdentities[descendant.id] == child.id)
  #expect(filtered.parentIdentities[child.id] == root.id)
  #expect(filtered.parentIdentities[root.id] == nil)
  #expect(ProcessHierarchy(families, query: ExplorerQuery("nothing-matches")).processes.isEmpty)
}

@Test func hierarchyCannotAttachSearchContextToANewerParentGeneration() {
  let olderChild = hierarchyProcess(10, parent: 20, start: 1)
  let newerParent = hierarchyProcess(20, start: 2)
  let hierarchy = ProcessHierarchy(
    ProcessFamilies([olderChild, newerParent]), query: ExplorerQuery("pid:10"))
  #expect(hierarchy.processes.map(\.id) == [olderChild.id])
  #expect(hierarchy.parentIdentities.isEmpty)
}

@Test func userQueriesMatchNumericOwnersAndRejectMalformedIdentifiers() {
  let process = hierarchyProcess(10)
  #expect(ExplorerQuery("uid:501 /fixture").matches(process))
  #expect(!ExplorerQuery("uid:502").matches(process))
  #expect(!ExplorerQuery("uid:-1").matches(process))
  #expect(!ExplorerQuery("uid:99999999999999999999999").matches(process))
}
