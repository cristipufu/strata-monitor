import StrataCore
import Testing

private func identity(_ pid: Int32, started: UInt64 = 1) -> ProcessIdentity {
  ProcessIdentity(pid: pid, startSeconds: started, startMicroseconds: 0)
}

private func gpu(_ times: GPUProcessTimes?, unreadable: Set<Int32> = []) -> GPUReading {
  GPUReading(devices: [], processTimes: times, unreadablePIDs: unreadable)
}

@Test func gpuUsageIsTheShareOfWallTimeSpentOnTheGPU() {
  var rates = GPUUsageRates()
  let processes = [identity(10), identity(20)]
  _ = rates.fractions(of: gpu([10: 1_000_000_000, 20: 0]), for: processes, at: 1)
  let fractions = rates.fractions(
    of: gpu([10: 2_000_000_000, 20: 500_000_000]), for: processes, at: 3)
  #expect(fractions == [identity(10): 0.5, identity(20): 0.25])
}

@Test func processesWithoutGPUClientsUsedNoGPUTime() {
  var rates = GPUUsageRates()
  _ = rates.fractions(of: gpu([:]), for: [identity(30)], at: 1)
  #expect(rates.fractions(of: gpu([:]), for: [identity(30)], at: 2) == [identity(30): 0])
}

@Test func unreadableGPUSamplesAreNotZeroAndKeepBaselines() {
  var rates = GPUUsageRates()
  _ = rates.fractions(of: gpu([10: 0, 20: 0]), for: [identity(10), identity(20)], at: 1)
  #expect(rates.fractions(of: nil, for: [identity(10), identity(20)], at: 2).isEmpty)
  #expect(rates.fractions(of: gpu(nil), for: [identity(10), identity(20)], at: 3).isEmpty)
  let partial = rates.fractions(
    of: gpu([10: 1_000_000_000, 20: 9], unreadable: [20]), for: [identity(10), identity(20)], at: 4)
  #expect(Set(partial.keys) == [identity(10)])
  #expect(abs((partial[identity(10)] ?? 0) - 1.0 / 3) < 1e-12)
  let resumed = rates.fractions(
    of: gpu([10: 1_000_000_000, 20: 1_000_000_000]), for: [identity(10), identity(20)], at: 5)
  #expect(resumed == [identity(10): 0, identity(20): 0.25])
}

@Test func gpuCounterDropsFromClosedClientsAreResetsNotNegativeUsage() {
  var rates = GPUUsageRates()
  _ = rates.fractions(of: gpu([10: 5_000_000_000]), for: [identity(10)], at: 1)
  #expect(rates.fractions(of: gpu([10: 1_000_000_000]), for: [identity(10)], at: 2).isEmpty)
  #expect(
    rates.fractions(of: gpu([10: 1_500_000_000]), for: [identity(10)], at: 3)
      == [identity(10): 0.5])
}

@Test func gpuUsageGuardsAgainstProcessIDReuse() {
  var rates = GPUUsageRates()
  _ = rates.fractions(of: gpu([10: 0]), for: [identity(10, started: 1)], at: 1)
  let reused = rates.fractions(
    of: gpu([10: 1_000_000_000]), for: [identity(10, started: 2)], at: 2)
  #expect(reused.isEmpty)
}

@Test func gpuReadingDistinguishesUnknownFromUnusedTime() {
  let reading = gpu([10: 7], unreadable: [20])
  #expect(reading.accumulatedTime(of: identity(10)) == 7)
  #expect(reading.accumulatedTime(of: identity(30)) == 0)
  #expect(reading.accumulatedTime(of: identity(20)) == nil)
  #expect(gpu(nil).accumulatedTime(of: identity(10)) == nil)
}

@Test func duplicateProcessIdentitiesAreCountedOnce() {
  var rates = GPUUsageRates()
  _ = rates.fractions(of: gpu([10: 0]), for: [identity(10), identity(10)], at: 1)
  let fractions = rates.fractions(
    of: gpu([10: 1_000_000_000]), for: [identity(10), identity(10)], at: 2)
  #expect(fractions == [identity(10): 1])
}
