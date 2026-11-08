import Foundation

public struct ResourcePathScope: Equatable, Sendable {
  public let path: String
  public init(_ url: URL) { path = url.standardizedFileURL.path }
  public func contains(_ resource: ProcessResource) -> Bool {
    guard resource.path.hasPrefix("/") else { return false }
    return path == "/" || resource.path == path || resource.path.hasPrefix(path + "/")
  }
}
