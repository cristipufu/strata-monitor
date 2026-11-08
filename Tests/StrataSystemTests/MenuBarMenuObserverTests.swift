import CoreGraphics
import Foundation
import Testing

@testable import StrataSystem

private let strataProcess: pid_t = 100
private let barBottom: CGFloat = 33

private func window(pid: pid_t = 200, layer: Int32 = 101, frame: CGRect) -> [String: Any] {
  [
    kCGWindowOwnerPID as String: NSNumber(value: pid),
    kCGWindowLayer as String: NSNumber(value: layer),
    kCGWindowBounds as String: frame.dictionaryRepresentation as NSDictionary,
  ]
}

private func hasMenu(_ windows: [[String: Any]], at pointerX: CGFloat = 610) -> Bool {
  MenuBarMenuWindows.containsMenu(
    in: windows, at: pointerX, below: barBottom, excluding: strataProcess)
}

@Test func aMenuOpeningFromTheBarAcrossTheClickedItemCounts() {
  #expect(hasMenu([window(frame: CGRect(x: 600, y: 33, width: 220, height: 300))]))
  #expect(hasMenu([window(layer: 25, frame: CGRect(x: 560, y: 40, width: 320, height: 400))]))
}

@Test func barItemsOrdinaryWindowsAndStrataPanelsAreNotMenus() {
  #expect(!hasMenu([window(layer: 25, frame: CGRect(x: 590, y: 0, width: 40, height: 33))]))
  #expect(!hasMenu([window(layer: 0, frame: CGRect(x: 0, y: 33, width: 1200, height: 800))]))
  #expect(
    !hasMenu([window(pid: strataProcess, frame: CGRect(x: 600, y: 33, width: 220, height: 300))]))
}

@Test func windowsAwayFromTheClickOrTheBarAreNotItsMenu() {
  #expect(!hasMenu([window(frame: CGRect(x: 800, y: 33, width: 220, height: 300))]))
  #expect(!hasMenu([window(frame: CGRect(x: 600, y: 200, width: 220, height: 300))]))
  #expect(!hasMenu([window(frame: CGRect(x: 600, y: 33, width: 220, height: 300))], at: .nan))
  #expect(!hasMenu([[kCGWindowOwnerPID as String: NSNumber(value: 200)]]))
}
