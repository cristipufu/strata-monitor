import AppKit
import Combine
import StrataCore
import SwiftUI

@MainActor
final class PanelPresentation: ObservableObject {
  @Published private(set) var presented = false
  // A hidden panel keeps no live content, so new readings never redraw what nobody sees.
  @Published private(set) var hostsContent = false
  @Published private(set) var style: UnfoldStyle = .morph
  private let window: any PanelOrdering
  private let didHide: () -> Void
  private var transitionTask: Task<Void, Never>?
  private var targetVisible = false
  init(window: any PanelOrdering, didHide: @escaping () -> Void) {
    self.window = window
    self.didHide = didHide
  }
  func setVisible(_ visible: Bool, style: UnfoldStyle, reducedMotion: Bool) {
    self.style = style
    guard visible != targetVisible else { return }
    targetVisible = visible
    transitionTask?.cancel()
    // A fading panel must not catch the click that follows a dismissal.
    window.ignoresMouseEvents = !visible
    if visible {
      hostsContent = true
      window.orderFrontRegardless()
      // The hidden hosting tree must receive a rendered starting state before
      // its first presentation. Existing transitions reverse from their current value.
      transitionTask = Task { @MainActor [weak self] in
        await Task.yield()
        guard !Task.isCancelled, let self, self.targetVisible else { return }
        self.presented = true
      }
    } else {
      presented = false
      let duration = reducedMotion ? MotionPolicy.reducedTransition : MotionPolicy.transition
      transitionTask = Task { @MainActor [weak self] in
        do { try await Task.sleep(for: .seconds(duration)) } catch { return }
        guard let self, !self.targetVisible else { return }
        self.window.orderOut(nil)
        self.hostsContent = false
        self.didHide()
      }
    }
  }
  func stop() {
    transitionTask?.cancel()
    transitionTask = nil
    targetVisible = false
    presented = false
    window.orderOut(nil)
    hostsContent = false
  }
}

struct AnimatedPanelShell<Content: View>: View {
  @ObservedObject var presentation: PanelPresentation
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ViewBuilder let content: Content
  var body: some View {
    let morphs = presentation.style == .morph && !reduceMotion
    ZStack { if presentation.hostsContent { content } }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .scaleEffect(
        x: presentation.presented || !morphs ? 1 : 0.72,
        y: presentation.presented || !morphs ? 1 : 0.8, anchor: .top
      )
      .opacity(presentation.presented ? 1 : 0)
      .animation(
        .easeInOut(
          duration: reduceMotion ? MotionPolicy.reducedTransition : MotionPolicy.transition),
        value: presentation.presented
      )
      .allowsHitTesting(presentation.presented)
      // Give the glass edge room to render outside the card without touching
      // the rectangular window's backing-store boundary.
      .padding(FloatingPanel.contentInset)
  }
}
