import StrataCore
import SwiftUI

struct ProcessHistorySection: View {
  let history: ObservedProcessHistory
  private var points: [ProcessHistoryPoint] { history.points }
  var body: some View {
    VStack(alignment: .leading, spacing: Design.Spacing.medium) {
      SectionHeading(String(localized: "Observed history"))
      if points.count < 2 {
        Text("History starts when you select this process.").footnoteStyle()
      } else {
        historyGraph(
          String(localized: "CPU"), value: ValueFormat.percent(points.last?.cpu), values: points.map(\.cpu),
          maximum: max(1, points.compactMap(\.cpu).max() ?? 1), color: Design.mint)
        historyGraph(
          String(localized: "Footprint"),
          value: points.last?.footprint.map(ValueFormat.bytes) ?? ReadingValue.unavailable,
          values: points.map { $0.footprint.map(Double.init) },
          maximum: max(1, points.compactMap(\.footprint).map(Double.init).max() ?? 1),
          color: Design.violet)
        historyGraph(
          String(localized: "Disk read"), value: ValueFormat.rate(points.last?.diskRead),
          values: points.map(\.diskRead),
          maximum: max(1000, points.compactMap(\.diskRead).max() ?? 0), color: .blue)
        historyGraph(
          String(localized: "Disk write"), value: ValueFormat.rate(points.last?.diskWritten),
          values: points.map(\.diskWritten),
          maximum: max(1000, points.compactMap(\.diskWritten).max() ?? 0), color: Design.violet)
        Text("Last 60s · CPU: 100% = one core. Gaps mean unavailable data.").footnoteStyle()
      }
    }
  }
  private func historyGraph(
    _ title: String, value: String, values: [Double?], maximum: Double, color: Color
  ) -> some View {
    VStack(spacing: Design.Spacing.small) {
      DetailRow(label: title, value: value)
      Sparkline(values: values, timestamps: points.map(\.uptime), color: color, maximum: maximum)
        .frame(height: 38).accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), observed history").accessibilityValue(value)
    }
  }
}

struct ProcessDetailsSection: View {
  let details: ProcessDetails?
  let loading: Bool
  var issue: String?
  let rowActions: ExplorerRowActions
  @State private var showArguments = false
  @State private var showMappings = false
  var body: some View {
    VStack(alignment: .leading, spacing: Design.Spacing.large) {
      if loading {
        ProgressView(String(localized: "Inspecting process details…")).controlSize(.small)
          .font(Design.Typography.footnote)
      } else if let issue {
        Text(issue).footnoteStyle()
      } else if let details {
        signing(details.signing)
        DisclosureGroup(String(localized: "Arguments"), isExpanded: $showArguments) {
          VStack(alignment: .leading, spacing: Design.Spacing.small) {
            if let arguments = details.arguments {
              ForEach(Array(arguments.enumerated()), id: \.offset) { index, argument in
                HStack(alignment: .top, spacing: Design.Spacing.small) {
                  Text(String(index)).foregroundStyle(.tertiary).frame(
                    width: 18, alignment: .trailing)
                  Text(argument.isEmpty ? "\"\"" : argument).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }.font(Design.Typography.footnote.monospaced())
              }
              if arguments.isEmpty { Text("No arguments reported.") }
            } else {
              Text(details.argumentsIssue ?? String(localized: "Arguments unavailable."))
            }
          }.padding(.top, Design.Spacing.small).foregroundStyle(.secondary)
        }
        DisclosureGroup(
          String(localized: "Executable mappings (\(details.executableMappings.count))"), isExpanded: $showMappings
        ) {
          VStack(alignment: .leading, spacing: Design.Spacing.small) {
            Text(
              "Executable file mappings observed at inspection. A shared cache path does not enumerate every library inside it."
            )
            .footnoteStyle()
            if let reason = details.mappingSummary.explanation {
              Text(reason).footnoteStyle()
            }
            ForEach(Array(details.executableMappings.prefix(150)), id: \.self) { path in
              Text(path).font(Design.Typography.footnote.monospaced()).textSelection(.enabled)
                .contextMenu { ExplorerActionButtons(actions: rowActions.file(path)) }
            }
            if details.executableMappings.count > 150 {
              Text("Showing 150 paths. Export the snapshot for the complete collected list.")
                .footnoteStyle()
            }
          }.padding(.top, Design.Spacing.small)
        }
        Text("Inspected \(details.inspectedAt.formatted(date: .omitted, time: .standard))")
          .font(Design.Typography.footnote.monospaced()).foregroundStyle(.tertiary)
      }
    }.font(Design.Typography.secondary)
  }
  private func signing(_ info: SigningInfo) -> some View {
    VStack(alignment: .leading, spacing: Design.Spacing.medium) {
      SectionHeading(String(localized: "Code signature"))
      Label(
        info.kind.title,
        systemImage: info.kind == .apple || info.kind == .signed
          ? "signature" : "doc.badge.gearshape"
      )
      .font(Design.Typography.itemTitle)
      if let identifier = info.identifier { DetailRow(label: String(localized: "Identifier"), value: identifier) }
      if let team = info.teamIdentifier { DetailRow(label: String(localized: "Team"), value: team) }
      if let reason = info.explanation { Text(reason).foregroundStyle(.secondary) }
      Text("Signing identifies code; it is not a safety verdict.").footnoteStyle()
    }
  }
}
