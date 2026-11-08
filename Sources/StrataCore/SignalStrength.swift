public enum SignalStrength: Int, Sendable {
  case weak = 1
  case fair, strong
  public var fraction: Double { Double(rawValue) / 3 }
}

public struct SignalStrengthPolicy: Sendable {
  public private(set) var level: SignalStrength?
  private let weakBoundary = -78
  private let strongBoundary = -62
  private let hysteresis = 3
  public init() {}
  @discardableResult public mutating func update(rssi: Int?) -> SignalStrength? {
    guard let rssi, (-110 ... -1).contains(rssi) else {
      level = nil
      return nil
    }
    let candidate: SignalStrength =
      rssi < weakBoundary ? .weak : rssi < strongBoundary ? .fair : .strong
    guard let current = level else {
      level = candidate
      return candidate
    }
    if candidate.rawValue > current.rawValue {
      let boundary = current == .weak ? weakBoundary : strongBoundary
      if rssi >= boundary + hysteresis { level = candidate }
    } else if candidate.rawValue < current.rawValue {
      let boundary = current == .strong ? strongBoundary : weakBoundary
      if rssi < boundary - hysteresis { level = candidate }
    }
    return level
  }
}

public enum ConnectionState: String, Sendable {
  case unknown, offline, connecting, wifi, wired, other
  public var isAvailable: Bool? {
    switch self {
    case .unknown, .connecting: nil
    case .offline: false
    case .wifi, .wired, .other: true
    }
  }
}
