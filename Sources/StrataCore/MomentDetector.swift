import Foundation

public struct StatusMoment: Equatable, Sendable {
  public let symbol: String
  public let title: String
  public let priority: Int
  public init(symbol: String, title: String, priority: Int) {
    self.symbol = symbol
    self.title = title
    self.priority = priority
  }
}

public struct DeviceObservation: Sendable {
  public let batteryFraction: Double?
  public let externalPower: Bool?
  public let muted: Bool?
  public let outputName: String?
  public let volumeNamesByID: [String: String]?
  public init(
    batteryFraction: Double?, externalPower: Bool?, muted: Bool?, outputName: String?,
    volumeNamesByID: [String: String]? = nil
  ) {
    self.batteryFraction = batteryFraction
    self.externalPower = externalPower
    self.muted = muted
    self.outputName = outputName
    self.volumeNamesByID = volumeNamesByID
  }
}

public struct MomentDetector: Sendable {
  private var previousDevice: DeviceObservation?
  private var previousConnection: Bool?
  private var previousBluetooth: [String: String]?
  private var batteryWarningActive = false
  private let lowBatteryThreshold = 0.15
  private let batteryRecoveryThreshold = 0.20
  // A process that stays heavy is announced once an hour at most, so alerts stay rare.
  private static let alertInterval: TimeInterval = 3600
  private var lastAlerts: [ProcessIdentity: Date] = [:]
  public init() {}
  public mutating func reset() {
    previousDevice = nil
    previousConnection = nil
    previousBluetooth = nil
    batteryWarningActive = false
  }
  public mutating func observe(episodeStart episode: Episode) -> StatusMoment? {
    guard let process = episode.process else {
      return episode.kind == .memoryPressure
        ? StatusMoment(symbol: "memorychip", title: String(localized: "Memory pressure is high"), priority: 2) : nil
    }
    if let last = lastAlerts[process.identity], episode.start.timeIntervalSince(last) < Self.alertInterval {
      return nil
    }
    lastAlerts = lastAlerts.filter { episode.start.timeIntervalSince($0.value) < Self.alertInterval }
    lastAlerts[process.identity] = episode.start
    let name = process.project.map { "\(process.name) · \($0)" } ?? process.name
    switch episode.kind {
    case .cpu:
      return StatusMoment(symbol: "flame", title: String(localized: "\(name) at \(Int(episode.peak))% CPU"), priority: 2)
    case .watts:
      return StatusMoment(
        symbol: "bolt", title: String(localized: "\(name) drawing \(ValueFormat.watts(episode.peak))"), priority: 2)
    case .memoryGrowth:
      return StatusMoment(
        symbol: "memorychip", title: String(localized: "\(name) grew \(ValueFormat.bytes(UInt64(max(0, episode.peak))))"),
        priority: 2)
    case .wakeups:
      return StatusMoment(symbol: "alarm", title: String(localized: "\(name) wakes the Mac often"), priority: 1)
    case .systemCPU, .memoryPressure:
      return nil
    }
  }
  public mutating func observe(_ next: DeviceObservation) -> StatusMoment? {
    defer { previousDevice = next }
    guard let previousDevice else {
      batteryWarningActive = (next.batteryFraction ?? 1) <= lowBatteryThreshold
      return nil
    }
    var events: [StatusMoment] = []
    if let fraction = next.batteryFraction {
      if fraction <= lowBatteryThreshold && !batteryWarningActive {
        batteryWarningActive = true
        events.append(
          StatusMoment(symbol: "battery.25percent", title: String(localized: "Battery is low"), priority: 3))
      } else if fraction >= batteryRecoveryThreshold && batteryWarningActive {
        batteryWarningActive = false
        events.append(
          StatusMoment(symbol: "battery.75percent", title: String(localized: "Battery recovered"), priority: 1))
      }
    }
    if let external = next.externalPower, previousDevice.externalPower != nil,
      external != previousDevice.externalPower
    {
      events.append(
        StatusMoment(
          symbol: external ? "powerplug.fill" : "battery.75percent",
          title: external ? String(localized: "Power connected") : String(localized: "On battery"), priority: 2))
    }
    if let name = next.outputName, let previousName = previousDevice.outputName,
      name != previousName
    {
      events.append(StatusMoment(symbol: "headphones", title: name, priority: 1))
    }
    if let muted = next.muted, previousDevice.muted != nil, muted != previousDevice.muted {
      events.append(
        StatusMoment(
          symbol: muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
          title: muted ? String(localized: "Muted") : String(localized: "Sound on"), priority: 1))
    }
    if let current = next.volumeNamesByID, let previous = previousDevice.volumeNamesByID {
      let mounted = current.keys.filter { previous[$0] == nil }.sorted()
      let removed = previous.keys.filter { current[$0] == nil }.sorted()
      if let id = mounted.first {
        events.append(
          StatusMoment(
            symbol: "externaldrive.badge.plus",
            title: mounted.count == 1
              ? String(localized: "\(current[id] ?? "Drive") mounted") : String(localized: "\(mounted.count) drives mounted"), priority: 1
          ))
      } else if let id = removed.first {
        events.append(
          StatusMoment(
            symbol: "externaldrive.badge.minus",
            title: removed.count == 1
              ? String(localized: "\(previous[id] ?? "Drive") disconnected") : String(localized: "\(removed.count) drives disconnected"),
            priority: 1))
      }
    }
    return events.enumerated().max { lhs, rhs in
      lhs.element.priority == rhs.element.priority
        ? lhs.offset > rhs.offset : lhs.element.priority < rhs.element.priority
    }?.element
  }
  public mutating func observe(connection: ConnectionState) -> StatusMoment? {
    guard let available = connection.isAvailable else { return nil }
    defer { previousConnection = available }
    guard let previousConnection, previousConnection != available else { return nil }
    return StatusMoment(
      symbol: available ? "network" : "wifi.exclamationmark",
      title: available ? String(localized: "Network available") : String(localized: "Network unavailable"), priority: 2)
  }
  public mutating func observeBluetooth(connectedDevices next: [String: String]?) -> StatusMoment? {
    defer { previousBluetooth = next }
    guard let next, let previousBluetooth else { return nil }
    let connected = next.keys.filter { previousBluetooth[$0] == nil }.sorted()
    let disconnected = previousBluetooth.keys.filter { next[$0] == nil }.sorted()
    if !connected.isEmpty && !disconnected.isEmpty {
      return StatusMoment(symbol: "wave.3.right", title: String(localized: "Bluetooth devices changed"), priority: 1)
    }
    if let identity = connected.first {
      return StatusMoment(
        symbol: "wave.3.right",
        title: connected.count == 1
          ? String(localized: "\(next[identity] ?? "Device") connected") : String(localized: "\(connected.count) devices connected"),
        priority: 1)
    }
    if let identity = disconnected.first {
      return StatusMoment(
        symbol: "wave.3.right",
        title: disconnected.count == 1
          ? String(localized: "\(previousBluetooth[identity] ?? "Device") disconnected")
          : String(localized: "\(disconnected.count) devices disconnected"), priority: 1)
    }
    return nil
  }
}
