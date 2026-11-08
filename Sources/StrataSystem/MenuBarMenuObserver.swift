import CoreGraphics
import Foundation

public actor MenuBarMenuObserver {
  private let excludedProcess: pid_t

  public init(excludedProcess: pid_t = ProcessInfo.processInfo.processIdentifier) {
    self.excludedProcess = excludedProcess
  }

  public func hasMenu(at pointerX: CGFloat, below barBottom: CGFloat) -> Bool {
    guard
      let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], 0)
        as? [[String: Any]]
    else { return false }
    return MenuBarMenuWindows.containsMenu(
      in: windows.prefix(512), at: pointerX, below: barBottom, excluding: excludedProcess)
  }
}

enum MenuBarMenuWindows {
  // Status-item menus and popovers open from the bar's lower edge, across the clicked item.
  static let anchorTolerance: CGFloat = 24

  static func containsMenu(
    in windows: some Sequence<[String: Any]>, at pointerX: CGFloat, below barBottom: CGFloat,
    excluding excludedProcess: pid_t
  ) -> Bool {
    guard pointerX.isFinite, barBottom.isFinite else { return false }
    let minimumLayer = CGWindowLevelForKey(.mainMenuWindow)
    return windows.contains { window in
      guard let owner = window[kCGWindowOwnerPID as String] as? NSNumber,
        owner.int32Value != excludedProcess,
        let layer = window[kCGWindowLayer as String] as? NSNumber,
        layer.int32Value >= minimumLayer,
        let bounds = window[kCGWindowBounds as String] as? [String: Any],
        let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary), !frame.isEmpty,
        frame.minX.isFinite, frame.minY.isFinite, frame.width.isFinite, frame.height.isFinite
      else { return false }
      return frame.minY >= barBottom - 2 && frame.minY <= barBottom + anchorTolerance
        && frame.minX <= pointerX && pointerX <= frame.maxX
    }
  }
}
