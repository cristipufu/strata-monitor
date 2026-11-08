import Foundation
import StrataCore

/// Hook for a fallback source of other users' CPU time and resident memory, such as a fixed-argv
/// `/bin/ps` launch. Return nil when the source is unavailable; the merge never fills gaps with 0.
public protocol OtherUsersUsageSource: Sendable {
  func usageEstimates() async -> [ProcessUsageEstimate]?
}

/// Uses the privileged helper's snapshot, which covers every process, whenever the helper answers.
/// Otherwise it scans with the current user's access and asks the fallback source for other
/// users' CPU and memory. The helper rescans on request, so a separate local scan would only
/// repeat its work.
public actor MergedProcessInventory: ProcessListing {
  private let local: any ProcessListing
  private let otherUsers: (any OtherUsersUsageSource)?
  private var privileged: (any PrivilegedProcessSnapshotting)?
  // Estimates cost a tool launch, so they are read only while a view shows other users' rows.
  private var estimatesWanted = true
  public private(set) var privilegedIssue: PrivilegedHelperError?

  public init(
    local: any ProcessListing = ProcessInventoryCollector(),
    privileged: (any PrivilegedProcessSnapshotting)? = nil,
    otherUsers: (any OtherUsersUsageSource)? = nil
  ) {
    self.local = local
    self.privileged = privileged
    self.otherUsers = otherUsers
  }
  public func usePrivilegedSource(_ source: (any PrivilegedProcessSnapshotting)?) {
    privileged = source
    privilegedIssue = nil
  }
  public func useOtherUsersEstimates(_ wanted: Bool) { estimatesWanted = wanted }
  public func inventory() async -> ProcessInventory { await coveredInventory().inventory }

  public func coveredInventory() async -> CoveredProcessInventory {
    if let privilegedInventory = await readPrivileged() {
      return CoveredProcessInventory(inventory: privilegedInventory, coverage: .allProcesses)
    }
    let source = estimatesWanted ? otherUsers : nil
    async let estimates = source?.usageEstimates()
    let localInventory = await local.inventory()
    return ProcessInventoryMerge.merge(local: localInventory, estimates: await estimates)
  }
  private func readPrivileged() async -> ProcessInventory? {
    guard let privileged else { return nil }
    do {
      let inventory = try await privileged.processInventory()
      privilegedIssue = nil
      return inventory.summary.failed ? nil : inventory
    } catch let error as PrivilegedHelperError {
      privilegedIssue = error
      return nil
    } catch {
      return nil
    }
  }
}

/// Uses the helper for explicit inspections when it is available, so other users' ports and open
/// files appear; otherwise inspects with the current user's access.
public actor MergedResourceInspector: ResourceInspecting {
  private let local: any ResourceInspecting
  private var privileged: (any PrivilegedResourceInspecting)?

  public init(
    local: any ResourceInspecting = ResourceCollector(),
    privileged: (any PrivilegedResourceInspecting)? = nil
  ) {
    self.local = local
    self.privileged = privileged
  }
  public func usePrivilegedSource(_ source: (any PrivilegedResourceInspecting)?) {
    privileged = source
  }
  public func inspect(_ processes: [ProcessSample], socketsOnly: Bool) async throws
    -> ResourceReport
  {
    if let privileged {
      do {
        return try await privileged.resources(for: processes, socketsOnly: socketsOnly)
      } catch is PrivilegedHelperError {
        try Task.checkCancellation()
      }
    }
    return try await local.inspect(processes, socketsOnly: socketsOnly)
  }
  public func identityIsCurrent(_ identity: ProcessIdentity) async -> Bool {
    await local.identityIsCurrent(identity)
  }
}
