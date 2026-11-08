import AppKit
import SwiftUI
import XCTest

@testable import StrataBar

final class PanelHostingViewTests: CocoaTestCase {
  @MainActor func testPanelBackingClipsEveryCornerAfterResizing() throws {
    _ = NSApplication.shared
    let host = PanelHostingView(rootView: Color.black)
    for height in [200, 400] {
      host.frame = CGRect(x: 0, y: 0, width: Design.panelWidth, height: CGFloat(height))
      host.layoutSubtreeIfNeeded()
      host.displayIfNeeded()
      let image = try render(host)
      let lastColumn = image.pixelsWide - 1
      let lastRow = image.pixelsHigh - 1
      for point in [(0, 0), (lastColumn, 0), (0, lastRow), (lastColumn, lastRow)] {
        XCTAssertEqual(image.colorAt(x: point.0, y: point.1)?.alphaComponent, 0)
      }
      XCTAssertEqual(image.colorAt(x: lastColumn / 2, y: lastRow / 2)?.alphaComponent, 1)
      XCTAssertEqual(image.colorAt(x: 0, y: lastRow / 2)?.alphaComponent, 1)
      XCTAssertNil(host.window)
    }
  }

  @MainActor private func render(_ host: NSView) throws -> NSBitmapImageRep {
    let width = Int(host.bounds.width)
    let context = try XCTUnwrap(
      CGContext(
        data: nil, width: width, height: Int(host.bounds.height), bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    try XCTUnwrap(host.layer).render(in: context)
    return NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
  }
}
