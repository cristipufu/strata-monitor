import Foundation

public struct PreparedApplicationQuit: Identifiable, Sendable {
  public let id: UUID
  public let identity: ProcessIdentity
  public let name: String
  public init(id: UUID, identity: ProcessIdentity, name: String) {
    self.id = id
    self.identity = identity
    self.name = name
  }
}
