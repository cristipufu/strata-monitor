import StrataCore
import SwiftUI

struct OverviewOutliersCard: View {
  @ObservedObject var model: AppModel
  @ObservedObject private var actions: ProcessActionController
  let openExplorer: (ExplorerDestination) -> Void
  @State private var showingTen = false
  private let rowActions = ExplorerRowActions.system
  private static let defaultLimit = 5
  private static let expandedLimit = 10

  init(model: AppModel, openExplorer: @escaping (ExplorerDestination) -> Void) {
    self.model = model
    self.actions = model.processActions
    self.openExplorer = openExplorer
  }

  private var systemAlerts: [Diagnosis] {
    (model.historyRecorder?.diagnosis?.causes ?? []).filter {
      $0.cause != .cpuSaturation
    }
  }

  var body: some View {
    let ranked = model.activityOutliers
    let visible = Array(ranked.prefix(showingTen ? Self.expandedLimit : Self.defaultLimit))
    SurfaceCard {
      VStack(alignment: .leading, spacing: Design.Spacing.medium) {
        header(totalCount: ranked.count)
        if !systemAlerts.isEmpty {
          VStack(alignment: .leading, spacing: Design.Spacing.xSmall) {
            ForEach(systemAlerts, id: \.cause) { alert in
              HStack(spacing: Design.Spacing.xSmall) {
                Circle().fill(Design.orange).frame(width: 6, height: 6)
                Text(alert.title).font(Design.Typography.label).foregroundStyle(Design.orange)
                if let detail = alert.evidence.first {
                  Text(verbatim: "· \(detail)").font(Design.Typography.footnote)
                    .foregroundStyle(.secondary).lineLimit(1)
                }
              }
            }
          }
        }
        if let prepared = actions.prepared {
          InlineActionConfirmation(
            action: prepared, confirm: actions.confirm, cancel: actions.dismissConfirmation)
        }
        if visible.isEmpty {
          Text("Collecting process information…")
            .font(Design.Typography.body).foregroundStyle(.secondary)
        } else {
          VStack(alignment: .leading, spacing: Design.Spacing.small) {
            ForEach(visible) { outlier in
              ActivityOutlierRow(
                outlier: outlier, actions: actions, rowActions: rowActions,
                select: { select(outlier) }, openExplorer: openExplorer)
            }
          }
        }
        if LeaderMeasure.cpu.needsExactReadings {
          ExactReadingsOffer(visibility: model.fullVisibility, stacked: true).footnoteStyle()
        }
      }
    }
    .onDisappear {
      if actions.prepared != nil {
        actions.dismissConfirmation()
      }
    }
  }

  private func header(totalCount: Int) -> some View {
    HStack(spacing: Design.Spacing.small) {
      SectionHeading(String(localized: "Top issues & activity"))
      Spacer(minLength: Design.Spacing.small)
      if totalCount > Self.defaultLimit || showingTen {
        Button {
          showingTen.toggle()
        } label: {
          Text(showingTen ? String(localized: "Show 5") : String(localized: "Show 10"))
            .font(Design.Typography.footnote)
        }
        .buttonStyle(.plain).foregroundStyle(.secondary).fixedSize()
      }
      Button {
        openExplorer(.ranked(.cpu, nil))
      } label: {
        HStack(spacing: Design.Spacing.xSmall) {
          Text("View All")
          Image(systemName: Design.Symbol.explorer).font(Design.Typography.inlineSymbol)
        }.font(Design.Typography.footnote)
      }
      .buttonStyle(.plain).foregroundStyle(Design.mint).fixedSize()
    }
  }

  private func select(_ outlier: ActivityOutlier) {
    if let folder = outlier.workingDirectory, outlier.rootCount > 1 {
      openExplorer(.folderProcesses(folder, outlier.id))
    } else if outlier.isFamilyTree {
      openExplorer(.family(outlier.id))
    } else {
      openExplorer(.processes(outlier.id))
    }
  }
}

private struct InlineActionConfirmation: View {
  let action: ProcessActionConfirmation
  let confirm: () -> Void
  let cancel: () -> Void

  private var headline: String {
    action.count > 1
      ? String(localized: "\(action.title) \(action.name) (\(action.count) processes)?")
      : String(localized: "\(action.title) \(action.name) (PID \(String(action.identity.pid)))?")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Design.Spacing.small) {
      Text(headline).font(Design.Typography.itemTitle)
        .fixedSize(horizontal: false, vertical: true)
      Text(action.explanation).footnoteStyle()
        .fixedSize(horizontal: false, vertical: true)
      HStack(spacing: Design.Spacing.small) {
        Spacer(minLength: 0)
        Button("Cancel", action: cancel).buttonStyle(.glass).controlSize(.small)
        Button(action.title, role: .destructive, action: confirm)
          .buttonStyle(.glassProminent).controlSize(.small).tint(.red)
      }
    }
    .padding(Design.Spacing.medium)
    .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: Design.Radius.banner))
  }
}

private struct ActivityOutlierRow: View {
  let outlier: ActivityOutlier
  @ObservedObject var actions: ProcessActionController
  let rowActions: ExplorerRowActions
  let select: () -> Void
  let openExplorer: (ExplorerDestination) -> Void

  private var primaryProcess: ProcessSample? {
    outlier.targetProcesses.first { $0.id == outlier.id } ?? outlier.targetProcesses.first
  }

  var body: some View {
    HStack(spacing: Design.Spacing.small) {
      Button(action: select) {
        HStack(spacing: Design.Spacing.small) {
          Circle().fill(dotColor).frame(width: 6, height: 6)
          ProcessAppIcon(identity: outlier.id, side: 27)
          VStack(alignment: .leading, spacing: Design.Spacing.xxSmall) {
            Text(outlier.title).font(Design.Typography.body).lineLimit(1)
            Text(outlier.subtitle)
              .font(Design.Typography.footnote)
              .foregroundStyle(subtitleColor)
              .lineLimit(1)
              .truncationMode(.middle)
          }
          Spacer(minLength: Design.Spacing.xSmall)
          Text(outlier.primaryMetric)
            .font(Design.Typography.secondary.monospaced())
            .foregroundStyle(outlier.isPaused ? Design.yellow : .secondary)
            .fixedSize()
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help(tooltip)

      Menu {
        menuItems
      } label: {
        Image(systemName: "ellipsis.circle")
          .font(Design.Typography.controlSymbol)
          .foregroundStyle(.secondary)
          .frame(width: 22, height: 22)
          .contentShape(Rectangle())
      }
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
      .fixedSize()
      .help(String(localized: "Process Actions"))
    }
    .contextMenu { menuItems }
  }

  private var dotColor: Color {
    if outlier.isPaused { return Design.yellow }
    switch outlier.severity {
    case .critical: return .red
    case .elevated: return Design.orange
    case .normal: return Design.mint
    }
  }

  private var subtitleColor: Color {
    switch outlier.severity {
    case .critical: .red
    case .elevated: Design.orange
    case .normal: .secondary
    }
  }

  private var tooltip: String {
    var lines = ["\(outlier.title) — \(outlier.primaryMetric)", outlier.subtitle]
    if let folder = outlier.workingDirectory, folder != outlier.subtitle {
      lines.append(folder)
    }
    return lines.joined(separator: "\n")
  }

  @ViewBuilder private var menuItems: some View {
    Button(String(localized: "Show in Explorer"), action: select)
    if let folder = outlier.workingDirectory, !folder.isEmpty {
      Button(String(localized: "Filter Explorer to Folder")) {
        openExplorer(.folderProcesses(folder, outlier.id))
      }
      Button(String(localized: "Reveal Folder in Finder")) {
        rowActions.reveal(URL(fileURLWithPath: folder))
      }
      Button(String(localized: "Copy Folder Path")) {
        rowActions.copy(folder)
      }
    }
    Divider()
    processSignalItems
    if let primary = primaryProcess {
      Divider()
      ExplorerActionButtons(actions: rowActions.process(primary))
    }
  }

  @ViewBuilder private var processSignalItems: some View {
    let currentPID = ProcessInfo.processInfo.processIdentifier
    let currentUser = getuid()
    let targets = outlier.targetProcesses
    let name = primaryProcess?.name ?? outlier.title
    let resumable = ProcessActionPolicy.eligible(
      .resume, in: targets, currentPID: currentPID, currentUser: currentUser)
    let pausable = ProcessActionPolicy.eligible(
      .pause, in: targets, currentPID: currentPID, currentUser: currentUser)
    let terminable = ProcessActionPolicy.eligible(
      .terminate, in: targets, currentPID: currentPID, currentUser: currentUser)
    let killable = ProcessActionPolicy.eligible(
      .forceQuit, in: targets, currentPID: currentPID, currentUser: currentUser)

    if targets.count == 1, let single = primaryProcess, actions.canQuitApplication(single) {
      Button(String(localized: "Quit…")) { actions.requestApplicationQuit(single) }
        .disabled(actions.isBusy)
    }
    if !resumable.isEmpty {
      Button(
        resumable.count > 1
          ? String(localized: "Resume (\(resumable.count) processes)")
          : String(localized: "Resume")
      ) {
        actions.request(resumable, name: name, signal: .resume)
      }.disabled(actions.isBusy)
    } else {
      Button(
        pausable.count > 1
          ? String(localized: "Pause (\(pausable.count) processes)")
          : String(localized: "Pause")
      ) {
        actions.request(pausable, name: name, signal: .pause)
      }.disabled(actions.isBusy || pausable.isEmpty)
    }
    Button(
      terminable.count > 1
        ? String(localized: "Terminate (\(terminable.count) processes)…")
        : String(localized: "Terminate…")
    ) {
      actions.request(terminable, name: name, signal: .terminate)
    }.disabled(actions.isBusy || terminable.isEmpty)
    Button(
      killable.count > 1
        ? String(localized: "Force Quit (\(killable.count) processes)…")
        : String(localized: "Force Quit…"),
      role: .destructive
    ) {
      actions.request(killable, name: name, signal: .forceQuit)
    }.disabled(actions.isBusy || killable.isEmpty)
  }
}
