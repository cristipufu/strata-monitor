import AppKit
import CoreGraphics
import StrataCore
import StrataSystem
import SwiftUI

struct BatteryContent: View {
  @ObservedObject var model: AppModel
  let openExplorer: (ExplorerDestination) -> Void
  var body: some View {
    hero
    MeasureLeaders(model: model, measure: .power, openExplorer: openExplorer)
    if let snapshot = model.powerSnapshot {
      PowerBreakdown(power: snapshot.reading)
    }
    if let battery = model.devices?.battery {
      SurfaceCard {
        VStack(alignment: .leading, spacing: Design.Spacing.medium) {
          SectionHeading(String(localized: "Health"))
          DetailRow(label: String(localized: "Condition"), value: battery.health ?? ReadingValue.unavailable)
          DetailRow(
            label: String(localized: "Maximum capacity"),
            value: battery.maximumCapacityFraction.map { ValueFormat.percent($0) }
              ?? ReadingValue.unavailable)
          DetailRow(
            label: String(localized: "Cycle count"),
            value: battery.cycleCount.map(String.init) ?? ReadingValue.unavailable)
          DetailRow(
            label: String(localized: "Low Power Mode"), value: model.devices?.lowPowerMode == true ? String(localized: "On") : String(localized: "Off"))
        }
      }
    }
    if let snapshot = model.powerSnapshot {
      AwakeReasons(model: model, snapshot: snapshot)
    }
  }
  @ViewBuilder private var hero: some View {
    switch model.devices?.batteryObservation {
    case nil:
      LoadingState(String(localized: "Reading battery…"))
    case .present(let battery):
      MetricHero(
        value: battery.fraction.map { ValueFormat.percent($0) } ?? ReadingValue.unavailable,
        caption: state(battery))
    case .absent:
      if case .drawingFromAdapter(let watts, _)? = model.powerSnapshot.map(powerSummary) {
        MetricHero(value: ValueFormat.watts(watts), caption: String(localized: "drawn from the power adapter"))
      } else {
        LoadingState(String(localized: "Reading power…"))
      }
    case .unavailable:
      EmptyState(
        symbol: "battery.0percent", title: String(localized: "Battery information unavailable"),
        detail: String(localized: "Strata Monitor will try again."))
    }
  }
  private func powerSummary(_ snapshot: PowerSnapshot) -> PowerSummary {
    EnergyReport(
      power: snapshot.reading, sleepBlockers: nil,
      ownPID: ProcessInfo.processInfo.processIdentifier
    ).powerSummary
  }
  private func state(_ battery: BatteryState) -> String {
    let remaining = battery.minutesRemaining.map(Self.remaining)
    if battery.charging == true {
      return remaining.map { String(localized: "Charging · \($0) until full") }
        ?? String(localized: "Charging")
    }
    switch battery.externalPower {
    case true: return String(localized: "On power adapter")
    case false:
      return remaining.map { String(localized: "On battery · \($0) left") }
        ?? String(localized: "On battery")
    default: return ReadingValue.unavailable
    }
  }
  private static func remaining(_ minutes: Int) -> String {
    guard minutes > 0 else { return String(localized: "Less than a minute") }
    return Duration.seconds(minutes * 60).formatted(
      .units(allowed: [.hours, .minutes], width: .abbreviated))
  }
}

struct SoundContent: View {
  @ObservedObject var model: AppModel
  @State private var sliderValue = 0.5
  @State private var volumeEditing = VolumeEditingSession()
  var body: some View {
    if let audio = model.devices?.audio {
      if let issue = audio.issue {
        Label(issue, systemImage: "exclamationmark.triangle").footnoteStyle()
          .fixedSize(horizontal: false, vertical: true)
      }
      MetricHero(
        value: volumeEditing.isEditing ? ValueFormat.percent(sliderValue) : model.value(for: .sound),
        caption: audio.outputs.first(where: \.isDefault)?.name ?? String(localized: "No output selected"))
      SurfaceCard {
        VStack(alignment: .leading, spacing: Design.Spacing.medium) {
          HStack(spacing: Design.Spacing.medium) {
            Button {
              if let output = audio.outputIdentity, let muted = audio.muted {
                model.setMuted(!muted, on: output)
              }
            } label: {
              Image(systemName: audio.muted == true ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .frame(width: 18)
            }
            .buttonStyle(.glass).disabled(!audio.canSetMute || audio.outputIdentity == nil)
            .help(audio.muted == true ? String(localized: "Unmute") : String(localized: "Mute"))
            .accessibilityLabel(audio.muted == true ? String(localized: "Unmute") : String(localized: "Mute"))
            if audio.volume != nil {
              Slider(value: $sliderValue, in: 0...1) { editing in
                if editing {
                  volumeEditing.begin(on: audio.outputIdentity)
                } else if let output = volumeEditing.finish(
                  currentOutput: model.devices?.audio.outputIdentity,
                  isVisible: model.isReadingPageVisible(.sound))
                {
                  model.setVolume(sliderValue, on: output)
                }
              }
              .disabled(!audio.canSetVolume || audio.outputIdentity == nil).tint(Design.mint)
              .accessibilityLabel("Output volume")
            }
          }
          if audio.issue == nil, !audio.canSetVolume {
            Text("Volume is controlled by this device.").footnoteStyle()
          }
        }
      }
      ItemsCard(title: String(localized: "Output")) {
        ForEach(audio.outputs) { output in
          if output.id != audio.outputs.first?.id { Divider() }
          Button {
            if let identity = output.identity { model.selectOutput(identity) }
          } label: {
            HStack {
              Label(output.name, systemImage: "hifispeaker")
              Spacer(minLength: Design.Spacing.small)
              if output.isDefault {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Design.mint)
              }
            }.font(Design.Typography.body).padding(.vertical, Design.Spacing.xSmall)
              .contentShape(Rectangle())
          }.buttonStyle(.plain).disabled(output.identity == nil)
        }
      }
    } else {
      LoadingState(String(localized: "Reading sound devices…"))
    }
    Color.clear.frame(height: 0)
      .onAppear { sliderValue = model.devices?.audio.volume ?? 0.5 }
      .onChange(of: model.devices?.audio.volume) { _, value in
        if !volumeEditing.isEditing { sliderValue = value ?? 0.5 }
      }
      .onChange(of: model.devices?.audio.outputIdentity) { _, _ in
        volumeEditing.cancel()
        sliderValue = model.devices?.audio.volume ?? 0.5
      }
      .onChange(of: model.isReadingPageVisible(.sound)) { _, visible in
        if !visible {
          volumeEditing.cancel()
          sliderValue = model.devices?.audio.volume ?? 0.5
        }
      }
      .onDisappear { volumeEditing.cancel() }
  }
}

enum SystemSettings {
  enum PrivacyPane: String {
    case locationServices = "Privacy_LocationServices"
    case bluetooth = "Privacy_Bluetooth"
  }
  @MainActor static func open(_ reading: Reading) {
    let pane: String =
      switch reading {
      case .wifi: "com.apple.wifi-settings-extension"
      case .bluetooth: "com.apple.BluetoothSettings"
      case .sound: "com.apple.Sound-Settings.extension"
      case .battery: "com.apple.Battery-Settings.extension"
      case .display: "com.apple.Displays-Settings.extension"
      default: ""
      }
    open(pane: pane)
  }
  @MainActor static func openPrivacy(_ pane: PrivacyPane) {
    open(pane: "com.apple.preference.security?\(pane.rawValue)")
  }
  @MainActor private static func open(pane: String) {
    if let url = URL(string: "x-apple.systempreferences:\(pane)"), NSWorkspace.shared.open(url) {
      return
    }
    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
  }
}
