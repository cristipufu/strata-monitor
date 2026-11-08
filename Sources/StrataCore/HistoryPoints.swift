import Foundation

public enum HistoryPressure: UInt8, CaseIterable, Comparable, Sendable {
  case normal, elevated, high, critical

  public init?(_ pressure: MemoryPressure) {
    switch pressure {
    case .normal: self = .normal
    case .elevated: self = .elevated
    case .critical: self = .critical
    case .unavailable: return nil
    }
  }

  public init?(_ pressure: SystemSample.ThermalPressure) {
    switch pressure {
    case .normal: self = .normal
    case .elevated: self = .elevated
    case .high: self = .high
    case .critical: self = .critical
    case .unavailable: return nil
    }
  }

  public var title: String {
    switch self {
    case .normal: "normal"
    case .elevated: "elevated"
    case .high: "high"
    case .critical: "critical"
    }
  }

  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

  static func worst(_ lhs: Self?, _ rhs: Self?) -> Self? {
    guard let lhs else { return rhs }
    guard let rhs else { return lhs }
    return max(lhs, rhs)
  }
}

public enum HistoryMetric: Int, CaseIterable, Sendable {
  case cpu, memoryUsed, swap, networkIn, networkOut, diskRead, diskWrite, gpu, systemWatts

  /// The synthesized `allCases` builds a new array on every call; hot paths share this one.
  static let all = allCases
}

/// One whole-system observation. `cpu`, `memoryUsedFraction` and `gpu` are shares
/// of the whole machine from 0 to 1; rates are bytes per second.
public struct HistorySystemPoint: Equatable, Sendable {
  public var time: Date
  public var uptime: TimeInterval?
  public var cpu: Double?
  public var memoryUsedFraction: Double?
  public var memoryPressure: HistoryPressure?
  public var swapBytes: Double?
  public var networkInBytesPerSecond: Double?
  public var networkOutBytesPerSecond: Double?
  public var diskReadBytesPerSecond: Double?
  public var diskWriteBytesPerSecond: Double?
  public var gpu: Double?
  public var systemWatts: Double?
  public var thermal: HistoryPressure?

  public init(
    time: Date, uptime: TimeInterval? = nil, cpu: Double? = nil, memoryUsedFraction: Double? = nil,
    memoryPressure: HistoryPressure? = nil, swapBytes: Double? = nil,
    networkInBytesPerSecond: Double? = nil, networkOutBytesPerSecond: Double? = nil,
    diskReadBytesPerSecond: Double? = nil, diskWriteBytesPerSecond: Double? = nil,
    gpu: Double? = nil, systemWatts: Double? = nil, thermal: HistoryPressure? = nil
  ) {
    self.time = time
    self.uptime = uptime
    self.cpu = cpu
    self.memoryUsedFraction = memoryUsedFraction
    self.memoryPressure = memoryPressure
    self.swapBytes = swapBytes
    self.networkInBytesPerSecond = networkInBytesPerSecond
    self.networkOutBytesPerSecond = networkOutBytesPerSecond
    self.diskReadBytesPerSecond = diskReadBytesPerSecond
    self.diskWriteBytesPerSecond = diskWriteBytesPerSecond
    self.gpu = gpu
    self.systemWatts = systemWatts
    self.thermal = thermal
  }

  public init(_ sample: SystemSample, time: Date, systemWatts: Double? = nil) {
    let disk = sample.observedDiskActivity
    self.init(
      time: time, uptime: sample.uptime, cpu: sample.cpu,
      memoryUsedFraction: sample.memory?.fraction,
      memoryPressure: sample.memory.flatMap { HistoryPressure($0.pressure) },
      swapBytes: sample.memory?.swap.map { Double($0) },
      networkInBytesPerSecond: sample.network?.received,
      networkOutBytesPerSecond: sample.network?.sent,
      diskReadBytesPerSecond: disk?.read, diskWriteBytesPerSecond: disk?.written,
      gpu: sample.gpu?.deviceUtilization, systemWatts: systemWatts,
      thermal: HistoryPressure(sample.thermalPressure))
  }

  public subscript(metric: HistoryMetric) -> Double? {
    get {
      switch metric {
      case .cpu: cpu
      case .memoryUsed: memoryUsedFraction
      case .swap: swapBytes
      case .networkIn: networkInBytesPerSecond
      case .networkOut: networkOutBytesPerSecond
      case .diskRead: diskReadBytesPerSecond
      case .diskWrite: diskWriteBytesPerSecond
      case .gpu: gpu
      case .systemWatts: systemWatts
      }
    }
    set {
      switch metric {
      case .cpu: cpu = newValue
      case .memoryUsed: memoryUsedFraction = newValue
      case .swap: swapBytes = newValue
      case .networkIn: networkInBytesPerSecond = newValue
      case .networkOut: networkOutBytesPerSecond = newValue
      case .diskRead: diskReadBytesPerSecond = newValue
      case .diskWrite: diskWriteBytesPerSecond = newValue
      case .gpu: gpu = newValue
      case .systemWatts: systemWatts = newValue
      }
    }
  }
}

public struct HistoryProcessLabel: Hashable, Sendable {
  public let identity: ProcessIdentity
  public let name: String
  public let project: String?

  public init(identity: ProcessIdentity, name: String, project: String?) {
    self.identity = identity
    self.name = name
    self.project = project
  }
}

public enum HistoryProcessMetric: Int, CaseIterable, Sendable {
  case cpu, memory, watts, disk, network

  /// The synthesized `allCases` builds a new array on every call; hot paths share this one.
  static let all = allCases
}

/// One process observation. CPU uses 100% per logical core, like `ProcessSample`.
/// Only a name and a project are kept: a path given as either is reduced to its
/// last component so history never records where a program or project lives.
public struct HistoryProcessPoint: Equatable, Sendable {
  public let identity: ProcessIdentity
  public let name: String
  public let project: String?
  public var cpuPercent: Double?
  public var footprintBytes: UInt64?
  public var watts: Double?
  public var diskBytesPerSecond: Double?
  public var networkBytesPerSecond: Double?
  public var wakeupsPerSecond: Double?

  public init(
    identity: ProcessIdentity, name: String, project: String? = nil, cpuPercent: Double? = nil,
    footprintBytes: UInt64? = nil, watts: Double? = nil, diskBytesPerSecond: Double? = nil,
    networkBytesPerSecond: Double? = nil, wakeupsPerSecond: Double? = nil
  ) {
    self.identity = identity
    self.name = Self.lastComponent(name)
    self.project = project.map(Self.lastComponent)
    self.cpuPercent = cpuPercent
    self.footprintBytes = footprintBytes
    self.watts = watts
    self.diskBytesPerSecond = diskBytesPerSecond
    self.networkBytesPerSecond = networkBytesPerSecond
    self.wakeupsPerSecond = wakeupsPerSecond
  }

  public init(_ process: ProcessSample, project: String? = nil, networkBytesPerSecond: Double? = nil) {
    let disk: Double? =
      switch (process.diskReadBytesPerSecond, process.diskWrittenBytesPerSecond) {
      case (nil, nil): nil
      case let (read, written): (read ?? 0) + (written ?? 0)
      }
    self.init(
      identity: process.id, name: process.name, project: project, cpuPercent: process.cpuPercent,
      footprintBytes: process.footprintBytes, watts: process.watts, diskBytesPerSecond: disk,
      networkBytesPerSecond: networkBytesPerSecond, wakeupsPerSecond: process.wakeupsPerSecond)
  }

  public var label: HistoryProcessLabel {
    HistoryProcessLabel(identity: identity, name: name, project: project)
  }

  public subscript(metric: HistoryProcessMetric) -> Double? {
    switch metric {
    case .cpu: cpuPercent
    case .memory: footprintBytes.map { Double($0) }
    case .watts: watts
    case .disk: diskBytesPerSecond
    case .network: networkBytesPerSecond
    }
  }

  private static func lastComponent(_ text: String) -> String {
    guard let separator = text.lastIndex(of: "/") else { return text }
    return String(text[text.index(after: separator)...])
  }
}
