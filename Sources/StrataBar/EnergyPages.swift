import StrataCore
import StrataSystem
import SwiftUI

// Where the Mac's power comes from and goes, as its power controller reports it.
struct PowerBreakdown: View {
  let power: PowerReading
  var body: some View {
    SurfaceCard {
      VStack(alignment: .leading, spacing: Design.Spacing.medium) {
        SectionHeading(String(localized: "Power"))
        DetailRow(label: String(localized: "Mac is drawing"), value: watts(power.systemWatts))
        if power.onExternalPower == true {
          DetailRow(label: power.adapterName ?? String(localized: "Power adapter"), value: watts(power.adapterWatts))
        }
        if power.batteryInstalled == true {
          DetailRow(label: String(localized: "Battery"), value: batteryFlow)
          DetailRow(
            label: String(localized: "Battery temperature"),
            value: power.batteryTemperatureCelsius.map {
              Measurement(value: $0, unit: UnitTemperature.celsius).formatted(
                .measurement(
                  width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0))))
            } ?? ReadingValue.unavailable)
        }
      }
    }
  }
  private func watts(_ value: Double?) -> String {
    value.map(ValueFormat.watts) ?? ReadingValue.unavailable
  }
  private var batteryFlow: String {
    guard let flow = power.batteryWatts else { return ReadingValue.unavailable }
    if abs(flow) < 0.05 { return String(localized: "Idle") }
    let amount = ValueFormat.watts(abs(flow))
    return flow > 0
      ? String(localized: "Charging at \(amount)") : String(localized: "Supplying \(amount)")
  }
}

// Whether the display and the Mac may sleep, one fixed row each, naming what keeps them awake.
// Every holder, with what it asked for and since when, is in the row's help.
struct AwakeReasons: View {
  @ObservedObject var model: AppModel
  let snapshot: PowerSnapshot
  private enum Kind: CaseIterable {
    case display, system
    var title: String { self == .display ? String(localized: "Display") : String(localized: "Mac") }
    var symbol: String { self == .display ? "display" : "laptopcomputer" }
    func includes(_ prevention: SleepPrevention) -> Bool {
      switch prevention {
      case .keepsDisplayOn: self == .display
      case .keepsSystemAwake, .unrecognized: self == .system
      case .userActivity, .doesNotPreventSleep: false
      }
    }
  }
  var body: some View {
    let reasons = EnergyReport(
      power: snapshot.reading, sleepBlockers: snapshot.sleepBlockers,
      ownPID: ProcessInfo.processInfo.processIdentifier
    ).awakeReasons
    ItemsCard(title: String(localized: "Keeping your Mac awake")) {
      ForEach(Kind.allCases, id: \.self) { kind in
        let holders = reasons?.filter { kind.includes($0.blocker.prevention) }
        HStack(spacing: Design.Spacing.small) {
          Circle().fill(holders?.isEmpty == false ? Design.orange : Design.mint)
            .frame(width: 6, height: 6)
          Label(kind.title, systemImage: kind.symbol)
          Spacer(minLength: Design.Spacing.small)
          Text(summary(holders)).lineLimit(1).truncationMode(.middle)
            .foregroundStyle(.secondary)
        }
        .font(Design.Typography.body)
        .help(holders.map { $0.map(detail).joined(separator: "\n") } ?? "")
      }
    }
  }
  private func summary(_ holders: [AwakeReason]?) -> String {
    guard let holders else { return ReadingValue.unavailable }
    guard let first = holders.first else { return String(localized: "Can sleep") }
    let others = holders.count - 1
    return others > 0
      ? String(localized: "Kept awake by \(name(first)) +\(others)")
      : String(localized: "Kept awake by \(name(first))")
  }
  private func name(_ reason: AwakeReason) -> String {
    if reason.isStrataBarKeepAwake { return String(localized: "Strata Monitor Keep Awake") }
    return model.processes.first { $0.id.pid == reason.blocker.pid }?.name
      ?? reason.blocker.processName ?? "PID \(reason.blocker.pid)"
  }
  private func detail(_ reason: AwakeReason) -> String {
    let what = reason.blocker.name.map { "\(name(reason)): \($0)" } ?? name(reason)
    guard let since = reason.blocker.createdAt else { return what }
    return "\(what) · \(since.formatted(.relative(presentation: .named)))"
  }
}
