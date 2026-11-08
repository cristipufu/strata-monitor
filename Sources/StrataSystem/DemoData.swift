import Foundation
import StrataCore

// Made-up but realistic readings for screenshots and demos, so no real process, device or
// network name is ever shown. Values drift a little over time so charts move.
public enum DemoData {
  struct Process {
    let pid: Int32
    let parent: Int32
    let user: UInt32
    let name: String
    let path: String
    let cpu: Double
    let megabytes: Double
    let watts: Double
    let gpu: Double
    let writtenKilobytes: Double
    let threads: Int
    var project: String?
  }

  static let users: [UInt32: String] = [0: "root", 88: "_windowserver", 501: "alex"]
  static let xcodeTools = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin"
  static let processes: [Process] = [
    Process(pid: 0, parent: 0, user: 0, name: "kernel_task", path: "", cpu: 9, megabytes: 3_800, watts: 1.1, gpu: 0, writtenKilobytes: 0, threads: 520),
    Process(pid: 1, parent: 0, user: 0, name: "launchd", path: "/sbin/launchd", cpu: 0.3, megabytes: 28, watts: 0.02, gpu: 0, writtenKilobytes: 0, threads: 4),
    Process(pid: 160, parent: 1, user: 88, name: "WindowServer", path: "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer", cpu: 11, megabytes: 610, watts: 1.6, gpu: 21, writtenKilobytes: 40, threads: 24),
    Process(pid: 300, parent: 1, user: 0, name: "mds_stores", path: "/System/Library/Frameworks/CoreServices.framework/Frameworks/Metadata.framework/Support/mds_stores", cpu: 6, megabytes: 140, watts: 0.4, gpu: 0, writtenKilobytes: 3_800, threads: 9),
    Process(pid: 320, parent: 1, user: 0, name: "backupd", path: "/System/Library/CoreServices/backupd.bundle/Contents/Resources/backupd", cpu: 4, megabytes: 96, watts: 0.3, gpu: 0, writtenKilobytes: 18_500, threads: 12),
    Process(pid: 340, parent: 1, user: 0, name: "coreaudiod", path: "/usr/sbin/coreaudiod", cpu: 1.2, megabytes: 30, watts: 0.1, gpu: 0, writtenKilobytes: 0, threads: 9),
    Process(pid: 600, parent: 1, user: 501, name: "Finder", path: "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder", cpu: 0.8, megabytes: 160, watts: 0.06, gpu: 0.2, writtenKilobytes: 10, threads: 8),
    Process(pid: 640, parent: 1, user: 501, name: "Safari", path: "/Applications/Safari.app/Contents/MacOS/Safari", cpu: 5, megabytes: 540, watts: 0.5, gpu: 2, writtenKilobytes: 60, threads: 22),
    Process(pid: 648, parent: 640, user: 501, name: "Safari Networking", path: "/Applications/Safari.app/Contents/MacOS/Safari Networking", cpu: 1.5, megabytes: 70, watts: 0.08, gpu: 0, writtenKilobytes: 30, threads: 9),
    Process(pid: 655, parent: 640, user: 501, name: "Safari Web Content", path: "/Applications/Safari.app/Contents/MacOS/Safari Web Content", cpu: 14, megabytes: 860, watts: 1.2, gpu: 4, writtenKilobytes: 20, threads: 18),
    Process(pid: 660, parent: 640, user: 501, name: "Safari Web Content", path: "/Applications/Safari.app/Contents/MacOS/Safari Web Content", cpu: 3, megabytes: 380, watts: 0.3, gpu: 1, writtenKilobytes: 5, threads: 14),
    Process(pid: 700, parent: 1, user: 501, name: "Music", path: "/System/Applications/Music.app/Contents/MacOS/Music", cpu: 2.2, megabytes: 190, watts: 0.3, gpu: 0.5, writtenKilobytes: 0, threads: 16),
    Process(pid: 720, parent: 1, user: 501, name: "Photos", path: "/System/Applications/Photos.app/Contents/MacOS/Photos", cpu: 3, megabytes: 640, watts: 0.4, gpu: 1.5, writtenKilobytes: 120, threads: 20),
    Process(pid: 730, parent: 720, user: 501, name: "photoanalysisd", path: "/System/Library/PrivateFrameworks/PhotoAnalysis.framework/Support/photoanalysisd", cpu: 46, megabytes: 720, watts: 2.8, gpu: 34, writtenKilobytes: 2_400, threads: 11),
    Process(pid: 760, parent: 1, user: 501, name: "Messages", path: "/System/Applications/Messages.app/Contents/MacOS/Messages", cpu: 0.6, megabytes: 150, watts: 0.05, gpu: 0.3, writtenKilobytes: 0, threads: 10),
    Process(pid: 780, parent: 1, user: 501, name: "Mail", path: "/System/Applications/Mail.app/Contents/MacOS/Mail", cpu: 1.1, megabytes: 260, watts: 0.1, gpu: 0.2, writtenKilobytes: 40, threads: 18),
    Process(pid: 812, parent: 1, user: 501, name: "Xcode", path: "/Applications/Xcode.app/Contents/MacOS/Xcode", cpu: 32, megabytes: 2_150, watts: 2.9, gpu: 3, writtenKilobytes: 900, threads: 48),
    Process(pid: 840, parent: 812, user: 501, name: "SourceKitService", path: "/Applications/Xcode.app/Contents/SharedFrameworks/SourceKitService", cpu: 21, megabytes: 940, watts: 1.4, gpu: 0, writtenKilobytes: 30, threads: 14),
    Process(pid: 851, parent: 812, user: 501, name: "swift-frontend", path: "\(xcodeTools)/swift-frontend", cpu: 97, megabytes: 610, watts: 3.6, gpu: 0, writtenKilobytes: 1_800, threads: 6),
    Process(pid: 852, parent: 812, user: 501, name: "swift-frontend", path: "\(xcodeTools)/swift-frontend", cpu: 91, megabytes: 540, watts: 3.3, gpu: 0, writtenKilobytes: 1_500, threads: 6),
    Process(pid: 853, parent: 812, user: 501, name: "swift-frontend", path: "\(xcodeTools)/swift-frontend", cpu: 84, megabytes: 470, watts: 3.1, gpu: 0, writtenKilobytes: 1_200, threads: 6),
    Process(pid: 900, parent: 1, user: 501, name: "Terminal", path: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal", cpu: 1.4, megabytes: 130, watts: 0.1, gpu: 0.4, writtenKilobytes: 0, threads: 8),
    Process(pid: 905, parent: 900, user: 501, name: "zsh", path: "/bin/zsh", cpu: 0, megabytes: 6, watts: 0, gpu: 0, writtenKilobytes: 0, threads: 1),
    Process(pid: 910, parent: 905, user: 501, name: "node", path: "/opt/homebrew/bin/node", cpu: 17, megabytes: 340, watts: 1.0, gpu: 0, writtenKilobytes: 210, threads: 11, project: "web-app"),
    Process(pid: 920, parent: 905, user: 501, name: "bun", path: "/opt/homebrew/bin/bun", cpu: 8, megabytes: 210, watts: 0.5, gpu: 0, writtenKilobytes: 90, threads: 9, project: "api"),
  ]

  // App bundles of the demo processes, for their icons.
  public static let applicationPaths: [Int32: String] = Dictionary(
    uniqueKeysWithValues: processes.compactMap { process in
      process.path.range(of: ".app/").map { (process.pid, String(process.path[..<$0.lowerBound]) + ".app") }
    })

  // A quick wobble on a slow swell, so both the last minute and the last day have shape.
  static func wave(_ seed: Int32, _ time: TimeInterval) -> Double {
    1 + 0.12 * sin(time / 2.7 + Double(seed)) + 0.22 * sin(time / 900 + Double(seed) * 0.7)
  }

  // The wave plus short bursts at irregular moments, as real workloads have. The same moment
  // always gives the same burst, so the history and the live reading agree.
  static func busy(_ seed: Int32, _ time: TimeInterval) -> Double {
    var hash = UInt64(bitPattern: Int64(Int(time / 6))) &* 0x9E37_79B9_7F4A_7C15
    hash ^= UInt64(bitPattern: Int64(seed)) &* 0xBF58_476D_1CE4_E5B9
    hash ^= hash >> 29
    return wave(seed, time) + (hash % 4 == 0 ? 0.5 + Double(hash % 60) / 100 : 0)
  }

  // The last minute of readings, one every two seconds, for the live charts.
  public static func recentReadings() -> [SystemSample] {
    let uptime = ProcessInfo.processInfo.systemUptime
    return (1...30).reversed().map {
      DemoSystemSampler.reading(at: uptime - Double($0) * 2, includeProcesses: true)
    }
  }

  // A day of earlier whole-system readings for the history charts: every ten seconds for the
  // last two hours, which the hour chart draws from, and every minute before that.
  public static func history() -> [HistorySystemPoint] {
    let now = Date()
    let uptime = ProcessInfo.processInfo.systemUptime
    let offsets = Array(stride(from: 86_400, to: 7_200, by: -60)) + Array(stride(from: 7_200, to: 0, by: -10))
    return offsets.map { seconds in
      let offset = TimeInterval(seconds)
      return HistorySystemPoint(
        DemoSystemSampler.reading(at: uptime - offset, includeProcesses: false),
        time: now.addingTimeInterval(-offset), systemWatts: 17.8 * wave(9, uptime - offset))
    }
  }

  static func sample(_ process: Process, at time: TimeInterval) -> ProcessSample {
    let change = wave(process.pid, time)
    let bytes = process.megabytes * 1_048_576
    let started = UInt64(Date().timeIntervalSince1970) - UInt64(3_600 + Int(process.pid) % 50 * 900)
    var sample = ProcessSample(
      id: ProcessIdentity(pid: process.pid, startSeconds: started, startMicroseconds: 0),
      parentPID: process.parent, userID: process.user, name: process.name, path: process.path,
      cpuTimeNanoseconds: UInt64(process.cpu * 9e9), cpuPercent: process.cpu * change,
      residentBytes: UInt64(bytes * 1.1), footprintBytes: UInt64(bytes * (0.97 + 0.03 * change)),
      threads: process.threads, diskReadBytes: UInt64(process.writtenKilobytes * 240_000),
      diskWrittenBytes: UInt64(process.writtenKilobytes * 600_000),
      diskReadBytesPerSecond: process.writtenKilobytes * 400 * change,
      diskWrittenBytesPerSecond: process.writtenKilobytes * 1_000 * change, runState: .running,
      activity: ProcessActivityCounters(
        energyNanojoules: 0, wakeups: 0, instructions: 0, cycles: 0, performanceCoreNanoseconds: 0,
        peakFootprintBytes: UInt64(bytes * 1.2)))
    sample.watts = process.watts * change
    sample.wakeupsPerSecond = process.cpu * 3
    sample.performanceCoreShare = 0.7
    sample.gpuPercent = process.gpu * change
    sample.gpuTimeNanoseconds = UInt64(process.gpu * 4e9)
    sample.userName = users[process.user]
    sample.project = process.project
    return sample
  }
}

public struct DemoSystemSampler: SystemSampling {
  private static let coreCount = 14
  public init() {}
  public func sample(includeProcesses: Bool, includeGPU: Bool) async -> SystemSample {
    Self.reading(at: ProcessInfo.processInfo.systemUptime, includeProcesses: includeProcesses)
  }
  static func reading(at time: TimeInterval, includeProcesses: Bool) -> SystemSample {
    let cores: [Double?] = (0..<Self.coreCount).map { index in
      min(0.98, (index < 10 ? 0.5 : 0.15) * DemoData.busy(1, time) * DemoData.wave(Int32(index), time))
    }
    let gigabyte: UInt64 = 1 << 30
    return SystemSample(
      uptime: time, cpu: cores.compactMap { $0 }.reduce(0, +) / Double(Self.coreCount),
      cores: cores,
      memory: MemorySample(
        total: 36 * gigabyte, active: UInt64(14 * Double(gigabyte) * DemoData.wave(11, time)),
        wired: 4 * gigabyte,
        compressed: 2 * gigabyte, cached: 9 * gigabyte, free: 7 * gigabyte,
        swap: gigabyte / 2, pressure: .normal),
      network: NetworkRate(
        received: 2_400_000 * DemoData.busy(3, time), sent: 310_000 * DemoData.busy(5, time)),
      interfaces: ["en0"],
      processes: includeProcesses ? DemoData.processes.map { DemoData.sample($0, at: time) } : [],
      processScan: includeProcesses ? ScanSummary() : nil, thermalPressure: .normal,
      gpu: GPUSystemReading(
        model: "Apple M4 Pro", deviceUtilization: min(0.97, 0.38 * DemoData.busy(7, time)),
        rendererUtilization: min(0.95, 0.34 * DemoData.busy(7, time)), tilerUtilization: 0.12,
        inUseSystemMemoryBytes: 3 * gigabyte),
      processCoverage: includeProcesses ? .allProcesses : nil)
  }
  public func reset() async {}
}

public struct DemoDevices: DeviceControlling {
  public init() {}
  public func sample() async -> DeviceSnapshot {
    DeviceSnapshot(
      battery: .present(
        BatteryState(
          fraction: 0.82, charging: false, externalPower: false, minutesRemaining: 334,
          health: "Good", cycleCount: 143, maximumCapacityFraction: 0.96)),
      audio: AudioState(
        outputs: [
          AudioOutput(objectID: 40, name: "MacBook Pro Speakers", isDefault: true, uniqueID: "demo-speakers"),
          AudioOutput(objectID: 52, name: "Studio Headphones", isDefault: false, uniqueID: "demo-headphones"),
        ],
        volume: 0.62, muted: false, canSetVolume: true, canSetMute: true),
      wifi: WiFiState(powered: true, ssid: "Studio", rssi: -52, interface: "en0"),
      volumes: [
        VolumeState(
          url: URL(fileURLWithPath: "/"), name: "Macintosh HD", total: 994_662_584_320,
          available: 312_400_000_000,
          fileSystem: FileSystemIdentity(firstComponent: 16_777_234, secondComponent: 0)),
        VolumeState(
          url: URL(fileURLWithPath: "/Volumes/Archive"), name: "Archive",
          total: 2_000_000_000_000, available: 1_240_000_000_000),
      ],
      lowPowerMode: false)
  }
  public func setVolume(_ value: Double, on output: AudioOutputIdentity) async throws {}
  public func setMuted(_ muted: Bool, on output: AudioOutputIdentity) async throws {}
  public func selectOutput(_ output: AudioOutputIdentity) async throws {}
  public func setWiFiPower(_ powered: Bool) async throws {}
}

public struct DemoPower: PowerSampling {
  public init() {}
  public func sample() async -> PowerSnapshot {
    PowerSnapshot(
      reading: PowerReading(
        systemWatts: 17.8, batteryInstalled: true, batteryWatts: -17.8,
        batteryTemperatureCelsius: 31, onExternalPower: false, isCharging: false),
      sleepBlockers: [
        SleepBlocker(
          pid: 700, processName: "Music", assertionID: 1,
          assertionType: "PreventUserIdleSystemSleep", name: "Playing audio",
          createdAt: Date().addingTimeInterval(-1_500),
          prevention: SleepPrevention(assertionType: "PreventUserIdleSystemSleep"))
      ])
  }
}

public struct DemoNetworkUsage: NetworkUsageSampling {
  private static let rates: [Int32: NetworkRate] = [
    655: NetworkRate(received: 1_650_000, sent: 42_000),
    320: NetworkRate(received: 18_000, sent: 2_100_000),
    910: NetworkRate(received: 380_000, sent: 96_000),
    780: NetworkRate(received: 120_000, sent: 8_000),
  ]
  public init() {}
  public func sample(of processes: [ProcessIdentity]) async -> NetworkUsageState {
    .measured(
      Dictionary(
        processes.compactMap { identity in Self.rates[identity.pid].map { (identity, $0) } },
        uniquingKeysWith: { first, _ in first }))
  }
  public func reset() async {}
}
