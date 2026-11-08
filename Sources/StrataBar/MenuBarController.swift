import AppKit
import Combine
import StrataCore
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
  private let model: AppModel
  private let statusDefaults: UserDefaults
  private var statusItem: (any MenuBarStatusItemHosting)?
  private weak var indicatorHost: TrackingHost<MenuBarView>?
  private let popover: any MenuBarPanelHosting
  private let eventMonitor: any MenuBarEventMonitoring
  private lazy var popoverPresentation = PanelPresentation(window: popover) {}
  private lazy var menuMotion = MenuBarMotion(
    applyWidth: { [weak self] width in
      guard let self, !self.stopped else { return }
      let scale = self.statusItem?.button?.window?.backingScaleFactor ?? 2
      let pixelAlignedWidth = (width * scale).rounded() / scale
      guard self.statusItem?.length != pixelAlignedWidth else { return }
      MenuBarLayoutTransaction.perform {
        self.indicatorHost?.reserveCanvasWidth(pixelAlignedWidth)
        self.statusItem?.length = pixelAlignedWidth
        self.statusItem?.button?.superview?.layoutSubtreeIfNeeded()
      }
      self.positionPopover(animated: false)
    },
    prepareAnimation: { [weak self] begin in
      self?.prepareIndicatorAnimation(begin)
    }, didFold: { [weak self] in self?.receive(.foldFinished) })
  private var nativePointerMonitor: Any?
  private let openExplorer: (ExplorerDestination) -> Void
  private let openSettings: () -> Void
  private let activateApplication: @MainActor () -> Void
  private var stopped = false
  private var lastAccessibilityValue: String?
  private var policy = PresentationPolicy()
  private var hoverTask: Task<Void, Never>?
  private var leaveTask: Task<Void, Never>?
  private var previewTask: Task<Void, Never>?
  private var subscriptions: Set<AnyCancellable> = []
  private var preparedIndicatorAnimation: (@MainActor () -> Void)?
  private var globalMonitor: Any?
  private var localMonitor: Any?
  private var menuBarItems: MenuBarItemsController { model.menuBarItems }
  private var preferredPanelHeight: CGFloat = 560

  init(
    model: AppModel, openExplorer: @escaping (ExplorerDestination) -> Void,
    openSettings: @escaping () -> Void,
    autosaveName: String? = nil,
    statusDefaults: UserDefaults = .standard,
    statusItem: any MenuBarStatusItemHosting = NativeMenuBarStatusItem(),
    popover: any MenuBarPanelHosting = FloatingPanel(),
    eventMonitor: any MenuBarEventMonitoring = NativeMenuBarEventMonitor(),
    activateApplication: @escaping @MainActor () -> Void = {
      NSApp.activate(ignoringOtherApps: true)
    }
  ) {
    self.model = model
    self.statusDefaults = statusDefaults
    self.openExplorer = openExplorer
    self.openSettings = openSettings
    self.activateApplication = activateApplication
    self.statusItem = statusItem
    self.popover = popover
    self.eventMonitor = eventMonitor
    super.init()
    if let autosaveName {
      let key = "NSStatusItem Preferred Position \(autosaveName)"
      if statusDefaults.object(forKey: key) == nil { statusDefaults.set(0, forKey: key) }
    }
    statusItem.autosaveName = autosaveName
    configureStatusItem()
    menuBarItems.attach(indicator: statusItem.button, autosaveName: autosaveName)
    configurePopover()
    observeChanges()
    installDismissalMonitors()
  }
  private func configureStatusItem() {
    guard let statusItem else { return }
    statusItem.isVisible = true
    guard let button = statusItem.button else { return }
    button.postsFrameChangedNotifications = true
    button.toolTip = String(localized: "Strata Monitor · Hover to unfold, click for readings")
    button.target = self
    button.action = #selector(indicatorPressed)
    let view = TrackingHost(
      rootView: MenuBarView(
        model: model, motion: menuMotion, open: { [weak self] in self?.indicatorPressed() },
        openReading: { [weak self] reading in self?.selectReading(reading) }),
      event: { [weak self] event in self?.receive(event) },
      contextMenu: { [weak self] in self?.makeStatusMenu() }, usesSwiftUIControls: true)
    view.identifier = NSUserInterfaceItemIdentifier("StrataBar.Indicator")
    view.setAccessibilityElement(false)
    view.sizingOptions = []
    view.frame = button.bounds
    // Keep one drawing canvas while the native slot clips and reveals its leading edge.
    view.reserveCanvasWidth(
      GlyphLayout.statusItemWidth(for: model.profile) + GlyphMorphGeometry.extensionWidth)
    view.autoresizingMask = [.minXMargin, .height]
    button.clipsToBounds = true
    button.addSubview(view)
    indicatorHost = view
    button.setAccessibilityLabel("Strata Monitor")
    button.setAccessibilityHelp(String(localized: "Press to open readings. Hover to unfold."))
    refreshAccessibilityValue()
  }
  @objc private func indicatorPressed() {
    if policy.state != .engaged { show(.overview) }
    receive(.click)
  }
  func selectReading(_ reading: Reading) {
    guard !stopped else { return }
    if policy.state == .engaged && model.page == reading {
      receive(.dismiss)
      return
    }
    show(reading)
    receive(.engage)
  }
  // A page chosen while the panel is hidden appears directly; it must not replay a page
  // transition underneath the panel's own entrance.
  private func show(_ page: Reading) {
    guard model.page != page else { return }
    guard !popover.isVisible else {
      model.page = page
      return
    }
    var transaction = Transaction(animation: nil)
    transaction.disablesAnimations = true
    withTransaction(transaction) { model.page = page }
  }

  @objc private func explorerPressed() { openExplorer(.resume) }
  @objc private func settingsPressed() { openSettings() }
  private func makeStatusMenu() -> NSMenu {
    dismissImmediately()
    let menu = NSMenu()
    let explorer = menu.addItem(
      withTitle: String(localized: "Open Explorer"), action: #selector(explorerPressed), keyEquivalent: "e")
    explorer.target = self
    let settings = menu.addItem(
      withTitle: String(localized: "Settings…"), action: #selector(settingsPressed), keyEquivalent: ",")
    settings.target = self
    menu.addItem(.separator())
    menu.addItem(
      withTitle: String(localized: "Quit Strata Monitor"), action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
    return menu
  }
  private func refreshAccessibilityValue() {
    let next = model.accessibilityStatus
    guard next != lastAccessibilityValue else { return }
    lastAccessibilityValue = next
    statusItem?.button?.setAccessibilityValue(next)
  }
  private func configurePopover() {
    let view = AnimatedPanelShell(presentation: popoverPresentation) {
      PopoverView(
        model: model, openExplorer: openExplorer, openSettings: openSettings,
        preferHeight: { [weak self] height in self?.preferPanelHeight(height) })
    }
    .onHover { [weak self] inside in self?.receive(inside ? .entered(.popover) : .exited(.popover))
    }
    popover.contentView = PanelHostingView(rootView: view)
    popover.onInteraction = { [weak self] in self?.engageWithoutToggle() }
    popover.onEscape = { [weak self] in self?.receive(.dismiss) }
  }
  private func preferPanelHeight(_ height: CGFloat) {
    guard height.isFinite, height > 0, abs(height - preferredPanelHeight) > 0.5 else { return }
    preferredPanelHeight = height
    // Content measured while the panel is still opening takes its size before it appears.
    positionPopover(animated: popoverPresentation.presented)
  }
  private func prepareIndicatorAnimation(_ begin: @escaping @MainActor () -> Void) {
    preparedIndicatorAnimation = begin
    startPreparedIndicatorAnimation()
  }

  private func startPreparedIndicatorAnimation() {
    guard !stopped, let begin = preparedIndicatorAnimation, let statusItem else { return }
    if let button = statusItem.button, button.window != nil,
      button.bounds.width + 0.5 < statusItem.length
    {
      return
    }
    preparedIndicatorAnimation = nil
    begin()
  }

  private func observeChanges() {
    if let button = statusItem?.button {
      NotificationCenter.default.publisher(for: NSView.frameDidChangeNotification, object: button)
        .sink { [weak self] _ in
          Task { @MainActor [weak self] in self?.startPreparedIndicatorAnimation() }
        }.store(in: &subscriptions)
    }
    menuBarItems.$menuInteraction.dropFirst().sink { [weak self] interaction in
      guard interaction == nil else { return }
      Task { @MainActor [weak self] in
        guard let self, !self.stopped, self.policy.occupied.isEmpty else { return }
        self.receive(.leaveElapsed)
      }
    }.store(in: &subscriptions)
    model.$preferences.sink { [weak self] preferences in
      Task { @MainActor in
        guard let self, !self.stopped else { return }
        let previousState = self.policy.state
        self.policy.hoverOpensPage = preferences.hoverOpensPage
        if self.policy.state == .peeking && previousState != .peeking {
          self.show(.overview)
        }
        self.synchronizePanelVisibility()
        self.model.setDemand("popover", active: self.shouldShowPanel)
      }
    }.store(in: &subscriptions)
    model.$moment.dropFirst().sink { [weak self] _ in
      Task { @MainActor in self?.synchronizePanelVisibility() }
    }.store(in: &subscriptions)
    menuMotion.$isExpanded.dropFirst().removeDuplicates().sink { [weak self] _ in
      Task { @MainActor in self?.synchronizeItemVisibility() }
    }.store(in: &subscriptions)
    model.objectWillChange.sink { [weak self] in
      Task { @MainActor in
        guard let self, !self.stopped else { return }
        self.refreshAccessibilityValue()
      }
    }.store(in: &subscriptions)
    for name in [
      NSApplication.didChangeScreenParametersNotification,
      NSApplication.didResignActiveNotification,
    ] {
      NotificationCenter.default.publisher(for: name).sink { [weak self] _ in
        Task { @MainActor in
          guard let self else { return }
          if name == NSApplication.didResignActiveNotification {
            // Clicking another app already started the animated dismissal.
            if self.menuBarItems.menuInteraction == nil { self.receive(.dismiss) }
          } else {
            self.dismissImmediately()
          }
        }
      }.store(in: &subscriptions)
    }
    NotificationCenter.default.publisher(for: NSWindow.didMoveNotification).sink {
      [weak self] note in
      guard let self, note.object as? NSWindow === self.statusItem?.button?.window else { return }
      self.positionPopover(animated: false)
    }.store(in: &subscriptions)
  }
  private func installDismissalMonitors() {
    globalMonitor = eventMonitor.global([.leftMouseDown, .rightMouseDown]) {
      [weak self] _ in
      Task { @MainActor in
        if self?.beginNativeMenuAtPointer() == true { return }
        self?.receive(.dismiss)
      }
    }
    localMonitor = eventMonitor.local([
      .leftMouseDown, .rightMouseDown, .keyDown, .mouseMoved,
    ]) { [weak self] event in
      guard let self else { return event }
      if event.type == .mouseMoved {
        self.trackNativePointer()
        return event
      }
      if event.type == .keyDown && event.keyCode == 53 {
        self.receive(.dismiss)
      } else if event.type != .keyDown && event.window !== self.popover
        && event.window !== self.statusItem?.button?.window
      {
        self.receive(.dismiss)
      }
      return event
    }
  }
  private func receive(_ event: PresentationEvent) {
    guard !stopped else { return }
    if case .leaveElapsed = event, menuBarItems.menuInteraction != nil { return }
    let oldState = policy.state
    let effects = policy.receive(event)
    for effect in effects {
      switch effect {
      case .cancelHover:
        hoverTask?.cancel()
        hoverTask = nil
      case .cancelLeave:
        leaveTask?.cancel()
        leaveTask = nil
      case .scheduleHover:
        hoverTask?.cancel()
        hoverTask = Task { [weak self] in
          do { try await Task.sleep(for: MotionPolicy.hoverDelay) } catch { return }
          self?.receive(.hoverElapsed)
        }
      case .scheduleLeave:
        leaveTask?.cancel()
        leaveTask = Task { [weak self] in
          do { try await Task.sleep(for: MotionPolicy.leaveDelay) } catch { return }
          self?.receive(.leaveElapsed)
        }
      }
    }
    if oldState != policy.state {
      if case .hoverElapsed = event, policy.state == .peeking { show(.overview) }
      updatePresentation()
    }
  }
  private func engageWithoutToggle() {
    guard policy.state != .engaged else { return }
    receive(.engage)
  }

  private var revealedItemsFrame: CGRect? {
    guard let button = statusItem?.button, let window = button.window,
      let screen = window.screen, let primary = NSScreen.screens.first
    else { return nil }
    let ring = window.convertToScreen(button.convert(button.bounds, to: nil))
    let leftEdge = screen.auxiliaryTopRightArea?.minX ?? screen.frame.minX
    return CGRect(
      x: leftEdge, y: primary.frame.maxY - ring.maxY - 3,
      width: max(0, ring.maxX - leftEdge), height: ring.height + 6)
  }

  private var menuBarBottom: CGFloat? {
    guard let window = statusItem?.button?.window, let primary = NSScreen.screens.first else {
      return nil
    }
    return primary.frame.maxY - window.frame.minY
  }

  private var pointerInMenuCoordinates: CGPoint {
    let point = NSEvent.mouseLocation
    return CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - point.y)
  }

  private func updateNativePointerMonitor(active: Bool) {
    if !active {
      if let nativePointerMonitor { eventMonitor.remove(nativePointerMonitor) }
      nativePointerMonitor = nil
      // Hidden items can no longer report the pointer leaving them.
      if policy.occupied.contains(.nativeItems) { receive(.exited(.nativeItems)) }
    } else if nativePointerMonitor == nil {
      nativePointerMonitor = eventMonitor.global(.mouseMoved) {
        [weak self] _ in
        Task { @MainActor in self?.trackNativePointer() }
      }
      // Items can appear under a pointer that has already stopped moving.
      trackNativePointer()
    }
  }

  private func trackNativePointer() {
    guard !stopped, nativePointerMonitor != nil else { return }
    let inside = revealedItemsFrame?.contains(pointerInMenuCoordinates) == true
    guard policy.occupied.contains(.nativeItems) != inside else { return }
    receive(inside ? .entered(.nativeItems) : .exited(.nativeItems))
  }

  private func beginNativeMenuAtPointer() -> Bool {
    let pointer = pointerInMenuCoordinates
    guard !stopped, nativePointerMonitor != nil, let barBottom = menuBarBottom,
      revealedItemsFrame?.contains(pointer) == true
    else { return false }
    menuBarItems.beginMenu(at: pointer.x, barBottom: barBottom)
    return true
  }
  private func updatePresentation() {
    positionPopover(animated: false)
    synchronizePanelVisibility()
    model.setDemand("popover", active: shouldShowPanel)
    popover.acceptsKeyboard = policy.state == .engaged
    if policy.state == .engaged {
      if !popover.isKeyWindow {
        activateApplication()
        popover.makeKey()
      }
    } else if popover.isKeyWindow {
      popover.resignKey()
    }
  }
  private var shouldShowPanel: Bool { policy.state == .peeking || policy.state == .engaged }
  private func synchronizePanelVisibility() {
    let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    let unfolded =
      policy.state == .unfolded || policy.state == .peeking || policy.state == .engaged
    menuMotion.present(
      expanded: unfolded, moment: model.moment,
      compactWidth: GlyphLayout.statusItemWidth(for: model.profile),
      availableWidth: availableMenuBarWidth, reducedMotion: reduced)
    synchronizeItemVisibility()
    popoverPresentation.setVisible(
      shouldShowPanel, style: model.profile.unfoldStyle, reducedMotion: reduced)
  }
  // Other menu-bar items appear only after the strip has fully unfolded, and disappear as
  // soon as it starts folding, so the ring always opens first and closes last.
  private func synchronizeItemVisibility() {
    let unfolded =
      policy.state == .unfolded || policy.state == .peeking || policy.state == .engaged
    let revealsItems = unfolded && menuMotion.isExpanded
    menuBarItems.setUnfolded(revealsItems)
    updateNativePointerMonitor(active: revealsItems)
  }
  private func positionPopover(animated: Bool) {
    guard let button = statusItem?.button, let window = button.window else { return }
    let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
    let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? anchor
    let size = NSSize(
      width: Design.panelWidth,
      height: min(preferredPanelHeight, screen.height - 20))
    let proposed = NSRect(
      x: anchor.midX - size.width / 2,
      y: anchor.minY - size.height - 7,
      width: size.width, height: size.height)
    guard let frame = ScreenPlacement.clamped(proposed, to: screen.insetBy(dx: 8, dy: 8)),
      popover.frame != frame
    else { return }
    if animated && popover.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    {
      popover.animateFrame(frame, duration: MotionPolicy.transition)
    } else {
      popover.setFrame(frame, display: true)
    }
  }
  private var availableMenuBarWidth: CGFloat {
    let compact = GlyphLayout.statusItemWidth(for: model.profile)
    guard let button = statusItem?.button, let window = button.window, let screen = window.screen
    else { return compact }
    let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
    let leftEdge = MenuBarSpacePolicy.leftEdge(
      screen: screen.frame, rightOfNotch: screen.auxiliaryTopRightArea)
    return max(compact, anchor.maxX - leftEdge - MenuBarSpacePolicy.edgeInset)
  }
  func dismiss() { receive(.dismiss) }
  func dismissImmediately() {
    guard !stopped else { return }
    preparedIndicatorAnimation = nil
    hoverTask?.cancel()
    hoverTask = nil
    leaveTask?.cancel()
    leaveTask = nil
    policy = PresentationPolicy()
    policy.hoverOpensPage = model.preferences.hoverOpensPage
    menuMotion.reset(compactWidth: GlyphLayout.statusItemWidth(for: model.profile))
    popoverPresentation.stop()
    menuBarItems.setUnfolded(false)
    updateNativePointerMonitor(active: false)
    popover.acceptsKeyboard = false
    model.setDemand("popover", active: false)
  }
  var indicatorButton: NSButton? { statusItem?.button }
  var presentationState: Presentation { policy.state }
  var panel: any MenuBarPanelHosting { popover }
  var panelWindow: NSWindow? { popover as? NSWindow }
  func preview(_ page: Reading) {
    show(page)
    previewTask?.cancel()
    previewTask = Task { [weak self] in
      // Status items are placed asynchronously by AppKit. Showing a preview
      // before that first placement anchors the panel to the desktop origin.
      let deadline = ContinuousClock.now + .seconds(2)
      while let self, !self.hasMenuBarPlacement, ContinuousClock.now < deadline {
        do { try await Task.sleep(for: .milliseconds(32)) } catch { return }
      }
      guard !Task.isCancelled, let self, !self.stopped else { return }
      self.receive(.engage)
      self.previewTask = nil
    }
  }
  // Holds the hovered state without a pointer, for measuring and inspecting the strip.
  func previewUnfoldedStrip() {
    previewTask?.cancel()
    previewTask = Task { [weak self] in
      let deadline = ContinuousClock.now + .seconds(2)
      while let self, !self.hasMenuBarPlacement, ContinuousClock.now < deadline {
        do { try await Task.sleep(for: .milliseconds(32)) } catch { return }
      }
      guard !Task.isCancelled, let self, !self.stopped else { return }
      self.receive(.entered(.indicator))
      self.previewTask = nil
    }
  }
  private var hasMenuBarPlacement: Bool {
    guard let window = statusItem?.button?.window, let screen = window.screen else { return false }
    return window.frame.minY >= screen.visibleFrame.maxY - 2
      && window.frame.intersects(screen.frame)
  }
  func stop() {
    guard !stopped else { return }
    dismissImmediately()
    stopped = true
    previewTask?.cancel()
    previewTask = nil
    hoverTask?.cancel()
    leaveTask?.cancel()
    subscriptions.removeAll()
    if let globalMonitor { eventMonitor.remove(globalMonitor) }
    if let localMonitor { eventMonitor.remove(localMonitor) }
    globalMonitor = nil
    localMonitor = nil
    menuMotion.reset(compactWidth: GlyphLayout.statusItemWidth(for: model.profile))
    popoverPresentation.stop()
    let names = [statusItem?.autosaveName].compactMap { $0 }
    StatusItemPositions.preserve(names, in: statusDefaults) {
      statusItem?.autosaveName = nil
      menuBarItems.stop()
      if let statusItem {
        statusItem.isVisible = false
        statusItem.button?.target = nil
        statusItem.button?.action = nil
        for view in statusItem.button?.subviews ?? []
        where view.identifier?.rawValue == "StrataBar.Indicator" {
          view.removeFromSuperview()
        }
        statusItem.remove()
      }
    }
    statusItem = nil
  }
}
