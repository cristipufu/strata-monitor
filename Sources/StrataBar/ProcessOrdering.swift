import Foundation
import StrataCore

struct ProcessOrderingValues {
  let name: String
  let path: String
  let identity: ProcessIdentity
  let userID: UInt32
  let user: String
  let cpu: Double?
  let footprint: UInt64?
  let cpuTime: Double?
  let threads: Double?
  let watts: Double?
  let wakeups: Double?
  let diskRead: Double?
  let diskWrite: Double?
  let gpu: Double?
  let gpuTime: Double?
  let state: ProcessRunState?
  let isTranslated: Bool
  init(_ process: ProcessSample) {
    name = process.displayName
    path = process.path
    identity = process.id
    userID = process.userID
    user = process.userName ?? String(process.userID)
    cpu = Self.measured(process.cpuPercent)
    footprint = process.footprintBytes
    cpuTime = process.cpuTimeNanoseconds.map { Double($0) }
    threads = process.threads.map(Double.init)
    watts = Self.measured(process.watts)
    wakeups = Self.measured(process.wakeupsPerSecond)
    diskRead = Self.measured(process.diskReadBytesPerSecond)
    diskWrite = Self.measured(process.diskWrittenBytesPerSecond)
    gpu = Self.measured(process.gpuPercent)
    gpuTime = process.gpuTimeNanoseconds.map { Double($0) }
    state = process.runState
    isTranslated = process.isTranslated
  }
  init(_ family: ProcessFamily) {
    name = family.root.displayName
    path = family.root.path
    identity = family.id
    userID = family.root.userID
    user = family.root.userName ?? String(family.root.userID)
    cpu = Self.measured(family.cpuPercent)
    footprint = family.footprintBytes
    cpuTime = family.total { $0.cpuTimeNanoseconds.map { Double($0) } }
    threads = family.total { $0.threads.map(Double.init) }
    watts = family.total(\.watts)
    wakeups = family.total(\.wakeupsPerSecond)
    diskRead = family.total(\.diskReadBytesPerSecond)
    diskWrite = family.total(\.diskWrittenBytesPerSecond)
    gpu = family.total(\.gpuPercent)
    gpuTime = family.total { $0.gpuTimeNanoseconds.map { Double($0) } }
    state = family.root.runState
    isTranslated = family.root.isTranslated
  }
  private static func measured(_ value: Double?) -> Double? {
    value.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
  }
}

enum ProcessSort: String, CaseIterable, ExplorerSortKey {
  case name, path, cpu, memory, pid, user
  case cpuTime, threads, power, wakeups, diskRead, diskWrite, gpu, gpuTime, state, kind, started
  var title: String {
    switch self {
    case .name: String(localized: "Name")
    case .path: String(localized: "Executable Path")
    case .cpu: String(localized: "CPU Usage")
    case .memory: String(localized: "Memory Footprint")
    case .pid: "PID"
    case .user: String(localized: "User")
    case .cpuTime: String(localized: "CPU Time")
    case .threads: String(localized: "Threads")
    case .power: String(localized: "Power")
    case .wakeups: String(localized: "Wakeups")
    case .diskRead: String(localized: "Disk Reads")
    case .diskWrite: String(localized: "Disk Writes")
    case .gpu: String(localized: "GPU Usage")
    case .gpuTime: String(localized: "GPU Time")
    case .state: String(localized: "State")
    case .kind: String(localized: "Kind")
    case .started: String(localized: "Started")
    }
  }
  var ascendsByDefault: Bool {
    switch self {
    case .name, .path, .pid, .user, .state, .kind: true
    case .cpu, .memory, .cpuTime, .threads, .power, .wakeups, .diskRead, .diskWrite, .gpu,
      .gpuTime, .started:
      false
    }
  }
  private func measurement(_ values: ProcessOrderingValues) -> Double? {
    switch self {
    case .cpu: values.cpu
    case .memory: values.footprint.map { Double($0) }
    case .cpuTime: values.cpuTime
    case .threads: values.threads
    case .power: values.watts
    case .wakeups: values.wakeups
    case .diskRead: values.diskRead
    case .diskWrite: values.diskWrite
    case .gpu: values.gpu
    case .gpuTime: values.gpuTime
    case .name, .path, .pid, .user, .state, .kind, .started: nil
    }
  }
  func hasValue(in values: ProcessOrderingValues) -> Bool {
    switch self {
    case .name, .path, .pid, .user, .kind, .started: true
    case .state: values.state != nil
    case .cpu, .memory, .cpuTime, .threads, .power, .wakeups, .diskRead, .diskWrite, .gpu,
      .gpuTime:
      measurement(values) != nil
    }
  }
  func compareValues(_ lhs: ProcessOrderingValues, _ rhs: ProcessOrderingValues)
    -> ComparisonResult
  {
    switch self {
    case .name: lhs.name.localizedStandardCompare(rhs.name)
    case .path: lhs.path.localizedStandardCompare(rhs.path)
    case .pid: ComparisonResult(comparing: lhs.identity.pid, to: rhs.identity.pid)
    case .user: lhs.user.localizedStandardCompare(rhs.user)
    case .state:
      ComparisonResult(comparing: lhs.state?.rawValue ?? "", to: rhs.state?.rawValue ?? "")
    case .kind: ComparisonResult(comparing: lhs.isTranslated ? 1 : 0, to: rhs.isTranslated ? 1 : 0)
    case .started:
      ComparisonResult(comparing: lhs.identity.startMicrosecondsSinceEpoch, to: rhs.identity.startMicrosecondsSinceEpoch)
    case .cpu, .memory, .cpuTime, .threads, .power, .wakeups, .diskRead, .diskWrite, .gpu,
      .gpuTime:
      ComparisonResult(comparing: measurement(lhs), to: measurement(rhs))
    }
  }
  static func precedesWhenTied(_ lhs: ProcessOrderingValues, _ rhs: ProcessOrderingValues)
    -> Bool
  {
    lhs.identity.pid < rhs.identity.pid
  }
  // Each family's totals are summed once; only the leaders are kept in order.
  func ranked(_ families: [ProcessFamily], limit: Int = .max) -> [ProcessFamily] {
    let order = ProcessOrder(self)
    var leaders: [(family: ProcessFamily, values: ProcessOrderingValues)] = []
    for family in families {
      let values = ProcessOrderingValues(family)
      guard hasValue(in: values) else { continue }
      if leaders.count == limit {
        guard let last = leaders.last, order.areInIncreasingOrder(values, last.values) else {
          continue
        }
        leaders.removeLast()
      }
      let position =
        leaders.firstIndex { order.areInIncreasingOrder(values, $0.values) } ?? leaders.count
      leaders.insert((family, values), at: position)
    }
    return leaders.map(\.family)
  }
}

typealias ProcessOrder = ExplorerSortOrder<ProcessSort>

extension ExplorerSortOrder where Key == ProcessSort {
  func areInIncreasingOrder(_ lhs: ProcessSample, _ rhs: ProcessSample) -> Bool {
    areInIncreasingOrder(ProcessOrderingValues(lhs), ProcessOrderingValues(rhs))
  }
  // A family's ordering values sum all of its members, so each row is measured once
  // instead of on every comparison.
  func sorted<Row>(_ rows: [Row], by values: (Row) -> ProcessOrderingValues) -> [Row] {
    rows.map { ($0, values($0)) }.sorted { areInIncreasingOrder($0.1, $1.1) }.map(\.0)
  }
  func sorted(_ processes: [ProcessSample]) -> [ProcessSample] {
    sorted(processes, by: ProcessOrderingValues.init)
  }
}

struct ProcessTreeRow: Identifiable {
  var id: ProcessIdentity { process.id }
  let process: ProcessSample
  let parent: ProcessIdentity?
  let family: ProcessFamily?
  var orderingValues: ProcessOrderingValues {
    family.map(ProcessOrderingValues.init) ?? ProcessOrderingValues(process)
  }
  var title: String {
    family.map {
      $0.members.count > 1
        ? String(localized: "\(process.displayName) · \($0.members.count) processes") : process.displayName
    } ?? process.displayName
  }
  var cpu: Double? { family == nil ? process.cpuPercent : family?.cpuPercent }
  var footprint: UInt64? { family == nil ? process.footprintBytes : family?.footprintBytes }
  var partialCPU: Bool { family?.hasMissingCPU ?? false }
  var isCPUReadable: Bool { family?.isCPUReadable ?? process.isCPUReadable }
  var partialMemory: Bool { family?.hasMissingMemory ?? false }
}

// A family tree is rebuilt only when a new reading, search or order arrives.
@MainActor final class ProcessTreeCache {
  private var processes: [ProcessSample] = []
  private var query = ""
  private var filter = ProcessFilter.all
  private var context: ProcessFilterContext?
  private var order: ProcessOrder?
  private var snapshot: ProcessTreeSnapshot?
  func snapshot(
    of processes: [ProcessSample], families: @autoclosure () -> ProcessFamilies, query: String,
    filter: ProcessFilter, context: ProcessFilterContext, order: ProcessOrder
  ) -> ProcessTreeSnapshot {
    if let snapshot, order == self.order, query == self.query, filter == self.filter,
      context == self.context, processes.sharesStorage(with: self.processes)
    {
      return snapshot
    }
    let fresh = ProcessTreeSnapshot(
      families: families(), query: query, filter: filter, context: context, order: order)
    (self.processes, self.query, self.filter, self.order) = (processes, query, filter, order)
    self.context = context
    snapshot = fresh
    return fresh
  }
}

struct ProcessTreeSnapshot {
  let rows: [ProcessTreeRow]
  let matchingCount: Int
  let isSearching: Bool
  init(
    families: ProcessFamilies, query: String, filter: ProcessFilter = .all,
    context: ProcessFilterContext = ProcessFilterContext(currentUser: getuid()),
    order: ProcessOrder
  ) {
    let search = ExplorerQuery(query)
    let hierarchy = ProcessHierarchy(families) {
      search.matches($0) && filter.includes($0, in: context)
    }
    let rootFamilies = Dictionary(uniqueKeysWithValues: families.roots.map { ($0.id, $0) })
    rows = order.sorted(
      hierarchy.processes.map { process in
        ProcessTreeRow(
          process: process, parent: hierarchy.parentIdentities[process.id],
          family: rootFamilies[process.id])
      }, by: \.orderingValues)
    matchingCount = hierarchy.matchingIdentities.count
    isSearching = filter != .all || !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}
