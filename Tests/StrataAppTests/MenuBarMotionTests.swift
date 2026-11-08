import Foundation
import Testing

@testable import StrataBar
@testable import StrataCore

@MainActor private final class ControlledMenuBarAnimator: MenuBarAnimating {
  var completions: [@MainActor () -> Void] = []
  var reducedMotion: [Bool] = []
  func animate(
    reducedMotion: Bool, changes: () -> Void, completion: @escaping @MainActor () -> Void
  ) {
    self.reducedMotion.append(reducedMotion)
    changes()
    completions.append(completion)
  }
}

@Test @MainActor func expansionReservesSpaceOnceAndCollapseReleasesItOnlyAfterTheMorph() {
  let animator = ControlledMenuBarAnimator()
  var widths: [CGFloat] = []
  var folds = 0
  let motion = MenuBarMotion(
    animator: animator, applyWidth: { widths.append($0) }, didFold: { folds += 1 })
  motion.present(expanded: true, moment: nil, compactWidth: 36, reducedMotion: false)
  #expect(widths == [72] && motion.unfolding == 1)
  animator.completions[0]()
  #expect(widths == [72])
  motion.present(expanded: false, moment: nil, compactWidth: 36, reducedMotion: false)
  #expect(widths == [72] && folds == 0)
  animator.completions[1]()
  #expect(widths == [72, 36] && folds == 1)
}

@Test @MainActor func reversingTheMorphCannotReleaseSpaceFromAnObsoleteCompletion() {
  let animator = ControlledMenuBarAnimator()
  var widths: [CGFloat] = []
  var folds = 0
  let motion = MenuBarMotion(
    animator: animator, applyWidth: { widths.append($0) }, didFold: { folds += 1 })
  motion.present(expanded: true, moment: nil, compactWidth: 36, reducedMotion: false)
  motion.present(expanded: false, moment: nil, compactWidth: 36, reducedMotion: false)
  motion.present(expanded: true, moment: nil, compactWidth: 36, reducedMotion: false)
  animator.completions[0]()
  animator.completions[1]()
  #expect(widths == [72] && folds == 0 && motion.unfolding == 1)
  animator.completions[2]()
  #expect(widths == [72] && folds == 0)
}

@Test @MainActor func repeatedHoverAndMetricUpdatesDoNotRestartTheMorph() {
  let animator = ControlledMenuBarAnimator()
  let motion = MenuBarMotion(animator: animator, applyWidth: { _ in }, didFold: {})
  for _ in 0..<20 {
    motion.present(expanded: true, moment: nil, compactWidth: 42, reducedMotion: false)
  }
  #expect(animator.completions.count == 1)
}

@Test @MainActor func resetInvalidatesPendingAnimationCompletions() {
  let animator = ControlledMenuBarAnimator()
  var widths: [CGFloat] = []
  var folds = 0
  let motion = MenuBarMotion(
    animator: animator, applyWidth: { widths.append($0) }, didFold: { folds += 1 })
  motion.present(expanded: true, moment: nil, compactWidth: 36, reducedMotion: false)
  motion.reset(compactWidth: 36)
  animator.completions[0]()
  #expect(widths == [72, 36] && folds == 0 && motion.unfolding == 0)
}

@Test @MainActor func notEnoughSpaceKeepsTheCompleteCompactGlyphInsteadOfAHalfOpenShape() {
  let animator = ControlledMenuBarAnimator()
  var widths: [CGFloat] = []
  let motion = MenuBarMotion(animator: animator, applyWidth: { widths.append($0) }, didFold: {})
  motion.present(
    expanded: true, moment: nil, compactWidth: 36, availableWidth: 40, reducedMotion: false)
  #expect(motion.unfolding == 0 && widths.isEmpty && animator.completions.isEmpty)
}

@Test @MainActor func momentsRetainTheirSpaceUntilTheyFinishAndYieldToUnfolding() {
  let animator = ControlledMenuBarAnimator()
  var widths: [CGFloat] = []
  let motion = MenuBarMotion(animator: animator, applyWidth: { widths.append($0) }, didFold: {})
  let moment = StatusMoment(symbol: "powerplug.fill", title: "Power connected", priority: 2)
  motion.present(expanded: false, moment: moment, compactWidth: 36, reducedMotion: false)
  let momentWidth = widths.last
  #expect(
    momentWidth ?? 0 > 100 && motion.displayedMoment == moment && motion.momentVisibility == 1)
  motion.present(expanded: true, moment: nil, compactWidth: 36, reducedMotion: false)
  #expect(widths.count == 1 && motion.displayedMoment == moment)
  animator.completions[0]()
  #expect(widths.count == 1)
  animator.completions[1]()
  #expect(widths.last == 72 && motion.displayedMoment == nil && motion.unfolding == 1)
}

@Test @MainActor func reducedMotionUsesTheSameLayoutWithoutAnAnimatedIntermediateState() {
  var width: CGFloat = 36
  let motion = MenuBarMotion(applyWidth: { width = $0 }, didFold: {})
  motion.present(expanded: true, moment: nil, compactWidth: 36, reducedMotion: true)
  #expect(width == 72 && motion.unfolding == 1)
  motion.present(expanded: false, moment: nil, compactWidth: 36, reducedMotion: true)
  #expect(width == 36 && motion.unfolding == 0)
}

@Test @MainActor func morphWaitsForTheNativeViewportAndCanceledPreparationsCannotStart() {
  let animator = ControlledMenuBarAnimator()
  var preparations: [@MainActor () -> Void] = []
  var width: CGFloat = 36
  let motion = MenuBarMotion(
    animator: animator, applyWidth: { width = $0 },
    prepareAnimation: { preparations.append($0) }, didFold: {})
  motion.present(expanded: true, moment: nil, compactWidth: 36, reducedMotion: false)
  #expect(width == 72 && motion.unfolding == 0 && animator.completions.isEmpty)
  motion.reset(compactWidth: 36)
  preparations[0]()
  #expect(width == 36 && motion.unfolding == 0 && animator.completions.isEmpty)
  motion.present(expanded: true, moment: nil, compactWidth: 36, reducedMotion: false)
  preparations[1]()
  #expect(width == 72 && motion.unfolding == 1 && animator.completions.count == 1)
}

@Test @MainActor func otherItemsWaitForTheUnfoldAndLeaveBeforeTheFold() {
  let animator = ControlledMenuBarAnimator()
  var folds = 0
  let motion = MenuBarMotion(animator: animator, applyWidth: { _ in }, didFold: { folds += 1 })
  motion.present(expanded: true, moment: nil, compactWidth: 36, reducedMotion: false)
  #expect(!motion.isExpanded)
  animator.completions[0]()
  #expect(motion.isExpanded)
  motion.present(expanded: true, moment: nil, compactWidth: 36, reducedMotion: false)
  #expect(motion.isExpanded)
  motion.present(expanded: false, moment: nil, compactWidth: 36, reducedMotion: false)
  #expect(!motion.isExpanded && folds == 0)
  animator.completions[1]()
  #expect(!motion.isExpanded && folds == 1)
}

@Test @MainActor func aReversedUnfoldNeverReportsTheStripAsOpen() {
  let animator = ControlledMenuBarAnimator()
  let motion = MenuBarMotion(animator: animator, applyWidth: { _ in }, didFold: {})
  motion.present(expanded: true, moment: nil, compactWidth: 36, reducedMotion: false)
  motion.present(expanded: false, moment: nil, compactWidth: 36, reducedMotion: false)
  animator.completions[0]()
  animator.completions[1]()
  #expect(!motion.isExpanded)
}

@Test @MainActor func withoutRoomToUnfoldItemsAppearAtOnce() {
  let animator = ControlledMenuBarAnimator()
  let motion = MenuBarMotion(animator: animator, applyWidth: { _ in }, didFold: {})
  motion.present(
    expanded: true, moment: nil, compactWidth: 36, availableWidth: 40, reducedMotion: false)
  #expect(motion.isExpanded && motion.unfolding == 0)
}

@Test func rateChartsRescaleOnlyAtRoundSteps() {
  #expect(Sparkline.roundedCeiling(1_000) == 1_000)
  #expect(Sparkline.roundedCeiling(1_001) == 2_000)
  #expect(Sparkline.roundedCeiling(2_500) == 5_000)
  #expect(Sparkline.roundedCeiling(7_000) == 10_000)
  #expect(Sparkline.roundedCeiling(0) == 1 && Sparkline.roundedCeiling(.nan) == 1)
}

@Test @MainActor func itemsAppearOnceTheRingIsMostlyOpen() async throws {
  let animator = ControlledMenuBarAnimator()
  let motion = MenuBarMotion(
    animator: animator, applyWidth: { _ in }, itemRevealDelay: .milliseconds(10), didFold: {})
  motion.present(expanded: true, moment: nil, compactWidth: 36, reducedMotion: false)
  #expect(!motion.isExpanded)
  try await waitUntil { motion.isExpanded }
  motion.present(expanded: false, moment: nil, compactWidth: 36, reducedMotion: false)
  #expect(!motion.isExpanded)
}

@Test @MainActor func leavingBeforeTheRingOpensNeverRevealsItems() async throws {
  let animator = ControlledMenuBarAnimator()
  let motion = MenuBarMotion(
    animator: animator, applyWidth: { _ in }, itemRevealDelay: .milliseconds(10), didFold: {})
  motion.present(expanded: true, moment: nil, compactWidth: 36, reducedMotion: false)
  motion.present(expanded: false, moment: nil, compactWidth: 36, reducedMotion: false)
  try await Task.sleep(for: .milliseconds(60))
  #expect(!motion.isExpanded)
}
