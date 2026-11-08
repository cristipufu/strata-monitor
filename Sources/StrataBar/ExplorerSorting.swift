import Foundation
import StrataCore

protocol ExplorerSortKey: RawRepresentable<String>, Equatable {
  associatedtype Row
  var ascendsByDefault: Bool { get }
  func hasValue(in row: Row) -> Bool
  func compareValues(_ lhs: Row, _ rhs: Row) -> ComparisonResult
  static func precedesWhenTied(_ lhs: Row, _ rhs: Row) -> Bool
}

extension ExplorerSortKey {
  var ascendsByDefault: Bool { true }
  func hasValue(in row: Row) -> Bool { true }
}

struct ExplorerSortOrder<Key: ExplorerSortKey>: Equatable {
  let key: Key
  let ascending: Bool
  init(_ key: Key, ascending: Bool? = nil) {
    self.key = key
    self.ascending = ascending ?? key.ascendsByDefault
  }
  init?(_ descriptor: NSSortDescriptor) {
    guard let name = descriptor.key, let key = Key(rawValue: name) else { return nil }
    self.init(key, ascending: descriptor.ascending)
  }
  var descriptor: NSSortDescriptor { NSSortDescriptor(key: key.rawValue, ascending: ascending) }
  // AppKit keeps earlier header clicks as secondary descriptors; only the clicked column orders rows.
  var descriptors: [NSSortDescriptor] {
    get { [descriptor] }
    set {
      guard let order = newValue.first.flatMap({ Self($0) }) else { return }
      self = order
    }
  }
  // Rows without a value stay last in either direction.
  func areInIncreasingOrder(_ lhs: Key.Row, _ rhs: Key.Row) -> Bool {
    let lhsHasValue = key.hasValue(in: lhs)
    if lhsHasValue != key.hasValue(in: rhs) { return lhsHasValue }
    switch key.compareValues(lhs, rhs) {
    case .orderedAscending: return ascending
    case .orderedDescending: return !ascending
    case .orderedSame: return Key.precedesWhenTied(lhs, rhs)
    }
  }
}

enum ResourceSort: String, ExplorerSortKey {
  case process, pid, location, kind, state
  func compareValues(_ lhs: ProcessResource, _ rhs: ProcessResource) -> ComparisonResult {
    switch self {
    case .process: lhs.processName.localizedStandardCompare(rhs.processName)
    case .pid: ComparisonResult(comparing: lhs.owner.pid, to: rhs.owner.pid)
    case .location: lhs.location.localizedStandardCompare(rhs.location)
    case .kind: lhs.kind.title.localizedStandardCompare(rhs.kind.title)
    case .state: lhs.state.localizedStandardCompare(rhs.state)
    }
  }
  static func precedesWhenTied(_ lhs: ProcessResource, _ rhs: ProcessResource) -> Bool {
    (lhs.owner.pid, lhs.descriptor) < (rhs.owner.pid, rhs.descriptor)
  }
}
typealias ResourceOrder = ExplorerSortOrder<ResourceSort>

// A resource report changes only when an inspection finishes, while Explorer redraws on every
// sample. Sorting tens of thousands of rows on each redraw would stall the main actor.
@MainActor final class SortedRowCache<Row, Order: Equatable> {
  private var source: [Row] = []
  private var order: Order?
  private var sorted: [Row] = []
  private let sort: ([Row], Order) -> [Row]
  init(sort: @escaping ([Row], Order) -> [Row]) { self.sort = sort }
  func rows(_ rows: [Row], orderedBy order: Order) -> [Row] {
    if order != self.order || !rows.sharesStorage(with: source) {
      source = rows
      self.order = order
      sorted = sort(rows, order)
    }
    return sorted
  }
}

extension SortedRowCache {
  convenience init<Key: ExplorerSortKey>() where Row == Key.Row, Order == ExplorerSortOrder<Key> {
    self.init { rows, order in rows.sorted(by: order.areInIncreasingOrder) }
  }
}

extension Array {
  // Arrays share storage until one is mutated, and the cache retains its source,
  // so shared storage means identical elements.
  func sharesStorage(with other: [Element]) -> Bool {
    count == other.count
      && withUnsafeBufferPointer { elements in
        other.withUnsafeBufferPointer { $0.baseAddress == elements.baseAddress }
      }
  }
}

extension ComparisonResult {
  // Missing values compare equal here; sort orders place them with hasValue(in:).
  init<Value: Comparable>(comparing lhs: Value?, to rhs: Value?) {
    guard let lhs, let rhs else {
      self = .orderedSame
      return
    }
    self = lhs < rhs ? .orderedAscending : rhs < lhs ? .orderedDescending : .orderedSame
  }
}
