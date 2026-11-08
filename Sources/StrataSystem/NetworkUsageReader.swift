import StrataCore

public protocol NetworkUsageReading: Sendable {
  func read() async throws -> ProcessNetworkUsage
}

/// Cumulative per-process socket bytes for every user, without root.
public struct NetworkUsageReader: NetworkUsageReading {
  private let tool: any SystemToolLaunching
  public init(tool: any SystemToolLaunching = SystemTool()) {
    self.tool = tool
  }
  public func read() async throws -> ProcessNetworkUsage {
    try NetworkUsageParser.parse(try await tool.run(.networkUsage))
  }
}
