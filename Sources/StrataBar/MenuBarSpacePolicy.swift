import Foundation

enum MenuBarSpacePolicy {
  static let edgeInset: CGFloat = 8
  static func leftEdge(screen: CGRect, rightOfNotch: CGRect?) -> CGFloat {
    rightOfNotch?.minX ?? screen.minX + screen.width * 0.45
  }
}
