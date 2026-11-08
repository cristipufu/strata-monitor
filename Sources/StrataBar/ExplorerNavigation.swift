import Combine
import Foundation
import StrataCore

enum ExplorerSection: String, CaseIterable, Identifiable {
  case processes = "Processes"
  case ports = "Ports"
  case files = "Open resources"
  case timeline = "Timeline"
  case cpu = "CPU"
  case gpu = "GPU"
  case memory = "Memory"
  case disk = "Volumes"
  case network = "Network"
  var id: Self { self }
  var symbol: String {
    switch self {
    case .processes: "square.stack.3d.up"
    case .ports: "network"
    case .files: "doc.text.magnifyingglass"
    case .timeline: "clock.arrow.circlepath"
    case .cpu: "cpu"
    case .gpu: Reading.gpu.symbol
    case .memory: "memorychip"
    case .network: "arrow.up.arrow.down"
    case .disk: "internaldrive"
    }
  }
  var reading: Reading? {
    switch self {
    case .cpu: .cpu
    case .gpu: .gpu
    case .memory: .memory
    case .network: .network
    case .disk: .disk
    default: nil
    }
  }
}

enum ExplorerDestination {
  case resume
  case processes(ProcessIdentity?)
  case family(ProcessIdentity?)
  // Process families sorted by a page's measure, optionally with one selected.
  case ranked(ProcessSort, ProcessIdentity?)
  case ports
  case port(UInt16)
  case resources(URL?)
  case volume(VolumeResourceScope)
}
struct ResourceNavigationRequest: Equatable {
  let section: ExplorerSection?
  let revision: UUID
}
struct SelectedInspectionRequest: Equatable {
  let identity: ProcessIdentity?
  let path: String?
  let includeResources: Bool
  let revision: UUID
}

@MainActor
final class ExplorerNavigation: ObservableObject {
  @Published var section: ExplorerSection? = .processes
  @Published var identity: ProcessIdentity?
  @Published var query = ""
  @Published var pathScope: ResourcePathScope?
  @Published var volumeScope: VolumeResourceScope?
  @Published var grouping: ProcessGrouping = .individual
  @Published var processFilter = ProcessFilter.all
  @Published var processOrder = ProcessOrder(.name)
  @Published var resourceOrder = ResourceOrder(.process)
  @Published var showsInspector = true
  @Published private(set) var revision = UUID()
  @Published private(set) var searchFocusRequest = UUID()
  func requestSearchFocus() { searchFocusRequest = UUID() }
  var resourceRequest: ResourceNavigationRequest {
    ResourceNavigationRequest(section: section, revision: revision)
  }
  var resourceScopeTitle: String? {
    volumeScope.map { "Open files on \($0.name)" } ?? pathScope.map { "Paths under \($0.path)" }
  }
  func includesResource(_ resource: ProcessResource) -> Bool {
    (pathScope?.contains(resource) ?? true) && (volumeScope?.contains(resource) ?? true)
  }
  func clearResourceScope() {
    pathScope = nil
    volumeScope = nil
  }
  func open(_ destination: ExplorerDestination) {
    switch destination {
    case .resume: break
    case .processes(let identity):
      section = .processes
      grouping = .individual
      self.identity = identity
      query = ""
      clearResourceScope()
    case .family(let identity):
      section = .processes
      grouping = .families
      self.identity = identity
      query = ""
      clearResourceScope()
    case .ranked(let sort, let identity):
      open(.family(identity))
      processOrder = ProcessOrder(sort)
    case .ports:
      section = .ports
      identity = nil
      query = ""
      clearResourceScope()
    case .port(let port):
      section = .ports
      identity = nil
      query = "port:\(port)"
      clearResourceScope()
    case .resources(let volume):
      section = .files
      identity = nil
      query = ""
      volumeScope = nil
      pathScope = volume.map(ResourcePathScope.init)
    case .volume(let scope):
      section = .files
      identity = nil
      query = ""
      pathScope = nil
      volumeScope = scope
    }
    revision = UUID()
  }
}
