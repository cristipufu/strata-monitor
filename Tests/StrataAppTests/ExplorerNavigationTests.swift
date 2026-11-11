import Foundation
import StrataCore
import Testing

@testable import StrataBar

@Test func previewFlagsAreIsolatedAndRequireAnExplicitSurface() {
  let normal = PreviewConfiguration(arguments: [
    "app", "--appearance", "dark", "--preview-self", "--capture", "/tmp/unrequested.png",
    "--preview-families",
  ])
  #expect(!normal.isEnabled && normal.appearance == nil && !normal.selectsOwnProcess)
  #expect(normal.processGrouping == .individual)
  let explorer = PreviewConfiguration(arguments: [
    "app", "--preview", "--preview-self", "--appearance", "light",
  ])
  #expect(
    explorer.surface == .explorer && explorer.appearance == .light && explorer.selectsOwnProcess)
  let page = PreviewConfiguration(arguments: [
    "app", "--preview-page", "cpu", "--appearance", "dark",
  ])
  #expect(page.surface == .reading(.cpu) && page.appearance == .dark)
  let families = PreviewConfiguration(arguments: [
    "app", "--preview", "--preview-families", "--capture", "/tmp/requested.png",
  ])
  #expect(families.processGrouping == .families)
  let glyphs = PreviewConfiguration(arguments: [
    "app", "--render-glyphs", "/tmp/glyphs.png", "--preview", "--capture", "/tmp/unused.png",
    "--preview-self", "--preview-families",
  ])
  #expect(glyphs.isEnabled && glyphs.surface == .glyphs("/tmp/glyphs.png"))
  #expect(
    !glyphs.selectsOwnProcess && glyphs.processGrouping == .individual)
  #expect(PreviewConfiguration(arguments: ["app", "--appearance", "dark"]).surface == nil)
}

@Test @MainActor func explorerDestinationsReplaceScopeWhileResumePreservesInvestigation() {
  let navigation = ExplorerNavigation()
  let id = ProcessIdentity(pid: 42, startSeconds: 1, startMicroseconds: 0)
  navigation.open(.processes(id))
  #expect(navigation.section == .processes && navigation.identity == id)
  navigation.query = "worker"
  let previous = navigation.revision
  navigation.open(.resume)
  #expect(navigation.identity == id && navigation.query == "worker")
  #expect(navigation.revision != previous)
  navigation.open(.ports)
  #expect(navigation.section == .ports && navigation.identity == nil && navigation.query.isEmpty)
  navigation.open(.family(id))
  #expect(
    navigation.section == .processes && navigation.grouping == .families
      && navigation.identity == id)
  navigation.open(.resources(URL(fileURLWithPath: "/Volumes/Work Drive")))
  #expect(
    navigation.section == .files && navigation.pathScope?.path == "/Volumes/Work Drive"
      && navigation.query.isEmpty)
  let scope = VolumeResourceScope(
    identity: FileSystemIdentity(firstComponent: 1, secondComponent: 2),
    name: "Work", mountPath: "/Volumes/Work")
  navigation.open(.volume(scope))
  #expect(navigation.volumeScope == scope && navigation.pathScope == nil)
  navigation.open(.resume)
  #expect(navigation.volumeScope == scope)
  navigation.open(.processes(id))
  #expect(navigation.volumeScope == nil && navigation.pathScope == nil)
}

@Test @MainActor func lookingUpAPortOpensPortsSearchingForIt() {
  let navigation = ExplorerNavigation()
  navigation.open(.processes(nil))
  navigation.query = "bun"
  navigation.open(.port(3000))
  #expect(navigation.section == .ports && navigation.query == "port:3000")
  #expect(navigation.identity == nil && navigation.pathScope == nil)
  let pid = ProcessIdentity(pid: 99, startSeconds: 1, startMicroseconds: 0)
  navigation.open(.folderProcesses("/Users/me/code/strata", pid))
  #expect(navigation.section == .processes && navigation.grouping == .individual)
  #expect(navigation.query == "cwd:/Users/me/code/strata" && navigation.identity == pid)
}
