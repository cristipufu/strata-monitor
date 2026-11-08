import Foundation

public enum InspectionExportScope: String, Codable, Sendable {
  case processes, ports, resources
}

public struct InspectionExport: Codable, Sendable {
  public let schemaVersion: Int
  public let capturedAt: Date
  public let capturedUptime: TimeInterval
  public let processSampleUptime: TimeInterval?
  public let resourceInspectedAt: Date?
  public let scope: InspectionExportScope
  public let query: String
  public let resourcePathPrefix: String?
  public let resourceVolume: VolumeResourceScope?
  public let processGrouping: ProcessGrouping
  public let cpuSemantics: String
  public let processes: [ProcessSample]
  public let processScan: ScanSummary?
  public let resources: ResourceReport
  public let selectedDetails: ProcessDetails?
  public let observedHistory: [ProcessHistoryPoint]
  public init(
    scope: InspectionExportScope, query: String, processes: [ProcessSample],
    processScan: ScanSummary?,
    resources: ResourceReport, selectedDetails: ProcessDetails?,
    observedHistory: [ProcessHistoryPoint],
    includeArguments: Bool = false, capturedAt: Date = Date(),
    capturedUptime: TimeInterval = ProcessInfo.processInfo.systemUptime,
    processSampleUptime: TimeInterval? = nil, resourceInspectedAt: Date? = nil,
    resourcePathPrefix: String? = nil, processGrouping: ProcessGrouping = .individual,
    resourceVolume: VolumeResourceScope? = nil
  ) {
    schemaVersion = 1
    self.capturedAt = capturedAt
    self.scope = scope
    self.query = query
    self.resourcePathPrefix = resourcePathPrefix
    self.resourceVolume = resourceVolume
    self.processGrouping = processGrouping
    self.capturedUptime = capturedUptime
    self.processSampleUptime = processSampleUptime
    self.resourceInspectedAt = resourceInspectedAt
    cpuSemantics =
      "Process CPU: 100% equals one logical core. Missing values are unavailable, not zero."
    self.processes = processes
    self.processScan = processScan
    self.resources = resources
    self.observedHistory = observedHistory
    if let details = selectedDetails, !includeArguments {
      self.selectedDetails = ProcessDetails(
        identity: details.identity, inspectedAt: details.inspectedAt, signing: details.signing,
        arguments: nil, argumentsIssue: "Arguments omitted from this export.",
        executableMappings: details.executableMappings, mappingSummary: details.mappingSummary)
    } else {
      self.selectedDetails = selectedDetails
    }
  }
}
