import Foundation
import StrataCore
import StrataInventory

public enum InspectionError: LocalizedError, Sendable {
  case processEnded
  public var errorDescription: String? {
    String(localized: "This process ended or its identity changed. Refresh the process list.")
  }
}

public actor ResourceCollector {
  private let maximumResults = 50_000
  public init() {}

  public func inspect(_ processes: [ProcessSample], socketsOnly: Bool = false) async throws
    -> ResourceReport
  {
    let cancellation = try NativeScanCancellation()
    let owners = processes.map { ResourceOwner(id: $0.id, name: $0.name) }
    return try await withTaskCancellationHandler {
      try await NativeResourceInventory.collect(
        owners, socketsOnly: socketsOnly, maximumResults: maximumResults,
        cancellation: cancellation)
    } onCancel: {
      cancellation.cancel()
    }
  }
  public func identityIsCurrent(_ id: ProcessIdentity) -> Bool {
    ProcessIdentityVerifier().isCurrent(id)
  }
}
