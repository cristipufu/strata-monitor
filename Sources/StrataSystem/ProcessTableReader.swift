import StrataCore

public protocol ProcessTableReading: Sendable {
  func read() async throws -> ExternalProcessTable
}

/// Every user's processes through the setuid `ps`, for when the helper is off.
public struct ProcessTableReader: ProcessTableReading {
  private let tool: any SystemToolLaunching
  public init(tool: any SystemToolLaunching = SystemTool()) {
    self.tool = tool
  }

  /// ps always lists at least itself, so a table without records means the
  /// format changed, not that nothing runs.
  public func read() async throws -> ExternalProcessTable {
    let table = ProcessTableParser.parse(try await tool.run(.processTable))
    guard !table.records.isEmpty else { throw SystemToolError.unrecognizedOutput }
    return table
  }
}
