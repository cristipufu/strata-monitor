import Foundation

public struct DiagnosisContributor: Equatable, Sendable {
  public let identity: ProcessIdentity
  public let name: String
  public let project: String?
  public let value: Double
  public let formattedValue: String
}

public struct Diagnosis: Equatable, Sendable {
  public enum Cause: String, CaseIterable, Sendable {
    case cpuSaturation, memoryPressure, thermalPressure, diskActivity, gpuLoad, powerDraw
  }

  public enum Action: Sendable {
    case quit, inspect, none
  }

  public let cause: Cause
  public let title: String
  public let evidence: [String]
  public let contributors: [DiagnosisContributor]
  public let action: Action
  public let score: Double
}

public struct DiagnosisReport: Equatable, Sendable {
  public static let nothingUnusual = "Nothing unusual"

  public let causes: [Diagnosis]

  public var isNothingUnusual: Bool { causes.isEmpty }
  public var headline: String { causes.first?.title ?? Self.nothingUnusual }
}

public struct DiagnosisInput: Sendable {
  public var current: HistorySystemPoint
  public var processes: [HistoryProcessPoint]
  /// Summaries of the last ten minutes, oldest first, such as
  /// `TieredHistory.points(in:)` for that range.
  public var recent: [HistorySummaryPoint]
  public var logicalCores: Int?

  public init(
    current: HistorySystemPoint, processes: [HistoryProcessPoint], recent: [HistorySummaryPoint],
    logicalCores: Int? = nil
  ) {
    self.current = current
    self.processes = processes
    self.recent = recent
    self.logicalCores = logicalCores
  }
}

/// Maps a measurement linearly onto a score from 0 at `low` to 1 at `high`.
public struct ScoreRamp: Equatable, Sendable {
  public var low: Double
  public var high: Double

  public init(low: Double, high: Double) {
    self.low = low
    self.high = high
  }

  func score(_ value: Double?) -> Double {
    guard let value, value.isFinite, high > low else { return 0 }
    return min(1, max(0, (value - low) / (high - low)))
  }
}

public struct DiagnosisThresholds: Equatable, Sendable {
  public var minimumScore = 0.5
  public var sustainedWindow: TimeInterval = 180
  public var cpu = ScoreRamp(low: 0.7, high: 0.95)
  public var busyCPU = 0.8
  public var swapGrowth = ScoreRamp(low: 256 * 1_048_576, high: 2 * 1_073_741_824)
  public var memoryUsed = ScoreRamp(low: 0.85, high: 0.98)
  public var diskBytesPerSecond = ScoreRamp(low: 50_000_000, high: 400_000_000)
  public var gpu = ScoreRamp(low: 0.7, high: 0.95)
  public var systemWatts = ScoreRamp(low: 20, high: 60)
  /// A process using at least this much CPU is worth quitting rather than inspecting.
  public var quittableCPUPercent = 100.0
  public var quittableSwapGrowth: Double = 1_073_741_824
  public var maximumCauses = 3
  public var contributorsPerCause = 3

  public init() {}
}

public enum DiagnosisEngine {
  public static func diagnose(
    _ input: DiagnosisInput, thresholds: DiagnosisThresholds = DiagnosisThresholds()
  ) -> DiagnosisReport {
    let window = RecentWindow(input: input, sustained: thresholds.sustainedWindow)
    let candidates = [
      cpuSaturation(input, window, thresholds),
      memoryPressure(input, window, thresholds),
      thermalPressure(input, window, thresholds),
      diskActivity(input, window, thresholds),
      gpuLoad(window, thresholds),
      powerDraw(input, window, thresholds),
    ]
    let causes = candidates.compactMap { $0 }
      .filter { $0.score >= thresholds.minimumScore }
      .enumerated()
      .sorted { ($0.element.score, -$0.offset) > ($1.element.score, -$1.offset) }
      .prefix(max(0, thresholds.maximumCauses))
      .map(\.element)
    return DiagnosisReport(causes: causes)
  }

  private static func cpuSaturation(
    _ input: DiagnosisInput, _ window: RecentWindow, _ thresholds: DiagnosisThresholds
  ) -> Diagnosis? {
    guard let average = window.sustainedMean(.cpu) else { return nil }
    let minutes = DiagnosisText.minutes(thresholds.sustainedWindow)
    var evidence = ["CPU \(ValueFormat.percent(average)) busy on average for the last \(minutes)"]
    if let cores = input.logicalCores, cores > 0 {
      let busy = min(cores, Int((average * Double(cores)).rounded()))
      evidence.append("\(busy) of \(cores) cores busy")
    }
    let busyFor = window.trailingDuration(of: .cpu, atLeast: thresholds.busyCPU)
    if busyFor >= 60 { evidence.append("Busy for \(DiagnosisText.minutes(busyFor))") }
    let contributors = top(input.processes, by: .cpu, minimum: 5, count: thresholds.contributorsPerCause)
    let quittable = (contributors.first?.value ?? 0) >= thresholds.quittableCPUPercent
    return Diagnosis(
      cause: .cpuSaturation, title: "CPU saturated", evidence: evidence, contributors: contributors,
      action: action(contributors, quit: quittable), score: thresholds.cpu.score(average))
  }

  private static func memoryPressure(
    _ input: DiagnosisInput, _ window: RecentWindow, _ thresholds: DiagnosisThresholds
  ) -> Diagnosis? {
    let pressure = HistoryPressure.worst(input.current.memoryPressure, window.worstMemoryPressure)
    let swapGrowth = window.growth(of: .swap)
    let used = input.current.memoryUsedFraction
    let pressureScore: Double =
      switch pressure {
      case .critical: 1
      case .high: 0.85
      case .elevated: 0.65
      case .normal, nil: 0
      }
    let score = max(
      pressureScore, 0.9 * thresholds.swapGrowth.score(swapGrowth), 0.4 * thresholds.memoryUsed.score(used))
    guard score > 0 else { return nil }
    var evidence: [String] = []
    if let pressure { evidence.append("Memory pressure \(pressure.title)") }
    if let swapGrowth, swapGrowth > 0 {
      evidence.append(
        "Swap +\(DiagnosisText.bytes(swapGrowth)) in the last \(DiagnosisText.minutes(window.span))")
    }
    if let used { evidence.append("Memory \(ValueFormat.percent(used)) used") }
    let contributors = top(input.processes, by: .memory, minimum: 0, count: thresholds.contributorsPerCause)
    let quittable = (pressure ?? .normal) >= .high || (swapGrowth ?? 0) >= thresholds.quittableSwapGrowth
    let title =
      pressure.map { $0 > .normal ? "Memory pressure \($0.title)" : "Swap growing" } ?? "Swap growing"
    return Diagnosis(
      cause: .memoryPressure, title: title, evidence: evidence, contributors: contributors,
      action: action(contributors, quit: quittable), score: score)
  }

  private static func thermalPressure(
    _ input: DiagnosisInput, _ window: RecentWindow, _ thresholds: DiagnosisThresholds
  ) -> Diagnosis? {
    guard let thermal = HistoryPressure.worst(input.current.thermal, window.worstThermal), thermal > .normal
    else { return nil }
    let watts = window.sustainedMean(.systemWatts)
    let base: Double =
      switch thermal {
      case .critical: 1
      case .high: 0.8
      case .elevated, .normal: 0.4
      }
    let powerBoost = thresholds.systemWatts.score(watts) >= 0.5 ? 0.15 : 0
    var evidence = ["Thermal pressure \(thermal.title)"]
    if let watts { evidence.append("System power \(DiagnosisText.watts(watts)) on average") }
    let contributors = energyContributors(input.processes, count: thresholds.contributorsPerCause)
    return Diagnosis(
      cause: .thermalPressure, title: "Thermal pressure \(thermal.title)", evidence: evidence,
      contributors: contributors, action: action(contributors, quit: false), score: min(1, base + powerBoost))
  }

  private static func diskActivity(
    _ input: DiagnosisInput, _ window: RecentWindow, _ thresholds: DiagnosisThresholds
  ) -> Diagnosis? {
    let read = window.sustainedMean(.diskRead)
    let written = window.sustainedMean(.diskWrite)
    guard read != nil || written != nil else { return nil }
    let total = (read ?? 0) + (written ?? 0)
    let minutes = DiagnosisText.minutes(thresholds.sustainedWindow)
    let evidence = [
      "Disk \(ValueFormat.rate(total)) on average for the last \(minutes)",
      "Read \(ValueFormat.rate(read)), write \(ValueFormat.rate(written))",
    ]
    let contributors = top(input.processes, by: .disk, minimum: 1_000_000, count: thresholds.contributorsPerCause)
    return Diagnosis(
      cause: .diskActivity, title: "Heavy disk activity", evidence: evidence, contributors: contributors,
      action: action(contributors, quit: false), score: thresholds.diskBytesPerSecond.score(total))
  }

  private static func gpuLoad(_ window: RecentWindow, _ thresholds: DiagnosisThresholds) -> Diagnosis? {
    guard let average = window.sustainedMean(.gpu) else { return nil }
    let minutes = DiagnosisText.minutes(thresholds.sustainedWindow)
    return Diagnosis(
      cause: .gpuLoad, title: "GPU busy",
      evidence: ["GPU \(ValueFormat.percent(average)) busy on average for the last \(minutes)"],
      contributors: [], action: .none, score: thresholds.gpu.score(average))
  }

  private static func powerDraw(
    _ input: DiagnosisInput, _ window: RecentWindow, _ thresholds: DiagnosisThresholds
  ) -> Diagnosis? {
    guard let watts = window.sustainedMean(.systemWatts) else { return nil }
    let minutes = DiagnosisText.minutes(thresholds.sustainedWindow)
    let contributors = energyContributors(input.processes, count: thresholds.contributorsPerCause)
    return Diagnosis(
      cause: .powerDraw, title: "High power draw",
      evidence: ["System power \(DiagnosisText.watts(watts)) on average for the last \(minutes)"],
      contributors: contributors, action: action(contributors, quit: false),
      score: thresholds.systemWatts.score(watts))
  }

  private static func action(_ contributors: [DiagnosisContributor], quit: Bool) -> Diagnosis.Action {
    guard !contributors.isEmpty else { return .none }
    return quit ? .quit : .inspect
  }

  /// Measured power ranks heat best; CPU stands in when no process power is available.
  private static func energyContributors(_ processes: [HistoryProcessPoint], count: Int) -> [DiagnosisContributor] {
    let byWatts = top(processes, by: .watts, minimum: 0.1, count: count)
    return byWatts.isEmpty ? top(processes, by: .cpu, minimum: 5, count: count) : byWatts
  }

  private static func top(
    _ processes: [HistoryProcessPoint], by metric: HistoryProcessMetric, minimum: Double, count: Int
  ) -> [DiagnosisContributor] {
    processes
      .compactMap { process in process[metric].map { (process, $0) } }
      .filter { $0.1.isFinite && $0.1 > minimum }
      .sorted { ($0.1, $1.0.identity.pid) > ($1.1, $0.0.identity.pid) }
      .prefix(max(0, count))
      .map { process, value in
        DiagnosisContributor(
          identity: process.identity, name: process.name, project: process.project, value: value,
          formattedValue: DiagnosisText.value(value, metric: metric))
      }
  }
}

private struct RecentWindow {
  let input: DiagnosisInput
  let sustained: TimeInterval

  private var now: Double { input.current.time.timeIntervalSinceReferenceDate }

  var span: TimeInterval {
    guard let first = input.recent.first else { return 0 }
    return max(0, now - first.time.timeIntervalSinceReferenceDate)
  }

  var worstMemoryPressure: HistoryPressure? {
    input.recent.reduce(nil) { HistoryPressure.worst($0, $1.memoryPressure) }
  }

  var worstThermal: HistoryPressure? {
    input.recent.reduce(nil) { HistoryPressure.worst($0, $1.thermal) }
  }

  /// Mean over the sustained window, the current reading counted once.
  func sustainedMean(_ metric: HistoryMetric) -> Double? {
    var sum = 0.0
    var weight = 0.0
    for point in input.recent where point.end.timeIntervalSinceReferenceDate > now - sustained {
      guard let value = point[metric] else { continue }
      sum += value.mean * Double(point.sampleCount)
      weight += Double(point.sampleCount)
    }
    if let current = input.current[metric], current.isFinite, current >= 0 {
      sum += current
      weight += 1
    }
    return weight > 0 ? sum / weight : nil
  }

  func growth(of metric: HistoryMetric) -> Double? {
    guard let current = input.current[metric],
      let earliest = input.recent.lazy.compactMap({ $0[metric]?.mean }).first
    else { return nil }
    return current - earliest
  }

  /// How long, back from now, every summary has stayed at or above `level`.
  func trailingDuration(of metric: HistoryMetric, atLeast level: Double) -> TimeInterval {
    guard let current = input.current[metric], current >= level else { return 0 }
    var earliest = now
    for point in input.recent.reversed() {
      guard let value = point[metric], value.mean >= level else { break }
      earliest = point.time.timeIntervalSinceReferenceDate
    }
    return now - earliest
  }
}

private enum DiagnosisText {
  static func minutes(_ duration: TimeInterval) -> String {
    "\(max(1, Int((duration / 60).rounded()))) min"
  }

  static func bytes(_ value: Double) -> String {
    ValueFormat.bytes(UInt64(max(0, min(value, Double(UInt64.max / 2)))))
  }

  static func watts(_ value: Double) -> String { String(format: "%.1f W", value) }

  static func value(_ value: Double, metric: HistoryProcessMetric) -> String {
    switch metric {
    case .cpu: ValueFormat.processCPU(value)
    case .memory: bytes(value)
    case .watts: watts(value)
    case .disk, .network: ValueFormat.rate(value)
    }
  }
}
