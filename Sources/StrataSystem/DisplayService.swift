import Foundation

public actor DisplayService: DisplayManaging {
  private struct CatalogContext {
    let value: DisplayCatalog
    let captured: ContinuousClock.Instant
  }
  private struct Pending {
    var value: DisplayTrial
    var deadline: ContinuousClock.Instant
    let original: [DisplayInfo]
    var expected: [DisplayInfo]?
    let mutation: DisplayMutation
    var recoveryPersistence: DisplayPersistence = .application
  }
  private let hardware: any DisplayHardware
  private let previewDuration: Duration
  private let clock = ContinuousClock()
  private let catalogLifetime: Duration
  private let maximumRecoveryAttempts = 3
  private var context: CatalogContext?
  private var pending: Pending?
  private var recoveryTask: Task<Void, Never>?
  private var issue: String?

  public init() {
    hardware = NativeDisplayHardware()
    previewDuration = .seconds(15)
    catalogLifetime = .seconds(60)
  }
  init(
    hardware: any DisplayHardware, previewDuration: Duration = .seconds(15),
    catalogLifetime: Duration = .seconds(60)
  ) {
    self.hardware = hardware
    self.previewDuration = previewDuration
    self.catalogLifetime = catalogLifetime
  }
  public func catalog() throws -> DisplayCatalog {
    let displays = try hardware.snapshot()
    guard displays.identities.count == displays.count else {
      throw DisplayControlError.unavailable("Display identities are ambiguous.")
    }
    let result = DisplayCatalog(id: UUID(), displays: displays)
    context = CatalogContext(value: result, captured: clock.now)
    return result
  }
  public func preview(_ change: DisplayChange, catalogID: UUID) throws -> DisplayTrial {
    try Task.checkCancellation()
    guard pending == nil else {
      throw DisplayControlError.unavailable("Keep or revert the current preview first.")
    }
    guard let context, context.value.id == catalogID,
      clock.now - context.captured < catalogLifetime,
      context.value.canPreview
    else { throw DisplayControlError.unavailable("Refresh Displays before changing its settings.") }
    let original = try hardware.snapshot()
    guard original.sameConfiguration(as: context.value.displays), original.supportsRestoration
    else {
      throw DisplayControlError.unavailable("Display settings changed. Refresh and try again.")
    }
    let mutation = try mutation(for: change, displays: original)
    try Task.checkCancellation()
    issue = nil
    let trial = makeTrial(id: UUID(), catalogID: catalogID, canKeep: false)
    // Arm recovery before writing: a failed change or observation can still require rollback.
    pending = Pending(
      value: trial, deadline: clock.now + previewDuration, original: original,
      expected: nil, mutation: mutation)
    scheduleRecovery(trial.id, at: clock.now + previewDuration, attempt: 1)
    do {
      try hardware.apply([mutation], identities: original.identities, persistence: .application)
      let expected = try hardware.snapshot()
      guard expected.identities == original.identities, expected.supportsRestoration,
        satisfies(change, displays: expected)
      else {
        throw DisplayControlError.unavailable("The display did not apply the requested setting.")
      }
      try Task.checkCancellation()
      let ready = makeTrial(id: trial.id, catalogID: catalogID, canKeep: true)
      pending?.value = ready
      pending?.expected = expected
      pending?.deadline = clock.now + previewDuration
      scheduleRecovery(trial.id, at: clock.now + previewDuration, attempt: 1)
      return ready
    } catch {
      try recoverAfterFailure(error)
    }
  }
  public func accept(_ trialID: UUID) throws {
    try Task.checkCancellation()
    let current = try requireTrial(trialID)
    guard clock.now < current.deadline else {
      try revert(trialID)
      throw DisplayControlError.unavailable("The display preview expired.")
    }
    guard current.value.canKeep, let expected = current.expected else {
      throw DisplayControlError.unavailable("This preview needs recovery. Choose Revert.")
    }
    let observed = try hardware.snapshot()
    guard observed.sameConfiguration(as: expected) else { try abandonChangedConfiguration() }
    try Task.checkCancellation()
    pending?.recoveryPersistence = .session
    pending?.expected = nil
    pending?.value = makeTrial(id: trialID, catalogID: current.value.catalogID, canKeep: false)
    do {
      try hardware.apply(
        [current.mutation], identities: current.original.identities, persistence: .session)
      guard try hardware.snapshot().sameConfiguration(as: expected) else {
        throw DisplayControlError.unavailable(
          "The display configuration changed while keeping the preview.")
      }
      clearTrial()
    } catch {
      try recoverAfterFailure(error)
    }
  }
  public func revert(_ trialID: UUID) throws {
    // Cleanup deliberately ignores caller cancellation.
    let current = try requireTrial(trialID)
    let observed = try hardware.snapshot()
    if observed.sameConfiguration(as: current.original), current.recoveryPersistence == .application
    {
      clearTrial()
      return
    }
    if observed.identities != current.original.identities { try abandonChangedConfiguration() }
    if let expected = current.expected, !observed.sameConfiguration(as: expected) {
      try abandonChangedConfiguration()
    }
    do {
      try restore(current.original, persistence: current.recoveryPersistence)
      clearTrial()
    } catch {
      pending?.expected = nil
      pending?.value = makeTrial(id: trialID, catalogID: current.value.catalogID, canKeep: false)
      issue = error.localizedDescription
      throw error
    }
  }
  public func status() -> DisplayTrialStatus {
    DisplayTrialStatus(trial: pending?.value, issue: issue)
  }

  private func makeTrial(id: UUID, catalogID: UUID, canKeep: Bool) -> DisplayTrial {
    let seconds =
      Double(previewDuration.components.seconds)
      + Double(previewDuration.components.attoseconds) / 1e18
    return DisplayTrial(
      id: id, catalogID: catalogID, expiresAt: Date().addingTimeInterval(seconds), canKeep: canKeep)
  }
  private func recoverAfterFailure(_ error: any Error) throws -> Never {
    guard let current = pending else { throw error }
    do {
      try restore(current.original, persistence: current.recoveryPersistence)
      clearTrial()
    } catch let recovery {
      pending?.expected = nil
      pending?.value = makeTrial(
        id: current.value.id, catalogID: current.value.catalogID, canKeep: false)
      issue = "The change failed and recovery could not finish: \(recovery.localizedDescription)"
      throw DisplayControlError.unavailable(issue ?? "Display recovery failed.")
    }
    throw error
  }
  private func mutation(for change: DisplayChange, displays: [DisplayInfo]) throws
    -> DisplayMutation
  {
    switch change {
    case .mode(let identity, let mode):
      guard let display = displays.first(where: { $0.id == identity }),
        display.modes.contains(mode),
        display.currentMode != mode
      else {
        throw DisplayControlError.unavailable(
          "Choose an available resolution different from the current one.")
      }
      return .mode(identity, mode)
    case .mirror(let identity, let master):
      guard let display = displays.first(where: { $0.id == identity }), display.mirrorOf != master,
        master != identity
      else { throw DisplayControlError.unavailable("Choose a different mirroring arrangement.") }
      if let master {
        guard let target = displays.first(where: { $0.id == master }), target.mirrorOf == nil,
          !displays.contains(where: { $0.mirrorOf == identity })
        else {
          throw DisplayControlError.unavailable(
            "Separate the existing mirror group before changing its source.")
        }
      }
      return .mirror(identity, master)
    }
  }
  private func satisfies(_ change: DisplayChange, displays: [DisplayInfo]) -> Bool {
    switch change {
    case .mode(let identity, let mode):
      displays.first(where: { $0.id == identity })?.currentMode == mode
    case .mirror(let identity, let master):
      displays.first(where: { $0.id == identity }).map { $0.mirrorOf == master } == true
    }
  }
  private func requireTrial(_ id: UUID) throws -> Pending {
    guard let pending, pending.value.id == id else {
      throw DisplayControlError.unavailable("This display preview is no longer active.")
    }
    return pending
  }
  private func abandonChangedConfiguration() throws -> Never {
    clearTrial()
    issue =
      "Display settings or connected displays changed outside this preview. Review Displays settings."
    throw DisplayControlError.unavailable(issue ?? "Display configuration changed.")
  }
  private func restore(_ original: [DisplayInfo], persistence: DisplayPersistence) throws {
    let current = try hardware.snapshot()
    if current.sameConfiguration(as: original), persistence == .application { return }
    guard current.identities == original.identities else {
      throw DisplayControlError.unavailable(
        "Connected displays changed; the previous configuration cannot be restored safely.")
    }
    try hardware.apply(
      original.restoration, identities: original.identities, persistence: persistence)
    guard try hardware.snapshot().sameConfiguration(as: original) else {
      throw DisplayControlError.unavailable(
        "The previous display configuration could not be fully restored.")
    }
  }
  private func clearTrial() {
    recoveryTask?.cancel()
    recoveryTask = nil
    pending = nil
    context = nil
    issue = nil
  }
  private func scheduleRecovery(_ id: UUID, at deadline: ContinuousClock.Instant, attempt: Int) {
    recoveryTask?.cancel()
    // The bounded recovery task deliberately owns this service, never its UI, until it attempts rollback.
    recoveryTask = Task { [self] in
      do { try await clock.sleep(until: deadline) } catch { return }
      do { try revert(id) } catch {
        issue = error.localizedDescription
        if pending?.value.id == id && attempt < maximumRecoveryAttempts {
          scheduleRecovery(id, at: clock.now + .seconds(1), attempt: attempt + 1)
        } else {
          recoveryTask = nil
        }
      }
    }
  }
}
