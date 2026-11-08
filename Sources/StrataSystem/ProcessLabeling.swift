import Foundation
import StrataCore

/// The names a person reads in process lists: the owner's account name, and for interpreters,
/// shells and build tools the project they work in, so several `bun` rows tell themselves apart.
struct ProcessLabeling: Sendable {
  private static let projectRunners: Set<String> = [
    "bun", "node", "deno", "ruby", "java", "zsh", "bash", "fish", "sh", "swift", "swift-frontend",
    "cargo", "go", "npm", "pnpm", "yarn", "make", "uv", "php", "perl",
  ]
  private var projects: ProjectResolver
  private let workingDirectories: any WorkingDirectoryReading
  private let currentUser: UInt32

  init(
    projects: ProjectResolver = ProjectResolver(),
    workingDirectories: any WorkingDirectoryReading = ProcessWorkingDirectoryReader(),
    currentUser: UInt32 = getuid()
  ) {
    self.projects = projects
    self.workingDirectories = workingDirectories
    self.currentUser = currentUser
  }

  mutating func project(of process: ProcessSample) -> String? {
    guard process.userID == currentUser, Self.runsProjects(process.name),
      let directory = workingDirectories.workingDirectory(of: process.id.pid)
    else { return nil }
    return projects.project(forWorkingDirectory: directory)
  }

  static func runsProjects(_ name: String) -> Bool {
    projectRunners.contains(name) || name.hasPrefix("python")
  }
}
