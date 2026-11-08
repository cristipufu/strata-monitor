import Foundation
import StrataCore

// The Explorer's process columns. Optional columns start hidden and are shown from the
// table header's menu; the table remembers the choice.
enum ProcessColumns {
  static func individual() -> [ExplorerColumn<ProcessSample>] {
    [
      ExplorerColumn(
        title: String(localized: "Process"), width: 230, value: \.displayName, sortedBy: ProcessSort.name),
      ExplorerColumn(
        title: String(localized: "User"), width: 100, value: { $0.userName ?? String($0.userID) },
        sortedBy: ProcessSort.user),
      ExplorerColumn(
        title: String(localized: "CPU"), width: 70,
        value: \.cpuDescription, monospaced: true,
        sortedBy: ProcessSort.cpu),
      ExplorerColumn(
        title: String(localized: "Footprint"), width: 85,
        value: { $0.footprintBytes.map(ValueFormat.bytes) ?? ReadingValue.unavailable },
        monospaced: true, sortedBy: ProcessSort.memory),
      ExplorerColumn(
        title: String(localized: "Power"), width: 75, value: { power($0.watts, readable: $0.activity != nil) },
        monospaced: true, sortedBy: ProcessSort.power),
      ExplorerColumn(
        title: String(localized: "CPU Time"), width: 85,
        value: {
          $0.cpuTimeNanoseconds.map { ValueFormat.cpuTime(nanoseconds: $0) }
            ?? ReadingValue.unavailable
        }, monospaced: true, sortedBy: ProcessSort.cpuTime, isShownByDefault: false),
      ExplorerColumn(
        title: String(localized: "Threads"), width: 65,
        value: { $0.threads.map { String($0) } ?? ReadingValue.unavailable }, monospaced: true,
        sortedBy: ProcessSort.threads, isShownByDefault: false),
      ExplorerColumn(
        title: String(localized: "Wakeups"), width: 80,
        value: { perSecond($0.wakeupsPerSecond, readable: $0.activity != nil) },
        monospaced: true, sortedBy: ProcessSort.wakeups, isShownByDefault: false),
      ExplorerColumn(
        title: String(localized: "Disk Reads"), width: 85,
        value: { rate($0.diskReadBytesPerSecond, readable: $0.diskReadBytes != nil) },
        monospaced: true, sortedBy: ProcessSort.diskRead, isShownByDefault: false),
      ExplorerColumn(
        title: String(localized: "Disk Writes"), width: 85,
        value: { rate($0.diskWrittenBytesPerSecond, readable: $0.diskWrittenBytes != nil) },
        monospaced: true, sortedBy: ProcessSort.diskWrite, isShownByDefault: false),
      ExplorerColumn(
        title: String(localized: "GPU"), width: 65,
        value: { $0.gpuPercent.map(ValueFormat.processCPU) ?? ReadingValue.notObserved },
        monospaced: true, sortedBy: ProcessSort.gpu, isShownByDefault: false),
      ExplorerColumn(
        title: String(localized: "GPU Time"), width: 85,
        value: {
          $0.gpuTimeNanoseconds.map { ValueFormat.cpuTime(nanoseconds: $0) }
            ?? ReadingValue.notObserved
        }, monospaced: true, sortedBy: ProcessSort.gpuTime, isShownByDefault: false),
      ExplorerColumn(
        title: String(localized: "State"), width: 80, value: { state($0.runState) }, sortedBy: ProcessSort.state,
        isShownByDefault: false),
      ExplorerColumn(
        title: String(localized: "Kind"), width: 70, value: { kind(translated: $0.isTranslated) },
        sortedBy: ProcessSort.kind, isShownByDefault: false),
      ExplorerColumn(
        title: String(localized: "Started"), width: 130, value: { started($0.id) }, monospaced: true,
        sortedBy: ProcessSort.started, isShownByDefault: false),
      ExplorerColumn(
        title: "PID", width: 60, value: { String($0.id.pid) }, monospaced: true,
        sortedBy: ProcessSort.pid),
    ]
  }

  static func families() -> [ExplorerColumn<ProcessTreeRow>] {
    [
      ExplorerColumn(
        title: String(localized: "Process Family"), width: 260, value: \.title, sortedBy: ProcessSort.name),
      ExplorerColumn(
        title: String(localized: "CPU"), width: 80,
        value: { row in
          ReadingValue.processRate(
            row.cpu.map { (row.partialCPU ? "≥" : "") + ValueFormat.processCPU($0) },
            readable: row.isCPUReadable)
        }, monospaced: true, sortedBy: ProcessSort.cpu),
      ExplorerColumn(
        title: String(localized: "Footprint"), width: 90,
        value: { row in
          row.footprint.map { (row.partialMemory ? "≥" : "") + ValueFormat.bytes($0) }
            ?? ReadingValue.unavailable
        }, monospaced: true, sortedBy: ProcessSort.memory),
      ExplorerColumn(
        title: String(localized: "Power"), width: 75,
        value: { power($0.orderingValues.watts, readable: $0.isActivityReadable) },
        monospaced: true, sortedBy: ProcessSort.power),
      ExplorerColumn(
        title: String(localized: "Threads"), width: 65,
        value: { $0.orderingValues.threads.map { String(Int($0)) } ?? ReadingValue.unavailable },
        monospaced: true, sortedBy: ProcessSort.threads, isShownByDefault: false),
      ExplorerColumn(
        title: String(localized: "Disk Writes"), width: 85,
        value: { rate($0.orderingValues.diskWrite, readable: $0.isActivityReadable) },
        monospaced: true, sortedBy: ProcessSort.diskWrite, isShownByDefault: false),
      ExplorerColumn(
        title: "PID", width: 60, value: { String($0.id.pid) }, monospaced: true,
        sortedBy: ProcessSort.pid),
    ]
  }

  private static func power(_ watts: Double?, readable: Bool) -> String {
    ReadingValue.processRate(watts.map(ValueFormat.watts), readable: readable)
  }
  private static func perSecond(_ value: Double?, readable: Bool) -> String {
    ReadingValue.processRate(value.map(ValueFormat.perSecond), readable: readable)
  }
  private static func rate(_ value: Double?, readable: Bool) -> String {
    ReadingValue.processRate(value.map { ValueFormat.rate($0) }, readable: readable)
  }
  static func state(_ state: ProcessRunState?) -> String {
    switch state {
    case .running: String(localized: "Running")
    case .stopped: String(localized: "Paused")
    case .zombie: String(localized: "Exited")
    case .starting: String(localized: "Starting")
    case nil: ReadingValue.unavailable
    }
  }
  static func kind(translated: Bool) -> String {
    translated ? String(localized: "Intel") : String(localized: "Apple")
  }
  private static func started(_ identity: ProcessIdentity) -> String {
    let date = identity.startDate
    return Calendar.current.isDateInToday(date)
      ? date.formatted(date: .omitted, time: .shortened)
      : date.formatted(date: .abbreviated, time: .shortened)
  }
}

extension ProcessTreeRow {
  var isActivityReadable: Bool {
    family?.members.contains { $0.activity != nil } ?? (process.activity != nil)
  }
}
