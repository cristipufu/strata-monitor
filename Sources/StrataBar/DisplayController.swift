import Combine
import Foundation
import StrataSystem

@MainActor final class DisplayController: ObservableObject {
  @Published private(set) var catalog: DisplayCatalog?
  @Published private(set) var trial: DisplayTrial?
  @Published private(set) var recoveryIssue: String?
  @Published private(set) var errorMessage: String?
  @Published private(set) var isLoading = false
  @Published private(set) var isBusy = false
  private let service: any DisplayManaging
  private var isVisible = false
  private var isTerminating = false
  private var refreshID = UUID()
  private var operationID = UUID()
  private var ownedCatalogID: UUID?
  private var refreshTask: Task<Void, Never>?
  private var actionTask: Task<Void, Never>?
  private var statusTask: Task<Void, Never>?

  init(service: any DisplayManaging = DisplayService()) { self.service = service }
  var canPreview: Bool {
    isVisible && !isTerminating && !isLoading && !isBusy && trial == nil
      && catalog?.canPreview == true
  }
  func setVisible(_ visible: Bool) {
    guard visible != isVisible else { return }
    isVisible = visible
    if visible { refreshIfVisible() } else { cancelRefresh() }
  }
  func refreshIfVisible() {
    guard isVisible, !isTerminating, !isLoading, !isBusy, trial == nil else { return }
    let identifier = UUID()
    refreshID = identifier
    isLoading = true
    let service = service
    refreshTask = Task { [weak self] in
      defer { self?.finishRefresh(identifier) }
      do {
        try Task.checkCancellation()
        let next = try await service.catalog()
        try Task.checkCancellation()
        guard self?.refreshID == identifier else { return }
        self?.catalog = next
      } catch {
        guard !Task.isCancelled, self?.refreshID == identifier else { return }
        self?.catalog = nil
        self?.errorMessage = error.localizedDescription
      }
    }
  }
  func preview(_ change: DisplayChange) {
    guard canPreview, let catalog else { return }
    ownedCatalogID = catalog.id
    let service = service
    perform {
      _ = try await service.preview(change, catalogID: catalog.id)
    }
  }
  func keep() {
    guard trial?.canKeep == true, recoveryIssue == nil, let trial else { return }
    let service = service
    perform { try await service.accept(trial.id) }
  }
  func revert() {
    guard let trial else { return }
    let service = service
    perform { try await service.revert(trial.id) }
  }
  func dismissError() { errorMessage = nil }
  func dismissRecoveryIssue() {
    guard trial == nil else { return }
    recoveryIssue = nil
  }
  func prepareForTermination() async -> Bool {
    isTerminating = true
    cancelRefresh()
    statusTask?.cancel()
    statusTask = nil
    actionTask?.cancel()
    await actionTask?.value
    let status = await service.status()
    guard let trial = status.trial, trial.catalogID == ownedCatalogID else { return true }
    do {
      try await service.revert(trial.id)
      return true
    } catch {
      isTerminating = false
      errorMessage = error.localizedDescription
      publish(await service.status())
      return false
    }
  }
  private func perform(_ action: @escaping @Sendable () async throws -> Void) {
    guard !isTerminating, !isBusy else { return }
    cancelRefresh()
    isBusy = true
    errorMessage = nil
    let identifier = UUID()
    operationID = identifier
    let service = service
    let catalogID = ownedCatalogID
    actionTask = Task { [weak self] in
      var failure: String?
      do {
        try Task.checkCancellation()
        try await action()
      } catch { failure = error.localizedDescription }
      let status = await service.status()
      guard !Task.isCancelled, self?.operationID == identifier else {
        if let trial = status.trial, trial.catalogID == catalogID {
          try? await service.revert(trial.id)
        }
        self?.finishAction(identifier)
        return
      }
      self?.errorMessage = failure
      self?.publish(status)
      self?.finishAction(identifier)
      self?.refreshIfVisible()
    }
  }
  private func publish(_ status: DisplayTrialStatus) {
    let isOwned = status.trial.map { $0.catalogID == ownedCatalogID } ?? true
    trial = isOwned ? status.trial : nil
    recoveryIssue = isOwned ? status.issue : nil
    if trial != nil {
      observeRecovery()
    } else {
      statusTask?.cancel()
      statusTask = nil
    }
  }
  private func observeRecovery() {
    guard statusTask == nil, !isTerminating else { return }
    let service = service
    statusTask = Task { [weak self] in
      while !Task.isCancelled {
        do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
        guard let identifier = self?.operationID else { return }
        let status = await service.status()
        guard !Task.isCancelled else { return }
        guard self?.operationID == identifier, self?.isBusy == false else { continue }
        self?.publish(status)
        if status.trial == nil {
          self?.refreshIfVisible()
          return
        }
      }
    }
  }
  private func cancelRefresh() {
    refreshID = UUID()
    refreshTask?.cancel()
    refreshTask = nil
    isLoading = false
  }
  private func finishRefresh(_ identifier: UUID) {
    guard refreshID == identifier else { return }
    refreshTask = nil
    isLoading = false
  }
  private func finishAction(_ identifier: UUID) {
    guard operationID == identifier else { return }
    actionTask = nil
    isBusy = false
  }
  isolated deinit {
    refreshTask?.cancel()
    actionTask?.cancel()
    statusTask?.cancel()
    if let trial {
      let service = service
      Task { try? await service.revert(trial.id) }
    }
  }
}
