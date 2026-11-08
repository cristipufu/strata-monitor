import Foundation

public enum HistoryLayout {
  /// A fixed time window keeps a newly started graph at the right edge instead
  /// of implying that a few seconds of measurements represent a whole minute.
  public static func horizontalPosition(
    at time: TimeInterval, latest: TimeInterval, duration: TimeInterval = 60
  ) -> Double? {
    guard time.isFinite, latest.isFinite, duration.isFinite, duration > 0,
      time <= latest, time >= latest - duration
    else { return nil }
    return (time - latest + duration) / duration
  }
}
