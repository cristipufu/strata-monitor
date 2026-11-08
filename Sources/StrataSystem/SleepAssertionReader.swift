import Foundation
import IOKit.pwr_mgt
import StrataCore

protocol SleepAssertionSource: Sendable {
  // Nil when power management fails the query.
  func assertionsByProcess() -> [AnyHashable: Any]?
}

public struct SleepAssertionReader: Sendable {
  private let source: any SleepAssertionSource

  public init() { self.init(source: NativeSleepAssertionSource()) }

  init(source: any SleepAssertionSource) { self.source = source }

  public func read() -> [SleepBlocker]? {
    guard let byProcess = source.assertionsByProcess() else { return nil }
    let blockers = byProcess.flatMap { key, assertions in
      (assertions as? [Any] ?? []).compactMap {
        Self.blocker(ownerKey: key.base, assertion: $0 as? [String: Any] ?? [:])
      }
    }
    return blockers.sorted { ($0.pid, $0.assertionID ?? 0) < ($1.pid, $1.assertionID ?? 0) }
  }

  private static func blocker(ownerKey: Any, assertion: [String: Any]) -> SleepBlocker? {
    // Level 0 is an assertion its owner switched off; an unreadable level is still listed.
    guard let type = assertion[kIOPMAssertionTypeKey as String] as? String, !type.isEmpty,
      let pid = processID(ownerKey) ?? processID(assertion["AssertPID"]),
      PowerSourceValue.integer(assertion[kIOPMAssertionLevelKey as String]) != 0
    else { return nil }
    // Power management records the type it enforces when a deprecated alias was requested.
    let enforcedType = assertion["AssertionTrueType"] as? String ?? type
    return SleepBlocker(
      pid: pid, processName: nonEmpty(assertion["Process Name"]),
      assertionID: PowerSourceValue.integer(assertion["AssertionId"]).map(Int64.init),
      assertionType: type, name: nonEmpty(assertion[kIOPMAssertionNameKey as String]),
      createdAt: assertion["AssertStartWhen"] as? Date,
      prevention: SleepPrevention(assertionType: enforcedType))
  }

  private static func processID(_ value: Any?) -> Int32? {
    PowerSourceValue.integer(value).flatMap(Int32.init(exactly:)).flatMap { $0 >= 0 ? $0 : nil }
  }

  private static func nonEmpty(_ value: Any?) -> String? {
    guard let text = value as? String, !text.isEmpty else { return nil }
    return text
  }
}

struct NativeSleepAssertionSource: SleepAssertionSource {
  func assertionsByProcess() -> [AnyHashable: Any]? {
    var assertions: Unmanaged<CFDictionary>?
    let result = IOPMCopyAssertionsByProcess(&assertions)
    let dictionary = assertions?.takeRetainedValue()
    guard result == kIOReturnSuccess else { return nil }
    return dictionary as? [AnyHashable: Any]
  }
}
