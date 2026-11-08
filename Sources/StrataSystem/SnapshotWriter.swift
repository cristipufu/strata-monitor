import Foundation
import StrataCore

public actor SnapshotWriter {
  public init() {}
  public func write(_ snapshot: InspectionExport, to url: URL) throws {
    try Task.checkCancellation()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(snapshot)
    try Task.checkCancellation()
    try data.write(to: url, options: .atomic)
  }
}
