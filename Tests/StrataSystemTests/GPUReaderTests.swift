import Foundation
import IOKit
import StrataCore
import Testing

@testable import StrataSystem

// Immutable fixture data, never mutated after creation.
private struct AcceleratorFixture: AcceleratorRegistryWalking, @unchecked Sendable {
  let entries: [AcceleratorEntry]?
  func accelerators(includingClients: Bool) -> [AcceleratorEntry]? {
    includingClients
      ? entries
      : entries?.map {
        AcceleratorEntry(
          model: $0.model, statistics: $0.statistics, clients: nil, publishesUsage: false)
      }
  }
}

private func read(_ entries: [AcceleratorEntry]?) -> GPUReading? {
  GPUReader(walker: AcceleratorFixture(entries: entries)).read()
}

private var statistics: [String: Any] {
  [
    "Device Utilization %": 31, "Renderer Utilization %": 30, "Tiler Utilization %": 15,
    "In use system memory": 918_000_000, "Alloc system memory": 2_948_087_808,
  ]
}

private func client(_ creator: Any?, _ times: [Any]) -> AcceleratorClientEntry {
  AcceleratorClientEntry(
    creator: creator,
    appUsage: times.map { ["API": "Metal", "accumulatedGPUTime": $0] as [String: Any] })
}

private func accelerator(
  _ clients: [AcceleratorClientEntry]?, statistics: Any? = statistics,
  model: Any? = "Apple M4 Pro", publishesUsage: Bool = true
) -> AcceleratorEntry {
  AcceleratorEntry(
    model: model, statistics: statistics, clients: clients, publishesUsage: publishesUsage)
}

@Test func gpuSystemStatisticsBecomeFractionsAndBytes() throws {
  let device = try #require(read([accelerator([])])?.devices.first)
  #expect(device.model == "Apple M4 Pro")
  #expect(device.deviceUtilization == 0.31 && device.rendererUtilization == 0.3)
  #expect(device.tilerUtilization == 0.15 && device.inUseSystemMemoryBytes == 918_000_000)
}

@Test func aDeviceOnlyReadSkipsProcessUsage() throws {
  let entries = [accelerator([client("pid 98483, WindowServer", [1_000])])]
  let reading = try #require(
    GPUReader(walker: AcceleratorFixture(entries: entries)).read(includingProcesses: false))
  #expect(reading.devices.first?.deviceUtilization == 0.31)
  #expect(reading.processTimes == nil, "Unread process usage is unknown, not zero")
}

@Test func gpuTimeIsSummedPerProcessAcrossClientsAndQueues() throws {
  let reading = try #require(
    read([
      accelerator([
        client("pid 98483, WindowServer", [1_485_353_476_416, 5_009_375]),
        client("pid 65027, ghostty", [21_219_764_958]),
        client("pid 65027, ghostty", [5_056_469_791, 12_579_234_125]),
        client("pid 609, runningboardd", []),
      ])
    ]))
  #expect(
    reading.processTimes == [
      98_483: 1_485_358_485_791, 65_027: 38_855_468_874, 609: 0,
    ])
  #expect(reading.unreadablePIDs.isEmpty)
}

@Test func gpuClientsFromSeveralAcceleratorsAreCombined() throws {
  let reading = try #require(
    read([
      accelerator([client("pid 10, a", [100])]),
      accelerator([client("pid 10, a", [50]), client("pid 11, b", [1])], model: nil),
    ]))
  #expect(reading.devices.count == 2 && reading.devices[1].model == nil)
  #expect(reading.processTimes == [10: 150, 11: 1])
}

@Test func unreadableClientUsageMakesOnlyThatProcessUnknown() throws {
  let reading = try #require(
    read([
      accelerator([
        client("pid 10, a", [100]), client("pid 10, a", ["fast"]),
        client("pid 11, b", [-5]), client("pid 12, c", [1.5]), client("pid 13, d", [true]),
        AcceleratorClientEntry(creator: "pid 14, e", appUsage: "none"),
        AcceleratorClientEntry(creator: "pid 15, f", appUsage: [7]),
        client("pid 16, g", [Int64.max, Int64.max, 2]), client("pid 17, h", [Int64.max]),
        client("pid 17, h", [Int64.max, 2]), client("pid 18, i", [4]),
        client("pid 19, j", [UInt64.max]),
      ])
    ]))
  #expect(reading.processTimes == [18: 4])
  #expect(reading.unreadablePIDs == [10, 11, 12, 13, 14, 15, 16, 17, 19])
}

@Test func unattributableGPUTimeMakesTheWholeSampleUnreadable() throws {
  for creator in [nil, 5, "pid", "pid , x", "pid -4, x", "pid 99999999999, x", "process 4"]
    as [Any?]
  {
    let reading = try #require(
      read([accelerator([client("pid 1, a", [1]), client(creator, [100])])]))
    #expect(reading.processTimes == nil)
    #expect(reading.devices.first?.deviceUtilization == 0.31)
  }
}

@Test func clientListsChangedDuringTheWalkMakeProcessTimesUnreadable() throws {
  let reading = try #require(
    read([accelerator([client("pid 1, a", [1])]), accelerator(nil)]))
  #expect(reading.processTimes == nil && reading.devices.count == 2)
}

@Test func driversThatDoNotTrackUsageAreUnavailableNotZero() throws {
  let untracked = try #require(read([accelerator([], publishesUsage: false)]))
  #expect(untracked.processTimes == nil && untracked.devices.count == 1)
  let mixed = try #require(
    read([
      accelerator([client("pid 1, a", [1])]), accelerator([], publishesUsage: false),
    ]))
  #expect(mixed.processTimes == nil)
  #expect(read([accelerator([])])?.processTimes == [:])
}

@Test func garbageStatisticsAreUnavailableNotZero() throws {
  for garbage in [
    nil, "stats", ["Device Utilization %": 101, "Renderer Utilization %": -1],
    [
      "Device Utilization %": true, "Tiler Utilization %": 12.5, "In use system memory": -1,
      "Renderer Utilization %": "31",
    ],
  ] as [Any?] {
    let device = try #require(read([accelerator([], statistics: garbage, model: 7)])?.devices.first)
    #expect(device.deviceUtilization == nil && device.rendererUtilization == nil)
    #expect(device.tilerUtilization == nil && device.inUseSystemMemoryBytes == nil)
    #expect(device.model == nil)
  }
}

@Test func modelNamesMayArriveAsBytes() throws {
  let device = try #require(
    read([accelerator([], model: Data("Apple M4 Pro\0".utf8))])?.devices.first)
  #expect(device.model == "Apple M4 Pro")
}

@Test func missingAcceleratorsAreUnavailable() {
  #expect(read(nil) == nil)
  #expect(read([]) == nil)
}

extension SystemIntegrationTests {
  @Test func liveGPUReadIsPlausibleWithoutPrivileges() {
    guard let reading = GPUReader().read() else { return }  // Virtual machines may have no GPU.
    for device in reading.devices {
      for fraction in [device.deviceUtilization, device.rendererUtilization] {
        if let fraction { #expect((0...1).contains(fraction)) }
      }
    }
    for pid in reading.processTimes?.keys.map({ $0 }) ?? [] { #expect(pid >= 0) }
  }

  @Test func repeatedGPUReadsBalanceRegistrySendRights() {
    let service = IOServiceGetMatchingService(
      kIOMainPortDefault, IOServiceMatching("IOAccelerator"))
    guard service != 0 else { return }
    defer { IOObjectRelease(service) }
    let reader = GPUReader()
    _ = reader.read()
    var before: mach_port_urefs_t = 0
    var after: mach_port_urefs_t = 0
    #expect(
      mach_port_get_refs(mach_task_self_, service, mach_port_right_t(MACH_PORT_RIGHT_SEND), &before)
        == KERN_SUCCESS)
    for _ in 0..<200 { _ = reader.read() }
    #expect(
      mach_port_get_refs(mach_task_self_, service, mach_port_right_t(MACH_PORT_RIGHT_SEND), &after)
        == KERN_SUCCESS)
    #expect(before == after)
  }
}

private final class AdvancingAccelerator: AcceleratorRegistryWalking, @unchecked Sendable {
  private let lock = NSLock()
  private var reads: UInt64 = 0
  func accelerators(includingClients: Bool) -> [AcceleratorEntry]? {
    let time = lock.withLock {
      reads += 1
      return reads * 500_000_000
    }
    return [accelerator([client("pid \(getpid()), StrataSystemTests", [time])])]
  }
}

@Test func processSamplesCarryTheirShareOfGPUTimeAndTheSystemUtilization() async throws {
  let collector = SystemCollector(gpuReader: GPUReader(walker: AdvancingAccelerator()))
  _ = await collector.sample(includeProcesses: true)
  try await Task.sleep(for: .milliseconds(200))
  let sample = await collector.sample(includeProcesses: true)
  let own = try #require(sample.processes.first { $0.id.pid == getpid() })
  #expect(own.gpuTimeNanoseconds == 1_000_000_000)
  #expect(own.gpuPercent.map { $0 > 0 } == true)
  #expect(sample.gpu?.deviceUtilization == 0.31)
  let menuBarOnly = await collector.sample(includeProcesses: false)
  #expect(menuBarOnly.gpu == nil, "The GPU is read only while processes are wanted")
}
