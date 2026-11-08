import Foundation

enum BatteryRadioState { case ready, waiting, off, denied, unsupported }
enum BatteryReadEvent {
  case begin, cancel
  case radio(BatteryRadioState)
  case candidates([BatteryCandidate])
  case connected(UUID)
  case connectionFailed(UUID, String)
  case services(UUID, [UUID], String?)
  case characteristics(UUID, UUID, [BatteryCharacteristic], String?)
  case value(UUID, UUID, Data?, String?)
  case disconnected(UUID)
  case servicesChanged(UUID)
  case timedOut(UUID)
  case failed(AccessoryBatteryError)
}
enum BatteryReadCommand {
  case start, retrieve
  case retainDevices(Set<UUID>)
  case connect(UUID)
  case discoverServices(UUID)
  case discoverLevel(UUID, UUID)
  case read(UUID, UUID)
  case disconnect(UUID)
  case releaseDevice(UUID)
  case deadline(UUID, TimeInterval)
  case finish(Result<AccessoryBatteryReport, AccessoryBatteryError>)
}

/// Original protocol state, independent of Core Bluetooth objects and callback queues.
struct AccessoryBatteryFlow {
  enum Phase: Equatable {
    case idle, radio, candidates, connecting, services
    case characteristics(UUID)
    case value(UUID)
    case closing, finished
  }
  private(set) var phase: Phase = .idle
  private(set) var activeDevice: UUID?
  private(set) var watchdogID: UUID?
  private var watchdogDeadline: TimeInterval?
  private let policy = AccessoryBatteryPolicy()
  private var sessionEnd: TimeInterval = 0
  private var candidates: [BatteryCandidate] = []
  private var totalCandidates = 0
  private var index = 0
  private var reports: [AccessoryBatteryDevice] = []
  private var services: [UUID] = []
  private var levels: [AccessoryBatteryLevel] = []
  private var deviceIssue: String?
  private var reportIssue: String?
  private var terminalFailure: AccessoryBatteryError?

  mutating func receive(_ event: BatteryReadEvent, at now: TimeInterval) -> [BatteryReadCommand] {
    guard phase != .finished else { return [] }
    if let deadline = watchdogDeadline, now >= deadline {
      switch event {
      case .radio(.ready), .candidates, .connected, .services, .characteristics, .value:
        return timeout(at: now)
      default: break
      }
    }
    switch event {
    case .begin:
      guard phase == .idle else { return [] }
      sessionEnd = now + policy.sessionTimeout
      phase = .radio
      return arm(until: now + policy.radioTimeout) + [.start]
    case .cancel: return stop(with: .canceled, at: now)
    case .failed(let error): return stop(with: error, at: now)
    case .radio(let state): return receiveRadio(state, at: now)
    case .candidates(let found): return receiveCandidates(found, at: now)
    case .connected(let id):
      guard activeDevice == id, phase == .connecting else { return [] }
      phase = .services
      return [.discoverServices(id)]
    case .connectionFailed(let id, let message):
      guard activeDevice == id else { return [] }
      if phase == .closing { return completeDevice(at: now) }
      guard phase == .connecting else { return [] }
      return closeDevice(issue: message, at: now)
    case .services(let id, let found, let error):
      guard activeDevice == id, phase == .services else { return [] }
      guard error == nil, !found.isEmpty, found.count <= policy.maximumServices,
        Set(found).count == found.count
      else {
        return closeDevice(
          issue: error ?? "Standard battery services are unavailable or ambiguous.", at: now)
      }
      services = found
      return nextLevel(at: now)
    case .characteristics(let id, let service, let found, let error):
      guard activeDevice == id, phase == .characteristics(service) else { return [] }
      guard error == nil, found.count == 1, let characteristic = found.first,
        characteristic.readable
      else {
        return recordLevel(nil, issue: error ?? "A readable battery level is unavailable.", at: now)
      }
      phase = .value(characteristic.id)
      return [.read(id, characteristic.id)]
    case .value(let id, let characteristic, let data, let error):
      guard activeDevice == id, phase == .value(characteristic) else { return [] }
      guard error == nil, let data, data.count == 1, let percent = data.first, percent <= 100 else {
        return recordLevel(
          nil, issue: error ?? "The accessory returned an invalid battery level.", at: now)
      }
      return recordLevel(Int(percent), issue: nil, at: now)
    case .servicesChanged(let id):
      guard activeDevice == id, phase != .closing else { return [] }
      return closeDevice(issue: "Battery services changed. Read the accessory again.", at: now)
    case .disconnected(let id):
      guard activeDevice == id else { return [] }
      if phase != .closing { deviceIssue = "The accessory disconnected during the battery read." }
      return completeDevice(at: now)
    case .timedOut(let token):
      guard watchdogID == token, let deadline = watchdogDeadline, now >= deadline else { return [] }
      return timeout(at: now)
    }
  }
  private mutating func receiveRadio(_ state: BatteryRadioState, at now: TimeInterval)
    -> [BatteryReadCommand]
  {
    switch state {
    case .ready:
      guard phase == .radio else { return [] }
      phase = .candidates
      return [.retrieve]
    case .waiting:
      return phase == .radio
        ? [] : stop(with: .failed("Bluetooth reset during the battery read."), at: now)
    case .off: return stop(with: .poweredOff, at: now)
    case .denied: return stop(with: .permissionRequired, at: now)
    case .unsupported: return stop(with: .unsupported, at: now)
    }
  }
  private mutating func receiveCandidates(_ found: [BatteryCandidate], at now: TimeInterval)
    -> [BatteryReadCommand]
  {
    guard phase == .candidates else { return [] }
    guard Set(found.map(\.id)).count == found.count else {
      return stop(with: .failed("Accessory identities are ambiguous. Try reading again."), at: now)
    }
    totalCandidates = found.count
    candidates = Array(
      found.sorted { $0.id.uuidString < $1.id.uuidString }.prefix(policy.maximumDevices))
    if totalCandidates > candidates.count {
      reportIssue =
        "Read limited to \(policy.maximumDevices) of \(totalCandidates) connected battery accessories."
    }
    return [.retainDevices(Set(candidates.map(\.id)))] + nextDevice(at: now)
  }
  private mutating func nextDevice(at now: TimeInterval) -> [BatteryReadCommand] {
    if terminalFailure != nil || index >= candidates.count || now >= sessionEnd {
      return finish()
    }
    activeDevice = candidates[index].id
    levels = []
    services = []
    deviceIssue = nil
    let deviceEnd = min(sessionEnd, now + policy.deviceTimeout)
    phase = .connecting
    return arm(until: deviceEnd) + [.connect(candidates[index].id)]
  }
  private mutating func nextLevel(at now: TimeInterval) -> [BatteryReadCommand] {
    guard let activeDevice else { return [] }
    if levels.count >= services.count { return closeDevice(issue: nil, at: now) }
    let service = services[levels.count]
    phase = .characteristics(service)
    return [.discoverLevel(activeDevice, service)]
  }
  private mutating func recordLevel(_ percent: Int?, issue: String?, at now: TimeInterval)
    -> [BatteryReadCommand]
  {
    levels.append(AccessoryBatteryLevel(id: levels.count + 1, percent: percent, issue: issue))
    return nextLevel(at: now)
  }
  private mutating func closeDevice(issue: String?, at now: TimeInterval) -> [BatteryReadCommand] {
    if let issue { deviceIssue = issue }
    guard let activeDevice else { return finish() }
    guard phase != .closing else { return [] }
    phase = .closing
    return arm(until: now + policy.releaseTimeout) + [.disconnect(activeDevice)]
  }
  private mutating func completeDevice(at now: TimeInterval) -> [BatteryReadCommand] {
    guard let activeDevice else { return [] }
    reports.append(
      AccessoryBatteryDevice(
        id: activeDevice, name: candidates[index].name, levels: levels, issue: deviceIssue))
    self.activeDevice = nil
    index += 1
    return [.releaseDevice(activeDevice)] + nextDevice(at: now)
  }
  private mutating func timeout(at now: TimeInterval) -> [BatteryReadCommand] {
    if phase == .closing {
      reportIssue =
        "Temporary connection release was not confirmed. Remaining accessories were not read."
      index = candidates.count
      return finish()
    }
    if activeDevice != nil { return closeDevice(issue: "The battery read timed out.", at: now) }
    return stop(with: .failed("Bluetooth did not become ready before the read timed out."), at: now)
  }
  private mutating func stop(with error: AccessoryBatteryError, at now: TimeInterval)
    -> [BatteryReadCommand]
  {
    terminalFailure = terminalFailure ?? error
    if activeDevice != nil { return closeDevice(issue: nil, at: now) }
    return finish()
  }
  private mutating func finish() -> [BatteryReadCommand] {
    phase = .finished
    watchdogID = nil
    watchdogDeadline = nil
    if let terminalFailure { return [.finish(.failure(terminalFailure))] }
    let reported = Set(reports.map(\.id))
    let remaining = candidates.filter { !reported.contains($0.id) }.map {
      AccessoryBatteryDevice(
        id: $0.id, name: $0.name, levels: [],
        issue: "Not read: session time or connection cleanup limit.")
    }
    if !remaining.isEmpty && reportIssue == nil {
      reportIssue = "The battery reading reached its session time limit."
    }
    return [
      .finish(
        .success(
          AccessoryBatteryReport(
            devices: reports + remaining, totalCandidates: totalCandidates,
            observedAt: Date(), issue: reportIssue)))
    ]
  }
  private mutating func arm(until deadline: TimeInterval) -> [BatteryReadCommand] {
    let token = UUID()
    watchdogID = token
    watchdogDeadline = deadline
    return [.deadline(token, deadline)]
  }
}
