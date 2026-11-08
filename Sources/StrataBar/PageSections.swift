import StrataCore
import SwiftUI

// Every reading page follows one order: a notice when something needs attention, what is
// happening now, who is responsible, what it is made of, how it has been, the things the page
// manages, then one footnote and a way into the Explorer. These are the shared parts.

enum LeaderMeasure {
  case cpu, gpu, memory, power, diskWrites
  static let shownCount = 3
  var sort: ProcessSort {
    switch self {
    case .cpu: .cpu
    case .gpu: .gpu
    case .memory: .memory
    case .power: .power
    case .diskWrites: .diskWrite
    }
  }
  var title: LocalizedStringKey {
    switch self {
    case .cpu: "Using the most CPU"
    case .gpu: "Using the most GPU"
    case .memory: "Using the most memory"
    case .power: "Using the most power"
    case .diskWrites: "Writing the most"
    }
  }
  var idleText: LocalizedStringKey {
    switch self {
    case .cpu, .memory: "Collecting process information…"
    case .gpu: "Nothing is using the GPU right now."
    case .power: "Measured after the next reading."
    case .diskWrites: "Nothing is writing to disk right now."
    }
  }
  // Without the helper, system processes have no value for these.
  var needsExactReadings: Bool { sort.needsExactReadings }

  func rows(from families: [ProcessFamily]) -> [LeaderRow] {
    sort.ranked(families, limit: Self.shownCount).compactMap { family in
      let values = ProcessOrderingValues(family)
      // A rate of zero is no activity; only CPU and memory always have leaders.
      if self != .cpu, self != .memory, (measurement(values) ?? 0) <= 0 { return nil }
      return LeaderRow(
        id: family.id, name: family.root.displayName, memberCount: family.members.count,
        value: value(values, family: family))
    }
  }
  private func measurement(_ values: ProcessOrderingValues) -> Double? {
    switch self {
    case .cpu: values.cpu
    case .gpu: values.gpu
    case .memory: values.footprint.map(Double.init)
    case .power: values.watts
    case .diskWrites: values.diskWrite
    }
  }
  private func value(_ values: ProcessOrderingValues, family: ProcessFamily) -> String {
    switch self {
    case .cpu:
      ReadingValue.processRate(
        values.cpu.map { (family.hasMissingCPU ? "≥" : "") + ValueFormat.processCPU($0) },
        readable: family.isCPUReadable)
    case .gpu: values.gpu.map(ValueFormat.processCPU) ?? ReadingValue.notObserved
    case .memory:
      values.footprint.map { (family.hasMissingMemory ? "≥" : "") + ValueFormat.bytes($0) }
        ?? ReadingValue.unavailable
    case .power: values.watts.map(ValueFormat.watts) ?? ReadingValue.notObserved
    case .diskWrites: ValueFormat.rate(values.diskWrite)
    }
  }
}

struct LeaderRow: Identifiable {
  let id: ProcessIdentity
  let name: String
  var memberCount = 1
  let value: String
}

// "Using the most …": the processes behind a page's reading, each opening in the Explorer.
struct ProcessLeaders<Footer: View>: View {
  let title: LocalizedStringKey
  let rows: [LeaderRow]
  let emptyText: Text
  let select: (ProcessIdentity) -> Void
  var viewAll: (() -> Void)?
  @ViewBuilder var footer: Footer
  var body: some View {
    SurfaceCard {
      VStack(alignment: .leading, spacing: Design.Spacing.medium) {
        HStack {
          SectionHeading(title)
          Spacer(minLength: Design.Spacing.small)
          if let viewAll {
            Button(action: viewAll) {
              HStack(spacing: Design.Spacing.xSmall) {
                Text("View All")
                Image(systemName: Design.Symbol.explorer).font(Design.Typography.inlineSymbol)
              }.font(Design.Typography.footnote)
            }
            .buttonStyle(.plain).foregroundStyle(Design.mint).fixedSize()
          }
        }
        if rows.isEmpty {
          emptyText.font(Design.Typography.body).foregroundStyle(.secondary)
        }
        ForEach(rows) { row in
          Button { select(row.id) } label: { LeaderRowView(row: row) }.buttonStyle(.plain)
        }
        footer
      }
    }
  }
}

extension ProcessLeaders where Footer == EmptyView {
  init(
    title: LocalizedStringKey, rows: [LeaderRow], emptyText: Text,
    select: @escaping (ProcessIdentity) -> Void, viewAll: (() -> Void)? = nil
  ) {
    self.init(
      title: title, rows: rows, emptyText: emptyText, select: select, viewAll: viewAll,
      footer: { EmptyView() })
  }
}

// The leaders for a measure the Explorer can sort by.
struct MeasureLeaders: View {
  @ObservedObject var model: AppModel
  let measure: LeaderMeasure
  let openExplorer: (ExplorerDestination) -> Void
  var body: some View {
    ProcessLeaders(
      title: measure.title, rows: measure.rows(from: model.processFamilyRoots),
      emptyText: Text(measure.idleText),
      select: { openExplorer(.ranked(measure.sort, $0)) },
      viewAll: { openExplorer(.ranked(measure.sort, nil)) }
    ) {
      if measure.needsExactReadings {
        ExactReadingsOffer(visibility: model.fullVisibility, stacked: true).footnoteStyle()
      }
    }
  }
}

private struct LeaderRowView: View {
  let row: LeaderRow
  var body: some View {
    HStack(spacing: Design.Spacing.small) {
      ProcessAppIcon(identity: row.id, side: 27)
      VStack(alignment: .leading, spacing: Design.Spacing.xxSmall) {
        Text(row.name).font(Design.Typography.body).lineLimit(1)
        if row.memberCount > 1 {
          Text("\(row.memberCount) processes").font(Design.Typography.footnote)
            .foregroundStyle(.tertiary)
        }
      }
      Spacer()
      Text(row.value).font(Design.Typography.secondary.monospaced()).foregroundStyle(.secondary)
        .fixedSize()
      Image(systemName: "chevron.right").font(Design.Typography.inlineSymbol)
        .foregroundStyle(.tertiary)
    }.contentShape(Rectangle())
  }
}

// A page's list of things, such as volumes, outputs or devices, in one card with dividers.
struct ItemsCard<Accessory: View, Content: View>: View {
  let title: LocalizedStringKey
  @ViewBuilder var accessory: Accessory
  @ViewBuilder var content: Content
  var body: some View {
    SurfaceCard {
      VStack(alignment: .leading, spacing: Design.Spacing.small) {
        HStack {
          SectionHeading(title)
          Spacer(minLength: Design.Spacing.small)
          accessory
        }
        content
      }
    }
  }
}

extension ItemsCard where Accessory == EmptyView {
  init(title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
    self.init(title: title, accessory: { EmptyView() }, content: content)
  }
}

// Refresh sits in the heading of the list it refreshes; a spinner replaces it while busy.
struct RefreshAccessory: View {
  let isBusy: Bool
  var isDisabled = false
  let help: LocalizedStringKey
  let action: () -> Void
  var body: some View {
    if isBusy {
      ProgressView().controlSize(.mini)
    } else {
      Button(action: action) { Image(systemName: "arrow.clockwise") }
        .buttonStyle(.plain).foregroundStyle(.secondary).help(help).disabled(isDisabled)
    }
  }
}

struct ExplorerLink: View {
  let title: LocalizedStringKey
  let action: () -> Void
  var body: some View {
    Button(action: action) { Label(title, systemImage: Design.Symbol.explorer) }
      .buttonStyle(.glass)
  }
}

extension Reading {
  // One color per reading, shared by its tile, trend and history.
  var tint: Color {
    switch self {
    case .gpu: Design.orange
    case .memory: Design.violet
    case .network: .cyan
    default: Design.mint
    }
  }
}
