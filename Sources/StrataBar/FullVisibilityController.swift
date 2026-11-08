import Combine
import Foundation
import StrataCore
import StrataSystem

// "Show all processes": the optional root helper. Its registration with macOS is the only state,
// so the setting always reflects what System Settings shows.
@MainActor final class FullVisibilityController: ObservableObject {
  enum State: Equatable {
    case off, turningOn, needsApproval, on
    case unavailable(String)
    case failed(String)
  }
  @Published private(set) var state = State.off
  private let registration: any PrivilegedHelperRegistering
  private let client: PrivilegedHelperClient
  private let processes: MergedProcessInventory
  private let resources: MergedResourceInspector
  private let isAdministrator: Bool
  private let approvalCheckInterval: Duration
  private let approvalWaitLimit: Duration
  private var task: Task<Void, Never>?
  private var opensApprovalWhenNeeded = false

  init(
    registration: any PrivilegedHelperRegistering = PrivilegedHelperRegistration(),
    client: PrivilegedHelperClient = PrivilegedHelperClient(),
    processes: MergedProcessInventory, resources: MergedResourceInspector,
    isAdministrator: Bool = AccountMembership.isAdministrator(),
    approvalCheckInterval: Duration = .seconds(2), approvalWaitLimit: Duration = .seconds(600)
  ) {
    self.registration = registration
    self.client = client
    self.processes = processes
    self.resources = resources
    self.isAdministrator = isAdministrator
    self.approvalCheckInterval = approvalCheckInterval
    self.approvalWaitLimit = approvalWaitLimit
  }

  var isRequested: Bool { [.turningOn, .needsApproval, .on].contains(state) }

  // Views offer the helper where system processes lack readings, unless it cannot help.
  var offersExactReadings: Bool {
    switch state {
    case .on, .unavailable: false
    case .off, .turningOn, .needsApproval, .failed: isAdministrator
    }
  }

  // One click from where readings are missing: register, then land on the switch to approve.
  func requestExactReadings() {
    if state == .needsApproval { return openApproval() }
    opensApprovalWhenNeeded = true
    setEnabled(true)
  }

  func refresh() {
    let registration = registration
    run { try await self.synchronize(with: Self.offMain { registration.status() }) }
  }

  func setEnabled(_ enabled: Bool) {
    guard enabled != isRequested else { return }
    if !enabled { opensApprovalWhenNeeded = false }
    state = enabled ? .turningOn : .off
    let registration = registration
    run {
      if enabled {
        try await self.synchronize(with: Self.offMain { try registration.register() })
      } else {
        await self.detach()
        try await registration.unregister()
      }
    }
  }

  func openApproval() { registration.openLoginItemsSettings() }

  func stop() {
    task?.cancel()
    task = nil
  }

  // Operations run one after another: a registration already sent to the system cannot be
  // cancelled, so the next operation waits for it, and a superseded one changes nothing.
  private func run(_ operation: @escaping @MainActor () async throws -> Void) {
    let previous = task
    previous?.cancel()
    task = Task {
      await previous?.value
      guard !Task.isCancelled else { return }
      do {
        try await operation()
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled else { return }
        await detach()
        guard !Task.isCancelled else { return }
        let message = error.localizedDescription
        state =
          (error as? PrivilegedHelperRegistrationError) == .notFound
          ? .unavailable(message) : .failed(message)
      }
    }
  }

  // Registration calls are synchronous messages to the system; they must not stall the UI.
  private nonisolated static func offMain<Value: Sendable>(
    _ work: @escaping @Sendable () throws -> Value
  ) async throws -> Value {
    try await Task.detached { try work() }.value
  }

  private func synchronize(with status: PrivilegedHelperStatus) async throws {
    try Task.checkCancellation()
    switch status {
    case .notRegistered:
      await detach()
      state = .off
    case .notFound:
      await detach()
      state = .unavailable(status.title)
    case .requiresApproval:
      await detach()
      state = .needsApproval
      if opensApprovalWhenNeeded {
        opensApprovalWhenNeeded = false
        openApproval()
      }
      try await waitForApproval()
    case .enabled:
      try await attachVerifiedHelper()
    }
  }

  // macOS sends no notice when the switch is turned on, so the status is checked until it is;
  // returning to Strata Monitor checks again after the wait ends.
  private func waitForApproval() async throws {
    let registration = registration
    let deadline = ContinuousClock.now + approvalWaitLimit
    while ContinuousClock.now < deadline {
      try await Task.sleep(for: approvalCheckInterval)
      let status = try await Self.offMain { registration.status() }
      if status != .requiresApproval { return try await synchronize(with: status) }
    }
  }

  private func attachVerifiedHelper() async throws {
    await client.disconnect()
    do {
      _ = try await client.verify()
    } catch PrivilegedHelperError.needsReregistration {
      // An updated Strata Monitor carries an updated helper; macOS runs it only once re-registered.
      let status = try await registration.reregister()
      await client.disconnect()
      guard status == .enabled else { return try await synchronize(with: status) }
      _ = try await client.verify()
    }
    try Task.checkCancellation()
    await processes.usePrivilegedSource(client)
    await resources.usePrivilegedSource(client)
    try Task.checkCancellation()
    state = .on
  }

  private func detach() async {
    await processes.usePrivilegedSource(nil)
    await resources.usePrivilegedSource(nil)
    await client.disconnect()
  }
}
