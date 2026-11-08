import Foundation

public enum NetworkActivity: Equatable, Sendable {
  case unavailable, idle, receiving, sending, bidirectional
  // Background chatter below this rate is not shown as a direction of traffic.
  public static let threshold: Double = 4_096
  public init(_ rate: NetworkRate?) {
    guard let rate, rate.total != nil else {
      self = .unavailable
      return
    }
    switch (rate.received >= Self.threshold, rate.sent >= Self.threshold) {
    case (false, false): self = .idle
    case (true, false): self = .receiving
    case (false, true): self = .sending
    case (true, true): self = .bidirectional
    }
  }
}

extension NetworkRate {
  public var total: Double? {
    guard received.isFinite, sent.isFinite, received >= 0, sent >= 0 else { return nil }
    let sum = received + sent
    return sum.isFinite ? sum : nil
  }
  /// A qualitative activity scale, not a percentage of link capacity.
  public var activityIntensity: Double? {
    let saturationBytesPerSecond = 100_000_000.0
    return total.map { min(1, log10(1 + $0) / log10(1 + saturationBytesPerSecond)) }
  }
}

extension NetworkRate {
  // Averaging the last two samples keeps one short burst from flipping the indicator.
  public static func recentAverage(of points: [HistoryPoint]) -> NetworkRate? {
    let rates = points.suffix(2).compactMap { point -> NetworkRate? in
      guard let received = point.download, let sent = point.upload else { return nil }
      return NetworkRate(received: received, sent: sent)
    }
    guard !rates.isEmpty else { return nil }
    let count = Double(rates.count)
    return NetworkRate(
      received: rates.map(\.received).reduce(0, +) / count,
      sent: rates.map(\.sent).reduce(0, +) / count)
  }
}
