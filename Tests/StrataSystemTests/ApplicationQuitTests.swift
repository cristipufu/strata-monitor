import Foundation
import StrataCore
import Testing

@testable import StrataSystem

@MainActor private final class QuitTarget: ApplicationQuitTarget {
  var processIdentifier: Int32 = 42
  var isTerminated = false
  var hasApplicationBundle = true
  var acceptsRequest = true
  var requests = 0
  func isSameApplication(as other: any ApplicationQuitTarget) -> Bool { self === other }
  func requestQuit() -> Bool {
    requests += 1
    return acceptsRequest
  }
}
@MainActor private final class QuitApplications: ApplicationFinding {
  var target: QuitTarget?
  init(_ target: QuitTarget?) { self.target = target }
  func application(for pid: Int32) -> (any ApplicationQuitTarget)? { target }
}
@MainActor private final class QuitClock { var now = 10.0 }
private final class QuitIdentity: ProcessIdentityVerifying, @unchecked Sendable {
  private let lock = NSLock()
  private var valid = true
  func setValid(_ valid: Bool) {
    lock.lock()
    defer { lock.unlock() }
    self.valid = valid
  }
  func isCurrent(_ identity: ProcessIdentity) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return valid
  }
}
private func quitProcess() -> ProcessSample {
  ProcessSample(
    id: ProcessIdentity(pid: 42, startSeconds: 1, startMicroseconds: 0), parentPID: 1,
    userID: getuid(),
    name: "Owned fixture", path: "", cpuTimeNanoseconds: nil, residentBytes: nil,
    footprintBytes: nil, threads: nil)
}

@Test @MainActor func normalQuitTargetsTheRetainedApplicationInstanceAndCannotReplay() throws {
  let target = QuitTarget()
  let directory = QuitApplications(nil)
  directory.target = target
  let service = ApplicationQuitService(applications: directory, identities: QuitIdentity())
  let prepared = try service.prepare(quitProcess())
  try service.perform(prepared)
  #expect(target.requests == 1)
  #expect(throws: ApplicationQuitError.expired) { try service.perform(prepared) }
  #expect(target.requests == 1)
  target.acceptsRequest = false
  let rejected = try service.prepare(quitProcess())
  #expect(throws: ApplicationQuitError.requestRejected) { try service.perform(rejected) }
  #expect(target.requests == 2)
}

@Test @MainActor func quitRejectsReplacedAppEvenWhenPIDAndKernelIdentityAppearUnchanged() throws {
  let original = QuitTarget()
  let replacement = QuitTarget()
  let directory = QuitApplications(original)
  let service = ApplicationQuitService(applications: directory, identities: QuitIdentity())
  let prepared = try service.prepare(quitProcess())
  directory.target = replacement
  #expect(throws: ApplicationQuitError.targetChanged) { try service.perform(prepared) }
  #expect(original.requests == 0 && replacement.requests == 0)
}

@Test @MainActor func quitRejectsKernelIdentityChangesAndAutomaticallyRelaunchedPIDs() throws {
  let target = QuitTarget()
  let identities = QuitIdentity()
  let service = ApplicationQuitService(
    applications: QuitApplications(target), identities: identities)
  let first = try service.prepare(quitProcess())
  identities.setValid(false)
  #expect(throws: ApplicationQuitError.targetChanged) { try service.perform(first) }
  identities.setValid(true)
  let second = try service.prepare(quitProcess())
  target.processIdentifier = 43
  #expect(throws: ApplicationQuitError.targetChanged) { try service.perform(second) }
  #expect(target.requests == 0)
}

@Test @MainActor func quitConfirmationsExpireCancelAndRequireAnApplicationBundle() throws {
  let target = QuitTarget()
  let clock = QuitClock()
  let service = ApplicationQuitService(
    applications: QuitApplications(target), identities: QuitIdentity(), uptime: { clock.now })
  let first = try service.prepare(quitProcess())
  clock.now = 41
  #expect(throws: ApplicationQuitError.expired) { try service.perform(first) }
  let second = try service.prepare(quitProcess())
  service.cancel(second.id)
  #expect(throws: ApplicationQuitError.expired) { try service.perform(second) }
  target.hasApplicationBundle = false
  #expect(!service.canQuit(quitProcess()))
  #expect(throws: ApplicationQuitError.notAnApplication) { try service.prepare(quitProcess()) }
  #expect(target.requests == 0)
}
