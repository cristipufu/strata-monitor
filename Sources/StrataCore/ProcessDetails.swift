import Foundation

public enum SigningKind: String, Codable, Sendable {
  case apple = "Apple-signed"
  case signed = "Signed"
  case adHoc = "Ad hoc"
  case unsigned = "Unsigned"
  case invalid = "Invalid signature"
  case unavailable = "Unavailable"
}
public struct SigningInfo: Codable, Sendable {
  public let kind: SigningKind
  public let identifier: String?
  public let teamIdentifier: String?
  public let explanation: String?
  public init(
    kind: SigningKind, identifier: String? = nil, teamIdentifier: String? = nil,
    explanation: String? = nil
  ) {
    self.kind = kind
    self.identifier = identifier
    self.teamIdentifier = teamIdentifier
    self.explanation = explanation
  }
}
public struct ProcessDetails: Codable, Sendable {
  public let identity: ProcessIdentity
  public let inspectedAt: Date
  public let signing: SigningInfo
  public let arguments: [String]?
  public let argumentsIssue: String?
  public let executableMappings: [String]
  public let mappingSummary: ScanSummary
  public init(
    identity: ProcessIdentity, inspectedAt: Date = Date(), signing: SigningInfo,
    arguments: [String]?, argumentsIssue: String? = nil, executableMappings: [String],
    mappingSummary: ScanSummary
  ) {
    self.identity = identity
    self.inspectedAt = inspectedAt
    self.signing = signing
    self.arguments = arguments
    self.argumentsIssue = argumentsIssue
    self.executableMappings = executableMappings
    self.mappingSummary = mappingSummary
  }
}

public enum ProcessArguments {
  private static let pointerAlignment = 8  // Every process supported by macOS 26 is 64-bit.
  /// KERN_PROCARGS2 includes environment data after argv. Parse exactly argc
  /// arguments and never expose or retain the environment in the result.
  public static func parse(_ data: Data) -> [String]? {
    guard data.count >= 4 else { return nil }
    let count = data.withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
    guard (0...4096).contains(count) else { return nil }
    guard count > 0 else { return [] }
    return data.withUnsafeBytes { raw in
      parseArguments(raw.bindMemory(to: UInt8.self), count: count)
    }
  }
  private static func parseArguments(_ bytes: UnsafeBufferPointer<UInt8>, count: Int) -> [String]? {
    var cursor = 4
    guard let executableEnd = bytes[cursor...].firstIndex(of: 0) else { return nil }
    let pathLength = executableEnd - cursor + 1
    let alignedLength = ((pathLength + pointerAlignment - 1) / pointerAlignment) * pointerAlignment
    cursor += alignedLength
    guard cursor <= bytes.count, bytes[(executableEnd + 1)..<cursor].allSatisfy({ $0 == 0 }) else {
      return nil
    }
    var arguments: [String] = []
    for _ in 0..<count {
      guard cursor < bytes.count, let end = bytes[cursor...].firstIndex(of: 0) else { return nil }
      arguments.append(String(decoding: bytes[cursor..<end], as: UTF8.self))
      cursor = end + 1
    }
    return arguments
  }
}
