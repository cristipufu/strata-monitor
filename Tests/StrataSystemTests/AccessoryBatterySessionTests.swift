import Foundation
import Testing

@testable import StrataSystem

@Test func accessoryBatteryDeniedNativeSessionIsSingleUseAndReleasesItsTimerOwner() async throws {
  weak var owner: NativeAccessoryBatterySession?
  do {
    let session = NativeAccessoryBatterySession(isAuthorized: { false })
    owner = session
    await #expect(throws: AccessoryBatteryError.permissionRequired) { try await session.read() }
    await #expect(throws: AccessoryBatteryError.failed("This battery session has already ended.")) {
      try await session.read()
    }
  }
  let clock = ContinuousClock()
  let deadline = clock.now + .seconds(2)
  while owner != nil, clock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
  #expect(owner == nil)
}
