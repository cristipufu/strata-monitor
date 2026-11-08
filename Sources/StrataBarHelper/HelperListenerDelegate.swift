import Foundation
import StrataHelperInterface
import Synchronization
import os

final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate, Sendable {
  private let core: HelperCore
  private let admission: CallerAdmission
  private let maximumConnections: Int
  // One user running several copies cannot take every connection from the others.
  private let maximumConnectionsPerUser: Int
  private let openConnections = Mutex([uid_t: Int]())
  private let log = Logger(subsystem: HelperContract.machServiceName, category: "listener")

  init(
    core: HelperCore, admission: CallerAdmission = .live, maximumConnections: Int = 8,
    maximumConnectionsPerUser: Int = 2
  ) {
    self.core = core
    self.admission = admission
    self.maximumConnections = maximumConnections
    self.maximumConnectionsPerUser = maximumConnectionsPerUser
  }
  var connectionCount: Int { openConnections.withLock { $0.values.reduce(0, +) } }

  func listener(
    _ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection
  ) -> Bool {
    let caller = connection.processIdentifier
    guard
      admission.admits(
        effectiveUserID: connection.effectiveUserIdentifier, processIdentifier: caller)
    else {
      log.notice("Refused a connection from pid \(caller, privacy: .public)")
      return false
    }
    let user = connection.effectiveUserIdentifier
    guard reserveConnection(for: user) else {
      log.notice("Refused a connection beyond the limit from pid \(caller, privacy: .public)")
      return false
    }
    let service = HelperConnectionService(core: core, caller: admission.scope(user))
    connection.exportedInterface = HelperContract.makeInterface()
    connection.exportedObject = service
    connection.invalidationHandler = { [weak self] in
      service.connectionClosed()
      self?.releaseConnection(for: user)
    }
    core.activity.connectionAccepted()
    connection.activate()
    return true
  }
  private func reserveConnection(for user: uid_t) -> Bool {
    openConnections.withLock { open in
      guard open.values.reduce(0, +) < maximumConnections,
        open[user, default: 0] < maximumConnectionsPerUser
      else { return false }
      open[user, default: 0] += 1
      return true
    }
  }
  private func releaseConnection(for user: uid_t) {
    openConnections.withLock { open in
      let remaining = (open[user] ?? 0) - 1
      open[user] = remaining > 0 ? remaining : nil
    }
  }
}
