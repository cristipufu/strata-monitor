import ServiceManagement
import StrataCore
import SwiftUI

private enum SettingsSection: CaseIterable, Hashable {
  case indicator, interaction, general, about
  var title: String {
    switch self {
    case .indicator: String(localized: "Indicator")
    case .interaction: String(localized: "Interaction")
    case .general: String(localized: "General")
    case .about: String(localized: "About")
    }
  }
  var symbol: String {
    switch self {
    case .indicator: "circle.dotted"
    case .interaction: "cursorarrow.motionlines"
    case .general: "gearshape"
    case .about: "info.circle"
    }
  }
}

struct SettingsView: View {
  @ObservedObject var model: AppModel
  let updates: ApplicationUpdates
  let language: ApplicationLanguage?
  let showWelcome: () -> Void
  @State private var section = SettingsSection.indicator
  @State private var loginEnabled = SMAppService.mainApp.status == .enabled
  var body: some View {
    NavigationSplitView {
      List(SettingsSection.allCases, id: \.self, selection: $section) { section in
        Label(section.title, systemImage: section.symbol)
      }
      .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 240)
      .toolbar(removing: .sidebarToggle)
    } detail: {
      Form {
        switch section {
        case .indicator: indicator
        case .interaction: interaction
        case .general: general
        case .about: about
        }
      }.formStyle(.grouped).navigationTitle(section.title)
    }.frame(minWidth: 720, minHeight: 620)
  }
  private var profileBinding: Binding<Profile> {
    Binding(get: { model.profile }, set: { model.profile = $0 })
  }
  private var thicknessSelection: Binding<Double> {
    Binding(
      get: { Double(RingThicknessPreset.nearest(to: model.profile.ringThickness).rawValue) },
      set: { value in
        guard let preset = RingThicknessPreset(rawValue: Int(value.rounded())) else { return }
        var profile = model.profile
        profile.ringThickness = preset.thickness
        model.profile = profile
      })
  }
  @ViewBuilder private var indicator: some View {
    Section {
      HStack {
        Spacer()
        VStack(spacing: Design.Spacing.small) {
          StrataGlyph(model: model, size: model.profile.iconSize * 2.8)
            .frame(width: 150, height: 80)
          StrataGlyph(model: model, fitsMenuBar: true)
            .frame(width: GlyphLayout.statusItemWidth(for: model.profile), height: 24)
            .padding(.horizontal, Design.Spacing.xLarge).padding(.vertical, Design.Spacing.xSmall)
            .background(.primary.opacity(0.05), in: Capsule())
          Text("Actual menu-bar size").footnoteStyle()
        }.padding(Design.Spacing.medium)
        Spacer()
      }
      Picker("Profile", selection: $model.selectedProfile) {
        ForEach(model.preferences.profiles) { Text($0.name).tag($0.id) }
      }
      TextField("Name", text: profileBinding.name)
      Button("New Profile") {
        let profile = Profile(name: String(localized: "New profile"))
        model.preferences.profiles.append(profile)
        model.selectedProfile = profile.id
      }.disabled(model.preferences.profiles.count >= Self.profileLimit)
    }
    Section("Readings") {
      Picker("Ring", selection: profileBinding.ring) {
        ForEach(Profile.scalarReadings) { Text($0.title).tag($0) }
      }
      Picker("Center", selection: profileBinding.center) {
        ForEach(Reading.allCases.filter { $0 != .overview }) { Text($0.title).tag($0) }
      }
      Picker("Bar", selection: profileBinding.bar) {
        ForEach(Profile.scalarReadings) { Text($0.title).tag($0) }
      }
    }
    Section("Appearance") {
      Picker("Color", selection: profileBinding.accent) {
        ForEach(Accent.allCases, id: \.self) { Text($0.title).tag($0) }
      }
      Picker("Fill", selection: profileBinding.fillStyle) {
        ForEach(FillStyle.allCases, id: \.self) { Text($0.title).tag($0) }
      }
      Toggle("Show tracks", isOn: profileBinding.showsTracks)
      Toggle("Battery percentage", isOn: profileBinding.showsBatteryPercent)
      Grid(
        alignment: .leading, horizontalSpacing: Design.Spacing.medium,
        verticalSpacing: Design.Spacing.medium
      ) {
        PresetSliderRow(
          title: String(localized: "Ring thickness"), value: thicknessSelection,
          range: 0...Double(RingThicknessPreset.allCases.count - 1),
          selection: RingThicknessPreset.nearest(to: model.profile.ringThickness).title,
          choices: RingThicknessPreset.allCases.map(\.title))
        PresetSliderRow(
          title: String(localized: "Icon size"), value: profileBinding.iconSize, range: Profile.iconSizeRange,
          selection: Self.points(model.profile.iconSize),
          choices: stride(
            from: Profile.iconSizeRange.lowerBound, through: Profile.iconSizeRange.upperBound,
            by: 1
          ).map(Self.points),
          spokenValue: String(localized: "\(Int(model.profile.iconSize)) points"))
      }
    }
  }
  @ViewBuilder private var interaction: some View {
    Section("Hover") {
      Toggle("Open the overview on hover", isOn: $model.preferences.hoverOpensPage)
      Text(
        "Hover reveals the menu-bar items to the left of the ring without taking focus. Click the ring for readings."
      ).footnoteStyle()
      Picker("Unfold transition", selection: profileBinding.unfoldStyle) {
        ForEach(UnfoldStyle.allCases, id: \.self) { Text($0.title).tag($0) }
      }
      Picker("Reading changes", selection: profileBinding.fillMotion) {
        ForEach(FillMotion.allCases, id: \.self) { Text($0.title).tag($0) }
      }
    }
    Section("Moments") {
      Toggle("Briefly show device and power changes", isOn: $model.preferences.momentsEnabled)
      Text("Your configured readings return after each moment. macOS Reduce Motion is respected.")
        .footnoteStyle()
    }
    Section("Launch") {
      Toggle("Draw the indicator on launch", isOn: $model.preferences.launchAnimationEnabled)
    }
  }
  @ViewBuilder private var general: some View {
    if let language { LanguageSection(language: language) }
    UpdatesSection(updates: updates)
    Section {
      Picker("Theme", selection: $model.preferences.appearance) {
        ForEach(Appearance.allCases, id: \.self) { Text($0.title).tag($0) }
      }
      Picker("Update readings", selection: $model.preferences.updateSpeed) {
        Text("Every second").tag(UpdateSpeed.fast)
        Text("Every 2 seconds").tag(UpdateSpeed.normal)
        Text("Every 5 seconds").tag(UpdateSpeed.relaxed)
      }
      Toggle("Open at login", isOn: $loginEnabled).onChange(of: loginEnabled) { _, enabled in
        do {
          if enabled {
            try SMAppService.mainApp.register()
          } else {
            try SMAppService.mainApp.unregister()
          }
        } catch {
          model.errorMessage = error.localizedDescription
          loginEnabled = SMAppService.mainApp.status == .enabled
        }
      }
      Button("Show Welcome Tour", action: showWelcome)
    }
    Section("Privacy") {
      Text(
        "All readings stay on your Mac. No account, tracking, analytics, or cloud service. Permissions are requested only in the feature that needs them."
      )
      .font(Design.Typography.body).foregroundStyle(.secondary)
      FullVisibilitySetting(controller: model.fullVisibility)
      if let recorder = model.historyRecorder {
        HistorySetting(keeping: $model.preferences.historyKeeping, recorder: recorder)
      }
    }
  }
  @ViewBuilder private var about: some View {
    Section {
      Text("Strata Monitor").font(Design.Typography.displayTitle)
      Text("Every layer, understood.").foregroundStyle(.secondary)
      Text("An original native macOS application. Public source, MIT license.")
      Text("Version \(Self.version)").footnoteStyle()
      Link("Source Code", destination: URL(string: "https://github.com/cristipufu/strata-monitor")!)
      if let notices = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md") {
        Link("Third-Party Notices", destination: notices)
      }
    }
  }
  private static let profileLimit = 20
  private static var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? ReadingValue.unavailable
  }
  private static func points(_ size: Double) -> String { "\(Int(size)) pt" }
}

private struct PresetSliderRow: View {
  let title: String
  @Binding var value: Double
  let range: ClosedRange<Double>
  let selection: String
  let choices: [String]
  var spokenValue: String?

  var body: some View {
    GridRow {
      Text(title)
      Slider(value: $value, in: range, step: 1) { Text(title) }
        .labelsHidden().accessibilityValue(spokenValue ?? selection)
      // Reserving the widest choice keeps the slider still while the value changes.
      ZStack(alignment: .trailing) {
        ForEach(choices, id: \.self) { Text($0).hidden() }
        Text(selection)
      }
      .font(Design.Typography.secondary).monospacedDigit().foregroundStyle(.secondary).fixedSize()
      .accessibilityHidden(true)
    }
  }
}

private struct FullVisibilitySetting: View {
  @ObservedObject var controller: FullVisibilityController
  var body: some View {
    VStack(alignment: .leading, spacing: Design.Spacing.small) {
      SwitchRow(
        title: String(localized: "Show all processes"),
        isOn: Binding(get: { controller.isRequested }, set: { controller.setEnabled($0) }))
      Text(
        "Adds a small read-only helper that runs as root, so system processes and other users' processes show CPU, memory, disk and energy. An administrator approves it in System Settings."
      )
      .footnoteStyle().fixedSize(horizontal: false, vertical: true)
      status
    }
    .onAppear(perform: controller.refresh)
  }
  @ViewBuilder private var status: some View {
    switch controller.state {
    case .off: EmptyView()
    case .turningOn: ProgressView().controlSize(.small)
    case .on: Label("On", systemImage: "checkmark.circle").foregroundStyle(Design.mint)
    case .needsApproval:
      HStack {
        Label("Waiting for approval", systemImage: "hourglass").foregroundStyle(.secondary)
        Spacer(minLength: Design.Spacing.medium)
        Button("Open Login Items…", action: controller.openApproval)
      }
    case .unavailable(let message), .failed(let message):
      Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct HistorySetting: View {
  @Binding var keeping: HistoryKeeping
  @ObservedObject var recorder: HistoryRecorder
  @State private var isConfirmingClear = false
  var body: some View {
    VStack(alignment: .leading, spacing: Design.Spacing.small) {
      Picker("Keep history", selection: $keeping) {
        Text("Off").tag(HistoryKeeping.off)
        Text("24 hours").tag(HistoryKeeping.day)
        Text("7 days").tag(HistoryKeeping.week)
      }
      Text(
        "Readings and the busiest processes are kept on this Mac only, for longer charts, the Explorer timeline and alerts. Process names are kept; paths and arguments never are."
      )
      .footnoteStyle().fixedSize(horizontal: false, vertical: true)
      if let issue = recorder.issue {
        Label(issue, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Button("Clear History…") { isConfirmingClear = true }
        .disabled(!recorder.isRecording)
        .confirmationDialog("Clear all history?", isPresented: $isConfirmingClear) {
          Button("Clear History", role: .destructive) { Task { await recorder.clear() } }
        } message: {
          Text("Charts and the timeline start again from now.")
        }
    }
  }
}
