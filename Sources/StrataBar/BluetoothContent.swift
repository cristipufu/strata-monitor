import StrataCore
import StrataSystem
import SwiftUI

struct BluetoothContent: View {
  @ObservedObject var controller: BluetoothController
  var body: some View {
    if let message = controller.errorMessage {
      OperationErrorBanner(message: message, dismiss: controller.dismissError)
    }
    if let snapshot = controller.snapshot {
      notice(snapshot)
      if snapshot.access == .allowed {
        MetricHero(value: connected(snapshot), caption: paired(snapshot))
        ItemsCard(title: "Devices") {
          RefreshAccessory(
            isBusy: false, isDisabled: controller.busyDeviceID != nil, help: "Refresh devices",
            action: controller.refresh)
        } content: {
          if snapshot.powered == true && snapshot.devices.isEmpty {
            Text("Pair accessories in Bluetooth settings.").font(Design.Typography.body)
              .foregroundStyle(.secondary)
          }
          ForEach(snapshot.devices) { device in
            if device.id != snapshot.devices.first?.id { Divider() }
            deviceRow(device)
          }
        }
      }
    } else {
      LoadingState("Reading Bluetooth…")
    }
    AccessoryBatteryContent(controller: controller.batteries)
  }
  private func connected(_ snapshot: BluetoothSnapshot) -> String {
    if snapshot.powered == false { return String(localized: "Off") }
    guard let count = snapshot.connectedCount else { return ReadingValue.unavailable }
    return String(localized: "\(count) connected")
  }
  private func paired(_ snapshot: BluetoothSnapshot) -> String {
    if snapshot.powered == false { return String(localized: "Turn on Bluetooth in System Settings.") }
    return String(localized: "\(snapshot.devices.count) paired devices")
  }
  @ViewBuilder private func notice(_ snapshot: BluetoothSnapshot) -> some View {
    switch snapshot.access {
    case .notDetermined:
      PermissionPrompt(
        explanation:
          "Allow Bluetooth access to see paired devices.",
        action: .request("Allow Bluetooth Devices", controller.requestAccess))
    case .denied, .restricted:
      PermissionPrompt(
        explanation:
          "Bluetooth access is off, so paired devices are hidden.",
        action: .openPrivacySettings(.bluetooth))
    case .allowed:
      if let issue = snapshot.issue {
        Label(issue, systemImage: "exclamationmark.triangle").footnoteStyle()
      } else if snapshot.powered == nil {
        Label("Bluetooth controller information is unavailable.", systemImage: "exclamationmark.triangle")
          .footnoteStyle()
      }
    }
  }
  private func deviceRow(_ device: BluetoothPeripheral) -> some View {
    HStack(spacing: Design.Spacing.medium) {
      Image(systemName: "wave.3.right").foregroundStyle(device.connected ? Design.mint : .secondary)
      VStack(alignment: .leading, spacing: Design.Spacing.xxSmall) {
        Text(verbatim: device.name).font(Design.Typography.itemTitle)
          .fixedSize(horizontal: false, vertical: true)
        Text(
          controller.busyDeviceID == device.id
            ? (device.connected ? "Disconnecting…" : "Connecting…")
            : (device.connected ? "Connected" : "Not connected")
        ).footnoteStyle()
      }
      Spacer()
      if let battery = device.batteryFraction {
        Text(ValueFormat.percent(battery)).font(Design.Typography.footnote).monospacedDigit()
      }
      if controller.busyDeviceID == device.id {
        ProgressView().controlSize(.small)
          .accessibilityLabel(device.connected ? "Disconnecting" : "Connecting")
      } else {
        Button(device.connected ? "Disconnect" : "Connect") {
          controller.setConnected(!device.connected, deviceID: device.id)
        }.buttonStyle(.glass).controlSize(.small)
          .disabled(controller.busyDeviceID != nil || controller.batteries.isReading)
      }
    }.padding(.vertical, Design.Spacing.xSmall)
  }
}

private struct AccessoryBatteryContent: View {
  @ObservedObject var controller: AccessoryBatteryController
  var body: some View {
    ItemsCard(title: "Accessory batteries") {
      if controller.isReading {
        ProgressView().controlSize(.mini)
        Button("Cancel", action: controller.cancel).buttonStyle(.plain)
          .font(Design.Typography.footnote).disabled(controller.isCanceling)
      } else if controller.report != nil {
        RefreshAccessory(
          isBusy: false, isDisabled: !controller.canRead, help: "Read accessory batteries again",
          action: controller.read)
      }
    } content: {
      VStack(alignment: .leading, spacing: Design.Spacing.medium) {
        if let error = controller.errorMessage {
          OperationErrorBanner(message: error, dismiss: controller.dismissError)
        }
        if controller.report == nil {
          if !controller.isReading {
            Button("Read Accessory Batteries", action: controller.read).buttonStyle(.glass)
              .controlSize(.small).disabled(!controller.canRead)
              .help("Briefly connects to accessories that report a standard battery service.")
          }
        }
        if controller.isReading {
          Text(controller.isCanceling ? "Finishing battery read…" : "Reading batteries…")
            .footnoteStyle()
        }
        if let report = controller.report {
          Text("Read \(report.observedAt.formatted(date: .abbreviated, time: .shortened))")
            .footnoteStyle()
          if let issue = report.issue { Text(issue).footnoteStyle() }
          if report.devices.isEmpty {
            Text("No accessory reported a battery.").footnoteStyle()
          }
          ForEach(report.devices) { device in
            Divider()
            VStack(alignment: .leading, spacing: Design.Spacing.small) {
              Text(device.name).font(Design.Typography.itemTitle).textSelection(.enabled)
              if report.devices.filter({ $0.name == device.name }).count > 1 {
                Text("Device \(device.id.uuidString.prefix(8))")
                  .font(Design.Typography.footnote.monospaced())
                  .foregroundStyle(.tertiary).help(device.id.uuidString)
              }
              ForEach(device.levels) { level in
                DetailRow(
                  label: device.levels.count == 1 ? "Battery" : "Battery \(level.id)",
                  value: level.percent.map { "\($0)%" } ?? ReadingValue.unavailable)
                if let issue = level.issue { Text(issue).footnoteStyle() }
              }
              if let issue = device.issue { Text(issue).footnoteStyle() }
            }
          }
        }
      }
    }
  }
}
