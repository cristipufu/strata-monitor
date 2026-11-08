import Foundation

public struct DisplayIdentity: Hashable, Sendable {
  public let objectID: UInt32
  public let uuid: UUID
}
public struct DisplayMode: Hashable, Identifiable, Sendable {
  public let id: Int32
  public let width: Int
  public let height: Int
  public let pixelWidth: Int
  public let pixelHeight: Int
  public let refreshRate: Double
}
public struct DisplayPosition: Equatable, Sendable {
  public let x: Int32
  public let y: Int32
}
public struct DisplayInfo: Identifiable, Sendable {
  public let id: DisplayIdentity
  public let isBuiltIn: Bool
  public let currentMode: DisplayMode?
  public let modes: [DisplayMode]
  public let mirrorOf: DisplayIdentity?
  public let position: DisplayPosition
}
public struct DisplayCatalog: Sendable {
  public let id: UUID
  public let displays: [DisplayInfo]
  public var canPreview: Bool { displays.supportsRestoration }
}
public enum DisplayChange: Sendable {
  case mode(DisplayIdentity, DisplayMode)
  case mirror(DisplayIdentity, DisplayIdentity?)
}
public struct DisplayTrial: Identifiable, Sendable {
  public let id: UUID
  public let catalogID: UUID
  public let expiresAt: Date
  public let canKeep: Bool
}
public struct DisplayTrialStatus: Sendable {
  public let trial: DisplayTrial?
  public let issue: String?
}
public enum DisplayControlError: LocalizedError, Sendable {
  case unavailable(String)
  case native(String, Int32)
  public var errorDescription: String? {
    switch self {
    case .unavailable(let message): message
    case .native(let operation, let code):
      String(localized: "\(operation) failed (\(String(code))). Open Displays settings to review the configuration.")
    }
  }
}
public protocol DisplayManaging: Sendable {
  func catalog() async throws -> DisplayCatalog
  func preview(_ change: DisplayChange, catalogID: UUID) async throws -> DisplayTrial
  func accept(_ trialID: UUID) async throws
  func revert(_ trialID: UUID) async throws
  func status() async -> DisplayTrialStatus
}

enum DisplayPersistence { case application, session }
enum DisplayMutation {
  case mode(DisplayIdentity, DisplayMode)
  case mirror(DisplayIdentity, DisplayIdentity?)
  case position(DisplayIdentity, DisplayPosition)
}
protocol DisplayHardware {
  func snapshot() throws -> [DisplayInfo]
  func apply(
    _ mutations: [DisplayMutation], identities: Set<DisplayIdentity>,
    persistence: DisplayPersistence) throws
}

extension Array where Element == DisplayInfo {
  var identities: Set<DisplayIdentity> { Set(map(\.id)) }
  var supportsRestoration: Bool {
    !isEmpty && identities.count == count && Set(map(\.id.objectID)).count == count
      && allSatisfy { display in
        guard display.id.objectID != 0,
          display.currentMode.map({ display.modes.contains($0) }) == true
        else { return false }
        guard let master = display.mirrorOf else { return true }
        return master != display.id && contains { $0.id == master && $0.mirrorOf == nil }
      }
  }
  func sameConfiguration(as other: [DisplayInfo]) -> Bool {
    guard identities.count == count, other.identities.count == other.count,
      identities == other.identities, count == other.count
    else { return false }
    let lookup = Dictionary(uniqueKeysWithValues: other.map { ($0.id, $0) })
    return allSatisfy { display in
      guard let rhs = lookup[display.id] else { return false }
      return display.currentMode == rhs.currentMode && display.mirrorOf == rhs.mirrorOf
        && display.position == rhs.position
    }
  }
  var restoration: [DisplayMutation] {
    map { .mirror($0.id, $0.mirrorOf) }
      + compactMap { display in display.currentMode.map { .mode(display.id, $0) } }
      + filter { $0.mirrorOf == nil }.map { .position($0.id, $0.position) }
  }
}
