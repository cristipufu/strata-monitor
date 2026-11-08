import StrataCore
import StrataInventory

public protocol ProcessIdentityVerifying: Sendable {
  func isCurrent(_ identity: ProcessIdentity) -> Bool
}
public struct ProcessIdentityVerifier: ProcessIdentityVerifying {
  public init() {}
  public func isCurrent(_ identity: ProcessIdentity) -> Bool {
    NativeProcessIdentity.isCurrent(identity)
  }
}
