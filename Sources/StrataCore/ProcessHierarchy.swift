import Foundation

public enum ProcessGrouping: String, CaseIterable, Codable, Sendable {
  case individual, families
}

/// Search retains only matching processes and the ancestors needed to explain
/// their actual observed parent relationship. It never invents an app family.
public struct ProcessHierarchy: Sendable {
  public let processes: [ProcessSample]
  public let parentIdentities: [ProcessIdentity: ProcessIdentity]
  public let matchingIdentities: Set<ProcessIdentity>
  public init(_ families: ProcessFamilies, query: ExplorerQuery) {
    self.init(families, matching: query.matches)
  }
  public init(_ families: ProcessFamilies, matching: (ProcessSample) -> Bool) {
    let candidates = families.allProcesses
    matchingIdentities = Set(candidates.filter(matching).map(\.id))
    var included = Set<ProcessIdentity>()
    for identity in matchingIdentities {
      var current: ProcessIdentity? = identity
      while let next = current, included.insert(next).inserted {
        current = families.parent(of: next)?.id
      }
    }
    processes = candidates.filter { included.contains($0.id) }
    var parents: [ProcessIdentity: ProcessIdentity] = [:]
    for process in processes {
      if let parent = families.parent(of: process.id), included.contains(parent.id) {
        parents[process.id] = parent.id
      }
    }
    parentIdentities = parents
  }
}
