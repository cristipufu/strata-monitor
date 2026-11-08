import CoreBluetooth
import Dispatch
import Foundation

/// All framework references and flow transitions belong to one private serial queue.
/// Each explicit reading gets a new session; callbacks cannot cross into another reading.
final class NativeAccessoryBatterySession: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate,
  @unchecked Sendable
{
  private let queue = DispatchQueue(label: "dev.strata.accessory-battery", qos: .utility)
  private let batteryService = CBUUID(string: "180F")
  private let batteryLevel = CBUUID(string: "2A19")
  private let isAuthorized: @Sendable () -> Bool
  private var flow = AccessoryBatteryFlow()
  private var manager: CBCentralManager?
  private var peripherals: [UUID: CBPeripheral] = [:]
  private var services: [UUID: CBService] = [:]
  private var characteristics: [UUID: CBCharacteristic] = [:]
  private var attemptedConnections: Set<UUID> = []
  private var continuation: CheckedContinuation<AccessoryBatteryReport, Error>?
  private var timer: DispatchSourceTimer?
  private var canceledBeforeStart = false

  init(isAuthorized: @escaping @Sendable () -> Bool = { CBManager.authorization == .allowedAlways })
  {
    self.isAuthorized = isAuthorized
    super.init()
  }

  func read() async throws -> AccessoryBatteryReport {
    try Task.checkCancellation()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        queue.async { self.begin(continuation) }
      }
    } onCancel: {
      self.queue.async {
        if self.flow.phase == .idle {
          self.canceledBeforeStart = true
        } else {
          self.handle(.cancel)
        }
      }
    }
  }
  private func begin(_ continuation: CheckedContinuation<AccessoryBatteryReport, Error>) {
    dispatchPrecondition(condition: .onQueue(queue))
    guard self.continuation == nil, flow.phase == .idle else {
      continuation.resume(
        throwing: AccessoryBatteryError.failed(String(localized: "This battery session has already ended.")))
      return
    }
    self.continuation = continuation
    handle(canceledBeforeStart ? .cancel : .begin)
  }
  private func handle(_ event: BatteryReadEvent) {
    dispatchPrecondition(condition: .onQueue(queue))
    for command in flow.receive(event, at: ProcessInfo.processInfo.systemUptime) {
      execute(command)
    }
  }
  private func execute(_ command: BatteryReadCommand) {
    if case .finish(let result) = command {
      complete(result)
      return
    }
    guard continuation != nil, flow.phase != .finished else { return }
    switch command {
    case .start:
      guard requireAuthorization() else { return }
      manager = CBCentralManager(
        delegate: self, queue: queue,
        options: [CBCentralManagerOptionShowPowerAlertKey: false])
    case .retrieve:
      guard requireRadio(), let manager else { return }
      let found = manager.retrieveConnectedPeripherals(withServices: [batteryService])
      guard Set(found.map(\.identifier)).count == found.count else {
        handle(.failed(.failed(String(localized: "Accessory identities are ambiguous. Try reading again."))))
        return
      }
      peripherals = Dictionary(uniqueKeysWithValues: found.map { ($0.identifier, $0) })
      handle(
        .candidates(
          found.map {
            BatteryCandidate(id: $0.identifier, name: $0.name ?? String(localized: "Bluetooth LE accessory"))
          }))
    case .retainDevices(let identifiers):
      peripherals = peripherals.filter { identifiers.contains($0.key) }
    case .connect(let id):
      guard requireRadio(), let manager, let peripheral = peripherals[id] else { return }
      guard
        manager.retrieveConnectedPeripherals(withServices: [batteryService]).contains(where: {
          $0 === peripheral
        })
      else {
        handle(.connectionFailed(id, String(localized: "The accessory is no longer connected to this Mac.")))
        return
      }
      attemptedConnections.insert(id)
      peripheral.delegate = self
      manager.connect(peripheral, options: [CBConnectPeripheralOptionEnableAutoReconnect: false])
    case .discoverServices(let id):
      guard requireRadio() else { return }
      peripherals[id]?.discoverServices([batteryService])
    case .discoverLevel(let id, let serviceID):
      guard requireRadio(), let service = services[serviceID] else { return }
      peripherals[id]?.discoverCharacteristics([batteryLevel], for: service)
    case .read(let id, let characteristicID):
      guard requireRadio(), let characteristic = characteristics[characteristicID] else {
        return
      }
      peripherals[id]?.readValue(for: characteristic)
    case .disconnect(let id):
      guard let manager, manager.state == .poweredOn, let peripheral = peripherals[id],
        attemptedConnections.contains(id),
        peripheral.state != .disconnected
      else {
        handle(.disconnected(id))
        return
      }
      manager.cancelPeripheralConnection(peripheral)
    case .releaseDevice(let id):
      peripherals[id]?.delegate = nil
      peripherals.removeValue(forKey: id)
      attemptedConnections.remove(id)
      services.removeAll()
      characteristics.removeAll()
    case .deadline(let token, let deadline):
      guard flow.watchdogID == token else { return }
      if timer == nil {
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.resume()
        timer = source
      }
      timer?.setEventHandler { [weak self] in self?.handle(.timedOut(token)) }
      timer?.schedule(
        deadline: .now() + max(0, deadline - ProcessInfo.processInfo.systemUptime),
        leeway: .milliseconds(10))
    case .finish: break
    }
  }
  private func requireAuthorization() -> Bool {
    guard isAuthorized() else {
      handle(.failed(.permissionRequired))
      return false
    }
    return true
  }
  private func requireRadio() -> Bool {
    guard requireAuthorization() else { return false }
    guard let manager, manager.state == .poweredOn else {
      handle(.failed(.failed(String(localized: "Bluetooth became unavailable during the battery read."))))
      return false
    }
    return true
  }
  private func complete(_ result: Result<AccessoryBatteryReport, AccessoryBatteryError>) {
    timer?.setEventHandler {}
    timer?.cancel()
    timer = nil
    for id in attemptedConnections {
      if let manager, manager.state == .poweredOn, let peripheral = peripherals[id] {
        manager.cancelPeripheralConnection(peripheral)
      }
    }
    for peripheral in peripherals.values { peripheral.delegate = nil }
    manager?.delegate = nil
    manager = nil
    peripherals.removeAll()
    services.removeAll()
    characteristics.removeAll()
    attemptedConnections.removeAll()
    let completion = continuation
    continuation = nil
    switch result {
    case .success(let report): completion?.resume(returning: report)
    case .failure(.canceled): completion?.resume(throwing: CancellationError())
    case .failure(let error): completion?.resume(throwing: error)
    }
  }
  private func accepts(_ peripheral: CBPeripheral) -> Bool {
    dispatchPrecondition(condition: .onQueue(queue))
    return peripherals[peripheral.identifier] === peripheral
      && flow.activeDevice == peripheral.identifier
  }
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    guard central === manager else { return }
    let state: BatteryRadioState
    switch central.state {
    case .poweredOn: state = .ready
    case .poweredOff: state = .off
    case .unauthorized: state = .denied
    case .unsupported: state = .unsupported
    case .unknown, .resetting: state = .waiting
    @unknown default: state = .unsupported
    }
    handle(.radio(state))
  }
  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    guard central === manager, accepts(peripheral) else { return }
    handle(.connected(peripheral.identifier))
  }
  func centralManager(
    _ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?
  ) {
    guard central === manager, accepts(peripheral) else { return }
    handle(
      .connectionFailed(
        peripheral.identifier, error?.localizedDescription ?? String(localized: "The temporary connection failed.")))
  }
  func centralManager(
    _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?
  ) {
    guard central === manager, accepts(peripheral) else { return }
    handle(.disconnected(peripheral.identifier))
  }
  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    guard accepts(peripheral), flow.phase == .services else { return }
    let found = (peripheral.services ?? []).filter { $0.uuid == batteryService }
    guard found.count <= AccessoryBatteryPolicy().maximumServices else {
      handle(
        .services(peripheral.identifier, [], String(localized: "The accessory reported too many battery services.")))
      return
    }
    services = Dictionary(uniqueKeysWithValues: found.map { (UUID(), $0) })
    // Preserve the order reported by Core Bluetooth without inventing physical battery labels.
    let ordered = found.compactMap { service in services.first { $0.value === service }?.key }
    handle(.services(peripheral.identifier, ordered, error?.localizedDescription))
  }
  func peripheral(
    _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?
  ) {
    guard accepts(peripheral), let serviceID = services.first(where: { $0.value === service })?.key,
      flow.phase == .characteristics(serviceID)
    else { return }
    let found = (service.characteristics ?? []).filter { $0.uuid == batteryLevel }
    guard found.count == 1, let characteristic = found.first else {
      handle(.characteristics(peripheral.identifier, serviceID, [], error?.localizedDescription))
      return
    }
    let id = UUID()
    characteristics = [id: characteristic]
    handle(
      .characteristics(
        peripheral.identifier, serviceID,
        [BatteryCharacteristic(id: id, readable: characteristic.properties.contains(.read))],
        error?.localizedDescription))
  }
  func peripheral(
    _ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?
  ) {
    guard accepts(peripheral),
      let id = characteristics.first(where: { $0.value === characteristic })?.key,
      flow.phase == .value(id)
    else { return }
    let value = characteristic.value
    handle(
      .value(
        peripheral.identifier, id, value?.count == 1 ? value : nil, error?.localizedDescription))
  }
  func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
    guard accepts(peripheral), invalidatedServices.contains(where: { $0.uuid == batteryService })
    else { return }
    handle(.servicesChanged(peripheral.identifier))
  }
}
