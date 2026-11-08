import StrataCore
import SwiftUI

struct ExplorerView: View {
  @ObservedObject var model: AppModel
  @ObservedObject var navigation: ExplorerNavigation
  @State private var resourceSelection: String?
  @FocusState private var searchFocused: Bool
  @State private var sortedProcesses = SortedRowCache<ProcessSample, ProcessOrder> { $1.sorted($0) }
  @State private var processTrees = ProcessTreeCache()
  @StateObject private var applications = RunningApplications()
  @ObservedObject var exporter: SnapshotExportController
  private let rowActions = ExplorerRowActions.system
  private var section: ExplorerSection? { navigation.section }
  private var query: String { navigation.query }
  private var selectedProcess: ProcessIdentity? { navigation.identity }
  private var selectionRequest: SelectedInspectionRequest {
    SelectedInspectionRequest(
      identity: selectedProcess, path: selected?.path, includeResources: section == .processes,
      revision: navigation.revision)
  }
  private var processContent: ProcessBrowser.Content {
    let filter = navigation.processFilter
    let context = ProcessFilterContext(
      currentUser: getuid(),
      applicationPIDs: filter == .applications ? applications.processIdentifiers : [])
    if navigation.grouping == .families {
      return .families(
        processTrees.snapshot(
          of: model.processes, families: model.processFamilies, query: query, filter: filter,
          context: context, order: navigation.processOrder))
    }
    // Sorting before filtering keys the cache on the sample, which changes only every reading.
    let search = ExplorerQuery(query)
    return .processes(
      sortedProcesses.rows(model.processes, orderedBy: navigation.processOrder).filter {
        search.matches($0) && filter.includes($0, in: context)
      })
  }
  private var visibleProcesses: [ProcessSample] {
    switch processContent {
    case .processes(let rows): rows
    case .families(let snapshot): snapshot.rows.map(\.process)
    }
  }
  private var visibleResources: [ProcessResource] {
    model.resources.resources.filter(isVisible)
  }
  private var inspectorPresented: Binding<Bool> {
    Binding(
      get: { navigation.showsInspector && section?.reading == nil },
      set: { navigation.showsInspector = $0 })
  }
  private var processSortKey: Binding<ProcessSort> {
    Binding(
      get: { navigation.processOrder.key },
      set: { navigation.processOrder = ProcessOrder($0) })
  }
  var body: some View {
    NavigationSplitView {
      sidebar.navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
    } detail: {
      detail.frame(minWidth: 400).navigationTitle(section?.rawValue ?? "Processes")
    }
    .inspector(isPresented: inspectorPresented) {
      ProcessInspector(
        model: model, identity: selectedProcess, rowActions: rowActions,
        selectProcess: selectProcess
      )
      .inspectorColumnWidth(min: 260, ideal: 290, max: 360)
    }
    .frame(minHeight: 600)
    .modifier(ProcessActionConfirmationDialog(actions: model.processActions))
    .task(id: section) { model.setDemand(AppModel.networkUsageDemand, active: section == .network) }
    .onDisappear { model.setDemand(AppModel.networkUsageDemand, active: false) }
    .tint(Design.accent(model.profile.accent))
    .task(id: navigation.resourceRequest) {
      if section == .ports || section == .files {
        model.inspect(socketsOnly: section == .ports)
      } else if section?.reading != nil {
        model.cancelInspection()
      }
    }
    .task(id: selectionRequest) {
      model.trackProcess(selectedProcess)
      if let process = selected {
        if section == .processes { model.inspect(process) }
        model.inspectDetails(process)
      } else if section == .processes {
        model.cancelInspection()
      }
    }
    .onChange(of: resourceSelection) { _, id in
      if let resource = model.resources.resources.first(where: { $0.id == id }) {
        navigation.identity = resource.owner
      }
    }
    .safeAreaInset(edge: .bottom) {
      if let message = model.errorMessage {
        OperationErrorBanner(message: message) { model.errorMessage = nil }
          .padding(Design.Spacing.medium)
      }
    }
  }
  private var selected: ProcessSample? { model.processes.first { $0.id == selectedProcess } }
  private static let exploreSections = 4
  @ViewBuilder private var detail: some View {
    if section == .timeline {
      EpisodeTimeline(model: model, select: { navigation.open(.processes($0)) })
    } else if let reading = section?.reading {
      ScrollView {
        ReadingContent(
          model: model, reading: reading, openExplorer: navigation.open, showsHeading: false
        )
        .padding(Design.Spacing.xLarge).frame(maxWidth: 720)
      }
      .frame(maxWidth: .infinity)
    } else {
      VStack(spacing: 0) {
        if section == .files, let scopeTitle = navigation.resourceScopeTitle {
          resourceScope(scopeTitle)
        }
        if section == .processes {
          let content = processContent
          ProcessBrowser(
            content: content, scan: model.sample?.processScan, query: query,
            order: $navigation.processOrder, selection: $navigation.identity,
            actions: rowActions.process)
          statusBar(
            [
              "\(matchingCount(content)) matching processes",
              model.sample?.processCoverage?.title,
              "updates every \(model.preferences.updateSpeed.seconds)s",
            ].compactMap { $0 }.joined(separator: " · "),
            partialExplanation: model.sample?.processScan?.explanation,
            offersExactReadings: navigation.processOrder.key.needsExactReadings)
        } else {
          ResourceBrowser(
            resources: model.resources.resources, listsPorts: section == .ports,
            summary: model.resources.summary, isInspecting: model.isInspecting,
            isVisible: isVisible, order: $navigation.resourceOrder, selection: $resourceSelection,
            actions: { resource in
              rowActions.resource(resource, inspectOwner: selectProcess)
                + rowActions.freePort(
                  resource, owner: model.processes.first { $0.id == resource.owner },
                  terminate: terminate)
            })
          statusBar(
            "\(visibleResources.count) resources · snapshot",
            partialExplanation: model.resources.summary.explanation)
        }
      }
      .toolbar { toolbar }
      .searchable(
        text: $navigation.query,
        prompt: section == .processes ? "Name, path, or pid:123" : "Process, path, port:3000")
      .searchFocused($searchFocused)
      .onChange(of: navigation.searchFocusRequest) { searchFocused = true }
    }
  }
  private var sidebar: some View {
    VStack(spacing: 0) {
      List(selection: $navigation.section) {
        Section("Explore") {
          ForEach(Array(ExplorerSection.allCases.prefix(Self.exploreSections))) { item in
            Label(item.rawValue, systemImage: item.symbol).tag(item)
          }
        }
        Section("This Mac") {
          ForEach(Array(ExplorerSection.allCases.dropFirst(Self.exploreSections))) { item in
            Label(item.rawValue, systemImage: item.symbol).tag(item)
          }
        }
      }.listStyle(.sidebar)
      VStack(alignment: .leading, spacing: Design.Spacing.medium) {
        StrataGlyph(model: model, size: 25, animatesReadings: false)
        Text("Every layer, understood.").font(Design.Typography.secondary)
          .foregroundStyle(.secondary)
        HStack {
          Text("CPU")
          Spacer()
          Text(model.value(for: .cpu)).monospacedDigit()
        }.footnoteStyle()
        Sparkline(
          values: model.historyValues(for: .cpu), timestamps: model.history.points.map(\.uptime)
        ).frame(height: 26)
      }.padding(Design.Spacing.large)
    }
  }
  private func resourceScope(_ title: String) -> some View {
    HStack {
      Label(title, systemImage: navigation.volumeScope == nil ? "folder" : "internaldrive")
        .lineLimit(2).truncationMode(.middle).help(
          navigation.volumeScope?.mountPath ?? navigation.pathScope?.path ?? "")
      Spacer()
      Button("Clear") { navigation.clearResourceScope() }.buttonStyle(.plain)
    }.footnoteStyle().padding(Design.Spacing.medium).background(.bar)
  }
  private func statusBar(
    _ summary: String, partialExplanation: String?, offersExactReadings: Bool = false
  ) -> some View {
    HStack(spacing: Design.Spacing.small) {
      Circle().fill(Design.mint).frame(width: 5, height: 5)
      Text(summary)
      Spacer()
      if offersExactReadings { ExactReadingsOffer(visibility: model.fullVisibility) }
      if model.isInspecting {
        ProgressView().controlSize(.mini)
        Button("Cancel") { model.cancelInspection() }.buttonStyle(.plain)
      }
      if let partialExplanation {
        Label("Partial snapshot", systemImage: "exclamationmark.circle").help(partialExplanation)
      }
    }.footnoteStyle().padding(.horizontal, Design.Spacing.medium)
      .padding(.vertical, Design.Spacing.small).background(.bar)
  }
  @ToolbarContentBuilder private var toolbar: some ToolbarContent {
    ToolbarItemGroup {
      if section == .processes {
        Picker("Process view", selection: $navigation.grouping) {
          Text("Processes").tag(ProcessGrouping.individual)
          Text("Families").tag(ProcessGrouping.families)
        }.pickerStyle(.segmented).help("Browse individual processes or their observed parent tree")
        Picker("Show", selection: $navigation.processFilter) {
          ForEach(ProcessFilter.allCases, id: \.self) { Text($0.title).tag($0) }
        }.pickerStyle(.menu).fixedSize().help("Choose which processes to show")
        Menu {
          Picker("Sort", selection: processSortKey) {
            ForEach(ProcessSort.allCases, id: \.self) { Text($0.title).tag($0) }
          }
        } label: {
          Image(systemName: "arrow.up.and.down.text.horizontal")
        }.help("Sort processes")
      }
      Button {
        refreshResources()
      } label: {
        Image(systemName: "arrow.clockwise")
      }.help("Refresh inspection")
      Menu {
        Button("Export Snapshot…") { exportSnapshot() }
        if model.processDetails?.arguments != nil {
          Button("Export Including Selected Arguments…") { exportSnapshot(includeArguments: true) }
        }
      } label: {
        Image(systemName: "square.and.arrow.up")
      }
      .disabled(exporter.isBusy || (model.processes.isEmpty && model.resources.resources.isEmpty))
      .help("Export visible results and selected process as JSON")
      Button {
        navigation.showsInspector.toggle()
      } label: {
        Image(systemName: "sidebar.right")
      }.help("Toggle inspector")
    }
  }
  private func terminate(_ process: ProcessSample) {
    navigation.identity = process.id
    model.processActions.request(process, signal: .terminate)
  }
  private func matchingCount(_ content: ProcessBrowser.Content) -> Int {
    switch content {
    case .processes(let rows): rows.count
    case .families(let snapshot): snapshot.matchingCount
    }
  }
  private func isVisible(_ resource: ProcessResource) -> Bool {
    (section != .ports || resource.ownsLocalPort)
      && (section != .files || navigation.includesResource(resource))
      && ExplorerQuery(query).matches(resource)
  }
  private func selectProcess(_ identity: ProcessIdentity?) {
    navigation.open(
      section == .processes && navigation.grouping == .families
        ? .family(identity) : .processes(identity))
  }
  private func exportSnapshot(includeArguments: Bool = false) {
    let scope: InspectionExportScope =
      section == .ports ? .ports : section == .files ? .resources : .processes
    let exportedResources =
      scope == .processes
      ? model.resources.resources.filter { $0.owner == selectedProcess } : visibleResources
    let owners = Set(exportedResources.map(\.owner))
    let exportedProcesses =
      scope == .processes ? visibleProcesses : model.processes.filter { owners.contains($0.id) }
    let snapshot = InspectionExport(
      scope: scope, query: query, processes: exportedProcesses,
      processScan: model.sample?.processScan,
      resources: ResourceReport(
        resources: exportedResources,
        summary: scope == .processes && selectedProcess == nil
          ? ScanSummary() : model.resources.summary),
      selectedDetails: model.processDetails?.identity == selectedProcess
        ? model.processDetails : nil,
      observedHistory: model.processHistory.identity == selectedProcess
        ? model.processHistory.points : [],
      includeArguments: includeArguments, processSampleUptime: model.sample?.uptime,
      resourceInspectedAt: model.resourceInspectedAt,
      resourcePathPrefix: section == .files ? navigation.pathScope?.path : nil,
      processGrouping: navigation.grouping,
      resourceVolume: section == .files ? navigation.volumeScope : nil)
    exporter.present(snapshot, in: NSApp.keyWindow) { model.errorMessage = $0 }
  }
  private func refreshResources() {
    if section == .ports || section == .files {
      model.inspect(socketsOnly: section == .ports)
    } else if let process = selected {
      model.inspect(process)
      model.inspectDetails(process)
    } else {
      model.cancelInspection()
    }
  }
}
