import Foundation
import StrataCore
import StrataHelperInterface
import Testing

@testable import StrataBar
@testable import StrataSystem

private final class FakeRegistration: PrivilegedHelperRegistering, @unchecked Sendable {
  var current: PrivilegedHelperStatus
  var registered = 0
  var unregistered = 0
  var openedLoginItems = 0
  init(_ status: PrivilegedHelperStatus) { current = status }
  func status() -> PrivilegedHelperStatus { current }
  func register() throws(PrivilegedHelperRegistrationError) -> PrivilegedHelperStatus {
    registered += 1
    current = .requiresApproval
    return current
  }
  func unregister() async throws(PrivilegedHelperRegistrationError) {
    unregistered += 1
    current = .notRegistered
  }
  func reregister() async throws(PrivilegedHelperRegistrationError) -> PrivilegedHelperStatus {
    current
  }
  func openLoginItemsSettings() { openedLoginItems += 1 }
}

private struct UnreachableHelper: PrivilegedHelperConnecting {
  func makeConnection() throws(PrivilegedHelperError) -> NSXPCConnection { throw .unreachable }
}

@MainActor private func controller(
  _ registration: FakeRegistration, isAdministrator: Bool = true
) -> FullVisibilityController {
  FullVisibilityController(
    registration: registration, client: PrivilegedHelperClient(connector: UnreachableHelper()),
    processes: MergedProcessInventory(), resources: MergedResourceInspector(local: ResourceCollector()),
    isAdministrator: isAdministrator, approvalCheckInterval: .milliseconds(10))
}

@Test @MainActor func turningOnWaitsForApprovalAndTurningOffUnregisters() async throws {
  let registration = FakeRegistration(.notRegistered)
  let visibility = controller(registration)
  visibility.refresh()
  try await waitUntil { visibility.state == .off }
  visibility.setEnabled(true)
  try await waitUntil { visibility.state == .needsApproval }
  #expect(visibility.isRequested && registration.registered == 1)
  visibility.setEnabled(false)
  try await waitUntil { registration.unregistered == 1 }
  #expect(visibility.state == .off && !visibility.isRequested)
}

@Test @MainActor func anApprovedHelperThatCannotBeReachedIsReportedNotTrusted() async throws {
  let visibility = controller(FakeRegistration(.enabled))
  visibility.refresh()
  try await waitUntil {
    if case .failed = visibility.state { return true }
    return false
  }
  let missing = controller(FakeRegistration(.notFound))
  missing.refresh()
  try await waitUntil {
    if case .unavailable = missing.state { return true }
    return false
  }
}

@Test @MainActor func turningOffWhileTurningOnEndsUnregisteredAndOff() async throws {
  let registration = FakeRegistration(.notRegistered)
  let visibility = controller(registration)
  visibility.setEnabled(true)
  visibility.setEnabled(false)
  try await waitUntil { registration.unregistered == 1 }
  try await Task.sleep(for: .milliseconds(50))
  #expect(registration.registered <= 1, "A superseded request may never reach the system")
  #expect(registration.current == .notRegistered && visibility.state == .off)
}

@Test @MainActor func oneClickOpensLoginItemsAndNoticesTheApprovalWithoutReturningToTheApp()
  async throws
{
  let registration = FakeRegistration(.notRegistered)
  let visibility = controller(registration)
  #expect(visibility.offersExactReadings)
  visibility.requestExactReadings()
  try await waitUntil { visibility.state == .needsApproval }
  #expect(registration.openedLoginItems == 1)
  #expect(visibility.offersExactReadings, "The offer shows how to finish")
  // The fake helper can't be reached, so noticing the approval ends in a reported failure.
  registration.current = .enabled
  try await waitUntil { visibility.state != .needsApproval }
  #expect(registration.openedLoginItems == 1)
  #expect(visibility.offersExactReadings, "A failure can be tried again")
}

@Test @MainActor func approvalRefusedInSystemSettingsTurnsTheSettingOff() async throws {
  let registration = FakeRegistration(.notRegistered)
  let visibility = controller(registration)
  visibility.requestExactReadings()
  try await waitUntil { visibility.state == .needsApproval }
  registration.current = .notRegistered
  try await waitUntil { visibility.state == .off }
  visibility.stop()
}

@Test @MainActor func turningOnFromSettingsDoesNotOpenLoginItemsByItself() async throws {
  let registration = FakeRegistration(.notRegistered)
  let visibility = controller(registration)
  visibility.setEnabled(true)
  try await waitUntil { visibility.state == .needsApproval }
  #expect(registration.openedLoginItems == 0)
  visibility.stop()
}

@Test @MainActor func onlyAdministratorsAreOfferedExactReadings() {
  #expect(!controller(FakeRegistration(.notRegistered), isAdministrator: false).offersExactReadings)
}
