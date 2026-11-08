import AppKit
import StrataCore
import SwiftUI
import XCTest

@testable import StrataBar

final class MenuBarIndicatorTests: CocoaTestCase {
  @MainActor func testResizingTheIndicatorKeepsItsExistingHoverTrackingRegion() throws {
    _ = NSApplication.shared
    let host = TrackingHost(rootView: Text("Indicator"), event: { _ in })
    host.frame = CGRect(x: 0, y: 0, width: 42, height: 24)
    host.updateTrackingAreas()
    let tracking = try XCTUnwrap(host.trackingAreas.first)
    host.frame.size.width = 78
    host.updateTrackingAreas()
    XCTAssertEqual(host.trackingAreas.count, 1)
    XCTAssertTrue(host.trackingAreas.first === tracking)
    XCTAssertTrue(tracking.options.contains(.inVisibleRect))
    XCTAssertEqual(host.layer?.backgroundColor?.alpha, 0)
    XCTAssertFalse(host.layer?.isOpaque ?? true)
  }

  @MainActor func testCollapsingTheNativeSlotKeepsOneUnscaledDrawingCanvas() throws {
    _ = NSApplication.shared
    let model = AppModel(persistsPreferences: false)
    let status = HeadlessStatusItem()
    let controller = MenuBarController(
      model: model, openExplorer: { _ in }, openSettings: {},
      statusItem: status, popover: HeadlessPanel(),
      eventMonitor: HeadlessMenuBarEvents(), activateApplication: {})
    defer {
      controller.stop()
      model.stop()
    }
    let button = try XCTUnwrap(status.button)
    let host = try XCTUnwrap(
      button.subviews.first { $0.identifier?.rawValue == "StrataBar.Indicator" })
    let compact = GlyphLayout.statusItemWidth(for: model.profile)
    let expanded = compact + GlyphMorphGeometry.extensionWidth
    button.setFrameSize(CGSize(width: expanded, height: 24))
    let canvas = host.bounds.size
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.34
      context.allowsImplicitAnimation = true
      button.setFrameSize(CGSize(width: compact, height: 24))
    }
    XCTAssertEqual(host.bounds.size, canvas)
    XCTAssertEqual(host.frame.maxX, button.bounds.maxX, accuracy: 0.01)
    XCTAssertEqual(canvas.width, expanded)
    XCTAssertTrue(button.clipsToBounds)
    XCTAssertNil(host.layer?.animation(forKey: "position"))
    XCTAssertNil(host.layer?.animation(forKey: "bounds"))
    XCTAssertNil(host.window)
  }

  @MainActor func testExpandedReadingControlsOpenTheirPageAndSwitchWithoutDismissing() {
    _ = NSApplication.shared
    let model = AppModel(persistsPreferences: false)
    let controller = MenuBarController(
      model: model, openExplorer: { _ in }, openSettings: {},
      statusItem: HeadlessStatusItem(), popover: HeadlessPanel(),
     
      eventMonitor: HeadlessMenuBarEvents(), activateApplication: {})
    defer {
      controller.stop()
      model.stop()
    }
    controller.selectReading(.battery)
    XCTAssertEqual(model.page, .battery)
    XCTAssertEqual(controller.presentationState, .engaged)
    controller.selectReading(.network)
    XCTAssertEqual(model.page, .network)
    XCTAssertEqual(controller.presentationState, .engaged)
    controller.selectReading(.network)
    XCTAssertEqual(controller.presentationState, .collapsed)
    controller.stop()
    controller.selectReading(.wifi)
    XCTAssertEqual(model.page, .network)
  }

  @MainActor func testStoppedIndicatorDetachesItsHostedViewAndDisablesItsRetainedButton() throws {
    _ = NSApplication.shared
    let model = AppModel(persistsPreferences: false)
    defer { model.stop() }
    let statusItem = HeadlessStatusItem()
    let events = HeadlessMenuBarEvents()
    let controller = MenuBarController(
      model: model, openExplorer: { _ in }, openSettings: {},
      statusItem: statusItem, popover: HeadlessPanel(),
      eventMonitor: events)
    let button = try XCTUnwrap(controller.indicatorButton)
    let host = try XCTUnwrap(
      button.subviews.first(where: {
        $0.identifier?.rawValue == "StrataBar.Indicator"
      }))
    controller.stop()
    XCTAssertNil(controller.indicatorButton)
    XCTAssertNil(host.superview)
    XCTAssertNil(host.window)
    XCTAssertNil(button.target)
    XCTAssertNil(button.action)
    XCTAssertTrue(statusItem.removed)
    XCTAssertTrue(events.activeMonitors.isEmpty)
  }

  @MainActor func testStoppingDetachesAutosaveBeforeNativeRemovalCanClearItsPosition() throws {
    _ = NSApplication.shared
    let suite = "IndicatorRemovalTests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let name = "indicator"
    let key = "NSStatusItem Preferred Position \(name)"
    defaults.set(209, forKey: key)
    let model = AppModel(persistsPreferences: false)
    defer { model.stop() }
    let status = HeadlessStatusItem()
    var queuedRemovals: [String] = []
    status.onRemove = { name in
      if let name { queuedRemovals.append("NSStatusItem Preferred Position \(name)") }
    }
    let controller = MenuBarController(
      model: model, openExplorer: { _ in }, openSettings: {},
      autosaveName: name, statusDefaults: defaults, statusItem: status,
      popover: HeadlessPanel(),
      eventMonitor: HeadlessMenuBarEvents(), activateApplication: {})
    controller.stop()
    for key in queuedRemovals { defaults.removeObject(forKey: key) }
    XCTAssertTrue(status.removed && queuedRemovals.isEmpty)
    XCTAssertNil(status.autosaveName)
    XCTAssertEqual(defaults.integer(forKey: key), 209)
  }

  @MainActor func testIndicatorButtonSupportsPressAndContextActions() throws {
    _ = NSApplication.shared
    let model = AppModel(persistsPreferences: false)
    var activations = 0
    var explorerRequests = 0
    var settingsRequests = 0
    let controller = MenuBarController(
      model: model, openExplorer: { _ in explorerRequests += 1 },
      openSettings: { settingsRequests += 1 },
      statusItem: HeadlessStatusItem(), popover: HeadlessPanel(),
      eventMonitor: HeadlessMenuBarEvents(), activateApplication: { activations += 1 })
    defer {
      controller.stop()
      model.stop()
    }
    let button = try XCTUnwrap(controller.indicatorButton)
    XCTAssertTrue(button.action != nil && button.target === controller)
    model.presentMoment(StatusMoment(symbol: "speaker.slash.fill", title: "Muted", priority: 1))
    waitFor { (button.accessibilityValue() as? String)?.contains("Muted") == true }
    model.page = .cpu
    button.performClick(nil)
    XCTAssertTrue(controller.presentationState == .engaged && activations == 1)
    XCTAssertEqual(model.page, .overview)
    XCTAssertTrue(controller.panel.canBecomeKey)
    let host = try XCTUnwrap(
      button.subviews.first { $0.identifier?.rawValue == "StrataBar.Indicator" })
    let event = try XCTUnwrap(
      NSEvent.mouseEvent(
        with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 0))
    let menu = try XCTUnwrap(host.menu(for: event))
    XCTAssertTrue(controller.presentationState == .collapsed && !controller.panel.isVisible)
    XCTAssertTrue(
      menu.items.map(\.title) == [
        "Open Explorer", "Settings…", "", "Quit Strata Monitor",
      ])
    menu.performActionForItem(at: 0)
    menu.performActionForItem(at: 1)
    XCTAssertTrue(explorerRequests == 1 && settingsRequests == 1)
    controller.stop()
    button.performClick(nil)
    pumpRunLoop(for: .milliseconds(50))
    XCTAssertTrue(!controller.panel.isVisible && activations == 1)
  }

  @MainActor func testHoverNeverActivatesAndImmediateDismissalCancelsUnfoldingWork() throws {
    _ = NSApplication.shared
    let model = AppModel(persistsPreferences: false)
    var activations = 0
    let controller = MenuBarController(
      model: model, openExplorer: { _ in }, openSettings: {},
      statusItem: HeadlessStatusItem(), popover: HeadlessPanel(),
      eventMonitor: HeadlessMenuBarEvents(), activateApplication: { activations += 1 })
    defer {
      controller.stop()
      model.stop()
    }
    let button = try XCTUnwrap(controller.indicatorButton)
    let host = try XCTUnwrap(
      button.subviews.first { $0.identifier?.rawValue == "StrataBar.Indicator" })
    let event = try XCTUnwrap(
      NSEvent.enterExitEvent(
        with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: 0, context: nil, eventNumber: 1, trackingNumber: 0, userData: nil))
    host.mouseEntered(with: event)
    waitFor { controller.presentationState == .unfolded }
    XCTAssertTrue(activations == 0 && !controller.panel.canBecomeKey)
    XCTAssertFalse(controller.panel.isVisible)
    model.page = .cpu
    model.preferences.hoverOpensPage = true
    waitFor { controller.presentationState == .peeking && controller.panel.isVisible }
    XCTAssertTrue(model.page == .overview && activations == 0)
    model.preferences.hoverOpensPage = false
    waitFor { controller.presentationState == .unfolded && !controller.panel.isVisible }
    XCTAssertTrue(activations == 0)
    NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
    waitFor { controller.presentationState == .collapsed }
    host.mouseEntered(with: event)
    controller.dismissImmediately()
    pumpRunLoop(for: .milliseconds(250))
    XCTAssertTrue(controller.presentationState == .collapsed && activations == 0)
    XCTAssertTrue(!controller.panel.isVisible)
  }
  // AppKit's native status-item ordering runs and stops nested CFRunLoops.
  // XCTest's Cocoa host owns that loop; a bare Swift async-main host can exit
  // early when AppKit stops it, leaving Swift Testing's run unfinished.
  @MainActor private func waitFor(_ condition: () -> Bool) {
    let clock = ContinuousClock()
    let deadline = ContinuousClock.now + .seconds(3)
    while !condition(), clock.now < deadline {
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
    }
    XCTAssertTrue(condition())
  }
  @MainActor private func pumpRunLoop(for duration: Duration) {
    let clock = ContinuousClock()
    let deadline = ContinuousClock.now + duration
    while clock.now < deadline { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01)) }
  }

}
