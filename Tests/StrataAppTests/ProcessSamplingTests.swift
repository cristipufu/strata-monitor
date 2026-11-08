import Foundation
import StrataCore
import Testing

@testable import StrataBar
@testable import StrataSystem

private struct InstantSampler: ProcessSampling {
  func sample(pid: Int32, seconds: Int) async throws -> SampleReport {
    SampleReport(
      pid: pid, processName: "worker", topFrames: [SampleFrame(symbol: "spin", binary: "w", count: 3)],
      totalSamples: 4, rawText: "Sampling process \(pid)")
  }
}

private final class ChangingIdentity: ProcessIdentityVerifying, @unchecked Sendable {
  private let lock = NSLock()
  private var checks = 0
  let currentChecks: Int
  init(currentChecks: Int) { self.currentChecks = currentChecks }
  func isCurrent(_ identity: ProcessIdentity) -> Bool {
    lock.withLock {
      checks += 1
      return checks <= currentChecks
    }
  }
}

private func worker(user: UInt32 = getuid(), pid: Int32 = 4242) -> ProcessSample {
  ProcessSample(
    id: ProcessIdentity(pid: pid, startSeconds: 1, startMicroseconds: 0), parentPID: 1,
    userID: user, name: "worker", path: "", cpuTimeNanoseconds: nil, residentBytes: nil,
    footprintBytes: nil, threads: nil)
}

@Test @MainActor func samplingReportsOnlyTheProcessThatWasSampled() async throws {
  let steady = ProcessSamplingController(
    sampler: InstantSampler(), identities: ChangingIdentity(currentChecks: .max))
  steady.sample(worker())
  try await waitUntil {
    if case .finished(_, let report) = steady.state { return report.topFrames.count == 1 }
    return false
  }
  let reused = ProcessSamplingController(
    sampler: InstantSampler(), identities: ChangingIdentity(currentChecks: 1))
  reused.sample(worker())
  try await waitUntil {
    if case .failed = reused.state { return true }
    return false
  }
  reused.cancel()
  if case .idle = reused.state {} else { Issue.record("Cancelling returns to idle") }
}

@Test @MainActor func onlyThePersonsOwnOtherProcessesCanBeSampled() {
  #expect(ProcessSamplingController.canSample(worker()))
  #expect(!ProcessSamplingController.canSample(worker(user: 0)))
  #expect(!ProcessSamplingController.canSample(worker(pid: ProcessInfo.processInfo.processIdentifier)))
}
