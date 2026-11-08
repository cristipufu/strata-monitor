import Foundation
import StrataCore
import StrataHelperInterface

/// A process's path and name are chosen by whoever started it, so one user could otherwise make
/// every user's snapshot too large to send. Long values are shortened, and as a last resort
/// paths are left out and the snapshot is marked truncated instead of failing.
enum SnapshotReply {
  static let maximumPathBytes = 1024
  static let maximumNameBytes = 256

  static func encode(_ inventory: ProcessInventory) -> Data {
    var bounded = inventory
    bounded.processes = inventory.processes.map { process in
      var shortened = process
      shortened.path = prefix(process.path, bytes: maximumPathBytes)
      shortened.name = prefix(process.name, bytes: maximumNameBytes)
      return shortened
    }
    do throws(HelperFailure) {
      return try HelperCoding.encode(HelperReply(.success(bounded)))
    } catch .payloadTooLarge {
      bounded.processes = bounded.processes.map { process in
        var withoutPath = process
        withoutPath.path = ""
        return withoutPath
      }
      bounded.summary.truncated = true
      return HelperCoding.reply(bounded)
    } catch {
      return HelperCoding.failureReply(error)
    }
  }

  static func prefix(_ value: String, bytes limit: Int) -> String {
    guard value.utf8.count > limit else { return value }
    var length = 0
    var scalars = String.UnicodeScalarView()
    for scalar in value.unicodeScalars {
      length += String(scalar).utf8.count
      guard length <= limit else { break }
      scalars.append(scalar)
    }
    return String(scalars)
  }
}
