import ColorSync
import CoreGraphics
import Foundation

struct NativeDisplayHardware: DisplayHardware {
  private let maximumDisplays = 64
  // Built-in Retina panels list their scaled (HiDPI) modes, including the active one,
  // only among the duplicate low-resolution modes.
  private static var modeOptions: CFDictionary {
    [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
  }
  func snapshot() throws -> [DisplayInfo] {
    let ids = try onlineDisplays()
    var identities: [UInt32: DisplayIdentity] = [:]
    for id in ids {
      identities[id] = try identity(for: id)
    }
    let result = try ids.map { id in
      guard let identity = identities[id] else {
        throw DisplayControlError.unavailable("The display list changed.")
      }
      let bounds = CGDisplayBounds(id)
      guard let x = Int32(exactly: bounds.origin.x), let y = Int32(exactly: bounds.origin.y) else {
        throw DisplayControlError.unavailable("Display geometry is unavailable.")
      }
      let choices = (CGDisplayCopyAllDisplayModes(id, Self.modeOptions) as? [CGDisplayMode] ?? [])
        .filter { $0.isUsableForDesktopGUI() }.map(describe)
      let distinct = Dictionary(grouping: choices, by: \.id).values.compactMap {
        values -> DisplayMode? in
        guard let first = values.first, values.allSatisfy({ $0 == first }) else { return nil }
        return first
      }.sorted {
        ($0.width, $0.height, $0.pixelWidth, $0.pixelHeight, $0.refreshRate, $0.id) < (
          $1.width, $1.height, $1.pixelWidth, $1.pixelHeight, $1.refreshRate, $1.id
        )
      }
      let mirrorID = CGDisplayMirrorsDisplay(id)
      guard mirrorID == kCGNullDirectDisplay || identities[mirrorID] != nil else {
        throw DisplayControlError.unavailable(
          "The mirroring arrangement changed. Refresh Displays.")
      }
      return DisplayInfo(
        id: identity, isBuiltIn: CGDisplayIsBuiltin(id) != 0,
        currentMode: CGDisplayCopyDisplayMode(id).map(describe), modes: distinct,
        mirrorOf: identities[mirrorID], position: DisplayPosition(x: x, y: y))
    }
    guard Set(try onlineDisplays()) == Set(ids) else {
      throw DisplayControlError.unavailable("The connected displays changed. Refresh Displays.")
    }
    for id in ids where try identity(for: id) != identities[id] {
      throw DisplayControlError.unavailable("A connected display was replaced. Refresh Displays.")
    }
    return result
  }
  private func identity(for id: UInt32) throws -> DisplayIdentity {
    guard let reference = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
      let uuid = UUID(uuidString: CFUUIDCreateString(nil, reference) as String)
    else {
      throw DisplayControlError.unavailable(
        "A display could not be identified. Try refreshing Displays.")
    }
    return DisplayIdentity(objectID: id, uuid: uuid)
  }
  func apply(
    _ mutations: [DisplayMutation], identities: Set<DisplayIdentity>,
    persistence: DisplayPersistence
  ) throws {
    guard try snapshot().identities == identities else {
      throw DisplayControlError.unavailable("Displays changed. Refresh before trying again.")
    }
    var configuration: CGDisplayConfigRef?
    try check(
      CGBeginDisplayConfiguration(&configuration), operation: "Starting display configuration")
    guard let configuration else {
      throw DisplayControlError.unavailable("Display configuration is unavailable.")
    }
    var consumed = false
    defer { if !consumed { _ = CGCancelDisplayConfiguration(configuration) } }
    for mutation in mutations {
      switch mutation {
      case .mode(let display, let requested):
        guard
          let modes = CGDisplayCopyAllDisplayModes(display.objectID, Self.modeOptions)
            as? [CGDisplayMode],
          let mode = modes.first(where: { $0.isUsableForDesktopGUI() && describe($0) == requested })
        else {
          throw DisplayControlError.unavailable("That resolution is no longer available.")
        }
        try check(
          CGConfigureDisplayWithDisplayMode(configuration, display.objectID, mode, nil),
          operation: "Setting resolution")
      case .mirror(let display, let master):
        try check(
          CGConfigureDisplayMirrorOfDisplay(
            configuration, display.objectID, master?.objectID ?? kCGNullDirectDisplay),
          operation: "Setting mirroring")
      case .position(let display, let position):
        try check(
          CGConfigureDisplayOrigin(configuration, display.objectID, position.x, position.y),
          operation: "Restoring display position")
      }
    }
    guard try snapshot().identities == identities else {
      throw DisplayControlError.unavailable(
        "Displays changed before the configuration could be applied.")
    }
    consumed = true
    try check(
      CGCompleteDisplayConfiguration(
        configuration, persistence == .application ? .forAppOnly : .forSession),
      operation: "Applying display configuration")
  }
  private func onlineDisplays() throws -> [UInt32] {
    var count: UInt32 = 0
    try check(CGGetOnlineDisplayList(0, nil, &count), operation: "Reading displays")
    guard count <= maximumDisplays else {
      throw DisplayControlError.unavailable("The display list exceeds the supported limit.")
    }
    if count == 0 { return [] }
    var displays = [UInt32](repeating: 0, count: Int(count))
    let capacity = count
    try check(CGGetOnlineDisplayList(capacity, &displays, &count), operation: "Reading displays")
    guard count <= capacity, Set(displays.prefix(Int(count))).count == count else {
      throw DisplayControlError.unavailable("The display list changed. Refresh and try again.")
    }
    return Array(displays.prefix(Int(count)))
  }
  private func describe(_ mode: CGDisplayMode) -> DisplayMode {
    DisplayMode(
      id: mode.ioDisplayModeID, width: mode.width, height: mode.height,
      pixelWidth: mode.pixelWidth, pixelHeight: mode.pixelHeight, refreshRate: mode.refreshRate)
  }
  private func check(_ error: CGError, operation: String) throws {
    guard error == .success else { throw DisplayControlError.native(operation, error.rawValue) }
  }
}
