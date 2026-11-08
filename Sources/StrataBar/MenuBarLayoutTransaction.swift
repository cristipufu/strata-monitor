import AppKit
import QuartzCore

@MainActor enum MenuBarLayoutTransaction {
  static func perform(_ update: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    defer { CATransaction.commit() }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0
      context.allowsImplicitAnimation = false
      update()
    }
  }
}
