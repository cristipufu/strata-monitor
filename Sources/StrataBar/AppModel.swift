import AppKit
import Combine
import StrataCore
import StrataSystem

@MainActor
final class AppModel: ObservableObject {
  @Published private(set) var sample: SystemSample?
  @Published private(set) var devices: DeviceSnapshot?
  @Published private(set) var history = RecentHistory()
  // For demo data only: earlier readings, oldest first, so the live charts start full.
  func prefillRecentHistory(_ samples: [SystemSample]) {
    for sample in samples { history.append(sample) }
  }
  @Published var page: Reading = .overview {
    didSet { updateReadingPageDemand() }
  }
  @Published var preferences: Preferences {
    didSet {
      if preferences.selectedProfile != oldValue.selectedProfile
        || preferences.profiles != oldValue.profiles
      {
        preferences.hasSelectedInitialPreset = true
      }
      persistPreferences()
      bluetooth.setDemand(.indicator, active: preferences.activeProfile.center == .bluetooth)
      if !stopped { historyRecorder?.apply(preferences.historyKeeping) }
    }
  }
  @Published private(set) var moment: StatusMoment?
  @Published private(set) var resources = ResourceReport(resources: [])
  @Published private(set) var isInspecting = false
  @Published private(set) var processDetails: ProcessDetails?
  @Published private(set) var isLoadingDetails = false
  @Published private(set) var detailsIssue: String?
  @Published private(set) var observedProcess: ProcessSample?
  @Published private(set) var resourceInspectedAt: Date?
  @Published private(set) var processHistory = ObservedProcessHistory()
  @Published private(set) var connection: ConnectionState = .unknown
  @Published private(set) var signalStrength: SignalStrength?
  @Published var errorMessage: String?
  let power = KeepAwakeController()
  let bluetooth: BluetoothController
  let wifi: WiFiController
  let displays: DisplayController
  let menuBarItems: MenuBarItemsController
  private var bluetoothChanges: AnyCancellable?
  private var wifiChanges: AnyCancellable?
  private let collector: any SystemSampling
  private let powerCollector: any PowerSampling
  @Published private(set) var powerSnapshot: PowerSnapshot?
  private let networkUsageCollector: any NetworkUsageSampling
  @Published private(set) var networkUsage = NetworkUsageState.measuring
  private let deviceCollector: any DeviceControlling
  private let deviceEvents: (any DeviceEventObserving)?
  private let resourceCollector: any ResourceInspecting
  // Every process reading and inspection goes through these, so the optional helper and the
  // `ps` fallback serve the readings panel, the Explorer and inspections alike.
  private let processSources: MergedProcessInventory
  private let resourceSources: MergedResourceInspector
  // Only the running app passes one; previews and tests never write history files.
  let historyRecorder: HistoryRecorder?
  private(set) lazy var fullVisibility = FullVisibilityController(
    processes: processSources, resources: resourceSources)
  private let processControl: any ProcessControlling
  private let inventoryCollector: any ProcessListing
  private let detailsCollector: any ProcessDetailInspecting
  private(set) lazy var processActions = ProcessActionController(
    service: processControl, paused: savedPausedProcesses(),
    savePaused: { [weak self] in self?.savePausedProcesses($0) }
  ) { [weak self] message in
    self?.errorMessage = message
  }
  private func savedPausedProcesses() -> PausedProcessLedger {
    guard persistsPreferences,
      let data = defaults.data(forKey: ApplicationPreferences.pausedProcessesKey)
    else { return PausedProcessLedger() }
    return (try? JSONDecoder().decode(PausedProcessLedger.self, from: data)) ?? PausedProcessLedger()
  }
  private func savePausedProcesses(_ ledger: PausedProcessLedger) {
    guard persistsPreferences else { return }
    if ledger.identities.isEmpty {
      defaults.removeObject(forKey: ApplicationPreferences.pausedProcessesKey)
    } else if let data = try? JSONEncoder().encode(ledger) {
      defaults.set(data, forKey: ApplicationPreferences.pausedProcessesKey)
    }
  }
  private let connectivity = ConnectivityMonitor()
  private var momentDetector = MomentDetector()
  private var signalPolicy = SignalStrengthPolicy()
  private let defaults: UserDefaults
  private let persistsPreferences: Bool
  private var systemMonitoringTask: Task<Void, Never>?
  private var deviceMonitoringTask: Task<Void, Never>?
  private var deviceEventsTask: Task<Void, Never>?
  private var deviceEventBindingTask: Task<Void, Never>?
  private var deviceEventObservationID: UUID?
  private var deviceEventRefresh: DeviceEventRefresh?
  private var inspectionTask: Task<Void, Never>?
  private var detailsTask: Task<Void, Never>?
  private var momentTask: Task<Void, Never>?
  private var deviceRefreshTask: Task<Void, Never>?
  private enum DeviceAction: Hashable { case volume, mute, output, wifi }
  private var deviceActions: [DeviceAction: (id: UUID, task: Task<Void, Never>)] = [:]
  @Published private var demand: Set<String> = []
  private var sampleFamilies: SampleFamilies?
  private var stopped = false
  private static let baselineInterval: Duration = .seconds(1)
  private static let deviceInterval: Duration = .seconds(6)
  private let momentDuration: Duration

  init(
    defaults: UserDefaults = .standard, collector: (any SystemSampling)? = nil,
    powerCollector: any PowerSampling = PowerCollector(),
    networkUsageCollector: any NetworkUsageSampling = NetworkUsageCollector(),
    deviceCollector: any DeviceControlling = DeviceCollector(),
    resourceCollector: (any ResourceInspecting)? = nil,
    processControl: any ProcessControlling = ProcessControl(),
    inventoryCollector: (any ProcessListing)? = nil,
    detailsCollector: any ProcessDetailInspecting = ProcessDetailsCollector(),
    bluetoothService: any BluetoothManaging = BluetoothCollector(),
    accessoryBatteryReader: any AccessoryBatteryReading = AccessoryBatteryReader(),
    wifiService: any WiFiNetworking = WiFiService(),
    displayService: any DisplayManaging = DisplayService(),
    deviceEvents: (any DeviceEventObserving)? = nil,
    historyRecorder: HistoryRecorder? = nil,
    persistsPreferences: Bool = true, momentDuration: Duration = MotionPolicy.momentDuration
  ) {
    self.defaults = defaults
    self.persistsPreferences = persistsPreferences
    self.momentDuration = momentDuration
    processSources = MergedProcessInventory(otherUsers: ProcessTableUsageSource())
    self.historyRecorder = historyRecorder
    resourceSources = MergedResourceInspector(local: ResourceCollector())
    self.collector = collector ?? SystemCollector(inventory: processSources)
    self.powerCollector = powerCollector
    self.networkUsageCollector = networkUsageCollector
    self.deviceCollector = deviceCollector
    self.deviceEvents = deviceEvents
    self.resourceCollector = resourceCollector ?? resourceSources
    self.processControl = processControl
    self.inventoryCollector = inventoryCollector ?? processSources
    self.detailsCollector = detailsCollector
    bluetooth = BluetoothController(
      service: bluetoothService, batteryReader: accessoryBatteryReader)
    wifi = WiFiController(service: wifiService)
    displays = DisplayController(service: displayService)
    menuBarItems = MenuBarItemsController(
      divider: persistsPreferences ? NativeMenuBarDivider(defaults: defaults) : nil)
    let saved = persistsPreferences ? defaults.data(forKey: ApplicationPreferences.key) : nil
    preferences = Preferences.decode(saved)
    bluetooth.setDemand(.indicator, active: preferences.activeProfile.center == .bluetooth)
    bluetoothChanges = bluetooth.$snapshot.dropFirst().sink { [weak self] snapshot in
      guard let self else { return }
      self.objectWillChange.send()
      if let moment = self.momentDetector.observeBluetooth(
        connectedDevices: snapshot?.connectedDeviceNames)
      {
        self.presentMoment(moment)
      }
    }
    wifiChanges = wifi.$connectionAttemptFinished.compactMap { $0 }.sink { [weak self] _ in
      self?.refreshDeviceReadings()
    }
  }
  var selectedProfile: UUID {
    get { preferences.selectedProfile }
    set { preferences.selectProfile(newValue) }
  }
  var profile: Profile {
    get { preferences.activeProfile }
    set {
      guard let index = preferences.profiles.firstIndex(where: { $0.id == newValue.id }) else {
        return
      }
      var validated = newValue
      validated.validate()
      preferences.profiles[index] = validated
    }
  }
  var processes: [ProcessSample] { sample?.processes ?? [] }
  // Several views read the same process tree for one reading; it is built once per sample.
  var processFamilies: ProcessFamilies { familiesOfCurrentSample().families }
  var processFamilyRoots: [ProcessFamily] { familiesOfCurrentSample().roots }
  var activityOutliers: [ActivityOutlier] { familiesOfCurrentSample().outliers }
  private func familiesOfCurrentSample() -> SampleFamilies {
    if let sampleFamilies, sampleFamilies.uptime == sample?.uptime { return sampleFamilies }
    let current = SampleFamilies(uptime: sample?.uptime, processes: processes)
    sampleFamilies = current
    return current
  }
  func isReadingPageVisible(_ reading: Reading) -> Bool {
    !stopped && page == reading && demand.contains("popover")
  }
  func setDemand(_ owner: String, active: Bool) {
    guard demand.contains(owner) != active else { return }
    if active { demand.insert(owner) } else { demand.remove(owner) }
    updateReadingPageDemand()
  }
  private func updateReadingPageDemand() {
    let showingReadings = !stopped && demand.contains("popover")
    let sources = processSources
    let estimatesWanted = viewsShowProcesses
    Task { await sources.useOtherUsersEstimates(estimatesWanted) }
    bluetooth.setDemand(.page, active: showingReadings && page == .bluetooth)
    wifi.setVisible(showingReadings && page == .wifi)
    displays.setVisible(showingReadings && page == .display)
  }
  func start(resetBaseline: Bool = false) {
    guard systemMonitoringTask == nil else { return }
    stopped = false
    historyRecorder?.apply(preferences.historyKeeping)
    menuBarItems.start()
    bluetooth.start()
    wifi.start()
    updateReadingPageDemand()
    connectivity.start { [weak self] state in
      guard let self, !self.stopped else { return }
      if let moment = self.momentDetector.observe(connection: state) { self.presentMoment(moment) }
      self.connection = state
    }
    startSystemMonitoring(resetBaseline: resetBaseline)
    startDeviceMonitoring()
    startDeviceEvents()
  }
  private func startDeviceEvents() {
    guard let deviceEvents else { return }
    deviceEventRefresh = DeviceEventRefresh(collector: deviceCollector) { [weak self] snapshot in
      self?.publishDevices(snapshot)
    }
    deviceEventsTask = Task { [weak self] in
      let observation = await deviceEvents.start()
      defer {
        if self?.deviceEventObservationID == observation.id { self?.deviceEventObservationID = nil }
        Task { await deviceEvents.stop(observationID: observation.id) }
      }
      guard !Task.isCancelled, self?.stopped == false else { return }
      self?.deviceEventObservationID = observation.id
      self?.bindDeviceEventOutput()
      for await _ in observation.events {
        guard !Task.isCancelled, self?.stopped == false else { return }
        self?.deviceEventRefresh?.request()
      }
    }
  }
  private func bindDeviceEventOutput() {
    guard let deviceEvents, let id = deviceEventObservationID, let devices else { return }
    let output = devices.audio.outputIdentity
    let uptime = devices.observationUptime
    deviceEventBindingTask?.cancel()
    deviceEventBindingTask = Task {
      guard !Task.isCancelled else { return }
      await deviceEvents.observeAudioOutput(output, at: uptime, observationID: id)
    }
  }
  private func startSystemMonitoring(resetBaseline: Bool) {
    let collector = collector
    systemMonitoringTask = Task { [weak self] in
      guard !Task.isCancelled else { return }
      if resetBaseline {
        await collector.reset()
        guard !Task.isCancelled, let includeProcesses = self?.wantsProcesses,
          let includeGPU = self?.wantsGPU
        else { return }
        // Rates need two observations; the first one after a reset only sets the baseline.
        _ = await collector.sample(includeProcesses: includeProcesses, includeGPU: includeGPU)
        do { try await Task.sleep(for: Self.baselineInterval) } catch { return }
      }
      while !Task.isCancelled {
        guard let includeProcesses = self?.wantsProcesses, let includeGPU = self?.wantsGPU else {
          return
        }
        let next = await collector.sample(includeProcesses: includeProcesses, includeGPU: includeGPU)
        guard !Task.isCancelled else { return }
        await self?.publish(next)
        let interval = self?.preferences.updateSpeed.interval ?? UpdateSpeed.normal.interval
        do { try await Task.sleep(for: interval) } catch { return }
      }
    }
  }
  private func startDeviceMonitoring() {
    let devices = deviceCollector
    deviceMonitoringTask = Task { [weak self] in
      while !Task.isCancelled && self != nil {
        let next = await devices.sample()
        guard !Task.isCancelled else { return }
        self?.publishDevices(next)
        do { try await Task.sleep(for: Self.deviceInterval) } catch { return }
      }
    }
  }
  private static let pagesShowingProcesses: Set<Reading> = [
    .overview, .cpu, .gpu, .memory, .network, .battery, .disk,
  ]
  // The device-wide GPU load is read on its own only where it is shown.
  private var wantsGPU: Bool {
    isReadingPageVisible(.gpu) || [profile.ring, profile.center, profile.bar].contains(.gpu)
  }
  // The Explorer and the panel pages that list processes; Wi-Fi or Sound never pay for a scan.
  private var viewsShowProcesses: Bool {
    demand.contains { $0 != "popover" }
      || (demand.contains("popover") && Self.pagesShowingProcesses.contains(page))
  }
  private var wantsProcesses: Bool {
    viewsShowProcesses || historyRecorder?.wantsProcesses == true
  }
  // Readings that depend on the sample are gathered first, so views redraw once per reading.
  private func publish(_ sample: SystemSample) async {
    // History keeps system watts with each process reading; the Battery page needs them live.
    let readsPower =
      isReadingPageVisible(.battery)
      || (historyRecorder?.isRecording == true && sample.processScan != nil)
    let power = readsPower ? await powerCollector.sample() : nil
    let network = await networkUsage(for: sample)
    guard !Task.isCancelled, !stopped else { return }
    publishSystem(sample)
    if let power { powerSnapshot = power }
    if network != networkUsage { networkUsage = network }
    await recordHistory(sample, systemWatts: power?.reading.systemWatts)
  }
  private func recordHistory(_ sample: SystemSample, systemWatts: Double?) async {
    guard let historyRecorder, !Task.isCancelled, !stopped else { return }
    let changes = await historyRecorder.record(
      sample, systemWatts: systemWatts, networkUsage: networkUsage.rates,
      diagnoses: isReadingPageVisible(.overview))
    for case .started(let episode) in changes {
      if let moment = momentDetector.observe(episodeStart: episode) { presentMoment(moment) }
    }
  }
  // Per-process traffic launches nettop, so it is read only while a Network view shows it.
  private var wantsNetworkUsage: Bool {
    isReadingPageVisible(.network) || demand.contains(Self.networkUsageDemand)
  }
  static let networkUsageDemand = "network-usage"
  private func networkUsage(for sample: SystemSample) async -> NetworkUsageState {
    guard wantsNetworkUsage, !sample.processes.isEmpty else {
      await networkUsageCollector.reset()
      return .measuring
    }
    return await networkUsageCollector.sample(of: sample.processes.map(\.id))
  }
  private func publishSystem(_ next: SystemSample) {
    sample = next
    history.append(next)
    processHistory.append(next)
    if let followed = next.processes.first(where: { $0.id == processHistory.identity }) {
      observedProcess = followed
    }
  }
  func stop() {
    stopped = true
    menuBarItems.stop()
    deviceEventRefresh?.stop()
    deviceEventRefresh = nil
    deviceEventObservationID = nil
    deviceEventsTask?.cancel()
    deviceEventsTask = nil
    deviceEventBindingTask?.cancel()
    deviceEventBindingTask = nil
    bluetooth.stop()
    wifi.stop()
    displays.setVisible(false)
    processActions.stop()
    connectivity.stop()
    connection = .unknown
    momentDetector.reset()
    signalPolicy = SignalStrengthPolicy()
    signalStrength = nil
    systemMonitoringTask?.cancel()
    systemMonitoringTask = nil
    deviceMonitoringTask?.cancel()
    deviceMonitoringTask = nil
    inspectionTask?.cancel()
    inspectionTask = nil
    detailsTask?.cancel()
    detailsTask = nil
    processDetails = nil
    isLoadingDetails = false
    detailsIssue = nil
    deviceRefreshTask?.cancel()
    deviceRefreshTask = nil
    momentTask?.cancel()
    momentTask = nil
    for action in deviceActions.values { action.task.cancel() }
    deviceActions.removeAll()
    moment = nil
    isInspecting = false
    power.disable()
  }
  func resume() {
    stop()
    history.reset()
    processHistory.restart(at: ProcessInfo.processInfo.systemUptime)
    observedProcess = nil
    // Readings from before sleep stay visible until fresh measurements replace them.
    start(resetBaseline: true)
  }
  func inspect(_ process: ProcessSample? = nil, socketsOnly: Bool = false) {
    guard !stopped else { return }
    inspectionTask?.cancel()
    resources = ResourceReport(resources: [])
    resourceInspectedAt = nil
    isInspecting = true
    inspectionTask = Task { [weak self] in
      guard let self else { return }
      do {
        let candidates: [ProcessSample]
        var inventorySummary = ScanSummary()
        if let process {
          candidates = [process]
        } else {
          let inventory = await self.inventoryCollector.inventory()
          if inventory.summary.failed {
            guard !Task.isCancelled else { return }
            self.resources = ResourceReport(resources: [], summary: inventory.summary)
            self.isInspecting = false
            return
          }
          candidates = inventory.processes
          inventorySummary = inventory.summary
        }
        try Task.checkCancellation()
        var result = try await self.resourceCollector.inspect(candidates, socketsOnly: socketsOnly)
        try Task.checkCancellation()
        result.summary.merge(inventorySummary)
        self.resources = result
        self.resourceInspectedAt = Date()
        self.isInspecting = false
      } catch is CancellationError {
        // The replacing request owns the visible loading state.
      } catch {
        guard !Task.isCancelled else { return }
        self.errorMessage = error.localizedDescription
        var summary = ScanSummary()
        summary.failed = true
        summary.failureMessage = error.localizedDescription
        self.resources = ResourceReport(resources: [], summary: summary)
        self.isInspecting = false
      }
    }
  }
  func cancelInspection() {
    inspectionTask?.cancel()
    inspectionTask = nil
    isInspecting = false
  }
  func trackProcess(_ identity: ProcessIdentity?) {
    guard identity != processHistory.identity else { return }
    processHistory.track(identity, at: ProcessInfo.processInfo.systemUptime)
    observedProcess = processes.first { $0.id == identity }
    cancelDetails()
  }
  private func cancelDetails() {
    detailsTask?.cancel()
    detailsTask = nil
    processDetails = nil
    isLoadingDetails = false
    detailsIssue = nil
  }
  func inspectDetails(_ process: ProcessSample) {
    guard !stopped else { return }
    detailsTask?.cancel()
    processDetails = nil
    isLoadingDetails = true
    detailsIssue = nil
    detailsTask = Task { [weak self] in
      guard let self else { return }
      do {
        let details = try await self.detailsCollector.inspect(process)
        try Task.checkCancellation()
        self.processDetails = details
        self.isLoadingDetails = false
      } catch {
        guard !Task.isCancelled else { return }
        self.detailsIssue = error.localizedDescription
        self.isLoadingDetails = false
      }
    }
  }
  func endExplorerSession() {
    setDemand("explorer", active: false)
    cancelInspection()
    trackProcess(nil)
    cancelDetails()
    processActions.stop()
    resources = ResourceReport(resources: [])
  }
  func setVolume(_ value: Double, on output: AudioOutputIdentity) {
    performDeviceAction(.volume) { try await $0.setVolume(value, on: output) }
  }
  func setMuted(_ muted: Bool, on output: AudioOutputIdentity) {
    performDeviceAction(.mute) { try await $0.setMuted(muted, on: output) }
  }
  func selectOutput(_ output: AudioOutputIdentity) {
    performDeviceAction(.output) { try await $0.selectOutput(output) }
  }
  func setWiFiPower(_ powered: Bool) {
    guard wifi.joiningNetworkID == nil else { return }
    wifi.cancelScan()
    performDeviceAction(.wifi) { try await $0.setWiFiPower(powered) }
  }
  func refreshDeviceReadings() {
    guard !stopped else { return }
    deviceRefreshTask?.cancel()
    let collector = deviceCollector
    deviceRefreshTask = Task { [weak self] in
      let next = await collector.sample()
      guard !Task.isCancelled, self?.stopped == false else { return }
      self?.publishDevices(next)
    }
  }

  private func performDeviceAction(
    _ kind: DeviceAction, _ action: @escaping @Sendable (any DeviceControlling) async throws -> Void
  ) {
    guard !stopped else { return }
    deviceActions[kind]?.task.cancel()
    let identifier = UUID()
    let collector = deviceCollector
    let task = Task { [weak self] in
      guard self?.stopped == false, !Task.isCancelled else { return }
      defer { if self?.deviceActions[kind]?.id == identifier { self?.deviceActions[kind] = nil } }
      do {
        try await action(collector)
        try Task.checkCancellation()
        let next = await collector.sample()
        guard !Task.isCancelled, self?.stopped == false else { return }
        self?.publishDevices(next)
      } catch {
        if self?.stopped == false && !Task.isCancelled {
          self?.errorMessage = error.localizedDescription
          self?.refreshDeviceReadings()
        }
      }
    }
    deviceActions[kind] = (identifier, task)
  }
  private func persistPreferences() {
    guard persistsPreferences else { return }
    guard let data = try? JSONEncoder().encode(preferences) else { return }
    defaults.set(data, forKey: ApplicationPreferences.key)
  }
  private func publishDevices(_ next: DeviceSnapshot) {
    if let current = devices, next.observationUptime < current.observationUptime { return }
    if !preferences.hasSelectedInitialPreset, let installed = next.batteryObservation.isInstalled {
      preferences.selectInitialPreset(hasBattery: installed)
    }
    let observation = DeviceObservation(
      batteryFraction: next.battery?.fraction,
      externalPower: next.battery?.externalPower,
      muted: next.audio.muted, outputName: next.audio.observedOutputName,
      volumeNamesByID: next.mountedVolumeNamesByID)
    if let moment = momentDetector.observe(observation) { presentMoment(moment) }
    signalStrength = signalPolicy.update(rssi: next.wifi.rssi)
    devices = next
    bindDeviceEventOutput()
    displays.refreshIfVisible()
  }
  func presentMoment(_ next: StatusMoment) {
    guard !stopped, preferences.momentsEnabled, moment.map({ next.priority >= $0.priority }) ?? true
    else {
      return
    }
    momentTask?.cancel()
    moment = next
    let duration = momentDuration
    momentTask = Task { [weak self] in
      do { try await Task.sleep(for: duration) } catch { return }
      self?.moment = nil
    }
  }
  isolated deinit {
    deviceEventRefresh?.stop()
    deviceEventsTask?.cancel()
    deviceEventBindingTask?.cancel()
    systemMonitoringTask?.cancel()
    deviceMonitoringTask?.cancel()
    deviceRefreshTask?.cancel()
    inspectionTask?.cancel()
    detailsTask?.cancel()
    momentTask?.cancel()
    for action in deviceActions.values { action.task.cancel() }
  }
}

private final class SampleFamilies {
  let uptime: TimeInterval?
  let processes: [ProcessSample]
  let families: ProcessFamilies
  private(set) lazy var roots = families.roots
  private(set) lazy var outliers = ActivityOutlierRanker.rank(
    processes, families: families, currentUser: getuid(), limit: 10)
  init(uptime: TimeInterval?, processes: [ProcessSample]) {
    self.uptime = uptime
    self.processes = processes
    families = ProcessFamilies(processes)
  }
}
