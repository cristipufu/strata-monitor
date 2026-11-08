import CSystem
import Darwin
import Foundation
import Synchronization
import Testing

@testable import StrataSystem

private final class FakeProjectTree: ProjectFileProbing {
  private let markers: Set<String>
  private let links: [String: String]
  private let probes = Mutex(0)
  init(markers: Set<String>, links: [String: String] = [:]) {
    self.markers = markers
    self.links = links
  }
  var probeCount: Int { probes.withLock { $0 } }

  func containsProjectMarker(_ directory: String) -> Bool {
    probes.withLock { $0 += 1 }
    return markers.contains(directory)
  }
  func resolvingSymbolicLinks(_ path: String) -> String {
    for (link, target) in links where path == link || path.hasPrefix(link + "/") {
      return target + path.dropFirst(link.count)
    }
    return path
  }
}

@Suite struct ProjectResolverTests {
  private let tree = FakeProjectTree(
    markers: ["/Users/me/code/mono", "/Users/me/code/mono/packages/app", "/Users/me", "/opt/tool"],
    links: ["/Users/me/linked": "/Volumes/Work/client", "/home/me": "/Users/me"])
  private func resolver(home: String = "/Users/me", capacity: Int = 512) -> ProjectResolver {
    ProjectResolver(homeDirectory: home, probe: tree, capacity: capacity)
  }

  @Test(arguments: [
    ("/Users/me/code/mono/packages/app/src/routes", "app"),
    ("/Users/me/code/mono/docs", "mono"),
    ("/Users/me/code/mono", "mono"),
    ("/Users/me/code/mono/packages/app/", "app"),
    ("/Users/me/Downloads/scratch", "scratch"),
    ("/Users/me/Documents", "Documents"),
    ("/opt/tool/bin", "tool"),
    ("/private/tmp/build", "build"),
  ])
  func nearestMarkedFolderOrTheDirectoryItselfNamesTheProject(_ path: String, _ project: String) {
    var resolver = resolver()
    #expect(resolver.project(forWorkingDirectory: path) == project)
  }

  @Test(arguments: ["/", "/Users/me", "/Users/me/", "relative/path", ""])
  func homeRootAndRelativePathsHaveNoProject(_ path: String) {
    var resolver = resolver()
    #expect(resolver.project(forWorkingDirectory: path) == nil)
  }

  @Test func symbolicLinksResolveBeforeTheWalk() {
    let linkedTree = FakeProjectTree(
      markers: ["/Volumes/Work/client"], links: ["/Users/me/linked": "/Volumes/Work/client"])
    var resolver = ProjectResolver(homeDirectory: "/Users/me", probe: linkedTree)
    #expect(resolver.project(forWorkingDirectory: "/Users/me/linked/web") == "client")
  }

  @Test func linkedHomeFolderIsStillTheHomeFolder() {
    var resolver = resolver(home: "/home/me")
    #expect(resolver.project(forWorkingDirectory: "/Users/me") == nil)
    #expect(resolver.project(forWorkingDirectory: "/home/me") == nil)
    #expect(resolver.project(forWorkingDirectory: "/Users/me/Documents") == "Documents")
  }

  @Test func eachDirectoryIsProbedOnce() {
    var resolver = resolver()
    _ = resolver.project(forWorkingDirectory: "/Users/me/Downloads/scratch")
    let probesAfterFirstLookup = tree.probeCount
    #expect(probesAfterFirstLookup == 2)
    _ = resolver.project(forWorkingDirectory: "/Users/me/Downloads/scratch")
    #expect(tree.probeCount == probesAfterFirstLookup)
  }

  @Test func cacheStaysWithinItsCapacity() {
    let counted = FakeProjectTree(markers: [])
    var resolver = ProjectResolver(homeDirectory: "/Users/me", probe: counted, capacity: 2)
    for path in ["/a", "/b", "/c", "/a"] { _ = resolver.project(forWorkingDirectory: path) }
    #expect(counted.probeCount == 4)
    _ = resolver.project(forWorkingDirectory: "/a")
    #expect(counted.probeCount == 4)
  }
}

@Suite struct FileSystemProjectProbeTests {
  @Test func realFoldersAreProbedForEveryMarker() throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "strata-project-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let probe = FileSystemProjectProbe()
    for marker in FileSystemProjectProbe.markers {
      let folder = root.appending(path: marker.replacingOccurrences(of: ".", with: "-"))
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      #expect(!probe.containsProjectMarker(folder.path))
      FileManager.default.createFile(atPath: folder.appending(path: marker).path, contents: nil)
      #expect(probe.containsProjectMarker(folder.path))
    }
    let resolved = probe.resolvingSymbolicLinks(root.path)
    #expect(resolved.hasPrefix("/private/"))
    #expect(probe.resolvingSymbolicLinks("/strata-bar-missing") == "/strata-bar-missing")
  }
}

@Suite struct ProcessWorkingDirectoryTests {
  @Test func ownWorkingDirectoryMatchesTheFileSystemView() throws {
    let directory = try #require(ProcessWorkingDirectoryReader().workingDirectory(of: getpid()))
    let expected = FileSystemProjectProbe().resolvingSymbolicLinks(
      FileManager.default.currentDirectoryPath)
    #expect(directory == expected)
  }

  @Test(arguments: [Int32(0), -1, Int32.max])
  func invalidOrMissingProcessesHaveNoWorkingDirectory(_ pid: Int32) {
    #expect(ProcessWorkingDirectoryReader().workingDirectory(of: pid) == nil)
  }

  @Test func otherUsersProcessesAreDeniedRatherThanEmpty() {
    var buffer = [CChar](repeating: 0x41, count: 64)
    #expect(sb_process_cwd(1, &buffer, buffer.count) == EPERM)
    #expect(buffer[0] == 0)
  }

  @Test func shortBuffersAreRejectedWithATerminatedString() {
    var buffer = [CChar](repeating: 0x41, count: 2)
    #expect(sb_process_cwd(getpid(), &buffer, buffer.count) == ERANGE)
    #expect(buffer[0] == 0)
    #expect(sb_process_cwd(getpid(), nil, 16) == EINVAL)
    #expect(sb_process_cwd(getpid(), &buffer, 0) == EINVAL)
  }
}
