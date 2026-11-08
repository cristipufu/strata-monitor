import StrataCore
import Testing

@Test func wakeDoesNotResumeWhileTheDisplayOrSessionIsStillUnavailable() {
  var availability = MonitoringAvailability()
  #expect(availability.receive(.screensDidSleep) == .suspend)
  #expect(availability.receive(.systemWillSleep) == nil)
  #expect(availability.receive(.sessionResigned) == nil)
  #expect(availability.receive(.systemDidWake) == nil)
  #expect(availability.receive(.screensDidWake) == nil)
  #expect(!availability.isAvailable)
  #expect(availability.receive(.sessionBecameActive) == .resume)
  #expect(availability.isAvailable)
  #expect(availability.receive(.sessionBecameActive) == nil)
}

@Test func initiallyInactiveSessionsRequireAnActualSwitchIn() {
  var availability = MonitoringAvailability(isConsoleSession: false)
  #expect(!availability.isAvailable)
  #expect(availability.receive(.systemDidWake) == nil)
  #expect(availability.receive(.sessionBecameActive) == .resume)
  #expect(availability.receive(.systemWillSleep) == .suspend)
  #expect(availability.receive(.systemWillSleep) == nil)
}
