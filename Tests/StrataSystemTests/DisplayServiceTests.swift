import Foundation
import Testing

@testable import StrataSystem

@Suite struct DisplayServiceTests {
  @Test func displayPreviewIsTemporaryAndKeepIsSessionScopedAndSingleUse() async throws {
    let hardware = ControlledDisplayHardware()
    let service = DisplayService(hardware: hardware)
    let catalog = try await service.catalog()
    let trial = try await service.preview(
      .mode(hardware.firstID, hardware.alternate), catalogID: catalog.id)
    #expect(trial.canKeep)
    #expect(hardware.state.applied == [.application])
    try await service.accept(trial.id)
    #expect(hardware.state.applied == [.application, .session])
    #expect(await service.status().trial == nil)
    await #expect(throws: DisplayControlError.self) { try await service.accept(trial.id) }
    #expect(hardware.state.applied.count == 2)
  }

  @Test func displayTimeoutRestoresTheEntireConfigurationAndDoesNotOwnTheUI() async throws {
    let hardware = ControlledDisplayHardware()
    hardware.update { $0.adjustsOtherDisplay = true }
    let original = hardware.state.displays
    var service: DisplayService? = DisplayService(
      hardware: hardware, previewDuration: .milliseconds(40))
    weak let weakService = service
    let catalog = try await #require(service).catalog()
    _ = try await #require(service).preview(
      .mode(hardware.firstID, hardware.alternate), catalogID: catalog.id)
    #expect(!hardware.state.displays.sameConfiguration(as: original))
    service = nil
    for _ in 0..<200 {
      if weakService == nil { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(weakService == nil)
    #expect(hardware.state.displays.sameConfiguration(as: original))
    #expect(hardware.state.applied == [.application, .application])
  }

  @Test func displayMirrorAndSeparateCanBeReverted() async throws {
    let hardware = ControlledDisplayHardware()
    let original = hardware.state.displays
    let service = DisplayService(hardware: hardware)
    let catalog = try await service.catalog()
    let trial = try await service.preview(
      .mirror(hardware.secondID, hardware.firstID), catalogID: catalog.id)
    #expect(hardware.state.displays[1].mirrorOf == hardware.firstID)
    try await service.revert(trial.id)
    #expect(hardware.state.displays.sameConfiguration(as: original))
    await #expect(throws: DisplayControlError.self) { try await service.revert(trial.id) }
  }

  @Test func displaySelectionAndCatalogAreValidatedBeforeAnyWrite() async throws {
    let hardware = ControlledDisplayHardware()
    let service = DisplayService(hardware: hardware)
    let catalog = try await service.catalog()
    await #expect(throws: DisplayControlError.self) {
      try await service.preview(.mode(hardware.firstID, hardware.alternate), catalogID: UUID())
    }
    await #expect(throws: DisplayControlError.self) {
      try await service.preview(.mode(hardware.firstID, hardware.base), catalogID: catalog.id)
    }
    let forged = DisplayMode(
      id: 333, width: 1, height: 1, pixelWidth: 1, pixelHeight: 1, refreshRate: 1)
    await #expect(throws: DisplayControlError.self) {
      try await service.preview(.mode(hardware.firstID, forged), catalogID: catalog.id)
    }
    await #expect(throws: DisplayControlError.self) {
      try await service.preview(.mirror(hardware.firstID, hardware.firstID), catalogID: catalog.id)
    }
    hardware.update { $0.displays[0] = $0.displays[0].with(mode: hardware.alternate) }
    await #expect(throws: DisplayControlError.self) {
      try await service.preview(.mode(hardware.firstID, hardware.alternate), catalogID: catalog.id)
    }
    #expect(hardware.state.applied.isEmpty)
  }

  @Test func displayUnrestorableBaselineAndStaleCatalogCannotPreview() async throws {
    let hardware = ControlledDisplayHardware()
    hardware.update { $0.displays[0] = $0.displays[0].with(choices: [hardware.alternate]) }
    let service = DisplayService(hardware: hardware)
    let catalog = try await service.catalog()
    #expect(!catalog.canPreview)
    await #expect(throws: DisplayControlError.self) {
      try await service.preview(.mode(hardware.firstID, hardware.alternate), catalogID: catalog.id)
    }
    hardware.update {
      $0.displays[0] = $0.displays[0].with(choices: [hardware.base, hardware.alternate])
    }
    let first = try await service.catalog()
    _ = try await service.catalog()
    await #expect(throws: DisplayControlError.self) {
      try await service.preview(.mode(hardware.firstID, hardware.alternate), catalogID: first.id)
    }
    #expect(hardware.state.applied.isEmpty)
  }

  @Test(arguments: [3, 0]) func displayFailedObservationOrPartialWriteRollsBack(failedRead: Int)
    async throws
  {
    let hardware = ControlledDisplayHardware()
    let original = hardware.state.displays
    hardware.update {
      if failedRead > 0 { $0.failedSnapshots = [failedRead] } else { $0.failedApplies = [1] }
    }
    let service = DisplayService(hardware: hardware)
    let catalog = try await service.catalog()
    await #expect(throws: DisplayControlError.self) {
      try await service.preview(.mode(hardware.firstID, hardware.alternate), catalogID: catalog.id)
    }
    #expect(hardware.state.displays.sameConfiguration(as: original))
    #expect(await service.status().trial == nil)
  }

  @Test func displayFailedRecoveryRemainsActionableAndCanBeRetried() async throws {
    let hardware = ControlledDisplayHardware()
    let original = hardware.state.displays
    hardware.update { $0.failedApplies = [1, 2] }
    let service = DisplayService(hardware: hardware)
    let catalog = try await service.catalog()
    await #expect(throws: DisplayControlError.self) {
      try await service.preview(.mode(hardware.firstID, hardware.alternate), catalogID: catalog.id)
    }
    let status = await service.status()
    let pending = try #require(status.trial)
    #expect(!pending.canKeep)
    #expect(status.issue != nil)
    await #expect(throws: DisplayControlError.self) { try await service.accept(pending.id) }
    try await service.revert(pending.id)
    #expect(hardware.state.displays.sameConfiguration(as: original))
    #expect(await service.status().trial == nil)
    #expect(await service.status().issue == nil)
  }

  @Test func displayFailedKeepRestoresSessionStateRatherThanAnAppOnlyOverride() async throws {
    let hardware = ControlledDisplayHardware()
    let original = hardware.state.displays
    let service = DisplayService(hardware: hardware)
    let catalog = try await service.catalog()
    let trial = try await service.preview(
      .mode(hardware.firstID, hardware.alternate), catalogID: catalog.id)
    hardware.update { $0.failedApplies = [2] }
    await #expect(throws: DisplayControlError.self) { try await service.accept(trial.id) }
    #expect(hardware.state.displays.sameConfiguration(as: original))
    #expect(hardware.state.applied == [.application, .session, .session])
    #expect(await service.status().trial == nil)
  }

  @Test func displayCancellationAfterWriteStillRestoresTheBaseline() async throws {
    let hardware = ControlledDisplayHardware()
    let original = hardware.state.displays
    hardware.update { $0.canceledApplies = [1] }
    let service = DisplayService(hardware: hardware)
    let catalog = try await service.catalog()
    let operation = Task {
      try await service.preview(.mode(hardware.firstID, hardware.alternate), catalogID: catalog.id)
    }
    await #expect(throws: CancellationError.self) { try await operation.value }
    #expect(hardware.state.displays.sameConfiguration(as: original))
    #expect(await service.status().trial == nil)
  }

  @Test(arguments: [false, true]) func displayExternalChangesAreNeverOverwritten(
    replacesHardware: Bool
  ) async throws {
    let hardware = ControlledDisplayHardware()
    let service = DisplayService(hardware: hardware)
    let catalog = try await service.catalog()
    let trial = try await service.preview(
      .mode(hardware.firstID, hardware.alternate), catalogID: catalog.id)
    hardware.update {
      $0.displays[0] = $0.displays[0].with(
        identity: replacesHardware
          ? DisplayIdentity(objectID: hardware.firstID.objectID, uuid: UUID()) : nil,
        position: DisplayPosition(x: 75, y: 24))
    }
    let external = hardware.state.displays
    await #expect(throws: DisplayControlError.self) { try await service.revert(trial.id) }
    #expect(hardware.state.displays.sameConfiguration(as: external))
    #expect(hardware.state.applied.count == 1)
    #expect(await service.status().trial == nil)
    #expect(await service.status().issue != nil)
  }

  @Test func displayPendingPreviewRejectsAnotherWrite() async throws {
    let hardware = ControlledDisplayHardware()
    let service = DisplayService(hardware: hardware)
    let catalog = try await service.catalog()
    let trial = try await service.preview(
      .mode(hardware.firstID, hardware.alternate), catalogID: catalog.id)
    await #expect(throws: DisplayControlError.self) {
      try await service.preview(.mirror(hardware.secondID, hardware.firstID), catalogID: catalog.id)
    }
    #expect(hardware.state.applied.count == 1)
    try await service.revert(trial.id)
  }

  @Test func displayFreshReadMustStillSupportRestoringTheBaseline() async throws {
    let hardware = ControlledDisplayHardware()
    let service = DisplayService(hardware: hardware)
    let catalog = try await service.catalog()
    hardware.update { $0.displays[0] = $0.displays[0].with(choices: [hardware.alternate]) }
    await #expect(throws: DisplayControlError.self) {
      try await service.preview(.mode(hardware.firstID, hardware.alternate), catalogID: catalog.id)
    }
    #expect(hardware.state.applied.isEmpty)
  }

  @Test func displayCatalogLeaseExpiresBeforeAWrite() async throws {
    let hardware = ControlledDisplayHardware()
    let service = DisplayService(hardware: hardware, catalogLifetime: .milliseconds(5))
    let catalog = try await service.catalog()
    try await Task.sleep(for: .milliseconds(15))
    await #expect(throws: DisplayControlError.self) {
      try await service.preview(.mode(hardware.firstID, hardware.alternate), catalogID: catalog.id)
    }
    #expect(hardware.state.applied.isEmpty)
  }

  @Test func displayPartialRevertCanBeRetriedRatherThanMistakenForAnExternalChange() async throws {
    let hardware = ControlledDisplayHardware()
    let original = hardware.state.displays
    let service = DisplayService(hardware: hardware)
    let catalog = try await service.catalog()
    let trial = try await service.preview(
      .mode(hardware.firstID, hardware.alternate), catalogID: catalog.id)
    hardware.update { $0.partialApplies = [2] }
    await #expect(throws: DisplayControlError.self) { try await service.revert(trial.id) }
    #expect(await service.status().trial?.canKeep == false)
    try await service.revert(trial.id)
    #expect(hardware.state.displays.sameConfiguration(as: original))
    #expect(await service.status().trial == nil)
  }

  @Test func displayAutomaticRecoveryRetriesAreBoundedAndLeaveManualRecoveryAvailable() async throws
  {
    let hardware = ControlledDisplayHardware()
    hardware.update { $0.failedSnapshots = Set(3...100) }
    let service = DisplayService(hardware: hardware, previewDuration: .milliseconds(10))
    let catalog = try await service.catalog()
    await #expect(throws: DisplayControlError.self) {
      try await service.preview(.mode(hardware.firstID, hardware.alternate), catalogID: catalog.id)
    }
    let initialReads = hardware.state.snapshots
    try await Task.sleep(for: .milliseconds(2200))
    let reads = hardware.state.snapshots
    #expect(reads - initialReads == 3)
    #expect(await service.status().trial != nil)
    #expect(await service.status().issue != nil)
    try await Task.sleep(for: .milliseconds(1100))
    #expect(hardware.state.snapshots == reads)
    hardware.update { $0.failedSnapshots = [] }
    try await service.revert(try #require(await service.status().trial?.id))
    #expect(await service.status().trial == nil)
  }

  @Test func nativeDisplayCatalogOnlyReadsPublicHardwareState() async throws {
    let service = DisplayService()
    for _ in 0..<3 {
      let catalog = try await service.catalog()
      #expect(catalog.displays.identities.count == catalog.displays.count)
      for display in catalog.displays {
        #expect(display.id.objectID != 0)
        #expect(
          display.modes.allSatisfy { $0.width > 0 && $0.height > 0 && $0.refreshRate.isFinite })
      }
    }
  }
}

private final class ControlledDisplayHardware: DisplayHardware, @unchecked Sendable {
  struct State {
    var displays: [DisplayInfo]
    var applied: [DisplayPersistence] = []
    var snapshots = 0
    var failedSnapshots: Set<Int> = []
    var failedApplies: Set<Int> = []
    var partialApplies: Set<Int> = []
    var canceledApplies: Set<Int> = []
    var adjustsOtherDisplay = false
  }
  let firstID = DisplayIdentity(objectID: 1, uuid: UUID())
  let secondID = DisplayIdentity(objectID: 2, uuid: UUID())
  let base = DisplayMode(
    id: 10, width: 1440, height: 900, pixelWidth: 2880, pixelHeight: 1800, refreshRate: 60)
  let alternate = DisplayMode(
    id: 11, width: 1280, height: 800, pixelWidth: 2560, pixelHeight: 1600, refreshRate: 60)
  private let lock = NSLock()
  private var storage: State!
  init() {
    storage = State(
      displays: [firstID, secondID].enumerated().map { index, identity in
        DisplayInfo(
          id: identity, isBuiltIn: index == 0, currentMode: base, modes: [base, alternate],
          mirrorOf: nil,
          position: DisplayPosition(x: Int32(index * 1440), y: 0))
      })
  }
  var state: State { lock.withLock { storage } }
  func update(_ edit: (inout State) -> Void) { lock.withLock { edit(&storage) } }
  func snapshot() throws -> [DisplayInfo] {
    try lock.withLock {
      storage.snapshots += 1
      if storage.failedSnapshots.contains(storage.snapshots) {
        throw DisplayControlError.unavailable("Controlled display read failed.")
      }
      return storage.displays
    }
  }
  func apply(
    _ mutations: [DisplayMutation], identities: Set<DisplayIdentity>,
    persistence: DisplayPersistence
  ) throws {
    try lock.withLock {
      guard storage.displays.identities == identities else {
        throw DisplayControlError.unavailable("Controlled topology changed.")
      }
      storage.applied.append(persistence)
      let call = storage.applied.count
      for mutation in mutations {
        switch mutation {
        case .mode(let id, let mode):
          storage.displays = storage.displays.map { $0.id == id ? $0.with(mode: mode) : $0 }
        case .mirror(let id, let master):
          storage.displays = storage.displays.map {
            $0.id == id ? $0.with(mirror: .some(master)) : $0
          }
        case .position(let id, let position):
          storage.displays = storage.displays.map { $0.id == id ? $0.with(position: position) : $0 }
        }
      }
      if storage.partialApplies.contains(call) {
        throw DisplayControlError.unavailable(
          "Controlled configuration stopped after its first mutation.")
      }
      if storage.adjustsOtherDisplay && call == 1 {
        storage.displays[1] = storage.displays[1].with(
          mode: alternate, position: DisplayPosition(x: 10, y: 20))
      }
      if storage.canceledApplies.contains(call) { withUnsafeCurrentTask { $0?.cancel() } }
      if storage.failedApplies.contains(call) {
        throw DisplayControlError.unavailable("Controlled partial configuration failed.")
      }
    }
  }
}

extension DisplayInfo {
  fileprivate func with(
    identity: DisplayIdentity? = nil, mode: DisplayMode? = nil, choices: [DisplayMode]? = nil,
    mirror: DisplayIdentity?? = nil, position: DisplayPosition? = nil
  ) -> DisplayInfo {
    DisplayInfo(
      id: identity ?? id, isBuiltIn: isBuiltIn, currentMode: mode ?? currentMode,
      modes: choices ?? modes, mirrorOf: mirror ?? mirrorOf, position: position ?? self.position)
  }
}
