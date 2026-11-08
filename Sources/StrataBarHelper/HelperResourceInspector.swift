import Foundation
import StrataCore
import StrataHelperInterface
import StrataInventory

/// Runs one resource scan at a time for all connections. Only identities named by the caller are
/// read, and each must still match its pid and start time.
actor HelperResourceInspector {
  private let maximumResults: Int
  private let record: @Sendable (Int32) -> (identity: ProcessIdentity, owner: uid_t)?

  init(
    maximumResults: Int = 20_000,
    record: @escaping @Sendable (Int32) -> (identity: ProcessIdentity, owner: uid_t)? = {
      NativeProcessIdentity.record(of: $0)
    }
  ) {
    self.maximumResults = maximumResults
    self.record = record
  }
  func reply(to request: Data, for caller: CallerScope) async -> Data {
    do throws(HelperFailure) {
      let request = try HelperCoding.decode(
        ResourceRequest.self, from: request, limit: HelperContract.maximumRequestBytes
      ).validated()
      return HelperCoding.reply(await report(for: request, caller: caller))
    } catch {
      return HelperCoding.failureReply(error)
    }
  }
  private func report(for request: ResourceRequest, caller: CallerScope) async -> ResourceReport {
    let permission = caller.permission()
    let permitted = request.identities.filter { permission.permits(owner: record($0.pid)?.owner) }
    var report = await collect(permitted, socketsOnly: request.socketsOnly, permission: permission)
    if permitted.count < request.identities.count { report.summary.restricted = true }
    return report
  }
  private func collect(
    _ identities: [ProcessIdentityWire], socketsOnly: Bool, permission: ResourcePermission
  ) async -> ResourceReport {
    let record = record
    // Checked again around every read: a process may change owner by running a setuid program
    // while keeping its pid and start time.
    let stillPermitted: (ProcessIdentity) -> Bool = { identity in
      guard let current = record(identity.pid), current.identity == identity else { return false }
      return permission.permits(owner: current.owner)
    }
    let owners = identities.map { wire in
      ResourceOwner(
        id: ProcessIdentity(
          pid: wire.pid, startSeconds: wire.startSeconds,
          startMicroseconds: wire.startMicroseconds),
        name: NativeProcessIdentity.name(of: wire.pid))
    }
    do {
      return try await NativeResourceInventory.collect(
        owners, socketsOnly: socketsOnly, maximumResults: maximumResults,
        cancellation: try NativeScanCancellation(), stillPermitted: stillPermitted)
    } catch {
      var summary = ScanSummary()
      summary.failed = true
      summary.failureMessage = error.localizedDescription
      return ResourceReport(resources: [], summary: summary)
    }
  }
}
