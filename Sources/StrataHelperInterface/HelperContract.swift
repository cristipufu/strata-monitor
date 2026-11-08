import Foundation

public enum HelperContract {
  public static let machServiceName = "dev.stratabar.helper"
  public static let launchDaemonPlistName = "dev.stratabar.helper.plist"
  public static let helperSigningIdentifier = "dev.stratabar.helper"
  public static let appSigningIdentifier = "dev.stratabar.app"
  // Bump helperVersion when the helper's behavior changes and schemaVersion when any encoded
  // payload changes shape; either mismatch makes the app register the bundled helper again.
  public static let helperVersion = 1
  public static let schemaVersion = 2
  public static let maximumReplyBytes = 16 << 20
  public static let maximumRequestBytes = 256 << 10
  public static let maximumResourceIdentities = 4096

  public static func makeInterface() -> NSXPCInterface {
    NSXPCInterface(with: StrataHelperProtocol.self)
  }
}

/// Every method replies exactly once with an encoded `HelperReply`.
@objc(StrataHelperProtocol) public protocol StrataHelperProtocol {
  func handshake(reply: @escaping @Sendable (Data) -> Void)
  func processSnapshot(reply: @escaping @Sendable (Data) -> Void)
  func resources(_ request: Data, reply: @escaping @Sendable (Data) -> Void)
}
