import Foundation
import StrataCore
import Testing

@testable import StrataSystem

private struct MarkedFolders: ProjectFileProbing {
  let projects: Set<String>
  func containsProjectMarker(_ directory: String) -> Bool { projects.contains(directory) }
  func resolvingSymbolicLinks(_ path: String) -> String { path }
}

private struct FixedDirectories: WorkingDirectoryReading {
  let directories: [Int32: String]
  func workingDirectory(of pid: Int32) -> String? { directories[pid] }
}

@Test func runnersAreNamedAfterTheProjectTheyWorkIn() {
  func process(_ pid: Int32, _ name: String, user: UInt32 = 501) -> ProcessSample {
    ProcessSample(
      id: ProcessIdentity(pid: pid, startSeconds: 1, startMicroseconds: 0), parentPID: 1,
      userID: user, name: name, path: "", cpuTimeNanoseconds: nil, residentBytes: nil,
      footprintBytes: nil, threads: nil)
  }
  var labeling = ProcessLabeling(
    projects: ProjectResolver(
      homeDirectory: "/Users/me", probe: MarkedFolders(projects: ["/Users/me/code/culprit"])),
    workingDirectories: FixedDirectories(directories: [
      10: "/Users/me/code/culprit/app", 11: "/Users/me/code/culprit", 12: "/Users/me/code/culprit",
      13: "/Users/me/code/culprit",
    ]), currentUser: 501)
  #expect(labeling.project(of: process(10, "bun")) == "culprit")
  #expect(labeling.project(of: process(11, "python3.14")) == "culprit")
  #expect(labeling.project(of: process(12, "Safari")) == nil, "Apps are named by themselves")
  #expect(labeling.project(of: process(13, "node", user: 0)) == nil)
  var named = process(10, "bun")
  named.project = "culprit"
  #expect(named.displayName == "bun · culprit")
}
