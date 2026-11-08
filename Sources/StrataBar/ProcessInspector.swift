import StrataCore
import SwiftUI

struct ProcessInspector: View {
  @ObservedObject var model: AppModel
  let identity: ProcessIdentity?
  let rowActions: ExplorerRowActions
  let selectProcess: (ProcessIdentity?) -> Void
  @StateObject private var sampling = ProcessSamplingController()
  private var liveProcess: ProcessSample? { model.processes.first { $0.id == identity } }
  private var process: ProcessSample? {
    liveProcess ?? (model.observedProcess?.id == identity ? model.observedProcess : nil)
  }
  private var relatedResources: [ProcessResource] {
    model.resources.resources.filter { $0.owner == identity }
  }
  var body: some View {
    ScrollView {
      if let process {
        VStack(alignment: .leading, spacing: Design.Spacing.large) {
          ProcessAppIcon(identity: process.id, side: 44)
            .padding(.top, Design.Spacing.small)
          VStack(alignment: .leading, spacing: Design.Spacing.xSmall) {
            Text(process.name).font(Design.Typography.pageTitle).textSelection(.enabled)
            Text("PID \(String(process.id.pid))").font(Design.Typography.secondary.monospaced())
              .foregroundStyle(.secondary)
            if process.runState == .stopped {
              Label("Paused", systemImage: "pause.circle").font(Design.Typography.label)
                .foregroundStyle(Design.yellow)
            }
          }.contextMenu { ExplorerActionButtons(actions: rowActions.process(process)) }
          if liveProcess == nil {
            Label("Ended or unavailable · last observed values", systemImage: "clock.badge.xmark")
              .footnoteStyle()
          }
          if model.processHistory.identity == process.id {
            ProcessHistorySection(history: model.processHistory)
          }
          SurfaceCard {
            VStack(spacing: Design.Spacing.medium) {
              DetailRow(label: "CPU", value: process.cpuDescription)
              DetailRow(
                label: "Footprint",
                value: process.footprintBytes.map(ValueFormat.bytes) ?? ReadingValue.unavailable)
              DetailRow(
                label: "Resident",
                value: process.residentBytes.map(ValueFormat.bytes) ?? ReadingValue.unavailable)
              DetailRow(
                label: "Peak footprint",
                value: process.activity.map { ValueFormat.bytes($0.peakFootprintBytes) }
                  ?? ReadingValue.unavailable)
              DetailRow(
                label: "Power",
                value: ReadingValue.processRate(
                  process.watts.map(ValueFormat.watts), readable: process.activity != nil))
              DetailRow(
                label: "Wakeups",
                value: ReadingValue.processRate(
                  process.wakeupsPerSecond.map(ValueFormat.perSecond),
                  readable: process.activity != nil))
              DetailRow(
                label: "Performance cores",
                value: ReadingValue.processRate(
                  process.performanceCoreShare.map { ValueFormat.percent($0) },
                  readable: process.activity != nil))
              DetailRow(
                label: "GPU",
                value: process.gpuPercent.map(ValueFormat.processCPU) ?? ReadingValue.notObserved)
              DetailRow(
                label: "CPU time",
                value: process.cpuTimeNanoseconds.map { ValueFormat.cpuTime(nanoseconds: $0) }
                  ?? ReadingValue.unavailable)
              DetailRow(
                label: "Threads",
                value: process.threads.map(String.init) ?? ReadingValue.unavailable)
              DetailRow(
                label: "Disk read",
                value: ReadingValue.processRate(
                  process.diskReadBytesPerSecond.map { ValueFormat.rate($0) },
                  readable: process.diskReadBytes != nil))
              DetailRow(
                label: "Disk write",
                value: ReadingValue.processRate(
                  process.diskWrittenBytesPerSecond.map { ValueFormat.rate($0) },
                  readable: process.diskWrittenBytes != nil))
              DetailRow(
                label: "User",
                value: process.userName.map { "\($0) (\(process.userID))" } ?? String(process.userID))
              if let project = process.project { DetailRow(label: "Project", value: project) }
              DetailRow(label: "Kind", value: ProcessColumns.kind(translated: process.isTranslated))
              DetailRow(
                label: "Started",
                value: Date(timeIntervalSince1970: Double(process.id.startSeconds)).formatted(
                  date: .abbreviated, time: .shortened))
            }
          }
          if process.lacksExactReadings {
            ExactReadingsOffer(visibility: model.fullVisibility, stacked: true).footnoteStyle()
          }
          if let live = liveProcess, ProcessSamplingController.canSample(live) {
            ProcessSampleSection(controller: sampling, process: live)
          }
          if !process.path.isEmpty {
            VStack(alignment: .leading, spacing: Design.Spacing.medium) {
              SectionHeading("Executable")
              Text(process.path).font(Design.Typography.footnote.monospaced())
                .foregroundStyle(.secondary).textSelection(.enabled).contextMenu {
                ExplorerActionButtons(actions: rowActions.file(process.path))
              }
              HStack {
                ExplorerActionButtons(actions: rowActions.file(process.path))
              }.buttonStyle(.glass).controlSize(.small)
            }
          }
          family(process)
          ProcessDetailsSection(
            details: model.processDetails?.identity == process.id ? model.processDetails : nil,
            loading: model.isLoadingDetails, issue: model.detailsIssue, rowActions: rowActions
          )
          .id(process.id)
          ProcessActionButtons(actions: model.processActions, process: process)
            .disabled(liveProcess == nil)
          VStack(alignment: .leading, spacing: Design.Spacing.medium) {
            HStack {
              SectionHeading("Open resources")
              Spacer()
              if model.isInspecting {
                ProgressView().controlSize(.mini)
              } else {
                Button {
                  model.inspect(process)
                  model.inspectDetails(process)
                } label: {
                  Image(systemName: "arrow.clockwise")
                }.buttonStyle(.plain).help("Inspect process resources").disabled(liveProcess == nil)
              }
            }
            if relatedResources.isEmpty {
              Text(
                model.isInspecting
                  ? "Inspecting…"
                  : model.resources.summary.explanation ?? "No resources in this snapshot."
              )
              .footnoteStyle()
            }
            ForEach(Array(relatedResources.prefix(100))) { resource in
              VStack(alignment: .leading, spacing: Design.Spacing.xSmall) {
                HStack {
                  Text(resource.kind.title).textCase(.uppercase)
                    .font(Design.Typography.sectionHeading).foregroundStyle(Design.mint)
                  Spacer()
                  Text(resource.state).footnoteStyle()
                }
                Group {
                  Text(resource.location).textSelection(.enabled)
                  if let endpoint = resource.remoteEndpoint { Text("→ \(endpoint)") }
                }.font(Design.Typography.footnote.monospaced()).foregroundStyle(.secondary)
              }.padding(.vertical, Design.Spacing.xSmall).contextMenu {
                ExplorerActionButtons(actions: rowActions.resource(resource))
              }
            }
            if relatedResources.count > 100 {
              Text("Showing 100 of \(relatedResources.count) resources").footnoteStyle()
            }
          }
        }.padding(Design.Spacing.xLarge)
      } else {
        EmptyState(
          symbol: identity == nil ? "cursorarrow.rays" : "clock.badge.xmark",
          title: identity == nil ? "Follow a process" : "Process no longer available",
          detail: identity == nil
            ? "Select a process or port to explore the next layer."
            : "It may have ended, or macOS may restrict its information.")
      }
    }.background(.background.opacity(0.35))
    .onChange(of: identity) { sampling.cancel() }
    .onDisappear { sampling.cancel() }
  }
  @ViewBuilder private func family(_ process: ProcessSample) -> some View {
    let families = model.processFamilies
    let parent = families.parent(of: process.id)
    let children = families.directChildren(of: process.id)
    if parent != nil || !children.isEmpty {
      VStack(alignment: .leading, spacing: Design.Spacing.medium) {
        SectionHeading("Process family")
        if let parent {
          Button {
            selectProcess(parent.id)
          } label: {
            Label(parent.name, systemImage: "arrow.turn.up.left").lineLimit(1)
          }.buttonStyle(.plain).font(Design.Typography.footnote)
        }
        ForEach(Array(children.prefix(20))) { child in
          Button {
            selectProcess(child.id)
          } label: {
            Label(child.name, systemImage: "arrow.turn.down.right").lineLimit(1)
          }.buttonStyle(.plain).font(Design.Typography.footnote)
        }
        if children.count > 20 {
          Text("\(children.count - 20) more children").footnoteStyle()
        }
        if let family = families.subtree(of: process.id), family.members.count > 1 {
          DetailRow(label: "Subtree", value: "\(family.members.count) processes")
          DetailRow(
            label: "CPU subtotal",
            value: ReadingValue.processRate(
              family.cpuPercent.map(ValueFormat.processCPU), readable: family.isCPUReadable))
          DetailRow(
            label: "Footprint subtotal",
            value: family.footprintBytes.map(ValueFormat.bytes) ?? ReadingValue.unavailable)
          Text(
            family.hasMissingCPU || family.hasMissingMemory
              ? "Some measurements are unavailable. Totals include measured members only."
              : "Includes this process and its observed descendants, each counted once."
          )
          .footnoteStyle()
        }
      }
    }
  }
}

struct ProcessActionButtons: View {
  @ObservedObject var actions: ProcessActionController
  let process: ProcessSample
  var body: some View {
    HStack {
      Menu {
        Button("Quit…") { actions.requestApplicationQuit(process) }
          .disabled(!actions.canQuitApplication(process))
        Divider()
        if process.runState == .stopped {
          signalButton(.resume, title: "Resume")
        } else {
          signalButton(.pause, title: "Pause")
        }
        Divider()
        signalButton(.terminate, title: "Terminate…")
        signalButton(.forceQuit, title: "Force Quit…", role: .destructive)
      } label: {
        Label("Process Actions", systemImage: "stop.circle")
      }
      .menuStyle(.borderlessButton)
      .disabled(
        actions.isBusy
          || !ProcessActionPolicy.allows(
            process, currentPID: ProcessInfo.processInfo.processIdentifier, currentUser: getuid())
      )
      if actions.isBusy { ProgressView().controlSize(.mini) }
    }
  }
  private func signalButton(_ signal: ProcessSignal, title: String, role: ButtonRole? = nil)
    -> some View
  {
    Button(title, role: role) { actions.request(process, signal: signal) }
      .disabled(
        !ProcessActionPolicy.allows(
          signal, for: process, currentPID: ProcessInfo.processInfo.processIdentifier,
          currentUser: getuid()))
  }
}

// Attached at the window's root so an action started from any row or menu is confirmed in view.
struct ProcessActionConfirmationDialog: ViewModifier {
  @ObservedObject var actions: ProcessActionController
  func body(content: Content) -> some View {
    content.confirmationDialog(
      actions.prepared.map { "\($0.title) \($0.name) (PID \($0.identity.pid))?" }
        ?? "Process action",
      isPresented: Binding(
        get: { actions.prepared != nil }, set: { if !$0 { actions.dismissConfirmation() } }),
      titleVisibility: .visible
    ) {
      if let action = actions.prepared {
        Button(action.title, role: .destructive) { actions.confirm() }
      }
      Button("Cancel", role: .cancel) { actions.dismissConfirmation() }
    } message: {
      Text(actions.prepared?.explanation ?? "")
    }
  }
}
