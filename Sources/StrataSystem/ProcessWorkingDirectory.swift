import CSystem
import Darwin

public protocol WorkingDirectoryReading: Sendable {
  func workingDirectory(of pid: Int32) -> String?
}

/// Other users' processes give nil, as the kernel denies them without root.
public struct ProcessWorkingDirectoryReader: WorkingDirectoryReading {
  public init() {}
  public func workingDirectory(of pid: Int32) -> String? {
    var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    guard sb_process_cwd(pid, &buffer, buffer.count) == 0 else { return nil }
    let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return String(decoding: bytes, as: UTF8.self)
  }
}
