import Foundation

public struct HelperInfo: Codable, Sendable, Equatable {
  public let helperVersion: Int
  public let schemaVersion: Int
  public let effectiveUserID: UInt32
  public init(helperVersion: Int, schemaVersion: Int, effectiveUserID: UInt32) {
    self.helperVersion = helperVersion
    self.schemaVersion = schemaVersion
    self.effectiveUserID = effectiveUserID
  }
  public var matchesThisBuild: Bool {
    helperVersion == HelperContract.helperVersion && schemaVersion == HelperContract.schemaVersion
  }
}

public enum HelperFailure: String, Codable, Sendable, Error {
  case unsupportedSchema, invalidRequest, rateLimited, payloadTooLarge, malformedReply
}

public struct HelperReply<Payload: Codable & Sendable>: Codable, Sendable {
  public enum Outcome: Codable, Sendable {
    case success(Payload)
    case failure(HelperFailure)
  }
  public let schemaVersion: Int
  public let outcome: Outcome
  public init(_ outcome: Outcome, schemaVersion: Int = HelperContract.schemaVersion) {
    self.schemaVersion = schemaVersion
    self.outcome = outcome
  }
  public func payload() throws(HelperFailure) -> Payload {
    guard schemaVersion == HelperContract.schemaVersion else { throw .unsupportedSchema }
    switch outcome {
    case .success(let payload): return payload
    case .failure(let failure): throw failure
    }
  }
}

public struct ProcessIdentityWire: Codable, Sendable, Hashable {
  public let pid: Int32
  public let startSeconds: UInt64
  public let startMicroseconds: UInt64
  public init(pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64) {
    self.pid = pid
    self.startSeconds = startSeconds
    self.startMicroseconds = startMicroseconds
  }
}

public struct ResourceRequest: Codable, Sendable {
  public let schemaVersion: Int
  public let identities: [ProcessIdentityWire]
  public let socketsOnly: Bool
  public init(
    identities: [ProcessIdentityWire], socketsOnly: Bool,
    schemaVersion: Int = HelperContract.schemaVersion
  ) {
    self.schemaVersion = schemaVersion
    self.identities = identities
    self.socketsOnly = socketsOnly
  }
  public func validated() throws(HelperFailure) -> ResourceRequest {
    guard schemaVersion == HelperContract.schemaVersion else { throw .unsupportedSchema }
    guard identities.count <= HelperContract.maximumResourceIdentities,
      identities.allSatisfy({ $0.pid > 0 })
    else { throw .invalidRequest }
    return self
  }
}

public enum HelperCoding {
  public static func encode<Value: Encodable>(
    _ value: Value, limit: Int = HelperContract.maximumReplyBytes
  ) throws(HelperFailure) -> Data {
    // JSON encodes and decodes these payloads faster than a binary property list; its larger
    // size costs little over XPC.
    let encoder = JSONEncoder()
    encoder.outputFormatting = .withoutEscapingSlashes
    guard let data = try? encoder.encode(value) else { throw .malformedReply }
    guard data.count <= limit else { throw .payloadTooLarge }
    return data
  }
  public static func decode<Value: Decodable>(
    _ type: Value.Type, from data: Data, limit: Int = HelperContract.maximumReplyBytes
  ) throws(HelperFailure) -> Value {
    guard data.count <= limit else { throw .payloadTooLarge }
    guard let value = try? JSONDecoder().decode(type, from: data) else {
      throw .malformedReply
    }
    return value
  }
  // A failure carries no payload, so any payload type encodes it identically. An empty reply
  // is reported to the caller as malformed.
  public static func failureReply(_ failure: HelperFailure) -> Data {
    (try? encode(HelperReply<NoPayload>(.failure(failure)))) ?? Data()
  }
  private struct NoPayload: Codable, Sendable {}
  public static func reply<Payload: Codable & Sendable>(_ payload: Payload) -> Data {
    do throws(HelperFailure) {
      return try encode(HelperReply(.success(payload)))
    } catch {
      return failureReply(error)
    }
  }
}
