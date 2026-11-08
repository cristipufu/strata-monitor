import Darwin

public protocol UserNameLookup: Sendable {
  func userName(for userID: UInt32) -> String?
}

public struct PasswordDatabaseLookup: UserNameLookup {
  private static let maximumBufferBytes = 1 << 20
  public init() {}

  public func userName(for userID: UInt32) -> String? {
    let suggested = sysconf(_SC_GETPW_R_SIZE_MAX)
    var capacity = suggested > 0 ? Int(suggested) : 4096
    while capacity <= Self.maximumBufferBytes {
      switch lookUp(userID, bufferBytes: capacity) {
      case .found(let name): return name
      case .missing: return nil
      case .bufferTooSmall: capacity *= 2
      }
    }
    return nil
  }

  private enum Outcome {
    case found(String)
    case missing
    case bufferTooSmall
  }

  private func lookUp(_ userID: UInt32, bufferBytes: Int) -> Outcome {
    var buffer = [CChar](repeating: 0, count: bufferBytes)
    return buffer.withUnsafeMutableBufferPointer { storage in
      var entry = passwd()
      var result: UnsafeMutablePointer<passwd>?
      let status = getpwuid_r(uid_t(userID), &entry, storage.baseAddress, storage.count, &result)
      if status == ERANGE { return .bufferTooSmall }
      guard status == 0, result != nil, let name = entry.pw_name, name.pointee != 0 else {
        return .missing
      }
      return .found(String(cString: name))
    }
  }
}

/// Unknown users are remembered too, so a missing account costs one lookup.
public actor UserNameDirectory {
  private let lookup: any UserNameLookup
  private let capacity: Int
  private var names: [UInt32: String?] = [:]

  public init(lookup: any UserNameLookup = PasswordDatabaseLookup(), capacity: Int = 1024) {
    self.lookup = lookup
    self.capacity = max(1, capacity)
  }

  public func name(for userID: UInt32) -> String? {
    if let known = names[userID] { return known }
    let name = lookup.userName(for: userID)
    if names.count >= capacity { names.removeAll(keepingCapacity: true) }
    names[userID] = name
    return name
  }

  public func names(for userIDs: Set<UInt32>) -> [UInt32: String] {
    userIDs.reduce(into: [:]) { result, userID in result[userID] = name(for: userID) }
  }
}
