import CSystem
import Foundation
import StrataCore

package struct ResourceOwner: Sendable {
  package let id: ProcessIdentity
  package let name: String
  package init(id: ProcessIdentity, name: String) {
    self.id = id
    self.name = name
  }
}

package enum NativeResourceInventory {
  /// Each owner is checked before and after its descriptors are read, so a reused pid, or a
  /// process that changed owner by running a setuid program, never contributes resources the
  /// caller may not see. The default check is the identity alone.
  package static func collect(
    _ owners: [ResourceOwner], socketsOnly: Bool, maximumResults: Int,
    cancellation: NativeScanCancellation,
    stillPermitted: (ProcessIdentity) -> Bool = NativeProcessIdentity.isCurrent,
    isolation: isolated (any Actor)? = #isolation
  ) async throws -> ResourceReport {
    var report = ResourceReport(resources: [])
    var seen = Set<ProcessIdentity>()
    for owner in owners where seen.insert(owner.id).inserted {
      try Task.checkCancellation()
      guard stillPermitted(owner.id) else {
        report.summary.changedDuringScan = true
        continue
      }
      let partial = resources(for: owner, socketsOnly: socketsOnly, cancellation: cancellation)
      try Task.checkCancellation()
      report.summary.merge(partial.summary)
      guard stillPermitted(owner.id) else {
        report.summary.changedDuringScan = true
        continue
      }
      report.resources.append(contentsOf: partial.resources)
      if report.resources.count >= maximumResults {
        report.resources = Array(report.resources.prefix(maximumResults))
        report.summary.truncated = true
        break
      }
      await Task.yield()
    }
    try Task.checkCancellation()
    return report
  }
  private static func resources(
    for owner: ResourceOwner, socketsOnly: Bool, cancellation: NativeScanCancellation
  ) -> ResourceReport {
    var count = 0
    var status = SBScanStatus()
    guard let buffer = sb_resources(owner.id.pid, &count, socketsOnly, &status, cancellation.handle)
    else {
      return ResourceReport(resources: [], summary: scanSummary(status))
    }
    defer { sb_free(buffer) }
    let resources = UnsafeBufferPointer(start: buffer, count: count).map {
      resource($0, owner: owner)
    }
    return ResourceReport(resources: resources, summary: scanSummary(status))
  }
  private static func resource(_ raw: SBResource, owner: ResourceOwner) -> ProcessResource {
    let kind: ResourceKind =
      switch raw.kind {
      case 1: .file
      case 2: .directory
      case 3: .device
      case 4: .pipe
      case 5: .unixSocket
      case 6: .tcp
      case 7: .udp
      default: .other
      }
    return ProcessResource(
      owner: owner.id, processName: owner.name, descriptor: raw.descriptor,
      kind: kind, path: nativeString(raw.path), localAddress: nativeString(raw.local_address),
      remoteAddress: nativeString(raw.remote_address), localPort: raw.local_port,
      remotePort: raw.remote_port, state: socketState(raw, kind: kind),
      fileSystem: raw.file_system_valid
        ? FileSystemIdentity(
          firstComponent: raw.file_system_id.0, secondComponent: raw.file_system_id.1) : nil)
  }
  private static func socketState(_ raw: SBResource, kind: ResourceKind) -> String {
    guard kind == .tcp else {
      return kind == .udp ? (raw.remote_port == 0 ? "Bound datagram" : "Connected datagram") : ""
    }
    switch raw.tcp_state {
    case 1: return "Listening"
    case 2, 3: return "Connecting"
    case 4: return "Established"
    case 5...10: return "Closing"
    default: return "Closed"
    }
  }
}
