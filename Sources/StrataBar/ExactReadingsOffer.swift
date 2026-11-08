import StrataCore
import SwiftUI

// Shown only where system processes lack readings. macOS asks an administrator to approve the
// helper once; after that the readings fill in without another step.
struct ExactReadingsOffer: View {
  @ObservedObject var visibility: FullVisibilityController
  var stacked = false
  var body: some View {
    if visibility.offersExactReadings {
      if stacked {
        VStack(alignment: .leading, spacing: Design.Spacing.xSmall) {
          message.fixedSize(horizontal: false, vertical: true)
          HStack(spacing: Design.Spacing.medium) { actions }
        }
      } else {
        HStack(spacing: Design.Spacing.small) {
          message.lineLimit(1)
          actions
        }
      }
    }
  }
  @ViewBuilder private var message: some View {
    switch visibility.state {
    case .turningOn:
      Label { Text("Asking macOS…") } icon: { ProgressView().controlSize(.mini) }
    case .needsApproval:
      Label("Turn on Strata Monitor in Login Items to finish", systemImage: "hourglass")
    case .failed(let message):
      Label(message, systemImage: "exclamationmark.triangle").help(message)
    case .off, .on, .unavailable:
      Label("System processes need a one-time approval", systemImage: "lock")
    }
  }
  @ViewBuilder private var actions: some View {
    switch visibility.state {
    case .turningOn:
      EmptyView()
    case .needsApproval:
      Button("Open Login Items…", action: visibility.openApproval).buttonStyle(.link)
      Button("Cancel") { visibility.setEnabled(false) }.buttonStyle(.link)
    case .failed:
      Button("Try Again", action: visibility.requestExactReadings).buttonStyle(.link)
    case .off, .on, .unavailable:
      Button("Show Exact Readings…", action: visibility.requestExactReadings).buttonStyle(.link)
        .help("Adds a read-only helper that an administrator approves once in System Settings")
    }
  }
}

extension ProcessSort {
  // Without the helper, system processes have no value in these columns.
  var needsExactReadings: Bool {
    switch self {
    case .memory, .power, .wakeups, .threads, .diskRead, .diskWrite: true
    default: false
    }
  }
}

extension ProcessSample {
  var lacksExactReadings: Bool { activity == nil && userID != getuid() }
}
