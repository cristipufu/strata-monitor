import Foundation

// Tabs follow this order: the summary, the Mac's own resources, its power, then its connections.
public enum Reading: String, CaseIterable, Codable, Identifiable, Sendable {
  case overview, cpu, gpu, memory, disk, network, battery, wifi, bluetooth, sound, display
  public var id: String { rawValue }
  public var title: String {
    switch self {
    case .overview: "Overview"
    case .cpu: "CPU"
    case .gpu: "GPU"
    case .memory: "Memory"
    case .network: "Network"
    case .battery: "Battery"
    case .sound: "Sound"
    case .wifi: "Wi-Fi"
    case .bluetooth: "Bluetooth"
    case .disk: "Disk"
    case .display: "Displays"
    }
  }
  public var symbol: String {
    switch self {
    case .overview: "square.grid.2x2"
    case .cpu: "cpu"
    case .gpu: "cube.transparent"
    case .memory: "memorychip"
    case .network: "arrow.up.arrow.down"
    case .battery: "battery.75percent"
    case .sound: "speaker.wave.2"
    case .wifi: "wifi"
    case .bluetooth: "wave.3.right"
    case .disk: "internaldrive"
    case .display: "display"
    }
  }
}

public struct ProcessIdentity: Hashable, Codable, Sendable {
  public let pid: Int32
  public let startSeconds: UInt64
  public let startMicroseconds: UInt64
  public init(pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64) {
    self.pid = pid
    self.startSeconds = startSeconds
    self.startMicroseconds = startMicroseconds
  }
  public var startMicrosecondsSinceEpoch: UInt64 {
    startSeconds.multipliedReportingOverflow(by: 1_000_000).partialValue &+ startMicroseconds
  }
  public var startDate: Date {
    Date(timeIntervalSince1970: TimeInterval(startSeconds) + TimeInterval(startMicroseconds) / 1e6)
  }
}

// The kernel's process table tells stopped and exited processes apart, not running from sleeping.
public enum ProcessRunState: String, Codable, Sendable {
  case running, stopped, zombie, starting
}

public struct ProcessActivityCounters: Codable, Sendable, Equatable {
  public let energyNanojoules: UInt64
  public let wakeups: UInt64
  public let instructions: UInt64
  public let cycles: UInt64
  public let performanceCoreNanoseconds: UInt64
  public let peakFootprintBytes: UInt64
  public init(
    energyNanojoules: UInt64, wakeups: UInt64, instructions: UInt64, cycles: UInt64,
    performanceCoreNanoseconds: UInt64, peakFootprintBytes: UInt64
  ) {
    self.energyNanojoules = energyNanojoules
    self.wakeups = wakeups
    self.instructions = instructions
    self.cycles = cycles
    self.performanceCoreNanoseconds = performanceCoreNanoseconds
    self.peakFootprintBytes = peakFootprintBytes
  }
}

public struct ProcessSample: Identifiable, Codable, Sendable {
  public let id: ProcessIdentity
  public let parentPID: Int32
  public let userID: UInt32
  public var name: String
  public var path: String
  public var cpuTimeNanoseconds: UInt64?
  public var cpuPercent: Double?
  public var residentBytes: UInt64?
  public let footprintBytes: UInt64?
  public let threads: Int?
  public let diskReadBytes: UInt64?
  public let diskWrittenBytes: UInt64?
  public var diskReadBytesPerSecond: Double?
  public var diskWrittenBytesPerSecond: Double?
  public let runState: ProcessRunState?
  public let isTranslated: Bool
  public let activity: ProcessActivityCounters?
  public var watts: Double?
  public var wakeupsPerSecond: Double?
  public var performanceCoreShare: Double?
  public var gpuTimeNanoseconds: UInt64?
  public var gpuPercent: Double?
  public var userName: String?
  public var project: String?
  // CPU time and resident memory came from a slower outside source, so only that source's own
  // CPU percentage is meaningful for this row.
  public var isEstimated = false
  public var displayName: String { project.map { "\(name) · \($0)" } ?? name }
  public init(
    id: ProcessIdentity, parentPID: Int32, userID: UInt32, name: String, path: String,
    cpuTimeNanoseconds: UInt64?, cpuPercent: Double? = nil, residentBytes: UInt64?,
    footprintBytes: UInt64?, threads: Int?, diskReadBytes: UInt64? = nil,
    diskWrittenBytes: UInt64? = nil,
    diskReadBytesPerSecond: Double? = nil, diskWrittenBytesPerSecond: Double? = nil,
    runState: ProcessRunState? = nil, isTranslated: Bool = false,
    activity: ProcessActivityCounters? = nil
  ) {
    self.runState = runState
    self.isTranslated = isTranslated
    self.activity = activity
    self.id = id
    self.parentPID = parentPID
    self.userID = userID
    self.name = name
    self.path = path
    self.cpuTimeNanoseconds = cpuTimeNanoseconds
    self.cpuPercent = cpuPercent
    self.residentBytes = residentBytes
    self.footprintBytes = footprintBytes
    self.threads = threads
    self.diskReadBytes = diskReadBytes
    self.diskWrittenBytes = diskWrittenBytes
    self.diskReadBytesPerSecond = diskReadBytesPerSecond
    self.diskWrittenBytesPerSecond = diskWrittenBytesPerSecond
  }
}

public struct MemorySample: Sendable {
  public let total: UInt64
  public let active: UInt64
  public let wired: UInt64
  public let compressed: UInt64
  public let cached: UInt64
  public let free: UInt64
  public let swap: UInt64?
  public let pressure: MemoryPressure
  public var used: UInt64 {
    [active, wired, compressed].reduce(0) { partial, value in
      let (sum, overflow) = partial.addingReportingOverflow(value)
      return overflow ? total : min(total, sum)
    }
  }
  public var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
  public init(
    total: UInt64, active: UInt64, wired: UInt64, compressed: UInt64,
    cached: UInt64, free: UInt64, swap: UInt64?, pressure: MemoryPressure
  ) {
    self.total = total
    self.active = active
    self.wired = wired
    self.compressed = compressed
    self.cached = cached
    self.free = free
    self.swap = swap
    self.pressure = pressure
  }
}

public enum MemoryPressure: String, Sendable {
  case normal, elevated, critical, unavailable
}

public struct NetworkRate: Sendable, Equatable {
  public let received: Double
  public let sent: Double
  public init(received: Double, sent: Double) {
    self.received = received
    self.sent = sent
  }
}

public struct SystemSample: Sendable {
  public enum ThermalPressure: String, Sendable {
    case normal = "Normal"
    case elevated = "Elevated"
    case high = "High"
    case critical = "Critical"
    case unavailable = "Unavailable"
  }
  public let uptime: TimeInterval
  public let cpu: Double?
  public let cores: [Double?]
  public let memory: MemorySample?
  public let network: NetworkRate?
  public let interfaces: [String]
  public let processes: [ProcessSample]
  public let processScan: ScanSummary?
  public let thermalPressure: ThermalPressure
  public let gpu: GPUSystemReading?
  public let processCoverage: ProcessCoverage?
  public var observedDiskActivity: ObservedDiskActivity? { ObservedDiskActivity(processes) }
  public init(
    uptime: TimeInterval, cpu: Double?, cores: [Double?], memory: MemorySample?,
    network: NetworkRate?, interfaces: [String], processes: [ProcessSample],
    processScan: ScanSummary? = nil, thermalPressure: ThermalPressure = .unavailable,
    gpu: GPUSystemReading? = nil, processCoverage: ProcessCoverage? = nil
  ) {
    self.gpu = gpu
    self.processCoverage = processCoverage
    self.uptime = uptime
    self.cpu = cpu
    self.cores = cores
    self.memory = memory
    self.network = network
    self.interfaces = interfaces
    self.processes = processes
    self.processScan = processScan
    self.thermalPressure = thermalPressure
  }
}

public struct HistoryPoint: Identifiable, Sendable {
  public var id: TimeInterval { uptime }
  public let uptime: TimeInterval
  public let cpu: Double?
  public let gpu: Double?
  public let memory: Double?
  public let download: Double?
  public let upload: Double?
  public let diskRead: Double?
  public let diskWritten: Double?
  public init(_ sample: SystemSample) {
    uptime = sample.uptime
    cpu = sample.cpu
    gpu = sample.gpu?.deviceUtilization
    memory = sample.memory?.fraction
    download = sample.network?.received
    upload = sample.network?.sent
    let activity = sample.observedDiskActivity
    diskRead = activity?.read
    diskWritten = activity?.written
  }
}

public struct RecentHistory: Sendable {
  public private(set) var points: [HistoryPoint] = []
  public let duration: TimeInterval
  private let maximumCount = 240
  public init(duration: TimeInterval = 60) { self.duration = max(1, duration) }
  public mutating func append(_ sample: SystemSample) {
    guard points.last.map({ sample.uptime > $0.uptime }) ?? true else { return }
    points.append(HistoryPoint(sample))
    points.removeAll { $0.uptime < sample.uptime - duration }
    if points.count > maximumCount { points.removeFirst(points.count - maximumCount) }
  }
  public mutating func reset() { points.removeAll(keepingCapacity: true) }
}
