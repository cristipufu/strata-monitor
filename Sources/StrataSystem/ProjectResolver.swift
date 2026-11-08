import Darwin
import Foundation

public protocol ProjectFileProbing: Sendable {
  func containsProjectMarker(_ directory: String) -> Bool
  func resolvingSymbolicLinks(_ path: String) -> String
}

public struct FileSystemProjectProbe: ProjectFileProbing {
  static let markers = [
    ".git", "package.json", "Package.swift", "pyproject.toml", "Cargo.toml", "go.mod",
  ]
  public init() {}
  public func containsProjectMarker(_ directory: String) -> Bool {
    Self.markers.contains { access(directory + "/" + $0, F_OK) == 0 }
  }
  public func resolvingSymbolicLinks(_ path: String) -> String {
    guard let resolved = realpath(path, nil) else { return path }
    defer { free(resolved) }
    return String(cString: resolved)
  }
}

/// Names the project a working directory belongs to: the nearest enclosing folder
/// with a project marker, else the directory itself. The home folder and `/` are
/// never projects, even when the home folder is a dotfiles repository.
public struct ProjectResolver: Sendable {
  private let probe: any ProjectFileProbing
  private let homeComponents: [Substring]
  private let capacity: Int
  private var projects: [String: String?] = [:]

  public init(
    homeDirectory: String = NSHomeDirectory(),
    probe: any ProjectFileProbing = FileSystemProjectProbe(), capacity: Int = 512
  ) {
    self.probe = probe
    homeComponents = Self.components(of: probe.resolvingSymbolicLinks(homeDirectory))
    self.capacity = max(1, capacity)
  }

  public mutating func project(forWorkingDirectory path: String) -> String? {
    if let cached = projects[path] { return cached }
    let project = resolve(path)
    if projects.count >= capacity { projects.removeAll(keepingCapacity: true) }
    projects[path] = project
    return project
  }

  private func resolve(_ path: String) -> String? {
    guard path.hasPrefix("/") else { return nil }
    let directory = Self.components(of: probe.resolvingSymbolicLinks(path))
    guard let ownName = directory.last, directory != homeComponents else { return nil }
    for depth in stride(from: directory.count, to: 0, by: -1) {
      let candidate = directory.prefix(depth)
      if candidate.elementsEqual(homeComponents) { break }
      if probe.containsProjectMarker("/" + candidate.joined(separator: "/")) {
        return String(directory[depth - 1])
      }
    }
    return String(ownName)
  }

  private static func components(of path: String) -> [Substring] {
    path.split(separator: "/")
  }
}
