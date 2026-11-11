import Foundation
import StrataCore

/// The names a person reads in process lists: the owner's account name, and for interpreters,
/// shells and build tools the project they work in, so several `bun` rows tell themselves apart.
struct ProcessLabeling: Sendable {
  private static let projectRunners: Set<String> = [
    "bun", "node", "deno", "ruby", "java", "zsh", "bash", "fish", "sh", "swift", "swift-frontend",
    "cargo", "go", "npm", "pnpm", "yarn", "make", "uv", "php", "perl", "rustc", "rustdoc",
    "rust-analyzer", "swift-build", "swift-test", "swift-package", "swift-format",
    "swiftpm-testing-helper", "xctest", "clang", "clang++", "ld", "git", "gh", "codex", "claude",
    "pytest", "jest", "vitest", "playwright", "esbuild", "tsc", "vite", "webpack", "tsx", "cmake",
    "ninja", "bazel", "gradle", "dotnet", "beam.smp", "elixir", "google chrome for testing",
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
    location(of: process).project
  }

  mutating func location(of process: ProcessSample) -> (workingDirectory: String?, project: String?) {
    guard process.userID == currentUser,
      Self.runsProjects(process.name) || Self.isCommandLineExecutable(process.path),
      let directory = workingDirectories.workingDirectory(of: process.id.pid),
      !directory.isEmpty, directory != "/"
    else { return (nil, nil) }
    return (directory, projects.project(forWorkingDirectory: directory))
  }

  static func runsProjects(_ name: String) -> Bool {
    let lower = name.lowercased()
    return projectRunners.contains(lower) || lower.hasPrefix("python")
  }

  private static func isCommandLineExecutable(_ path: String) -> Bool {
    guard !path.isEmpty else { return false }
    if path.hasPrefix("/Applications/") || path.hasPrefix("/System/")
      || path.hasPrefix("/Library/Apple/") || path.hasPrefix("/usr/libexec/")
      || path.hasPrefix("/usr/sbin/")
    {
      return false
    }
    return !path.contains(".app/") && !path.contains(".xpc/") && !path.contains(".appex/")
  }
}
