import CSystem
import Foundation
import StrataCore
import StrataInventory

public actor SystemCollector {
  private var coreDeltas: [CPUDelta] = []
  private var rates = CounterRates<String>()
  // History reads processes every 30 seconds while nothing is shown, so rates span that gap.
  private var processRates = CounterRates<ProcessCounter>(maximumInterval: 45)
  private var gpuRates = GPUUsageRates(maximumInterval: 45)
  private var churn = ProcessChurnTracker(maximumInterval: 45)
  private let gpuReader: GPUReader
  private let inventory: MergedProcessInventory
  private let userNames = UserNameDirectory()
  private var labeling = ProcessLabeling()
  // The helper may hand back the scan it already sent; measuring it again would find no time
  // elapsed and blank every rate.
  private var lastMeasured: ProcessInventory?
  public init(
    inventory: MergedProcessInventory = MergedProcessInventory(),
    gpuReader: GPUReader = GPUReader()
  ) {
    self.inventory = inventory
    self.gpuReader = gpuReader
  }

  public func reset() {
    coreDeltas.removeAll()
    rates.reset()
    processRates.reset()
    gpuRates.reset()
    churn.reset()
    lastMeasured = nil
  }
  public func sample(includeProcesses: Bool, includeGPU: Bool = false) async -> SystemSample {
    let covered = includeProcesses ? await inventory.coveredInventory() : nil
    let names = await userNames.names(for: Set(covered?.inventory.processes.map(\.userID) ?? []))
    let time = ProcessInfo.processInfo.systemUptime
    let raw = sb_system_counters()
    let cores = cpuFractions(raw)
    let memory = memorySample(raw)
    let interfaceNames = nativeString(raw.interfaces).components(separatedBy: ", ").filter {
      !$0.isEmpty
    }
    let network = networkRate(raw, at: time)
    // Process GPU shares need the GPU read at the same instant as the processes.
    let gpu =
      includeProcesses || includeGPU ? gpuReader.read(includingProcesses: includeProcesses) : nil
    let processes = covered.map { covered in
      if let lastMeasured, let capturedAt = covered.inventory.capturedAt,
        lastMeasured.capturedAt == capturedAt
      {
        return lastMeasured
      }
      let result = measured(
        covered.inventory, at: covered.inventory.capturedAt ?? time, gpu: gpu, names: names)
      lastMeasured = result
      return result
    }
    return SystemSample(
      uptime: time,
      cpu: cores.isEmpty || cores.contains(where: { $0 == nil })
        ? nil : cores.compactMap { $0 }.reduce(0, +) / Double(cores.count),
      cores: cores, memory: memory, network: network,
      interfaces: interfaceNames, processes: processes?.processes ?? [],
      processScan: processes?.summary, thermalPressure: thermalPressure, gpu: gpu?.devices.first,
      processCoverage: covered?.coverage)
  }
  private var thermalPressure: SystemSample.ThermalPressure {
    switch ProcessInfo.processInfo.thermalState {
    case .nominal: .normal
    case .fair: .elevated
    case .serious: .high
    case .critical: .critical
    @unknown default: .unavailable
    }
  }
  private func cpuFractions(_ raw: SBSystemCounters) -> [Double?] {
    guard raw.cpu_valid else {
      coreDeltas.removeAll()
      return []
    }
    let count = Int(raw.core_count)
    if coreDeltas.count != count { coreDeltas = Array(repeating: CPUDelta(), count: count) }
    var busyTuple = raw.busy
    var totalTuple = raw.total
    return withUnsafeBytes(of: &busyTuple) { busyBytes in
      withUnsafeBytes(of: &totalTuple) { totalBytes in
        let busy = busyBytes.bindMemory(to: UInt64.self)
        let total = totalBytes.bindMemory(to: UInt64.self)
        return (0..<count).map { coreDeltas[$0].fraction(busy: busy[$0], total: total[$0]) }
      }
    }
  }
  private func memorySample(_ raw: SBSystemCounters) -> MemorySample? {
    guard raw.memory_valid else { return nil }
    let pressure: MemoryPressure =
      switch raw.pressure {
      case 1: .normal
      case 2: .elevated
      case 4: .critical
      default: .unavailable
      }
    return MemorySample(
      total: raw.memory_total, active: raw.active, wired: raw.wired,
      compressed: raw.compressed, cached: raw.cached, free: raw.free_bytes,
      swap: raw.swap_valid ? raw.swap : nil, pressure: pressure)
  }
  private func networkRate(_ raw: SBSystemCounters, at time: TimeInterval) -> NetworkRate? {
    guard raw.network_valid else { return nil }
    let interfaces = nativeString(raw.interfaces).components(separatedBy: ", ").filter {
      !$0.isEmpty
    }
    let rx = rates.rate(for: "rx:\(interfaces)", value: raw.received, at: time)
    let tx = rates.rate(for: "tx:\(interfaces)", value: raw.sent, at: time)
    rates.retain(keys: Set(["rx:\(interfaces)", "tx:\(interfaces)"]))
    guard let rx, let tx else { return nil }
    return NetworkRate(received: rx, sent: tx)
  }
  private func measured(
    _ source: ProcessInventory, at time: TimeInterval, gpu: GPUReading?, names: [UInt32: String]
  ) -> ProcessInventory {
    var inventory = source
    let gpuShares = gpuRates.fractions(of: gpu, for: inventory.processes.map(\.id), at: time)
    let spawnRates = churn.observe(inventory.processes, at: time)
    inventory.processes = inventory.processes.map { source in
      var process = measuredRates(of: source, at: time)
      process.gpuTimeNanoseconds = gpu?.accumulatedTime(of: source.id)
      process.gpuPercent = gpuShares[source.id].map { $0 * 100 }
      process.userName = names[source.userID]
      let location = labeling.location(of: source)
      process.project = location.project
      process.workingDirectory = location.workingDirectory
      process.spawnsPerSecond = spawnRates[source.id]
      return process
    }
    let live = Set(inventory.processes.map(\.id))
    processRates.retain { live.contains($0.identity) }
    return inventory
  }
  private func measuredRates(of source: ProcessSample, at time: TimeInterval) -> ProcessSample {
    var process = source
    func rate(_ kind: ProcessCounter.Kind, _ value: UInt64?) -> Double? {
      value.flatMap {
        processRates.rate(for: ProcessCounter(identity: source.id, kind: kind), value: $0, at: time)
      }
    }
    // An estimated row's CPU time changes only when its source refreshes; its own percentage
    // is the only rate that means anything.
    let cpuNanosecondsPerSecond = source.isEstimated ? nil : rate(.cpu, source.cpuTimeNanoseconds)
    process.cpuPercent =
      source.isEstimated
      ? source.cpuPercent : cpuNanosecondsPerSecond.map { $0 / 1_000_000_000 * 100 }
    process.diskReadBytesPerSecond = rate(.diskRead, source.diskReadBytes)
    process.diskWrittenBytesPerSecond = rate(.diskWritten, source.diskWrittenBytes)
    if let activity = source.activity {
      process.watts = rate(.energy, activity.energyNanojoules).map { $0 / 1_000_000_000 }
      process.wakeupsPerSecond = rate(.wakeups, activity.wakeups)
      let performance = rate(.performanceCore, activity.performanceCoreNanoseconds)
      process.performanceCoreShare = performance.flatMap { performance in
        cpuNanosecondsPerSecond.flatMap { $0 > 0 ? min(1, performance / $0) : nil }
      }
    }
    return process
  }
}

private struct ProcessCounter: Hashable, Sendable {
  enum Kind: Hashable, Sendable { case cpu, diskRead, diskWritten, energy, wakeups, performanceCore }
  let identity: ProcessIdentity
  let kind: Kind
}
