import AppKit
import Combine
import StrataCore
import StrataSystem
import SwiftUI

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  private let model: AppModel
  private let preview: PreviewConfiguration
  private var menuBar: MenuBarController?
  private var explorerWindow: NSWindow?
  private var settingsWindow: NSWindow?
  private var welcomeWindow: NSWindow?
  private let navigation = ExplorerNavigation()
  private let snapshotExporter = SnapshotExportController()
  private var lifecycle: WorkspaceLifecycleMonitor?
  private var subscriptions: Set<AnyCancellable> = []
  private var errorPresenter: OperationErrorPresenter?
  private var displayRecovery: DisplayRecoveryWindow?
  private var demoBackdrop: DemoBackdrop?
  private var terminationTask: Task<Void, Never>?
  private var isTerminationApproved = false
  private lazy var processMenu = ProcessMenu(model: model, navigation: navigation) {
    [weak self] in
    guard let explorer = self?.explorerWindow else { return false }
    return NSApp.keyWindow === explorer
  }

  override init() {
    let configuration = PreviewConfiguration(arguments: CommandLine.arguments)
    preview = configuration
    if !configuration.isEnabled,
      Bundle.main.bundleIdentifier == ApplicationPreferences.bundleIdentifier,
      let legacy = UserDefaults(suiteName: ApplicationPreferences.legacyBundleIdentifier)
    {
      ApplicationPreferences.migrate(from: legacy, to: .standard)
    }
    model =
      configuration.usesDemoData
      ? Self.demoModel()
      : AppModel(
        deviceEvents: DeviceEventSource(workspaceCenter: NSWorkspace.shared.notificationCenter),
        historyRecorder: configuration.isEnabled
          ? nil : HistoryRecorder(directory: HistoryRecorder.defaultDirectory),
        persistsPreferences: !configuration.isEnabled)
    super.init()
    if let appearance = configuration.appearance { model.preferences.appearance = appearance }
  }

  // Readings, devices and history come from DemoData; history is kept in a temporary folder.
  private static func demoModel() -> AppModel {
    ProcessIconCache.shared = ProcessIconCache { pid in
      DemoData.applicationPaths[pid].map { NSWorkspace.shared.icon(forFile: $0) }
    }
    return AppModel(
      collector: DemoSystemSampler(), powerCollector: DemoPower(),
      networkUsageCollector: DemoNetworkUsage(), deviceCollector: DemoDevices(),
      historyRecorder: HistoryRecorder(
        directory: FileManager.default.temporaryDirectory.appending(
          path: "StrataMonitorDemo-\(UUID().uuidString)")),
      persistsPreferences: false)
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    observeAppearance()
    installMenu()
    // A previous run that ended without quitting cannot have resumed what it paused.
    Task { await model.processActions.resumePausedProcesses() }
    if !preview.isEnabled { observeFullVisibility() }
    displayRecovery = DisplayRecoveryWindow(controller: model.displays)
    model.start()
    if preview.usesDemoData {
      demoBackdrop = NSScreen.main.map(DemoBackdrop.init)
      model.prefillRecentHistory(DemoData.recentReadings())
      model.historyRecorder?.seed(DemoData.history())
    }
    if preview.surface != .explorer {
      menuBar = MenuBarController(
        model: model, openExplorer: { [weak self] destination in self?.showExplorer(destination) },
        openSettings: { [weak self] in self?.showSettings() },
        autosaveName: preview.isEnabled ? nil : ApplicationPreferences.statusItemName)
    }
    observeLifecycle()
    if case .reading(let reading) = preview.surface {
      menuBar?.preview(reading)
    } else if preview.surface == .unfoldedStrip {
      menuBar?.previewUnfoldedStrip()
    } else if preview.surface == .explorer {
      showExplorer(preview.processGrouping == .families ? .family(nil) : .processes(nil))
      if preview.selectsOwnProcess {
        model.$sample.compactMap { sample in
          sample?.processes.first { $0.id.pid == ProcessInfo.processInfo.processIdentifier }
        }
        .first().sink { [weak self] process in
          guard let self else { return }
          self.navigation.open(
            self.preview.processGrouping == .families ? .family(process.id) : .processes(process.id)
          )
        }
        .store(in: &subscriptions)
      }
    } else if !model.preferences.hasCompletedWelcome {
      showWelcome()
    }
  }
  // Approval happens in System Settings, so the helper's state is read again on return.
  private func observeFullVisibility() {
    model.fullVisibility.refresh()
    NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
      .sink { [weak self] _ in self?.model.fullVisibility.refresh() }
      .store(in: &subscriptions)
  }
  private func observeAppearance() {
    model.$preferences.map(\.appearance).removeDuplicates().sink { appearance in
      let name: NSAppearance.Name? =
        switch appearance {
        case .system: nil
        case .light: .aqua
        case .dark: .darkAqua
        }
      NSApp.appearance = name.flatMap(NSAppearance.init(named:))
    }.store(in: &subscriptions)
  }
  private func installMenu() {
    let menu = NSMenu()
    menu.addItem(submenu: applicationMenu())
    menu.addItem(submenu: editMenu())
    menu.addItem(submenu: processMenu.makeMenu())
    let windows = windowMenu()
    menu.addItem(submenu: windows)
    NSApp.mainMenu = menu
    NSApp.windowsMenu = windows
  }
  private func applicationMenu() -> NSMenu {
    let menu = NSMenu(title: "Strata Monitor")
    menu.addItem(
      withTitle: "About Strata Monitor",
      action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
    menu.addItem(.separator())
    menu.addItem(withTitle: "Settings…", action: #selector(settingsAction), keyEquivalent: ",")
      .target = self
    menu.addItem(withTitle: "Open Explorer", action: #selector(explorerAction), keyEquivalent: "e")
      .target = self
    menu.addItem(.separator())
    menu.addItem(withTitle: "Hide Strata Monitor", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Quit Strata Monitor", action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
    return menu
  }
  private func editMenu() -> NSMenu {
    let menu = NSMenu(title: "Edit")
    menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
    menu.addItem(.separator())
    menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    menu.addItem(
      withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    return menu
  }
  private func windowMenu() -> NSMenu {
    let menu = NSMenu(title: "Window")
    menu.addItem(
      withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
    menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    return menu
  }
  @objc private func settingsAction() { showSettings() }
  @objc private func explorerAction() { showExplorer(.resume) }
  private func showExplorer(_ destination: ExplorerDestination) {
    menuBar?.dismiss()
    navigation.open(destination)
    if explorerWindow == nil {
      let content = ExplorerView(model: model, navigation: navigation, exporter: snapshotExporter)
      explorerWindow = makeWindow(
        .workspace, title: "Strata Monitor", size: NSSize(width: 1120, height: 740),
        minimum: NSSize(width: 1000, height: 600), content: content)
      if !preview.isEnabled { explorerWindow?.setFrameAutosaveName("StrataBar.Explorer") }
      if let window = explorerWindow, window.contentLayoutRect.width < 1000 {
        window.setContentSize(NSSize(width: 1120, height: 740))
      }
    }
    model.setDemand("explorer", active: true)
    present(explorerWindow)
  }
  private func showSettings() {
    menuBar?.dismiss()
    if settingsWindow == nil {
      settingsWindow = makeWindow(
        .workspace, title: "Settings", size: NSSize(width: 720, height: 620),
        minimum: NSSize(width: 720, height: 620),
        content: SettingsView(model: model) { [weak self] in self?.showWelcome() })
      if !preview.isEnabled { settingsWindow?.setFrameAutosaveName("StrataBar.Settings") }
    }
    present(settingsWindow)
  }
  private func showWelcome() {
    if welcomeWindow == nil {
      welcomeWindow = makeWindow(
        .onboarding, title: "Welcome to Strata Monitor", size: NSSize(width: 560, height: 520),
        minimum: NSSize(width: 560, height: 520),
        content: WelcomeView(model: model) { [weak self] in
          self?.model.preferences.hasCompletedWelcome = true
          self?.welcomeWindow?.close()
        })
    }
    present(welcomeWindow)
  }
  private func present(_ window: NSWindow?) {
    window?.makeKeyAndOrderFront(nil)
    updateActivationPolicy()
    NSApp.activate(ignoringOtherApps: true)
  }
  // Strata Monitor keeps a Dock icon and a Command-Tab entry only while one of its windows is open.
  private func updateActivationPolicy(closing: NSWindow? = nil) {
    let hasWindow = [explorerWindow, settingsWindow, welcomeWindow].contains {
      $0 != nil && $0 !== closing && $0?.isVisible == true
    }
    NSApp.setActivationPolicy(hasWindow ? .regular : .accessory)
  }
  private enum WindowRole { case workspace, onboarding }
  private func makeWindow<Content: View>(
    _ role: WindowRole, title: String, size: NSSize, minimum: NSSize, content: Content
  ) -> NSWindow {
    let style: NSWindow.StyleMask =
      switch role {
      case .workspace: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
      case .onboarding: [.titled, .closable, .fullSizeContentView]
      }
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered,
      defer: false)
    window.title = title
    window.titlebarAppearsTransparent = true
    // Onboarding shows its own heading; the title still names the window for VoiceOver.
    if role == .onboarding { window.titleVisibility = .hidden }
    window.delegate = self
    let hosting = NSHostingController(rootView: content)
    // AppKit owns window geometry; intrinsic SwiftUI constraints must not
    // silently shrink a restored window and center oversized content in it.
    hosting.sizingOptions = [.minSize]
    window.isReleasedWhenClosed = false
    window.contentViewController = hosting
    window.contentMinSize = minimum
    window.setContentSize(size)
    window.center()
    return window
  }
  private func observeLifecycle() {
    // The readings panel and Explorer show errors inline; only windows without a banner use an alert.
    errorPresenter = OperationErrorPresenter(model: model) { [weak self] in
      guard let self, NSApp.isActive, let key = NSApp.keyWindow else { return nil }
      return [self.settingsWindow, self.welcomeWindow].contains(where: { $0 === key }) ? key : nil
    }
    lifecycle = WorkspaceLifecycleMonitor(
      suspend: { [weak self] in
        self?.menuBar?.dismissImmediately()
        self?.snapshotExporter.stop()
        self?.model.stop()
      }, resume: { [weak self] in self?.model.resume() })
  }
  func windowWillClose(_ notification: Notification) {
    guard let closing = notification.object as? NSWindow else { return }
    if closing === explorerWindow {
      snapshotExporter.stop()
      model.endExplorerSession()
    }
    updateActivationPolicy(closing: closing)
    // A closed window's SwiftUI content would otherwise keep rebuilding with every reading.
    Task { @MainActor [weak self] in self?.release(closing) }
  }
  private func release(_ window: NSWindow) {
    guard !window.isVisible else { return }
    if window === explorerWindow { explorerWindow = nil }
    if window === settingsWindow { settingsWindow = nil }
    if window === welcomeWindow { welcomeWindow = nil }
  }
  func windowDidResize(_ notification: Notification) {
    guard let window = notification.object as? NSWindow,
      !window.inLiveResize, let screen = window.screen,
      let frame = ScreenPlacement.clamped(window.frame, to: screen.visibleFrame),
      frame.origin != window.frame.origin
    else { return }
    window.setFrameOrigin(frame.origin)
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if isTerminationApproved { return .terminateNow }
    guard terminationTask == nil else { return .terminateLater }
    terminationTask = Task { [self] in
      await model.processActions.resumePausedProcesses()
      let recovered = await model.displays.prepareForTermination()
      isTerminationApproved = recovered
      terminationTask = nil
      sender.reply(toApplicationShouldTerminate: recovered)
    }
    return .terminateLater
  }
  func applicationWillTerminate(_ notification: Notification) {
    lifecycle?.stop()
    lifecycle = nil
    snapshotExporter.stop()
    model.fullVisibility.stop()
    model.stop()
    model.historyRecorder?.stop()
    errorPresenter?.stop()
    errorPresenter = nil
    menuBar?.stop()
    displayRecovery?.stop()
    displayRecovery = nil
    subscriptions.removeAll()
  }

}

struct WelcomeView: View {
  @ObservedObject var model: AppModel
  let finish: () -> Void
  var body: some View {
    VStack(spacing: Design.Spacing.xLarge) {
      Spacer()
      StrataGlyph(model: model, size: 84)
      VStack(spacing: Design.Spacing.small) {
        Text("Every layer, understood.").font(Design.Typography.displayTitle)
        Text("Meet Strata Monitor. A quiet place for everything\nhappening on your Mac.")
          .font(Design.Typography.lead).foregroundStyle(.secondary).multilineTextAlignment(.center)
      }
      HStack(alignment: .top, spacing: Design.Spacing.xLarge) {
        step("cursorarrow", "Hover", "Reveal your menu bar")
        step("hand.tap", "Click", "Find the details")
        step("square.stack.3d.up", "Explore", "Follow a process")
      }.padding(.vertical, Design.Spacing.small)
      Button("Make Yourself at Home", action: finish).buttonStyle(.glassProminent)
        .controlSize(.large).tint(Design.mint)
      Text("Local by design. No account. No tracking.").font(Design.Typography.footnote)
        .foregroundStyle(.tertiary)
      Spacer()
    }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(Design.Spacing.xLarge)
  }
  private func step(_ symbol: String, _ title: String, _ caption: String) -> some View {
    VStack(spacing: Design.Spacing.small) {
      Image(systemName: symbol).font(Design.Typography.lead).foregroundStyle(Design.mint)
      Text(title).font(Design.Typography.itemTitle)
      Text(caption).footnoteStyle()
    }
  }
}

extension NSMenu {
  fileprivate func addItem(submenu: NSMenu) {
    let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
    item.submenu = submenu
    addItem(item)
  }
}
