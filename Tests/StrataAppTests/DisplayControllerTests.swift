import Foundation
import Testing

@testable import StrataBar
@testable import StrataSystem

actor GatedDisplays: DisplayManaging {
  let identity = DisplayIdentity(objectID: 12, uuid: UUID())
  let mode = DisplayMode(
    id: 4, width: 1440, height: 900, pixelWidth: 2880, pixelHeight: 1800, refreshRate: 60)
  private var catalogs: [Int: CheckedContinuation<DisplayCatalog, Error>] = [:]
  private var previewContinuation: CheckedContinuation<DisplayTrial, Error>?
  private var previewCatalogID: UUID?
  private var current: DisplayTrial?
  private var issue: String?
  private var failsRevert = false
  private(set) var reads = 0
  private(set) var previews = 0
  private(set) var keeps = 0
  private(set) var reverts = 0
  func catalog() async throws -> DisplayCatalog {
    reads += 1
    let index = reads
    return try await withCheckedThrowingContinuation { catalogs[index] = $0 }
  }
  func finishCatalog(_ index: Int, failure: Bool = false) {
    if failure {
      catalogs.removeValue(forKey: index)?.resume(
        throwing: DisplayControlError.unavailable("Controlled display read failed"))
    } else {
      catalogs.removeValue(forKey: index)?.resume(
        returning: DisplayCatalog(
          id: UUID(),
          displays: [
            DisplayInfo(
              id: identity, isBuiltIn: true, currentMode: mode, modes: [mode], mirrorOf: nil,
              position: DisplayPosition(x: 0, y: 0))
          ]))
    }
  }
  func preview(_ change: DisplayChange, catalogID: UUID) async throws -> DisplayTrial {
    previews += 1
    previewCatalogID = catalogID
    return try await withCheckedThrowingContinuation { previewContinuation = $0 }
  }
  func finishPreview(failedRecovery: Bool = false) {
    let trial = DisplayTrial(
      id: UUID(), catalogID: previewCatalogID ?? UUID(), expiresAt: Date().addingTimeInterval(15),
      canKeep: !failedRecovery)
    current = trial
    if failedRecovery {
      issue = "Controlled recovery failed"
      previewContinuation?.resume(
        throwing: DisplayControlError.unavailable("Controlled preview failed"))
    } else {
      previewContinuation?.resume(returning: trial)
    }
    previewContinuation = nil
  }
  func accept(_ trialID: UUID) throws {
    guard current?.id == trialID else { throw DisplayControlError.unavailable("Unknown preview") }
    keeps += 1
    current = nil
    issue = nil
  }
  func revert(_ trialID: UUID) throws {
    guard current?.id == trialID else { throw DisplayControlError.unavailable("Unknown preview") }
    reverts += 1
    if failsRevert { throw DisplayControlError.unavailable("Controlled revert failed") }
    current = nil
    issue = nil
  }
  func status() -> DisplayTrialStatus { DisplayTrialStatus(trial: current, issue: issue) }
  func expire() {
    current = nil
    issue = nil
  }
  func setRevertFailure(_ failure: Bool) { failsRevert = failure }
  func finishRejectedPreviewWithAnotherOwnersTrial() {
    current = DisplayTrial(
      id: UUID(), catalogID: UUID(), expiresAt: Date().addingTimeInterval(15), canKeep: true)
    previewContinuation?.resume(
      throwing: DisplayControlError.unavailable("Another preview is active"))
    previewContinuation = nil
  }
}

@Test @MainActor func displayCatalogDemandCancelsObsoletePublicationWithoutClearingANewerRead()
  async throws
{
  let service = GatedDisplays()
  let controller = DisplayController(service: service)
  controller.refreshIfVisible()
  #expect(await service.reads == 0)
  controller.setVisible(true)
  try await waitUntil { await service.reads == 1 }
  controller.setVisible(false)
  controller.setVisible(true)
  try await waitUntil { await service.reads == 2 }
  await service.finishCatalog(1, failure: true)
  for _ in 0..<10 { await Task.yield() }
  #expect(controller.isLoading && controller.catalog == nil && controller.errorMessage == nil)
  await service.finishCatalog(2)
  try await waitUntil { !controller.isLoading }
  #expect(controller.catalog != nil && controller.canPreview)
}

@Test @MainActor func displayPreviewSurvivesPageClosureAndOnlyOneExplicitActionRuns() async throws {
  let service = GatedDisplays()
  let controller = DisplayController(service: service)
  try await loadDisplays(controller, service: service)
  controller.preview(.mode(service.identity, service.mode))
  controller.preview(.mode(service.identity, service.mode))
  try await waitUntil { await service.previews == 1 }
  controller.setVisible(false)
  await service.finishPreview()
  try await waitUntil { controller.trial != nil && !controller.isBusy }
  #expect(!controller.canPreview)
  controller.keep()
  try await waitUntil { controller.trial == nil && !controller.isBusy }
  #expect(await service.keeps == 1)
  #expect(await service.reads == 1)
}

@Test @MainActor func displayRecoveryIsObservedAfterThePopoverCloses() async throws {
  let service = GatedDisplays()
  let controller = DisplayController(service: service)
  try await loadDisplays(controller, service: service)
  controller.preview(.mode(service.identity, service.mode))
  try await waitUntil { await service.previews == 1 }
  await service.finishPreview()
  try await waitUntil { controller.trial != nil }
  controller.setVisible(false)
  await service.expire()
  try await waitUntil { controller.trial == nil }
  #expect(await service.reads == 1)
}

@Test @MainActor func displayFailedPreviewRecoveryRemainsVisibleAndCanBeRetried() async throws {
  let service = GatedDisplays()
  let controller = DisplayController(service: service)
  try await loadDisplays(controller, service: service)
  controller.preview(.mode(service.identity, service.mode))
  try await waitUntil { await service.previews == 1 }
  await service.finishPreview(failedRecovery: true)
  try await waitUntil { controller.trial != nil && !controller.isBusy }
  #expect(controller.trial?.canKeep == false && controller.recoveryIssue != nil)
  controller.keep()
  controller.dismissRecoveryIssue()
  #expect(await service.keeps == 0)
  #expect(controller.recoveryIssue != nil)
  controller.setVisible(false)
  controller.revert()
  try await waitUntil { controller.trial == nil && !controller.isBusy }
  #expect(controller.recoveryIssue == nil)
}

@Test @MainActor func displayTerminationWaitsForAnIssuedPreviewAndRevertsItsResult() async throws {
  let service = GatedDisplays()
  let controller = DisplayController(service: service)
  try await loadDisplays(controller, service: service)
  controller.preview(.mode(service.identity, service.mode))
  try await waitUntil { await service.previews == 1 }
  let termination = Task { await controller.prepareForTermination() }
  for _ in 0..<10 { await Task.yield() }
  await service.finishPreview()
  #expect(await termination.value)
  #expect(await service.status().trial == nil)
  #expect(await service.reverts == 1)
  #expect(!controller.canPreview)
}

@Test @MainActor func displayTerminationCancelsAQueuedPreviewBeforeTheService() async throws {
  let service = GatedDisplays()
  let controller = DisplayController(service: service)
  try await loadDisplays(controller, service: service)
  controller.preview(.mode(service.identity, service.mode))
  #expect(await controller.prepareForTermination())
  #expect(await service.previews == 0)
}

@Test @MainActor func displayFailedTerminationRecoveryKeepsTheControllerUsable() async throws {
  let service = GatedDisplays()
  let controller = DisplayController(service: service)
  try await loadDisplays(controller, service: service)
  controller.preview(.mode(service.identity, service.mode))
  try await waitUntil { await service.previews == 1 }
  await service.finishPreview(failedRecovery: true)
  try await waitUntil { controller.trial != nil && !controller.isBusy }
  await service.setRevertFailure(true)
  #expect(await controller.prepareForTermination() == false)
  #expect(controller.trial != nil && controller.errorMessage != nil)
  controller.setVisible(false)
  await service.setRevertFailure(false)
  controller.revert()
  try await waitUntil { controller.trial == nil && !controller.isBusy }
  #expect(await controller.prepareForTermination())
}

@Test @MainActor func displayControllerCanDeallocateDuringReadsAndAnIssuedPreview() async throws {
  let service = GatedDisplays()
  var controller: DisplayController? = DisplayController(service: service)
  controller?.setVisible(true)
  try await waitUntil { await service.reads == 1 }
  weak let reader = controller
  controller = nil
  #expect(reader == nil)
  await service.finishCatalog(1)
  controller = DisplayController(service: service)
  try await loadDisplays(try #require(controller), service: service, read: 2)
  controller?.preview(.mode(service.identity, service.mode))
  try await waitUntil { await service.previews == 1 }
  weak let writer = controller
  controller = nil
  #expect(writer == nil)
  await service.finishPreview()
  try await waitUntil { await service.reverts == 1 }
  #expect(await service.status().trial == nil)
}

@Test @MainActor func displayMonitoringSuspensionDoesNotAbandonAnExplicitPreview() async throws {
  let service = GatedDisplays()
  let model = AppModel(displayService: service, persistsPreferences: false)
  model.page = .display
  model.setDemand("popover", active: true)
  try await waitUntil { await service.reads == 1 }
  await service.finishCatalog(1)
  try await waitUntil { model.displays.canPreview }
  model.displays.preview(.mode(service.identity, service.mode))
  try await waitUntil { await service.previews == 1 }
  model.stop()
  await service.finishPreview()
  try await waitUntil { model.displays.trial != nil && !model.displays.isBusy }
  #expect(!model.displays.canPreview)
  model.displays.revert()
  try await waitUntil { model.displays.trial == nil }
}

@Test @MainActor func displayCanceledOwnerCannotRevertAnotherOwnersTrial() async throws {
  let service = GatedDisplays()
  var controller: DisplayController? = DisplayController(service: service)
  try await loadDisplays(try #require(controller), service: service)
  controller?.preview(.mode(service.identity, service.mode))
  try await waitUntil { await service.previews == 1 }
  weak let owner = controller
  controller = nil
  #expect(owner == nil)
  await service.finishRejectedPreviewWithAnotherOwnersTrial()
  for _ in 0..<20 { await Task.yield() }
  #expect(await service.reverts == 0)
  #expect(await service.status().trial != nil)
}

@MainActor private func loadDisplays(
  _ controller: DisplayController, service: GatedDisplays, read: Int = 1
) async throws {
  controller.setVisible(true)
  try await waitUntil { await service.reads == read }
  await service.finishCatalog(read)
  try await waitUntil { controller.canPreview }
}
