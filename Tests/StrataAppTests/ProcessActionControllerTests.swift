import Foundation
import StrataCore
import StrataSystem
import Testing

@testable import StrataBar

@MainActor private final class GatedApplicationQuit: ApplicationQuitting {
  private var continuation: CheckedContinuation<PreparedApplicationQuit, Never>?
  var preparations = 0
  var executions = 0
  var canceled: [UUID] = []
  func canQuit(_ process: ProcessSample) -> Bool { true }
  func prepare(_ process: ProcessSample) async -> PreparedApplicationQuit {
    preparations += 1
    return await withCheckedContinuation { continuation = $0 }
  }
  func perform(_ action: PreparedApplicationQuit) { executions += 1 }
  func cancel(_ identifier: UUID) { canceled.append(identifier) }
  func finish(_ action: PreparedApplicationQuit) {
    continuation?.resume(returning: action)
    continuation = nil
  }
}

@Test @MainActor func canceledNormalQuitCannotOpenALateConfirmationOrExecute() async throws {
  let service = GatedApplicationQuit()
  let controller = ProcessActionController(applicationQuit: service) { _ in
    Issue.record("Unexpected error")
  }
  let process = actionTarget()
  let action = PreparedApplicationQuit(id: UUID(), identity: process.id, name: process.name)
  controller.requestApplicationQuit(process)
  try await waitUntil { service.preparations == 1 }
  controller.stop()
  service.finish(action)
  try await waitUntil { service.canceled == [action.id] }
  #expect(controller.prepared == nil && service.executions == 0)
  controller.requestApplicationQuit(process)
  try await waitUntil { service.preparations == 2 }
  service.finish(action)
  try await waitUntil { controller.prepared != nil }
  controller.confirm()
  controller.dismissConfirmation()
  try await waitUntil { service.executions == 1 }
  #expect(service.canceled == [action.id])
  controller.stop()
}

private actor ControlledProcessControl: ProcessControlling {
  private var preparation: CheckedContinuation<PreparedProcessAction, Never>?
  private var execution: CheckedContinuation<Void, Never>?
  private(set) var preparations = 0
  private(set) var executions = 0
  private(set) var canceled: [UUID] = []
  func prepare(_ process: ProcessSample, signal: ProcessSignal) async -> PreparedProcessAction {
    preparations += 1
    return await withCheckedContinuation { preparation = $0 }
  }
  func perform(_ action: PreparedProcessAction) async {
    executions += 1
    await withCheckedContinuation { execution = $0 }
  }
  func cancel(_ identifier: UUID) { canceled.append(identifier) }
  func resumePaused(_ identity: ProcessIdentity) {}
  func finishPreparation(_ action: PreparedProcessAction) {
    preparation?.resume(returning: action)
    preparation = nil
  }
  func finishExecution() {
    execution?.resume()
    execution = nil
  }
}

private func actionTarget() -> ProcessSample {
  ProcessSample(
    id: ProcessIdentity(pid: 42, startSeconds: 1, startMicroseconds: 2), parentPID: 1,
    userID: 501, name: "Worker", path: "", cpuTimeNanoseconds: nil, residentBytes: nil,
    footprintBytes: nil, threads: nil)
}

@Test @MainActor func closingDuringPreparationDiscardsTheLeaseAndLateResult() async throws {
  let service = ControlledProcessControl()
  var errors: [String] = []
  let controller = ProcessActionController(service: service) { errors.append($0) }
  let target = actionTarget()
  let action = PreparedProcessAction(
    id: UUID(), identity: target.id, name: target.name, signal: .terminate)
  controller.request(target, signal: .terminate)
  try await waitUntil { await service.preparations == 1 }
  controller.stop()
  await service.finishPreparation(action)
  try await waitUntil { await service.canceled.contains(action.id) }
  #expect(controller.prepared == nil && !controller.isBusy && errors.isEmpty)
}

@Test @MainActor func dialogDismissalAfterConfirmDoesNotCancelAnAuthorizedAction() async throws {
  let service = ControlledProcessControl()
  let controller = ProcessActionController(service: service) { _ in Issue.record("Unexpected error")
  }
  let target = actionTarget()
  let action = PreparedProcessAction(
    id: UUID(), identity: target.id, name: target.name, signal: .terminate)
  controller.request(target, signal: .terminate)
  try await waitUntil { await service.preparations == 1 }
  await service.finishPreparation(action)
  try await waitUntil { controller.prepared != nil }
  controller.confirm()
  controller.dismissConfirmation()
  try await waitUntil { await service.executions == 1 }
  #expect(await service.canceled.isEmpty)
  await service.finishExecution()
  try await waitUntil { !controller.isBusy }
  controller.stop()
}

@Test @MainActor func cancelingConfirmationNeverExecutesTheSignal() async throws {
  let service = ControlledProcessControl()
  let controller = ProcessActionController(service: service) { _ in Issue.record("Unexpected error")
  }
  let target = actionTarget()
  let action = PreparedProcessAction(
    id: UUID(), identity: target.id, name: target.name, signal: .forceQuit)
  controller.request(target, signal: .forceQuit)
  try await waitUntil { await service.preparations == 1 }
  await service.finishPreparation(action)
  try await waitUntil { controller.prepared != nil }
  controller.dismissConfirmation()
  try await waitUntil { await service.canceled == [action.id] }
  #expect(await service.executions == 0)
  controller.stop()
}

@Test @MainActor func batchRequestPreparesGroupActionWithMemberCount() async throws {
  let service = ControlledProcessControl()
  let controller = ProcessActionController(service: service) { _ in Issue.record("Unexpected error")
  }
  let first = actionTarget()
  let second = ProcessSample(
    id: ProcessIdentity(pid: 43, startSeconds: 1, startMicroseconds: 3), parentPID: 1,
    userID: 501, name: "Worker", path: "", cpuTimeNanoseconds: nil, residentBytes: nil,
    footprintBytes: nil, threads: nil)
  let action = PreparedProcessAction(
    id: UUID(), identities: [first.id, second.id], name: "Worker", signal: .terminate)
  controller.request([first, second], name: "Worker", signal: .terminate)
  try await waitUntil { await service.preparations == 1 }
  await service.finishPreparation(action)
  try await waitUntil { controller.prepared != nil }
  #expect(controller.prepared?.count == 2)
  if case .signal(let prepared) = controller.prepared {
    #expect(prepared.identities == [first.id, second.id])
  } else {
    Issue.record("Expected prepared signal action")
  }
  controller.dismissConfirmation()
  try await waitUntil { await service.canceled == [action.id] }
  controller.stop()
}
