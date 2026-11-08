import Foundation

public enum ResourceKind: String, Codable, Sendable, CaseIterable {
  case file, directory, device, pipe, unixSocket, tcp, udp, other
}

public struct ProcessResource: Identifiable, Codable, Sendable {
  public var id: String {
    "\(owner.pid):\(owner.startSeconds):\(owner.startMicroseconds):\(descriptor)"
  }
  public let owner: ProcessIdentity
  public let processName: String
  public let descriptor: Int32
  public let kind: ResourceKind
  public let path: String
  public let localAddress: String
  public let remoteAddress: String
  public let localPort: UInt16
  public let remotePort: UInt16
  public let state: String
  public let fileSystem: FileSystemIdentity?
  public var isListener: Bool { kind == .tcp && state == "Listening" }
  public var ownsLocalPort: Bool { isListener || (kind == .udp && localPort > 0) }
  public var endpoint: String {
    localPort > 0 ? Self.formatEndpoint(localAddress, port: localPort) : path
  }
  public var remoteEndpoint: String? {
    remotePort > 0 ? Self.formatEndpoint(remoteAddress, port: remotePort) : nil
  }
  private static func formatEndpoint(_ address: String, port: UInt16) -> String {
    "\(address.contains(":") ? "[\(address)]" : address):\(port)"
  }
  public init(
    owner: ProcessIdentity, processName: String, descriptor: Int32, kind: ResourceKind,
    path: String = "", localAddress: String = "", remoteAddress: String = "",
    localPort: UInt16 = 0, remotePort: UInt16 = 0, state: String = "",
    fileSystem: FileSystemIdentity? = nil
  ) {
    self.owner = owner
    self.processName = processName
    self.descriptor = descriptor
    self.kind = kind
    self.path = path
    self.localAddress = localAddress
    self.remoteAddress = remoteAddress
    self.localPort = localPort
    self.remotePort = remotePort
    self.state = state
    self.fileSystem = fileSystem
  }
}

public struct ResourceReport: Codable, Sendable {
  public var resources: [ProcessResource]
  public var summary: ScanSummary
  public init(resources: [ProcessResource], summary: ScanSummary = ScanSummary()) {
    self.resources = resources
    self.summary = summary
  }
}

public struct ExplorerQuery: Sendable {
  public let text: String
  private let tokens: [String]
  public init(_ text: String) {
    self.text = text
    tokens = text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
  }
  public func matches(_ process: ProcessSample) -> Bool {
    tokens.allSatisfy { token in
      if token.hasPrefix("pid:") { return Int32(token.dropFirst(4)) == process.id.pid }
      if token.hasPrefix("uid:") { return UInt32(token.dropFirst(4)) == process.userID }
      if token.hasPrefix("user:") { return process.userName?.lowercased() == String(token.dropFirst(5)) }
      if token.hasPrefix("port:") { return false }
      let searchable =
        "\(process.name) \(process.project ?? "") \(process.path) \(process.id.pid) \(process.userID) \(process.userName ?? "")"
      return searchable.lowercased().contains(token)
    }
  }
  public func matches(_ resource: ProcessResource) -> Bool {
    tokens.allSatisfy { token in
      if token.hasPrefix("pid:") { return Int32(token.dropFirst(4)) == resource.owner.pid }
      if token.hasPrefix("port:") {
        guard let port = UInt16(token.dropFirst(5)), port > 0 else { return false }
        return resource.localPort == port || resource.remotePort == port
      }
      let searchable =
        "\(resource.processName) \(resource.owner.pid) \(resource.path) \(resource.localAddress) \(resource.remoteAddress) \(resource.kind.rawValue) \(resource.state)"
      return searchable.lowercased().contains(token)
    }
  }
}
