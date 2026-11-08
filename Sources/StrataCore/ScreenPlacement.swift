import CoreGraphics
import Foundation

public enum ScreenPlacement {
  /// Preserve the requested size, while keeping its origin within this display.
  /// An oversized window still starts on screen; its layout owns adaptation.
  public static func clamped(_ frame: CGRect, to bounds: CGRect) -> CGRect? {
    let components = [
      frame.minX, frame.minY, frame.width, frame.height,
      bounds.minX, bounds.minY, bounds.width, bounds.height,
    ]
    guard components.allSatisfy(\.isFinite), frame.width > 0, frame.height > 0,
      bounds.width > 0, bounds.height > 0
    else { return nil }
    let x = min(max(frame.minX, bounds.minX), max(bounds.minX, bounds.maxX - frame.width))
    let y = min(max(frame.minY, bounds.minY), max(bounds.minY, bounds.maxY - frame.height))
    return CGRect(origin: CGPoint(x: x, y: y), size: frame.size)
  }
}
