import Foundation

public enum Surface: Hashable, Sendable { case indicator, nativeItems, popover }
public enum Presentation: Equatable, Sendable {
  case collapsed, unfolded, peeking, engaged, folding
}
public enum PresentationEvent: Sendable {
  case entered(Surface)
  case exited(Surface)
  case hoverElapsed, leaveElapsed, foldFinished, click, dismiss, engage
}
public enum PresentationEffect: Equatable, Sendable {
  case scheduleHover, cancelHover, scheduleLeave, cancelLeave
}

public struct PresentationPolicy: Sendable {
  public private(set) var state: Presentation = .collapsed
  public private(set) var occupied: Set<Surface> = []
  public var hoverOpensPage = false {
    didSet {
      if state == .peeking || state == .unfolded {
        state = hoverOpensPage ? .peeking : .unfolded
      }
    }
  }
  private var suppressHoverUntilExit = false
  public init() {}

  @discardableResult
  public mutating func receive(_ event: PresentationEvent) -> [PresentationEffect] {
    switch event {
    case .entered(let surface):
      occupied.insert(surface)
      if state == .folding {
        state = hoverOpensPage ? .peeking : .unfolded
        return [.cancelLeave]
      }
      if state == .collapsed && !suppressHoverUntilExit { return [.cancelLeave, .scheduleHover] }
      return [.cancelLeave]
    case .exited(let surface):
      occupied.remove(surface)
      if occupied.isEmpty {
        suppressHoverUntilExit = false
        return state == .engaged ? [.cancelHover] : [.cancelHover, .scheduleLeave]
      }
      return []
    case .hoverElapsed:
      if !occupied.isEmpty && state == .collapsed && !suppressHoverUntilExit {
        state = hoverOpensPage ? .peeking : .unfolded
      }
      return []
    case .leaveElapsed:
      if occupied.isEmpty && (state == .unfolded || state == .peeking) { state = .folding }
      return []
    case .foldFinished:
      if state == .folding { state = .collapsed }
      return []
    case .click:
      if state == .engaged { return dismiss() }
      state = .engaged
      return [.cancelHover, .cancelLeave]
    case .engage:
      state = .engaged
      return [.cancelHover, .cancelLeave]
    case .dismiss:
      return dismiss()
    }
  }
  private mutating func dismiss() -> [PresentationEffect] {
    state = .collapsed
    suppressHoverUntilExit = !occupied.isEmpty
    return [.cancelHover, .cancelLeave]
  }
}

public enum MotionPolicy {
  public static let hoverDelay: Duration = .milliseconds(60)
  public static let leaveDelay: Duration = .milliseconds(400)
  public static let itemRevealDelay: Duration = .milliseconds(150)
  public static let transition = 0.24
  public static let reducedTransition = 0.1
  public static let launchDraw = 0.6
  public static let ringFill = 0.5
  public static let barFill = 0.3
  public static let readingChange = 0.2
  public static let momentDuration: Duration = .milliseconds(3000)
}
