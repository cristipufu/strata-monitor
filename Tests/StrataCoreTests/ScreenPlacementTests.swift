import CoreGraphics
import Foundation
import StrataCore
import Testing

@Test func placementUsesTheActualDisplayOrigin() throws {
  let screen = CGRect(x: -1512, y: 75, width: 1512, height: 874)
  let outside = CGRect(x: -100, y: 900, width: 390, height: 530)
  let fitted = try #require(ScreenPlacement.clamped(outside, to: screen))
  #expect(fitted.maxX == screen.maxX)
  #expect(fitted.maxY == screen.maxY)
  #expect(fitted.size == outside.size)
}

@Test func invalidGeometryIsRejectedAndOversizedWindowsStartOnScreen() throws {
  let screen = CGRect(x: 100, y: 50, width: 800, height: 600)
  #expect(ScreenPlacement.clamped(.zero, to: screen) == nil)
  #expect(
    ScreenPlacement.clamped(CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 200), to: screen)
      == nil)
  let fitted = try #require(
    ScreenPlacement.clamped(CGRect(x: 700, y: 300, width: 1000, height: 700), to: screen))
  #expect(fitted.origin == screen.origin)
}
