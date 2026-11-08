import Foundation
import IOKit
import StrataCore

struct AcceleratorClientEntry {
  let creator: Any?
  let appUsage: Any?
}

struct AcceleratorEntry {
  let model: Any?
  let statistics: Any?
  // Nil when its clients could not all be listed.
  let clients: [AcceleratorClientEntry]?
  // False when no client publishes usage, as with drivers that do not track it.
  let publishesUsage: Bool
}

protocol AcceleratorRegistryWalking: Sendable {
  // Nil when the registry cannot be queried. Without clients, entries carry no process usage.
  func accelerators(includingClients: Bool) -> [AcceleratorEntry]?
}

public struct GPUReader: Sendable {
  private let walker: any AcceleratorRegistryWalking

  public init() { self.init(walker: NativeAcceleratorRegistry()) }

  init(walker: any AcceleratorRegistryWalking) { self.walker = walker }

  // Per-process GPU time walks every GPU client; the device's own load needs none of them.
  public func read(includingProcesses: Bool = true) -> GPUReading? {
    guard let accelerators = walker.accelerators(includingClients: includingProcesses),
      !accelerators.isEmpty
    else { return nil }
    let clientLists = accelerators.compactMap(\.clients)
    let usageIsComplete =
      clientLists.count == accelerators.count && accelerators.allSatisfy(\.publishesUsage)
    let usage = usageIsComplete ? Self.processUsage(clientLists.flatMap { $0 }) : nil
    return GPUReading(
      devices: accelerators.map(Self.device), processTimes: usage?.times,
      unreadablePIDs: usage?.unreadable ?? [])
  }

  private static func device(_ entry: AcceleratorEntry) -> GPUSystemReading {
    let statistics = entry.statistics as? [String: Any] ?? [:]
    return GPUSystemReading(
      model: model(entry.model),
      deviceUtilization: utilization(statistics["Device Utilization %"]),
      rendererUtilization: utilization(statistics["Renderer Utilization %"]),
      tilerUtilization: utilization(statistics["Tiler Utilization %"]),
      inUseSystemMemoryBytes: counter(statistics["In use system memory"]))
  }

  private static func processUsage(_ clients: [AcceleratorClientEntry])
    -> (times: GPUProcessTimes, unreadable: Set<Int32>)?
  {
    var times: GPUProcessTimes = [:]
    var unreadable: Set<Int32> = []
    for client in clients {
      // Time that belongs to an unknown process would make another sample look like a burst.
      guard let pid = creatorPID(client.creator) else { return nil }
      if let time = accumulatedTime(client.appUsage), let sum = sum(times[pid, default: 0], time) {
        times[pid] = sum
      } else {
        unreadable.insert(pid)
      }
    }
    for pid in unreadable { times[pid] = nil }
    return (times, unreadable)
  }

  private static func creatorPID(_ value: Any?) -> Int32? {
    guard let text = value as? String, text.hasPrefix("pid ") else { return nil }
    guard let pid = Int32(text.dropFirst(4).prefix { $0 != "," }), pid >= 0 else { return nil }
    return pid
  }

  private static func accumulatedTime(_ value: Any?) -> UInt64? {
    guard let entries = value as? [Any] else { return nil }
    var total: UInt64 = 0
    for entry in entries {
      guard let usage = entry as? [String: Any], let time = counter(usage["accumulatedGPUTime"]),
        let sum = sum(total, time)
      else { return nil }
      total = sum
    }
    return total
  }

  private static func sum(_ left: UInt64, _ right: UInt64) -> UInt64? {
    let (sum, overflow) = left.addingReportingOverflow(right)
    return overflow ? nil : sum
  }

  private static func utilization(_ value: Any?) -> Double? {
    guard let percent = PowerSourceValue.integer(value), (0...100).contains(percent) else {
      return nil
    }
    return Double(percent) / 100
  }

  private static func counter(_ value: Any?) -> UInt64? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
      return nil
    }
    let integer = number.int64Value
    guard Double(integer) == number.doubleValue else { return nil }
    return UInt64(exactly: integer)
  }

  private static func model(_ value: Any?) -> String? {
    let text = value as? String ?? (value as? Data).flatMap { String(data: $0, encoding: .utf8) }
    let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
    return trimmed?.isEmpty == false ? trimmed : nil
  }
}

struct NativeAcceleratorRegistry: AcceleratorRegistryWalking {
  func accelerators(includingClients: Bool) -> [AcceleratorEntry]? {
    var services: io_iterator_t = 0
    guard
      IOServiceGetMatchingServices(
        kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &services) == KERN_SUCCESS
    else { return nil }
    defer { IOObjectRelease(services) }
    var entries: [AcceleratorEntry] = []
    while case let service = IOIteratorNext(services), service != IO_OBJECT_NULL {
      defer { IOObjectRelease(service) }
      let clients = includingClients ? clients(of: service) : nil
      entries.append(
        AcceleratorEntry(
          model: property(service, "model"), statistics: property(service, "PerformanceStatistics"),
          clients: clients?.withUsage, publishesUsage: clients?.publishUsage ?? false))
    }
    return entries
  }

  private func clients(of service: io_registry_entry_t)
    -> (withUsage: [AcceleratorClientEntry], publishUsage: Bool)?
  {
    var children: io_iterator_t = 0
    guard IORegistryEntryGetChildIterator(service, kIOServicePlane, &children) == KERN_SUCCESS
    else { return nil }
    defer { IOObjectRelease(children) }
    var clients: [AcceleratorClientEntry] = []
    var publishUsage = false
    while case let child = IOIteratorNext(children), child != IO_OBJECT_NULL {
      defer { IOObjectRelease(child) }
      guard let usage = property(child, "AppUsage") else { continue }
      publishUsage = true
      // Most clients never submit work; skipping them saves a registry query each.
      if (usage as? [Any])?.isEmpty == true { continue }
      clients.append(
        AcceleratorClientEntry(creator: property(child, "IOUserClientCreator"), appUsage: usage))
    }
    return IOIteratorIsValid(children) != 0 ? (clients, publishUsage) : nil
  }

  private func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
    IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
      .takeRetainedValue()
  }
}
