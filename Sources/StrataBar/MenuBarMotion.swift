import AppKit
import Combine
import StrataCore
import SwiftUI

@MainActor protocol MenuBarAnimating {
  func animate(
    reducedMotion: Bool, changes: () -> Void, completion: @escaping @MainActor () -> Void)
}

struct SwiftUIMenuBarAnimator: MenuBarAnimating {
  static let duration = 0.34
  func animate(
    reducedMotion: Bool, changes: () -> Void, completion: @escaping @MainActor () -> Void
  ) {
    withAnimation(
      reducedMotion ? nil : .interpolatingSpring(duration: Self.duration, bounce: 0),
      completionCriteria: .logicallyComplete, changes, completion: completion)
  }
}

@MainActor final class MenuBarMotion: ObservableObject {
  @Published private(set) var unfolding: Double = 0
  @Published private(set) var momentVisibility: Double = 0
  @Published private(set) var displayedMoment: StatusMoment?
  @Published private(set) var displayedMomentWidth: CGFloat = 36
  @Published private(set) var isExpanded = false
  private let animator: any MenuBarAnimating
  private let applyWidth: (CGFloat) -> Void
  private let prepareAnimation: (@escaping @MainActor () -> Void) -> Void
  private let didFold: () -> Void
  private let itemRevealDelay: Duration
  private var generation = UUID()
  private var reservedWidth: CGFloat = 36
  private var targetWidth: CGFloat = 36
  private var transitioning = false
  private var targetUnfolding: Double = 0
  private var targetMoment: Double = 0
  private var expansionRequested = false

  init(
    animator: any MenuBarAnimating = SwiftUIMenuBarAnimator(),
    applyWidth: @escaping (CGFloat) -> Void,
    prepareAnimation: @escaping (@escaping @MainActor () -> Void) -> Void = { $0() },
    itemRevealDelay: Duration = MotionPolicy.itemRevealDelay,
    didFold: @escaping () -> Void
  ) {
    self.animator = animator
    self.applyWidth = applyWidth
    self.prepareAnimation = prepareAnimation
    self.itemRevealDelay = itemRevealDelay
    self.didFold = didFold
  }

  func present(
    expanded: Bool, moment: StatusMoment?, compactWidth: CGFloat, availableWidth: CGFloat = 236,
    reducedMotion: Bool
  ) {
    let expandedWidth = compactWidth + GlyphMorphGeometry.extensionWidth
    let nextUnfolding = expanded && availableWidth >= expandedWidth ? 1.0 : 0
    let nextMoment = !expanded && moment != nil ? 1.0 : 0
    let desiredWidth =
      nextUnfolding > 0
      ? expandedWidth
      : nextMoment > 0 ? momentWidth(moment, compact: compactWidth) : compactWidth
    let nextWidth = max(compactWidth, min(desiredWidth, availableWidth))
    expansionRequested = expanded
    if !expanded && isExpanded { isExpanded = false }
    if let moment {
      let width = max(compactWidth, min(momentWidth(moment, compact: compactWidth), availableWidth))
      show(moment, width: width, reducedMotion: reducedMotion)
    }
    guard targetWidth != nextWidth || targetUnfolding != nextUnfolding || targetMoment != nextMoment
    else {
      if !transitioning { settle() }
      return
    }
    let id = UUID()
    generation = id
    targetWidth = nextWidth
    targetUnfolding = nextUnfolding
    targetMoment = nextMoment
    transitioning = true
    // Resizing NSStatusItem every frame makes macOS repeatedly rearrange every neighboring item.
    reserve(max(reservedWidth, nextWidth))
    prepareAnimation { [weak self] in
      guard let self, self.generation == id else { return }
      self.animator.animate(reducedMotion: reducedMotion) {
        self.unfolding = nextUnfolding
        self.momentVisibility = nextMoment
      } completion: { [weak self] in
        self?.complete(id)
      }
      if nextUnfolding == 1 && !reducedMotion { self.reportExpansionEarly(id) }
    }
  }

  // Other items follow the ring once it is mostly open instead of waiting for it to settle.
  private func reportExpansionEarly(_ id: UUID) {
    let delay = itemRevealDelay
    Task { [weak self] in
      do { try await Task.sleep(for: delay) } catch { return }
      guard let self, self.generation == id, self.expansionRequested, !self.isExpanded else {
        return
      }
      self.isExpanded = true
    }
  }

  // A visible moment crossfades into the next one instead of swapping in a single frame.
  private func show(_ moment: StatusMoment, width: CGFloat, reducedMotion: Bool) {
    guard displayedMoment != moment || displayedMomentWidth != width else { return }
    let replacesVisibleMoment = displayedMoment != nil && momentVisibility > 0 && !reducedMotion
    let update = {
      self.displayedMomentWidth = width
      self.displayedMoment = moment
    }
    if replacesVisibleMoment {
      withAnimation(.easeInOut(duration: MotionPolicy.readingChange), update)
    } else {
      update()
    }
  }

  func reset(compactWidth: CGFloat) {
    generation = UUID()
    transitioning = false
    expansionRequested = false
    isExpanded = false
    targetWidth = compactWidth
    targetUnfolding = 0
    targetMoment = 0
    var transaction = Transaction(animation: nil)
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      unfolding = 0
      momentVisibility = 0
      displayedMoment = nil
    }
    reserve(compactWidth)
  }

  private func momentWidth(_ moment: StatusMoment?, compact: CGFloat) -> CGFloat {
    guard let moment else { return compact }
    return max(compact, MomentLayout.width(for: moment))
  }

  private func reserve(_ width: CGFloat) {
    guard reservedWidth != width else { return }
    reservedWidth = width
    applyWidth(width)
  }

  private func complete(_ id: UUID) {
    guard generation == id else { return }
    transitioning = false
    reserve(targetWidth)
    if momentVisibility == 0 { displayedMoment = nil }
    settle()
  }

  // Unfolding settles once the strip is fully drawn; folding settles once the ring is back,
  // even while a moment is still showing.
  private func settle() {
    if expansionRequested {
      if !isExpanded { isExpanded = true }
    } else if unfolding == 0 {
      didFold()
    }
  }
}
