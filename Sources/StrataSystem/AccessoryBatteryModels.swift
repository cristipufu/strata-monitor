import Foundation

public struct AccessoryBatteryLevel: Identifiable, Sendable {
  public let id: Int
  public let percent: Int?
  public let issue: String?
}
public struct AccessoryBatteryDevice: Identifiable, Sendable {
  public let id: UUID
  public let name: String
  public let levels: [AccessoryBatteryLevel]
  public let issue: String?
}
public struct AccessoryBatteryReport: Sendable {
  public let devices: [AccessoryBatteryDevice]
  public let totalCandidates: Int
  public let observedAt: Date
  public let issue: String?
}
public protocol AccessoryBatteryReading: Sendable {
  func read() async throws -> AccessoryBatteryReport
}
public struct AccessoryBatteryReader: AccessoryBatteryReading {
  public init() {}
  public func read() async throws -> AccessoryBatteryReport {
    try Task.checkCancellation()
    return try await NativeAccessoryBatterySession().read()
  }
}

enum AccessoryBatteryError: LocalizedError, Equatable, Sendable {
  case canceled, permissionRequired, poweredOff, unsupported
  case failed(String)
  var errorDescription: String? {
    switch self {
    case .canceled: String(localized: "The battery reading was canceled.")
    case .permissionRequired: String(localized: "Allow Bluetooth access before reading accessory batteries.")
    case .poweredOff: String(localized: "Turn on Bluetooth before reading accessory batteries.")
    case .unsupported: String(localized: "Standard Bluetooth LE battery reading is unavailable on this Mac.")
    case .failed(let message): message
    }
  }
}
struct BatteryCandidate: Equatable, Sendable {
  let id: UUID
  let name: String
}
struct BatteryCharacteristic: Equatable, Sendable {
  let id: UUID
  let readable: Bool
}
struct AccessoryBatteryPolicy: Sendable {
  let maximumDevices = 16
  let maximumServices = 8
  let radioTimeout: TimeInterval = 5
  let deviceTimeout: TimeInterval = 8
  let sessionTimeout: TimeInterval = 45
  let releaseTimeout: TimeInterval = 2
}
