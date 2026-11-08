import Darwin
import Foundation
import StrataCore

struct FileSystemIdentityReader {
  func identity(at url: URL) -> FileSystemIdentity? {
    guard url.isFileURL else { return nil }
    var statistics = statfs()
    let result = url.withUnsafeFileSystemRepresentation { path in
      guard let path else { return -1 as Int32 }
      return statfs(path, &statistics)
    }
    guard result == 0 else { return nil }
    return FileSystemIdentity(
      firstComponent: statistics.f_fsid.val.0, secondComponent: statistics.f_fsid.val.1)
  }
}
