import StrataCore

public protocol SystemSampling: Sendable {
  func sample(includeProcesses: Bool, includeGPU: Bool) async -> SystemSample
  func reset() async
}
public protocol DeviceControlling: Sendable {
  func sample() async -> DeviceSnapshot
  func setVolume(_ value: Double, on output: AudioOutputIdentity) async throws
  func setMuted(_ muted: Bool, on output: AudioOutputIdentity) async throws
  func selectOutput(_ output: AudioOutputIdentity) async throws
  func setWiFiPower(_ powered: Bool) async throws
}
public protocol ResourceInspecting: Sendable {
  func inspect(_ processes: [ProcessSample], socketsOnly: Bool) async throws -> ResourceReport
  func identityIsCurrent(_ identity: ProcessIdentity) async -> Bool
}

extension SystemCollector: SystemSampling {}
extension DeviceCollector: DeviceControlling {}
extension ResourceCollector: ResourceInspecting {}
