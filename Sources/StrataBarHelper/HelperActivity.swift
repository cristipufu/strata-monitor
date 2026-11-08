import Foundation
import Synchronization

/// An open but quiet connection does not keep the helper running: launchd starts it again for
/// the next message, and the app reconnects transparently.
final class HelperActivity: Sendable {
  private struct State {
    var requestsInFlight = 0
    var lastActivity: TimeInterval
  }
  private let state: Mutex<State>
  private let uptime: @Sendable () -> TimeInterval
  let idleLimit: TimeInterval

  init(idleLimit: TimeInterval = 30, uptime: @escaping @Sendable () -> TimeInterval) {
    self.idleLimit = idleLimit
    self.uptime = uptime
    state = Mutex(State(lastActivity: uptime()))
  }
  func requestStarted() {
    let now = uptime()
    state.withLock {
      $0.requestsInFlight += 1
      $0.lastActivity = now
    }
  }
  func requestFinished() {
    let now = uptime()
    state.withLock {
      $0.requestsInFlight = max(0, $0.requestsInFlight - 1)
      $0.lastActivity = now
    }
  }
  func connectionAccepted() {
    let now = uptime()
    state.withLock { $0.lastActivity = now }
  }
  var isIdle: Bool {
    let now = uptime()
    return state.withLock { $0.requestsInFlight == 0 && now - $0.lastActivity >= idleLimit }
  }
}

final class IdleExitTimer: Sendable {
  private let timer: any DispatchSourceTimer

  init(
    activity: HelperActivity, checkInterval: DispatchTimeInterval = .seconds(5),
    queue: DispatchQueue = .main, exit: @escaping @Sendable () -> Void
  ) {
    timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + checkInterval, repeating: checkInterval, leeway: .seconds(1))
    timer.setEventHandler {
      if activity.isIdle { exit() }
    }
  }
  func start() { timer.activate() }
}
