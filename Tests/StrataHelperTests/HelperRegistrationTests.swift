import Foundation
import ServiceManagement
import StrataSystem
import Synchronization
import Testing

final class FakeLaunchDaemon: LaunchDaemonControlling {
  struct State {
    var status: SMAppService.Status = .notRegistered
    var registerError: NSError?
    var unregisterError: NSError?
    var calls: [String] = []
  }
  private let state = Mutex(State())
  init(_ configure: (inout State) -> Void = { _ in }) { state.withLock { configure(&$0) } }
  var calls: [String] { state.withLock { $0.calls } }
  var status: SMAppService.Status { state.withLock { $0.status } }
  func register() throws {
    try state.withLock {
      $0.calls.append("register")
      if let error = $0.registerError { throw error }
      $0.status = .requiresApproval
    }
  }
  func unregister() async throws {
    try state.withLock {
      $0.calls.append("unregister")
      if let error = $0.unregisterError { throw error }
      $0.status = .notRegistered
    }
  }
  func openSystemSettingsLoginItems() { state.withLock { $0.calls.append("openSettings") } }
}

private func serviceError(_ code: Int) -> NSError {
  NSError(domain: SMAppServiceErrorDomain, code: code)
}

@Test(arguments: [
  (SMAppService.Status.notRegistered, PrivilegedHelperStatus.notRegistered),
  (.enabled, .enabled), (.requiresApproval, .requiresApproval), (.notFound, .notFound),
])
func registrationStatusMapsEveryServiceState(
  _ status: SMAppService.Status, _ expected: PrivilegedHelperStatus
) {
  let registration = PrivilegedHelperRegistration(daemon: FakeLaunchDaemon { $0.status = status })
  #expect(registration.status() == expected)
}

@Test func registeringReportsThatApprovalIsPending() throws {
  let daemon = FakeLaunchDaemon()
  let registration = PrivilegedHelperRegistration(daemon: daemon)
  #expect(try registration.register() == .requiresApproval)
  registration.openLoginItemsSettings()
  #expect(daemon.calls == ["register", "openSettings"])
}

@Test func deniedLaunchIsReportedAsNotAllowed() {
  let registration = PrivilegedHelperRegistration(
    daemon: FakeLaunchDaemon {
      $0.status = .requiresApproval
      $0.registerError = serviceError(kSMErrorLaunchDeniedByUser)
    })
  #expect(throws: PrivilegedHelperRegistrationError.notAllowed) { try registration.register() }
}

@Test func genericErrorWhileAwaitingApprovalStillReportsTheStatus() throws {
  let registration = PrivilegedHelperRegistration(
    daemon: FakeLaunchDaemon {
      $0.status = .requiresApproval
      $0.registerError = NSError(domain: SMAppServiceErrorDomain, code: Int(EPERM))
    })
  #expect(try registration.register() == .requiresApproval)
}

@Test func unsignedOrIncompleteBundlesExplainWhyTheyCannotRegister() {
  for (code, expected) in [
    (kSMErrorInvalidSignature, PrivilegedHelperRegistrationError.invalidSignature),
    (kSMErrorJobPlistNotFound, .notFound), (kSMErrorToolNotValid, .notFound),
  ] {
    let registration = PrivilegedHelperRegistration(
      daemon: FakeLaunchDaemon { $0.registerError = serviceError(code) })
    #expect(throws: expected) { try registration.register() }
  }
  let unknown = PrivilegedHelperRegistration(
    daemon: FakeLaunchDaemon {
      $0.registerError = NSError(
        domain: "Other", code: 9, userInfo: [NSLocalizedDescriptionKey: "Fixture failure"])
    })
  #expect(throws: PrivilegedHelperRegistrationError.failed("Fixture failure")) {
    try unknown.register()
  }
}

@Test func reregisteringUnregistersFirstAndToleratesAMissingJob() async throws {
  let daemon = FakeLaunchDaemon {
    $0.status = .enabled
    $0.unregisterError = serviceError(kSMErrorJobNotFound)
  }
  let registration = PrivilegedHelperRegistration(daemon: daemon)
  #expect(try await registration.reregister() == .requiresApproval)
  #expect(daemon.calls == ["unregister", "register"])
}

@Test func failedUnregisterIsReported() async {
  let registration = PrivilegedHelperRegistration(
    daemon: FakeLaunchDaemon { $0.unregisterError = serviceError(kSMErrorAuthorizationFailure) })
  await #expect(throws: PrivilegedHelperRegistrationError.self) {
    try await registration.unregister()
  }
}
