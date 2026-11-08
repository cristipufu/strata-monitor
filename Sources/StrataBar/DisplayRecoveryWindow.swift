import AppKit
import Combine
import StrataCore
import SwiftUI

@MainActor protocol DisplayRecoveryHosting: AnyObject {
  var isVisible: Bool { get }
  var title: String { get set }
  func show()
  func hide()
  func placeOnVisibleDisplay()
  func stop()
}

@MainActor final class DisplayRecoveryWindow: NSObject {
  private let controller: DisplayController
  private let activateApplication: @MainActor () -> Void
  private var window: (any DisplayRecoveryHosting)?
  private let makeWindow:
    @MainActor (DisplayController, @escaping @MainActor () -> Bool) -> any DisplayRecoveryHosting
  private var subscription: AnyCancellable?
  private var screenObserver: NSObjectProtocol?
  init(
    controller: DisplayController,
    makeWindow:
      @escaping @MainActor (DisplayController, @escaping @MainActor () -> Bool) ->
      any DisplayRecoveryHosting = {
        NativeDisplayRecoveryPanel(controller: $0, shouldClose: $1)
      },
    activateApplication: @escaping @MainActor () -> Void = {
      NSApp.activate(ignoringOtherApps: true)
    }
  ) {
    self.controller = controller
    self.activateApplication = activateApplication
    self.makeWindow = makeWindow
    super.init()
    subscription = controller.$trial.combineLatest(controller.$recoveryIssue)
      .receive(on: RunLoop.main).sink { [weak self] _ in self?.updateVisibility() }
    screenObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { [weak self] _ in MainActor.assumeIsolated { self?.placeOnVisibleDisplay() } }
  }
  var visibleWindow: (any DisplayRecoveryHosting)? { window?.isVisible == true ? window : nil }
  private func updateVisibility() {
    guard controller.trial != nil || controller.recoveryIssue != nil else {
      window?.hide()
      return
    }
    if window == nil {
      window = makeWindow(controller) { [weak self] in self?.shouldClose() ?? true }
    }
    window?.title = controller.trial == nil ? String(localized: "Review Displays") : String(localized: "Keep Display Settings")
    guard window?.isVisible != true else { return }
    placeOnVisibleDisplay()
    window?.show()
    activateApplication()
  }
  private func placeOnVisibleDisplay() {
    window?.placeOnVisibleDisplay()
  }
  private func shouldClose() -> Bool {
    if controller.trial != nil {
      controller.revert()
      return false
    }
    controller.dismissRecoveryIssue()
    return true
  }
  func stop() {
    subscription?.cancel()
    subscription = nil
    if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    screenObserver = nil
    window?.stop()
    window = nil
  }
  isolated deinit {
    if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    window?.stop()
  }
}

@MainActor
final class NativeDisplayRecoveryPanel: NSObject, DisplayRecoveryHosting, NSWindowDelegate {
  private let panel: NSPanel
  private let shouldClose: @MainActor () -> Bool
  init(controller: DisplayController, shouldClose: @escaping @MainActor () -> Bool) {
    self.shouldClose = shouldClose
    panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 420, height: 350),
      styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
    super.init()
    panel.titlebarAppearsTransparent = true
    panel.isReleasedWhenClosed = false
    panel.hidesOnDeactivate = false
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    let hosting = NSHostingController(rootView: DisplayRecoveryView(controller: controller))
    // The panel grows with its wrapped text instead of clipping a longer translation.
    hosting.sizingOptions = [.preferredContentSize]
    panel.contentViewController = hosting
    panel.delegate = self
    panel.center()
  }
  var isVisible: Bool { panel.isVisible }
  var title: String {
    get { panel.title }
    set { panel.title = newValue }
  }
  func show() { panel.makeKeyAndOrderFront(nil) }
  func hide() { panel.orderOut(nil) }
  func placeOnVisibleDisplay() {
    guard let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first,
      let frame = ScreenPlacement.clamped(panel.frame, to: screen.visibleFrame)
    else { return }
    panel.setFrame(frame, display: panel.isVisible)
  }
  func windowShouldClose(_ sender: NSWindow) -> Bool { shouldClose() }
  func stop() {
    panel.orderOut(nil)
    panel.delegate = nil
  }
}

private struct DisplayRecoveryView: View {
  @ObservedObject var controller: DisplayController
  var body: some View {
    VStack(spacing: Design.Spacing.large) {
      Image(systemName: "display.trianglebadge.exclamationmark")
        .font(Design.Typography.stateSymbol).foregroundStyle(Design.mint)
      Group {
        if controller.trial == nil {
          Text("Review your displays")
        } else {
          Text("Keep these display settings?")
        }
      }
      .font(Design.Typography.pageTitle)
      .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
      if let issue = controller.recoveryIssue {
        ScrollView {
          Text(issue).font(Design.Typography.body).foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }.frame(maxHeight: 110)
      } else if let trial = controller.trial {
        TimelineView(.periodic(from: .now, by: 1)) { context in
          let remaining = max(0, Int(ceil(trial.expiresAt.timeIntervalSince(context.date))))
          Text("Reverting in \(Duration.seconds(remaining).formatted(.units(width: .wide)))")
            .font(Design.Typography.body).monospacedDigit().foregroundStyle(.secondary)
        }
      }
      HStack(spacing: Design.Spacing.medium) {
        if controller.trial != nil {
          Button("Revert", action: controller.revert).buttonStyle(.glass).keyboardShortcut(
            .cancelAction
          )
          .disabled(controller.isBusy)
          Button("Keep", action: controller.keep).buttonStyle(.glassProminent).tint(Design.mint)
            .disabled(
              controller.isBusy || controller.trial?.canKeep != true
                || controller.recoveryIssue != nil)
        } else {
          Button("Displays Settings") { SystemSettings.open(.display) }.buttonStyle(.glass)
          Button("Done", action: controller.dismissRecoveryIssue).buttonStyle(.glassProminent)
        }
      }.controlSize(.large)
      if controller.isBusy { ProgressView().controlSize(.small) }
    }
    .padding(Design.Spacing.xLarge).frame(width: 420)
  }
}
