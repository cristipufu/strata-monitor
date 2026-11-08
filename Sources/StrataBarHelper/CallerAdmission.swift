import CSystem
import Foundation
import StrataInventory

/// The code-signing requirement is enforced by the listener before this check runs.
struct CallerAdmission: Sendable {
  let processIsRunning: @Sendable (pid_t) -> Bool
  var scope: @Sendable (uid_t) -> CallerScope = { CallerScope.live(userID: $0) }

  static let live = CallerAdmission { NativeProcessIdentity.isRunning($0) }

  // A root caller already has every privilege the helper offers; refusing it keeps the helper
  // from becoming a relay for another root process.
  func admits(effectiveUserID: uid_t, processIdentifier: pid_t) -> Bool {
    effectiveUserID != 0 && processIdentifier > 0 && processIsRunning(processIdentifier)
  }
}

// What one connected user may inspect. Process counters are shared with every user, as
// Activity Monitor shows them; the open files and sockets of another user's process only with an
// administrator. Admin membership is decided for each request, never cached for a connection.
struct CallerScope: Sendable {
  let userID: uid_t
  let isAdministrator: @Sendable (uid_t) -> Bool

  static func live(userID: uid_t) -> CallerScope {
    CallerScope(userID: userID) { sb_user_is_administrator($0) }
  }
  func permission() -> ResourcePermission {
    ResourcePermission(userID: userID, isAdministrator: isAdministrator(userID))
  }
}

struct ResourcePermission: Sendable {
  let userID: uid_t
  let isAdministrator: Bool
  func permits(owner: uid_t?) -> Bool { isAdministrator || owner == userID }
}
