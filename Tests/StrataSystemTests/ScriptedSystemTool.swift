import Foundation
import Synchronization

@testable import StrataSystem

final class ScriptedSystemTool: SystemToolLaunching {
  private let responses: [SystemToolInvocation: Result<Data, SystemToolError>]
  private let received = Mutex<[SystemToolInvocation]>([])
  init(_ responses: [SystemToolInvocation: Result<Data, SystemToolError>]) {
    self.responses = responses
  }
  convenience init(_ invocation: SystemToolInvocation, output: String) {
    self.init([invocation: .success(Data(output.utf8))])
  }
  var invocations: [SystemToolInvocation] { received.withLock { $0 } }

  func run(_ invocation: SystemToolInvocation) async throws -> Data {
    received.withLock { $0.append(invocation) }
    guard let response = responses[invocation] else { throw SystemToolError.invalidRequest }
    return try response.get()
  }
}
