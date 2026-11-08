import Foundation
import StrataCore
import Testing

@Test func volumeScopeUsesObservedFilesystemInsteadOfPathSpelling() throws {
  let identity = FileSystemIdentity(firstComponent: 123, secondComponent: 456)
  let scope = VolumeResourceScope(identity: identity, name: "Work", mountPath: "/Volumes/Work")
  let owner = ProcessIdentity(pid: 42, startSeconds: 1, startMicroseconds: 0)
  func resource(_ path: String, fileSystem: FileSystemIdentity?) -> ProcessResource {
    ProcessResource(
      owner: owner, processName: "worker", descriptor: 1, kind: .file, path: path,
      fileSystem: fileSystem)
  }
  #expect(scope.contains(resource("/an/alias/to/a/file", fileSystem: identity)))
  #expect(
    !scope.contains(
      resource(
        "/Volumes/Work/nested-mount/file",
        fileSystem:
          FileSystemIdentity(firstComponent: 789, secondComponent: 456))))
  #expect(!scope.contains(resource("/Volumes/Work/unknown", fileSystem: nil)))
  let restored = try JSONDecoder().decode(
    VolumeResourceScope.self, from: JSONEncoder().encode(scope))
  #expect(restored == scope)
}

@Test func volumeResourceExportsPreserveTheObservedScopeAndFilesystem() throws {
  let identity = FileSystemIdentity(firstComponent: 1, secondComponent: 2)
  let scope = VolumeResourceScope(identity: identity, name: "Work", mountPath: "/Volumes/Work")
  let resource = ProcessResource(
    owner: ProcessIdentity(pid: 42, startSeconds: 1, startMicroseconds: 0),
    processName: "worker", descriptor: 3, kind: .file, fileSystem: identity)
  let snapshot = InspectionExport(
    scope: .resources, query: "", processes: [], processScan: nil,
    resources: ResourceReport(resources: [resource]), selectedDetails: nil,
    observedHistory: [], resourceVolume: scope)
  let restored = try JSONDecoder().decode(
    InspectionExport.self, from: JSONEncoder().encode(snapshot))
  #expect(restored.resourceVolume == scope)
  #expect(restored.resourcePathPrefix == nil)
  #expect(restored.resources.resources.first?.fileSystem == identity)
}
