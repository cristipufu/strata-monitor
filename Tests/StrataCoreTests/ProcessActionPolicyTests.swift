import Foundation
import StrataCore
import Testing

@Test func processActionsRejectSystemSelfAndOtherUsers() {
  func process(_ pid: Int32, user: UInt32) -> ProcessSample {
    ProcessSample(
      id: ProcessIdentity(pid: pid, startSeconds: 1, startMicroseconds: 0), parentPID: 1,
      userID: user, name: "Test", path: "", cpuTimeNanoseconds: nil, residentBytes: nil,
      footprintBytes: nil, threads: nil)
  }
  #expect(!ProcessActionPolicy.allows(process(1, user: 501), currentPID: 30, currentUser: 501))
  #expect(!ProcessActionPolicy.allows(process(30, user: 501), currentPID: 30, currentUser: 501))
  #expect(!ProcessActionPolicy.allows(process(31, user: 502), currentPID: 30, currentUser: 501))
  #expect(!ProcessActionPolicy.allows(process(31, user: 0), currentPID: 30, currentUser: 0))
  #expect(ProcessActionPolicy.allows(process(31, user: 501), currentPID: 30, currentUser: 501))
}

@Test func processConfirmationsExpireAndRejectInvalidClocks() {
  #expect(ProcessActionPolicy.confirmationIsCurrent(created: 10, now: 40))
  #expect(!ProcessActionPolicy.confirmationIsCurrent(created: 10, now: 40.01))
  #expect(!ProcessActionPolicy.confirmationIsCurrent(created: 10, now: 9))
  #expect(!ProcessActionPolicy.confirmationIsCurrent(created: .nan, now: 20))
}

@Test func pausingSparesTheSessionAndResumingNeedsAPausedProcess() {
  func process(_ name: String, state: ProcessRunState?) -> ProcessSample {
    ProcessSample(
      id: ProcessIdentity(pid: 40, startSeconds: 1, startMicroseconds: 0), parentPID: 1,
      userID: 501, name: name, path: "", cpuTimeNanoseconds: nil, residentBytes: nil,
      footprintBytes: nil, threads: nil, runState: state)
  }
  func allows(_ signal: ProcessSignal, _ process: ProcessSample) -> Bool {
    ProcessActionPolicy.allows(signal, for: process, currentPID: 30, currentUser: 501)
  }
  #expect(allows(.pause, process("bun", state: .running)))
  #expect(!allows(.pause, process("Dock", state: .running)))
  #expect(!allows(.pause, process("bun", state: .stopped)))
  #expect(allows(.resume, process("bun", state: .stopped)))
  #expect(!allows(.resume, process("bun", state: .running)))
  #expect(allows(.terminate, process("Dock", state: .running)))
  #expect(!ProcessSignal.pause.needsConfirmation && ProcessSignal.forceQuit.needsConfirmation)
}

@Test func theLedgerKeepsOnlyProcessesStillPausedByStrataBar() {
  let first = ProcessIdentity(pid: 40, startSeconds: 1, startMicroseconds: 0)
  let second = ProcessIdentity(pid: 41, startSeconds: 1, startMicroseconds: 0)
  var ledger = PausedProcessLedger()
  ledger.record(.pause, for: first)
  ledger.record(.pause, for: second)
  ledger.record(.resume, for: first)
  #expect(ledger.identities == [second])
  ledger.record(.forceQuit, for: second)
  #expect(ledger.identities.isEmpty)
}
