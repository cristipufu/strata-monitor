import CoreLocation
import StrataCore
import StrataSystem
import SwiftUI

@MainActor
final class LocationAuthorization: NSObject, ObservableObject, @MainActor CLLocationManagerDelegate
{
  private let manager = CLLocationManager()
  @Published var status: CLAuthorizationStatus = .notDetermined
  override init() {
    super.init()
    manager.delegate = self
    status = manager.authorizationStatus
  }
  func request() { manager.requestWhenInUseAuthorization() }
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    status = manager.authorizationStatus
  }
}

struct WiFiContent: View {
  @ObservedObject var model: AppModel
  @ObservedObject var controller: WiFiController
  @StateObject private var authorization = LocationAuthorization()
  var body: some View {
    if let message = controller.errorMessage {
      OperationErrorBanner(message: message, dismiss: controller.dismissError)
    }
    locationPrompt
    MetricHero(value: model.value(for: .wifi), caption: signalCaption)
    SurfaceCard {
      if let wifi = model.devices?.wifi, wifi.interface != nil {
        SwitchRow(title: "Wi-Fi", isOn: Binding(get: { wifi.powered }, set: model.setWiFiPower))
          .disabled(controller.joiningNetworkID != nil)
      } else {
        DetailRow(
          label: "Wi-Fi",
          value: model.devices == nil ? ReadingValue.notObserved : ReadingValue.unavailable)
      }
    }.onChange(of: authorization.status) { _, status in
      controller.cancelScan()
      if status == .authorizedAlways {
        model.refreshDeviceReadings()
      }
    }
    ItemsCard(title: "Nearby networks") {
      if controller.isScanning {
        ProgressView().controlSize(.mini)
        Button("Cancel", action: controller.cancelScan).buttonStyle(.plain)
          .font(Design.Typography.footnote)
      } else {
        RefreshAccessory(
          isBusy: false,
          isDisabled: controller.joiningNetworkID != nil || model.devices?.wifi.powered != true,
          help: "Find nearby networks", action: controller.scan)
      }
    } content: {
      nearbyNetworks
    }
  }
  private var signalCaption: String {
    guard let wifi = model.devices?.wifi else { return ReadingValue.notObserved }
    if let rssi = wifi.rssi { return String(localized: "Signal \(rssi) dBm") }
    return wifi.powered
      ? String(localized: "Not joined to a network") : String(localized: "Turn on Wi-Fi to join a network")
  }
  @ViewBuilder private var nearbyNetworks: some View {
    if let name = controller.joiningNetworkName {
      HStack {
        ProgressView().controlSize(.small)
        Text("Joining \(name)…").font(Design.Typography.body)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    if let report = controller.report {
      ForEach(report.networks) { network in
        if network.id != report.networks.first?.id { Divider() }
        networkRow(network)
      }
      if report.networks.isEmpty && report.unavailableNames == 0 {
        Text("No nearby networks reported.").footnoteStyle()
      }
      if report.unavailableNames > 0 {
        Text("Some names are hidden.").footnoteStyle()
      }
      if !controller.hasCurrentResults {
        Text("Refresh nearby networks before joining.").footnoteStyle()
      }
    } else if !controller.isScanning {
      Button("Find Nearby Networks", action: controller.scan).buttonStyle(.glass)
        .controlSize(.small)
        .disabled(controller.joiningNetworkID != nil || model.devices?.wifi.powered != true)
    }
  }
  @ViewBuilder private var locationPrompt: some View {
    switch authorization.status {
    case .notDetermined:
      PermissionPrompt(
        explanation:
          "Allow location access to see network names.",
        action: .request("Allow Network Names", authorization.request))
    case .denied, .restricted:
      PermissionPrompt(
        explanation:
          "Location access is off, so network names are hidden.",
        action: .openPrivacySettings(.locationServices))
    default:
      EmptyView()
    }
  }
  private func networkRow(_ network: NearbyNetwork) -> some View {
    VStack(alignment: .leading, spacing: Design.Spacing.small) {
      HStack {
        Text(verbatim: network.name).font(Design.Typography.itemTitle)
          .fixedSize(horizontal: false, vertical: true)
        Spacer()
        Text("\(network.rssi) dBm").footnoteStyle().monospacedDigit()
      }
      HStack {
        Label(
          network.securityLabel,
          systemImage: network.isProtected.map { $0 ? "lock.fill" : "lock.open" } ?? "questionmark"
        )
        .footnoteStyle()
        Spacer()
        switch network.joinCapability {
        case .unprotectedNetwork:
          Button("Join") { controller.join(network.id) }.buttonStyle(.glass).controlSize(.small)
            .disabled(controller.joiningNetworkID != nil || !controller.hasCurrentResults)
        case .systemSettings(let restriction):
          Button {
            SystemSettings.open(.wifi)
          } label: {
            Image(systemName: Design.Symbol.systemSettings)
          }
          .buttonStyle(.plain).help(restriction.explanation)
          .accessibilityLabel("Open Wi-Fi settings for \(network.name)")
        }
      }
    }.padding(.vertical, Design.Spacing.xSmall)
  }
}
