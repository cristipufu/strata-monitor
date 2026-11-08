import Foundation
import StrataCore
import Testing

private let gibibyte = Double(1 << 30)

private struct Conditions {
  var cpu = 0.05
  var memoryUsed = 0.55
  var pressure = HistoryPressure.normal
  var swapGrowth = 0.0
  var thermal = HistoryPressure.normal
  var diskRead = 1_000_000.0
  var diskWrite = 500_000.0
  var gpu = 0.05
  var watts = 6.0
}

/// Ten minutes of steady 2 s readings ending at the current one.
private func input(_ conditions: Conditions, processes: [HistoryProcessPoint] = []) -> DiagnosisInput {
  var history = TieredHistory()
  var current = HistorySystemPoint(time: historyTime(0))
  for second in stride(from: 0.0, through: 600, by: 2) {
    current = HistorySystemPoint(
      time: historyTime(second), uptime: second, cpu: conditions.cpu, memoryUsedFraction: conditions.memoryUsed,
      memoryPressure: conditions.pressure, swapBytes: gibibyte + conditions.swapGrowth * second / 600,
      diskReadBytesPerSecond: conditions.diskRead, diskWriteBytesPerSecond: conditions.diskWrite,
      gpu: conditions.gpu, systemWatts: conditions.watts, thermal: conditions.thermal)
    history.append(current)
  }
  let recent = history.points(in: historyTime(0)...historyTime(598))
  return DiagnosisInput(current: current, processes: processes, recent: recent, logicalCores: 14)
}

private let falcon = historyProcess(
  88, name: "com.crowdstrike.falcon.Agent", cpu: 160, footprint: 400 << 20, watts: 2.5)
private let culprit = HistoryProcessPoint(
  identity: historyIdentity(501), name: "bun", project: "culprit", cpuPercent: 42, footprintBytes: 1 << 30,
  watts: 0.8, diskBytesPerSecond: 3_000_000)
private let xcode = historyProcess(612, name: "Xcode", cpu: 12, footprint: 6 << 30, watts: 1.1)
private let indexer = historyProcess(77, name: "mds_stores", cpu: 30, footprint: 200 << 20, disk: 250_000_000)
private let idleHelper = historyProcess(900, name: "helper", cpu: 0.5, footprint: 10 << 20)
private let everyone = [falcon, culprit, xcode, indexer, idleHelper]

private struct Scenario: CustomTestStringConvertible, Sendable {
  let name: String
  let conditions: Conditions
  let causes: [Diagnosis.Cause]
  let contributors: [String]
  let action: Diagnosis.Action?

  var testDescription: String { name }
}

private let scenarios: [Scenario] = [
  Scenario(name: "idle", conditions: Conditions(), causes: [], contributors: [], action: nil),
  Scenario(
    name: "CPU-bound", conditions: Conditions(cpu: 0.98), causes: [.cpuSaturation],
    contributors: ["com.crowdstrike.falcon.Agent", "bun", "mds_stores"], action: .quit),
  Scenario(
    name: "memory-bound", conditions: Conditions(memoryUsed: 0.97, pressure: .critical, swapGrowth: 3 * gibibyte),
    causes: [.memoryPressure], contributors: ["Xcode", "bun", "com.crowdstrike.falcon.Agent"], action: .quit),
  Scenario(
    name: "thermal", conditions: Conditions(thermal: .high, watts: 45), causes: [.thermalPressure, .powerDraw],
    contributors: ["com.crowdstrike.falcon.Agent", "Xcode", "bun"], action: .inspect),
  Scenario(
    name: "disk-bound", conditions: Conditions(diskRead: 300_000_000, diskWrite: 100_000_000),
    causes: [.diskActivity], contributors: ["mds_stores", "bun"], action: .inspect),
  Scenario(
    name: "mixed",
    conditions: Conditions(
      cpu: 0.97, pressure: .high, swapGrowth: 1.5 * gibibyte, diskRead: 250_000_000, diskWrite: 50_000_000,
      gpu: 0.9),
    causes: [.cpuSaturation, .memoryPressure, .gpuLoad],
    contributors: ["com.crowdstrike.falcon.Agent", "bun", "mds_stores"], action: .quit),
]

@Test(arguments: scenarios)
private func diagnosisRanksCausesWithEvidence(_ scenario: Scenario) throws {
  let report = DiagnosisEngine.diagnose(input(scenario.conditions, processes: everyone))
  #expect(report.causes.map(\.cause) == scenario.causes)
  #expect(report.causes.count <= 3)
  #expect(zip(report.causes, report.causes.dropFirst()).allSatisfy { $0.score >= $1.score })
  #expect(report.causes.allSatisfy { !$0.evidence.isEmpty && $0.score >= 0.5 })
  guard let first = report.causes.first else {
    #expect(report.isNothingUnusual)
    #expect(report.headline == "Nothing unusual")
    return
  }
  #expect(first.contributors.map(\.name) == scenario.contributors)
  #expect(first.action == scenario.action)
  #expect(report.headline == first.title)
}

@Test func cpuEvidenceCountsCoresAndBusyTime() throws {
  let report = DiagnosisEngine.diagnose(input(Conditions(cpu: 0.98), processes: everyone))
  let cpu = try #require(report.causes.first)
  #expect(cpu.title == "CPU saturated")
  #expect(cpu.evidence.contains("CPU 98% busy on average for the last 3 min"))
  #expect(cpu.evidence.contains("14 of 14 cores busy"))
  #expect(cpu.evidence.contains("Busy for 10 min"))
  let top = try #require(cpu.contributors.first)
  #expect(top.identity == historyIdentity(88))
  #expect(top.formattedValue == "160.0%")
  #expect(cpu.contributors.contains { $0.project == "culprit" })
}

@Test func memoryEvidenceReportsPressureAndSwapGrowth() throws {
  let conditions = Conditions(memoryUsed: 0.97, pressure: .critical, swapGrowth: 3 * gibibyte)
  let memory = try #require(DiagnosisEngine.diagnose(input(conditions, processes: everyone)).causes.first)
  #expect(memory.title == "Memory pressure critical")
  #expect(memory.evidence.first == "Memory pressure critical")
  #expect(memory.evidence.contains { $0.hasPrefix("Swap +") && $0.hasSuffix("in the last 10 min") })
  #expect(memory.evidence.contains("Memory 97% used"))
}

@Test func swapGrowthAloneCanExplainSlowness() throws {
  let report = DiagnosisEngine.diagnose(input(Conditions(swapGrowth: 2 * gibibyte), processes: [xcode]))
  let memory = try #require(report.causes.first)
  #expect(memory.cause == .memoryPressure)
  #expect(memory.title == "Swap growing")
  #expect(memory.action == .quit)
}

@Test func aMomentarySpikeIsNotACause() {
  var spike = input(Conditions(cpu: 0.2), processes: everyone)
  spike.current.cpu = 1
  spike.current.diskReadBytesPerSecond = 2_000_000_000
  #expect(DiagnosisEngine.diagnose(spike).isNothingUnusual)
}

@Test func heatWithoutProcessPowerFallsBackToCPUContributors() throws {
  let unpowered = [historyProcess(1, name: "render", cpu: 300), historyProcess(2, name: "idle", cpu: 1)]
  let report = DiagnosisEngine.diagnose(input(Conditions(thermal: .critical, watts: 10), processes: unpowered))
  let thermal = try #require(report.causes.first)
  #expect(thermal.cause == .thermalPressure)
  #expect(thermal.contributors.map(\.name) == ["render"])
  #expect(thermal.evidence == ["Thermal pressure critical", "System power 10.0 W on average"])
}

@Test func unavailableMeasurementsAreNotTreatedAsCauses() {
  let unmeasured = DiagnosisInput(
    current: HistorySystemPoint(time: historyTime(0)), processes: [historyProcess(1)], recent: [])
  #expect(DiagnosisEngine.diagnose(unmeasured).isNothingUnusual)
}

@Test func thresholdsDecideWhatCounts() {
  var thresholds = DiagnosisThresholds()
  thresholds.maximumCauses = 1
  let mixed = Conditions(cpu: 0.97, pressure: .high, gpu: 0.9)
  #expect(DiagnosisEngine.diagnose(input(mixed), thresholds: thresholds).causes.map(\.cause) == [.cpuSaturation])
  thresholds.minimumScore = 1.1
  #expect(DiagnosisEngine.diagnose(input(mixed), thresholds: thresholds).isNothingUnusual)
}
