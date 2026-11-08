import Foundation

public struct ProcessFamily: Identifiable, Sendable {
  public var id: ProcessIdentity { root.id }
  public let root: ProcessSample
  public let members: [ProcessSample]
  public var cpuPercent: Double? {
    let values = members.compactMap(\.cpuPercent).filter { $0.isFinite && $0 >= 0 }
    guard !values.isEmpty else { return nil }
    let total = values.reduce(0, +)
    return total.isFinite ? total : nil
  }
  public var footprintBytes: UInt64? {
    let values = members.compactMap(\.footprintBytes)
    guard !values.isEmpty else { return nil }
    var total: UInt64 = 0
    for value in values {
      let addition = total.addingReportingOverflow(value)
      guard !addition.overflow else { return nil }
      total = addition.partialValue
    }
    return total
  }
  public func total(_ measurement: (ProcessSample) -> Double?) -> Double? {
    let values = members.compactMap(measurement).filter { $0.isFinite && $0 >= 0 }
    guard !values.isEmpty else { return nil }
    let sum = values.reduce(0, +)
    return sum.isFinite ? sum : nil
  }
  public var hasMissingCPU: Bool {
    members.contains { $0.cpuPercent.map { !$0.isFinite || $0 < 0 } ?? true } || cpuPercent == nil
  }
  public var hasMissingMemory: Bool {
    members.contains { $0.footprintBytes == nil } || footprintBytes == nil
  }
}

/// An observed parent relationship is valid only when that parent generation
/// existed before the child. Families partition the snapshot exactly once.
public struct ProcessFamilies: Sendable {
  private let processes: [ProcessIdentity: ProcessSample]
  private let parents: [ProcessIdentity: ProcessIdentity]
  private let children: [ProcessIdentity: [ProcessIdentity]]

  public init(_ samples: [ProcessSample]) {
    // Defensive deduplication also prevents two generations of one PID from
    // becoming members of the same supposedly instantaneous snapshot.
    var byPID: [Int32: ProcessSample] = [:]
    for sample in samples {
      if let previous = byPID[sample.id.pid], Self.startsBefore(sample.id, previous.id) { continue }
      byPID[sample.id.pid] = sample
    }
    processes = Dictionary(uniqueKeysWithValues: byPID.values.map { ($0.id, $0) })
    var observedParents: [ProcessIdentity: ProcessIdentity] = [:]
    for sample in byPID.values {
      if sample.parentPID > 1, let parent = byPID[sample.parentPID], parent.id != sample.id,
        !Self.startsBefore(sample.id, parent.id)
      {
        observedParents[sample.id] = parent.id
      }
    }
    Self.breakCycles(in: &observedParents)
    parents = observedParents
    var childIndex: [ProcessIdentity: [ProcessIdentity]] = [:]
    for (child, parent) in observedParents { childIndex[parent, default: []].append(child) }
    children = childIndex
  }
  public func parent(of identity: ProcessIdentity) -> ProcessSample? {
    parents[identity].flatMap { processes[$0] }
  }
  public var allProcesses: [ProcessSample] { processes.values.sorted { $0.id.pid < $1.id.pid } }
  public func directChildren(of identity: ProcessIdentity) -> [ProcessSample] {
    (children[identity] ?? []).compactMap { processes[$0] }.sorted { $0.id.pid < $1.id.pid }
  }
  public func subtree(of identity: ProcessIdentity) -> ProcessFamily? {
    guard let root = processes[identity] else { return nil }
    var pending = [identity]
    var members: [ProcessSample] = []
    while let next = pending.popLast() {
      if let member = processes[next] { members.append(member) }
      pending.append(contentsOf: children[next] ?? [])
    }
    return ProcessFamily(root: root, members: members.sorted { $0.id.pid < $1.id.pid })
  }
  public var roots: [ProcessFamily] {
    processes.keys.filter { parents[$0] == nil }.compactMap(subtree).sorted {
      $0.id.pid < $1.id.pid
    }
  }
  private static func startsBefore(_ lhs: ProcessIdentity, _ rhs: ProcessIdentity) -> Bool {
    lhs.startSeconds == rhs.startSeconds
      ? lhs.startMicroseconds < rhs.startMicroseconds : lhs.startSeconds < rhs.startSeconds
  }
  private static func breakCycles(in parents: inout [ProcessIdentity: ProcessIdentity]) {
    var settled: Set<ProcessIdentity> = []
    for origin in parents.keys.sorted(by: { $0.pid < $1.pid }) where !settled.contains(origin) {
      var path: [ProcessIdentity] = []
      var positions: [ProcessIdentity: Int] = [:]
      var current: ProcessIdentity? = origin
      while let next = current, !settled.contains(next) {
        if let position = positions[next] {
          // Equal start timestamps can conceal a corrupt/cyclic snapshot.
          // Break one deterministic edge so traversal remains finite.
          if let root = path[position...].min(by: { $0.pid < $1.pid }) { parents[root] = nil }
          break
        }
        positions[next] = path.count
        path.append(next)
        current = parents[next]
      }
      settled.formUnion(path)
    }
  }
}
