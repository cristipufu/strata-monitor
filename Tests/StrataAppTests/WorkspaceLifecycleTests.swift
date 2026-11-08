import AppKit
import Testing

@testable import StrataBar

@Test @MainActor func workspaceObserverCoalescesSleepEventsAndStopsDeliveryAfterTeardown() {
  let center = NotificationCenter()
  var suspends = 0
  var resumes = 0
  var monitor: WorkspaceLifecycleMonitor? = WorkspaceLifecycleMonitor(
    center: center, isConsoleSession: true,
    suspend: { suspends += 1 }, resume: { resumes += 1 })
  center.post(name: NSWorkspace.willSleepNotification, object: nil)
  center.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
  center.post(name: NSWorkspace.didWakeNotification, object: nil)
  #expect(suspends == 1 && resumes == 0)
  center.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
  #expect(resumes == 1)
  monitor?.stop()
  monitor = nil
  center.post(name: NSWorkspace.willSleepNotification, object: nil)
  #expect(suspends == 1)
}

@Test @MainActor func initiallyInactiveWorkspaceSuspendsUntilActiveAndDoesNotRetainItsOwner() {
  let center = NotificationCenter()
  var suspends = 0
  var resumes = 0
  var monitor: WorkspaceLifecycleMonitor? = WorkspaceLifecycleMonitor(
    center: center, isConsoleSession: false,
    suspend: { suspends += 1 }, resume: { resumes += 1 })
  weak let weakMonitor = monitor
  #expect(suspends == 1)
  center.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
  #expect(resumes == 1)
  monitor = nil
  #expect(weakMonitor == nil)
  center.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
  #expect(suspends == 1)
}
