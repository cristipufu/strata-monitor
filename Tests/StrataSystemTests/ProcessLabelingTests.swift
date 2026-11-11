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
  func process(_ pid: Int32, _ name: String, path: String = "", user: UInt32 = 501) -> ProcessSample {
    ProcessSample(
      id: ProcessIdentity(pid: pid, startSeconds: 1, startMicroseconds: 0), parentPID: 1,
      userID: user, name: name, path: path, cpuTimeNanoseconds: nil, residentBytes: nil,
      footprintBytes: nil, threads: nil)
  }
  var labeling = ProcessLabeling(
    projects: ProjectResolver(
      homeDirectory: "/Users/me", probe: MarkedFolders(projects: ["/Users/me/code/culprit"])),
    workingDirectories: FixedDirectories(directories: [
      10: "/Users/me/code/culprit/app", 11: "/Users/me/code/culprit", 12: "/Users/me/code/culprit",
      13: "/Users/me/code/culprit", 14: "/Users/me/code/culprit", 15: "/Users/me/scratch",
      16: "/Users/me", 17: "/",
    ]), currentUser: 501)
  #expect(labeling.project(of: process(10, "bun")) == "culprit")
  #expect(labeling.project(of: process(11, "python3.14")) == "culprit")
  #expect(
    labeling.project(
      of: process(
        14, "Python",
        path: "/Library/Frameworks/Python.framework/Versions/3.13/Resources/Python.app/Contents/MacOS/Python"
      )) == "culprit")
  #expect(
    labeling.location(
      of: process(15, "custom-cli", path: "/Users/me/bin/custom-cli")
    ).workingDirectory == "/Users/me/scratch")
  let homeLocation = labeling.location(of: process(16, "bun"))
  #expect(homeLocation.workingDirectory == "/Users/me" && homeLocation.project == nil)
  let rootLocation = labeling.location(of: process(17, "bun"))
  #expect(rootLocation.workingDirectory == nil && rootLocation.project == nil)
  #expect(
    labeling.project(of: process(12, "Safari", path: "/Applications/Safari.app/Contents/MacOS/Safari"))
      == nil, "Apps are named by themselves")
  #expect(labeling.project(of: process(13, "node", user: 0)) == nil)
  var named = process(10, "bun")
  named.project = "culprit"
  #expect(named.displayName == "bun · culprit")
}
