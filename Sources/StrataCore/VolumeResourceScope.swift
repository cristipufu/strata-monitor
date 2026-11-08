import Foundation

/// A public fsid_t identifies an observed mounted filesystem. It is not a
/// persistent disk identifier and does not identify an entire APFS container.
public struct FileSystemIdentity: Codable, Equatable, Sendable {
  public let firstComponent: Int32
  public let secondComponent: Int32
  public init(firstComponent: Int32, secondComponent: Int32) {
    self.firstComponent = firstComponent
    self.secondComponent = secondComponent
  }
}

public struct VolumeResourceScope: Codable, Equatable, Sendable {
  public let identity: FileSystemIdentity
  public let name: String
  public let mountPath: String
  public init(identity: FileSystemIdentity, name: String, mountPath: String) {
    self.identity = identity
    self.name = name
    self.mountPath = mountPath
  }
  public func contains(_ resource: ProcessResource) -> Bool {
    resource.fileSystem == identity
  }
}
