import Foundation

public struct GPUSystemReading: Codable, Equatable, Sendable {
  public let model: String?
  public let deviceUtilization: Double?
  public let rendererUtilization: Double?
  public let tilerUtilization: Double?
  public let inUseSystemMemoryBytes: UInt64?

  public init(
    model: String?, deviceUtilization: Double?, rendererUtilization: Double?,
    tilerUtilization: Double?, inUseSystemMemoryBytes: UInt64?
  ) {
    self.model = model
    self.deviceUtilization = deviceUtilization
    self.rendererUtilization = rendererUtilization
    self.tilerUtilization = tilerUtilization
    self.inUseSystemMemoryBytes = inUseSystemMemoryBytes
  }
}

// Accumulated GPU nanoseconds per PID, summed over every client the process opened.
public typealias GPUProcessTimes = [Int32: UInt64]

public struct GPUReading: Codable, Equatable, Sendable {
  public let devices: [GPUSystemReading]
  // Nil when the GPU clients could not all be listed or attributed to a process.
  public let processTimes: GPUProcessTimes?
  // Processes whose GPU time is unknown in this reading, which is not the same as none.
  public let unreadablePIDs: Set<Int32>

  public init(
    devices: [GPUSystemReading], processTimes: GPUProcessTimes?, unreadablePIDs: Set<Int32> = []
  ) {
    self.devices = devices
    self.processTimes = processTimes
    self.unreadablePIDs = unreadablePIDs
  }

  public func accumulatedTime(of process: ProcessIdentity) -> UInt64? {
    guard let processTimes, !unreadablePIDs.contains(process.pid) else { return nil }
    return processTimes[process.pid] ?? 0
  }
}

public struct GPUUsageRates: Sendable {
  private var gpuTime: CounterRates<ProcessIdentity>

  public init(maximumInterval: TimeInterval = 10) {
    gpuTime = CounterRates(maximumInterval: maximumInterval)
  }

  // Returns the share of GPU time per process, where 1 is one GPU's full time.
  // A process without any GPU client used no GPU time; a nil reading is an unreadable sample.
  public mutating func fractions(
    of reading: GPUReading?, for processes: [ProcessIdentity], at uptime: TimeInterval
  ) -> [ProcessIdentity: Double] {
    let counts = Dictionary(
      processes.map { ($0, reading?.accumulatedTime(of: $0)) },
      uniquingKeysWith: { first, _ in first })
    return gpuTime.rates(of: counts, at: uptime).mapValues { $0 / 1_000_000_000 }
  }

  public mutating func reset() { gpuTime.reset() }
}
