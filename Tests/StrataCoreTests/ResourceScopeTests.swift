import Foundation
import StrataCore
import Testing

@Test func pathScopesPreserveSpacesAndRespectDirectoryBoundaries() {
  let identity = ProcessIdentity(pid: 42, startSeconds: 1, startMicroseconds: 0)
  func resource(_ path: String) -> ProcessResource {
    ProcessResource(owner: identity, processName: "Fixture", descriptor: 3, kind: .file, path: path)
  }
  let scope = ResourcePathScope(URL(fileURLWithPath: "/Volumes/Work Drive/"))
  #expect(scope.contains(resource("/Volumes/Work Drive/file.txt")))
  #expect(scope.contains(resource("/Volumes/Work Drive")))
  #expect(!scope.contains(resource("/Volumes/Work Drive Backup/file.txt")))
  #expect(!scope.contains(resource("Pipe")))
  let root = ResourcePathScope(URL(fileURLWithPath: "/"))
  #expect(root.contains(resource("/tmp/file")))
}
