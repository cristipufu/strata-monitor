import AppKit
import StrataSystem
import SwiftUI

struct DisplayContent: View {
  @ObservedObject var controller: DisplayController
  @ObservedObject var power: KeepAwakeController
  var body: some View {
    if let error = controller.errorMessage {
      OperationErrorBanner(message: error, dismiss: controller.dismissError)
    }
    if controller.trial != nil {
      Label("Confirm your preview in the Keep Display Settings window.", systemImage: "timer")
        .footnoteStyle()
    }
    if let catalog = controller.catalog {
      MetricHero(value: count(catalog.displays), caption: mainDisplay(catalog.displays))
      HStack {
        SectionHeading(String(localized: "Displays"))
        Spacer()
        RefreshAccessory(
          isBusy: controller.isLoading,
          isDisabled: controller.isBusy || controller.trial != nil, help: String(localized: "Refresh displays"),
          action: controller.refreshIfVisible)
      }
      ForEach(catalog.displays) { display in
        DisplayCard(display: display, allDisplays: catalog.displays, controller: controller)
      }
      if !catalog.displays.isEmpty && !catalog.canPreview {
        Text("Previews aren't available for this setup.").footnoteStyle()
      }
    } else if controller.isLoading {
      LoadingState(String(localized: "Reading displays…"))
    }
    SurfaceCard {
      VStack(alignment: .leading, spacing: Design.Spacing.medium) {
        SwitchRow(
          title: String(localized: "Keep Awake"),
          isOn: Binding(get: { power.isEnabled }, set: { $0 ? power.enable() : power.disable() }))
        if let error = power.error {
          Label(error, systemImage: "exclamationmark.triangle").footnoteStyle()
        } else if let expiry = power.expiresAt {
          Text("Until \(expiry.formatted(date: .omitted, time: .shortened)) · 30-minute session")
            .footnoteStyle()
        } else {
          Text("Temporarily prevent idle display sleep.").footnoteStyle()
        }
      }
    }
  }
  private func count(_ displays: [DisplayInfo]) -> String {
    displays.count == 1 ? String(localized: "1 display") : String(localized: "\(displays.count) displays")
  }
  private func mainDisplay(_ displays: [DisplayInfo]) -> String {
    guard let main = displays.first else { return String(localized: "No displays reported") }
    let mode = main.currentMode.map(DisplayNames.mode) ?? ReadingValue.unavailable
    return "\(DisplayNames.name(main)) · \(mode)"
  }
}

private struct DisplayCard: View {
  let display: DisplayInfo
  let allDisplays: [DisplayInfo]
  @ObservedObject var controller: DisplayController
  @State private var selectedMode: DisplayMode?
  @State private var selectedMirror: DisplayIdentity?
  init(display: DisplayInfo, allDisplays: [DisplayInfo], controller: DisplayController) {
    self.display = display
    self.allDisplays = allDisplays
    self.controller = controller
    _selectedMode = State(initialValue: display.currentMode)
    _selectedMirror = State(initialValue: display.mirrorOf)
  }
  // Resolutions are offered at the current refresh rate; refresh rate is a separate choice.
  private var resolutionChoices: [DisplayMode] {
    guard let current = display.currentMode else { return display.modes }
    return display.modes.filter { $0.refreshRate == current.refreshRate }
  }
  var body: some View {
    SurfaceCard {
      VStack(alignment: .leading, spacing: Design.Spacing.medium) {
        Label(
          DisplayNames.name(display), systemImage: display.isBuiltIn ? "laptopcomputer" : "display"
        )
        .font(Design.Typography.cardTitle).lineLimit(2)
        DetailRow(
          label: String(localized: "Current"),
          value: display.currentMode.map(DisplayNames.mode) ?? ReadingValue.unavailable)
        if !display.modes.isEmpty {
          Picker("Resolution", selection: $selectedMode) {
            if display.currentMode == nil { Text("Choose a resolution").tag(DisplayMode?.none) }
            ForEach(resolutionChoices) { mode in
              Text(DisplayNames.mode(mode)).tag(Optional(mode))
            }
          }.pickerStyle(.menu).controlSize(.small)
          Button("Preview Resolution") {
            if let selectedMode { controller.preview(.mode(display.id, selectedMode)) }
          }.buttonStyle(.glass).controlSize(.small)
            .disabled(
              !controller.canPreview || selectedMode == nil || selectedMode == display.currentMode
                || !display.modes.contains(where: { $0 == selectedMode }))
        }
        if allDisplays.count > 1 {
          Divider()
          Picker("Mirror", selection: $selectedMirror) {
            Text("Separate display").tag(DisplayIdentity?.none)
            ForEach(mirrorChoices) { other in
              Text(DisplayNames.name(other)).tag(Optional(other.id))
            }
          }.pickerStyle(.menu).controlSize(.small)
          Button("Preview Mirroring") { controller.preview(.mirror(display.id, selectedMirror)) }
            .buttonStyle(.glass).controlSize(.small)
            .disabled(!controller.canPreview || selectedMirror == display.mirrorOf)
        }
      }
    }
    .onChange(of: display.currentMode) { _, mode in selectedMode = mode }
    .onChange(of: display.mirrorOf) { _, master in selectedMirror = master }
  }
  private var mirrorChoices: [DisplayInfo] {
    allDisplays.filter { $0.id != display.id && ($0.mirrorOf == nil || $0.id == display.mirrorOf) }
  }
}

@MainActor private enum DisplayNames {
  static func name(_ display: DisplayInfo) -> String {
    NSScreen.screens.first {
      ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        == display.id.objectID
    }?.localizedName ?? (display.isBuiltIn ? String(localized: "Built-in display") : String(localized: "Display \(String(display.id.objectID))"))
  }
  static func mode(_ mode: DisplayMode) -> String {
    var parts = ["\(mode.width) × \(mode.height)"]
    if mode.refreshRate > 0 {
      parts.append(mode.refreshRate.formatted(.number.precision(.fractionLength(0...2))) + " Hz")
    }
    if mode.pixelWidth > mode.width || mode.pixelHeight > mode.height { parts.append("HiDPI") }
    return parts.joined(separator: " · ")
  }
}
