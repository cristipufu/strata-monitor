import AppKit
import Foundation
import StrataCore

// "—" means nothing has been observed yet; "Unavailable" means macOS cannot provide
// the value or access is denied.
enum ReadingValue {
  static let notObserved = "—"
  static let unavailable = String(localized: "Unavailable")
  static func text<Observation>(
    observing observation: Observation?, _ value: (Observation) -> String?
  ) -> String {
    guard let observation else { return notObserved }
    return value(observation) ?? unavailable
  }
  // A process rate compares two scans, so a readable counter has no value before its second scan.
  static func processRate(_ text: String?, readable: Bool) -> String {
    guard readable else { return unavailable }
    return text ?? notObserved
  }
}

extension ProcessSample {
  var isCPUReadable: Bool { cpuTimeNanoseconds != nil }
  // An estimate from `ps` averages a few seconds rather than the last reading.
  var cpuDescription: String {
    let text = ReadingValue.processRate(cpuPercent.map(ValueFormat.processCPU), readable: isCPUReadable)
    return isEstimated && cpuPercent != nil ? "≈" + text : text
  }
}

extension ProcessFamily {
  var isCPUReadable: Bool { members.contains(where: \.isCPUReadable) }
}

extension AppModel {
  var accessibilityStatus: String {
    let readings = [profile.ring, profile.center, profile.bar].map {
      "\($0.title) \(accessibleValue(for: $0))"
    }.joined(separator: ", ")
    return [moment?.title, readings].compactMap { $0 }.joined(separator: ". ")
  }
  func accessibleValue(for reading: Reading) -> String {
    if reading == .network {
      return
        "receiving \(ValueFormat.rate(sample?.network?.received)), sending \(ValueFormat.rate(sample?.network?.sent))"
    }
    if reading == .battery, devices?.battery?.charging == true {
      return "\(value(for: reading)), charging"
    }
    return value(for: reading)
  }
  func value(for reading: Reading) -> String {
    switch reading {
    case .cpu: ValueFormat.percent(sample?.cpu)
    case .gpu: ValueFormat.percent(sample?.gpu?.deviceUtilization)
    case .memory: memoryDescription
    case .network: ValueFormat.rate(sample?.network?.received)
    case .battery: batteryDescription
    case .sound: soundDescription
    case .wifi: linkDescription
    case .bluetooth: bluetoothDescription
    case .disk: diskDescription
    case .display: "\(NSScreen.screens.count) displays"
    case .overview: "Strata Monitor"
    }
  }
  private var memoryDescription: String {
    ReadingValue.text(observing: sample) { $0.memory.map { ValueFormat.bytes($0.used) } }
  }
  private var batteryDescription: String {
    guard let observation = devices?.batteryObservation else { return ReadingValue.notObserved }
    switch observation {
    case .unavailable: return ReadingValue.unavailable
    case .absent: return "No battery"
    case .present(let battery):
      return battery.fraction.map { ValueFormat.percent($0) } ?? ReadingValue.unavailable
    }
  }
  private var soundDescription: String {
    ReadingValue.text(observing: devices?.audio) { audio in
      audio.muted == true ? "Muted" : audio.volume.map { ValueFormat.percent($0) }
    }
  }
  private var diskDescription: String {
    ReadingValue.text(observing: devices) {
      $0.volumes.first.map { ValueFormat.bytes($0.available) }
    }
  }
  private var bluetoothDescription: String {
    guard let snapshot = bluetooth.snapshot else { return ReadingValue.notObserved }
    switch snapshot.access {
    case .notDetermined: return "Open Bluetooth"
    case .denied, .restricted: return "Access unavailable"
    case .allowed:
      if snapshot.powered == false { return "Bluetooth off" }
      guard let count = snapshot.connectedCount else { return ReadingValue.unavailable }
      return count == 1 ? "1 connected" : "\(count) connected"
    }
  }
  private var linkDescription: String {
    if connection == .wired { return "Ethernet" }
    guard let wifi = devices?.wifi else { return ReadingValue.notObserved }
    if wifi.interface == nil { return "No Wi-Fi interface" }
    if !wifi.powered { return "Wi-Fi off" }
    if connection == .connecting { return "Connecting" }
    if connection == .offline { return "No connection" }
    return wifi.ssid ?? "Wi-Fi on"
  }
  func fraction(for reading: Reading) -> Double? {
    switch reading {
    case .cpu: sample?.cpu
    case .gpu: sample?.gpu?.deviceUtilization
    case .memory: sample?.memory?.fraction
    case .battery: devices?.battery?.fraction
    case .sound: devices?.audio.volume
    case .disk: devices?.volumes.first?.usedFraction
    case .network: sample?.network?.activityIntensity
    default: nil
    }
  }
  var centerSymbol: String {
    switch glyphCenter {
    case .symbol(let symbol, _, _), .count(_, let symbol): return symbol
    case .percentage: return profile.center.symbol
    }
  }
  func historyValues(for reading: Reading) -> [Double?] {
    switch reading {
    case .cpu: history.points.map(\.cpu)
    case .gpu: history.points.map(\.gpu)
    case .memory: history.points.map(\.memory)
    case .network: history.points.map(\.download)
    default: []
    }
  }
}

extension ProcessFilter {
  var title: String {
    switch self {
    case .all: String(localized: "All Processes")
    case .mine: String(localized: "My Processes")
    case .otherUsers: String(localized: "Other Users")
    case .system: String(localized: "System Processes")
    case .applications: String(localized: "Applications")
    case .active: String(localized: "Active Processes")
    case .paused: String(localized: "Paused Processes")
    }
  }
}
