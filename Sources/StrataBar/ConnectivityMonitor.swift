import Network
import StrataCore

@MainActor
final class ConnectivityMonitor {
  private var monitor: NWPathMonitor?
  private var generation = 0
  func start(deliver: @escaping @MainActor (ConnectionState) -> Void) {
    stop()
    let generation = self.generation
    let monitor = NWPathMonitor()
    self.monitor = monitor
    monitor.pathUpdateHandler = { [weak self] path in
      let state: ConnectionState
      switch path.status {
      case .unsatisfied: state = .offline
      case .requiresConnection: state = .connecting
      case .satisfied:
        state =
          path.usesInterfaceType(.wifi)
          ? .wifi : path.usesInterfaceType(.wiredEthernet) ? .wired : .other
      @unknown default: state = .unknown
      }
      Task { @MainActor [weak self] in
        guard let self, self.generation == generation, self.monitor != nil else { return }
        deliver(state)
      }
    }
    monitor.start(queue: DispatchQueue(label: "dev.strata.bar.connectivity", qos: .utility))
  }
  func stop() {
    generation += 1
    monitor?.cancel()
    monitor = nil
  }
  deinit { monitor?.cancel() }
}
