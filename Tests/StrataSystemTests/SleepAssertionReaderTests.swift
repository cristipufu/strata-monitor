import Foundation
import StrataCore
import Testing

@testable import StrataSystem

// Immutable fixture data, never mutated after creation.
private struct AssertionsFixture: SleepAssertionSource, @unchecked Sendable {
  let values: [AnyHashable: Any]?
  func assertionsByProcess() -> [AnyHashable: Any]? { values }
}

private func read(_ values: [AnyHashable: Any]?) -> [SleepBlocker]? {
  SleepAssertionReader(source: AssertionsFixture(values: values)).read()
}

private let started = Date(timeIntervalSince1970: 1_800_000_000)

private func assertion(_ type: String, _ fields: [String: Any] = [:]) -> [String: Any] {
  [
    "AssertType": type, "AssertLevel": 255, "AssertName": "caffeinate command-line tool",
    "AssertStartWhen": started, "AssertionId": 36_847, "Process Name": "caffeinate",
  ].merging(fields) { $1 }
}

@Test func sleepAssertionsBecomeBlockersWithTheirProcessNameAndAge() throws {
  let blockers = try #require(
    read([
      NSNumber(value: 41_364): [assertion("PreventUserIdleSystemSleep")],
      NSNumber(value: 98_483): [
        assertion("UserIsActive", ["Process Name": "WindowServer", "AssertionId": 34_409])
      ],
    ]))
  #expect(blockers.map(\.pid) == [41_364, 98_483])
  let caffeinate = try #require(blockers.first)
  #expect(caffeinate.processName == "caffeinate" && caffeinate.assertionID == 36_847)
  #expect(caffeinate.name == "caffeinate command-line tool")
  #expect(caffeinate.assertionType == "PreventUserIdleSystemSleep")
  #expect(caffeinate.preventsSystemSleep == true && caffeinate.preventsDisplaySleep == false)
  #expect(caffeinate.age(at: started + 60) == 60)
  #expect(blockers[1].prevention == .userActivity)
}

@Test func deprecatedAssertionTypesUseTheTypePowerManagementEnforces() throws {
  let blockers = try #require(
    read([
      NSNumber(value: 5): [
        assertion("NoDisplaySleepAssertion", ["AssertionTrueType": "PreventUserIdleDisplaySleep"])
      ]
    ]))
  #expect(blockers.first?.assertionType == "NoDisplaySleepAssertion")
  #expect(blockers.first?.prevention == .keepsDisplayOn)
}

@Test func releasedAssertionsAreNotSleepBlockers() {
  #expect(
    read([NSNumber(value: 5): [assertion("PreventUserIdleSystemSleep", ["AssertLevel": 0])]]) == [])
}

@Test func failedAssertionQueriesStayDistinctFromNoBlockers() {
  #expect(read(nil) == nil)
  #expect(read([:]) == [])
}

@Test func malformedAssertionsAreSkippedWithoutLosingValidOnes() throws {
  let blockers = try #require(
    read([
      "not a pid": [assertion("PreventUserIdleSystemSleep")],
      NSNumber(value: -3): [assertion("PreventUserIdleSystemSleep")],
      NSNumber(value: 7): "not a list",
      NSNumber(value: 8): [
        "not a dictionary", assertion("", [:]), [:] as [String: Any],
        assertion("PreventUserIdleSystemSleep", ["AssertType": 4]),
      ] as [Any],
      NSNumber(value: 9): [
        assertion(
          "PreventUserIdleSystemSleep",
          [
            "AssertName": 5, "Process Name": "", "AssertStartWhen": "yesterday",
            "AssertionId": true, "AssertLevel": "on",
          ])
      ],
    ]))
  #expect(blockers.count == 1)
  let survivor = try #require(blockers.first)
  #expect(survivor.pid == 9 && survivor.name == nil && survivor.processName == nil)
  #expect(survivor.createdAt == nil && survivor.assertionID == nil)
}

@Test func assertionOwnerFallsBackToTheRecordedProcessID() throws {
  let blockers = try #require(
    read(["unexpected key": [assertion("PreventUserIdleSystemSleep", ["AssertPID": 77])]]))
  #expect(blockers.map(\.pid) == [77])
}

@Test func unrecognizedAssertionTypesAreKeptButMakeNoClaims() throws {
  let blocker = try #require(read([NSNumber(value: 4): [assertion("FutureAssertion")]])?.first)
  #expect(blocker.prevention == .unrecognized)
  #expect(blocker.preventsSystemSleep == nil && blocker.preventsDisplaySleep == nil)
}

extension SystemIntegrationTests {
  @Test func liveSleepAssertionsAreReadableWithoutPrivileges() {
    for _ in 0..<20 {
      guard let blockers = SleepAssertionReader().read() else { continue }
      for blocker in blockers {
        #expect(blocker.pid >= 0 && !blocker.assertionType.isEmpty)
      }
    }
  }
}
