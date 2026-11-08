import StrataCore
import SwiftUI

// One fixed row per area, so the card keeps its height while readings come and go. A busy area
// names the process behind it; the explanation is in the row's help.
struct DiagnosisCard: View {
  @ObservedObject var recorder: HistoryRecorder
  let openExplorer: (ExplorerDestination) -> Void
  private static let areas: [Diagnosis.Cause] = [
    .cpuSaturation, .memoryPressure, .thermalPressure, .diskActivity, .gpuLoad, .powerDraw,
  ]
  var body: some View {
    if recorder.isRecording {
      SurfaceCard {
        VStack(alignment: .leading, spacing: Design.Spacing.small) {
          SectionHeading(String(localized: "Mac status"))
          ForEach(Self.areas, id: \.self) { area in
            row(area, finding: recorder.diagnosis?.causes.first { $0.cause == area })
          }
        }
      }
    }
  }
  @ViewBuilder private func row(_ area: Diagnosis.Cause, finding: Diagnosis?) -> some View {
    let contributor = finding?.contributors.first
    Button {
      if let contributor { openExplorer(.processes(contributor.identity)) }
    } label: {
      HStack(spacing: Design.Spacing.small) {
        Circle().fill(dotColor(finding)).frame(width: 6, height: 6)
        Label(Self.title(area), systemImage: Self.symbol(area)).lineLimit(1)
        Spacer(minLength: Design.Spacing.small)
        status(finding, contributor: contributor)
      }
      .font(Design.Typography.body).contentShape(Rectangle())
    }
    .buttonStyle(.plain).disabled(contributor == nil)
    .help(finding.map { ([$0.title] + $0.evidence).joined(separator: "\n") } ?? "")
  }
  @ViewBuilder private func status(_ finding: Diagnosis?, contributor: DiagnosisContributor?)
    -> some View
  {
    if let contributor {
      Text(contributor.project.map { "\(contributor.name) · \($0)" } ?? contributor.name)
        .lineLimit(1).truncationMode(.middle)
      Text(contributor.formattedValue).monospacedDigit().foregroundStyle(.secondary).fixedSize()
      Image(systemName: "chevron.right").font(Design.Typography.inlineSymbol)
        .foregroundStyle(.tertiary)
    } else if let finding {
      Text(finding.title).lineLimit(1).foregroundStyle(.secondary)
    } else {
      Text(recorder.diagnosis == nil ? ReadingValue.notObserved : String(localized: "Normal"))
        .foregroundStyle(.secondary)
    }
  }
  private func dotColor(_ finding: Diagnosis?) -> Color {
    if finding != nil { return Design.orange }
    return recorder.diagnosis == nil ? Color.secondary.opacity(0.4) : Design.mint
  }
  private static func title(_ area: Diagnosis.Cause) -> String {
    switch area {
    case .cpuSaturation: String(localized: "CPU")
    case .memoryPressure: String(localized: "Memory")
    case .thermalPressure: String(localized: "Temperature")
    case .diskActivity: String(localized: "Disk")
    case .gpuLoad: String(localized: "GPU")
    case .powerDraw: String(localized: "Power")
    }
  }
  private static func symbol(_ area: Diagnosis.Cause) -> String {
    switch area {
    case .cpuSaturation: "cpu"
    case .memoryPressure: "memorychip"
    case .thermalPressure: "thermometer.medium"
    case .diskActivity: "internaldrive"
    case .gpuLoad: Reading.gpu.symbol
    case .powerDraw: "bolt"
    }
  }
}
