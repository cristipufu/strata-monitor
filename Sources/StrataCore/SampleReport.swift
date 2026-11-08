import Foundation

public struct SampleFrame: Equatable, Codable, Sendable {
  public let symbol: String
  public let binary: String?
  public let count: Int
  public init(symbol: String, binary: String?, count: Int) {
    self.symbol = symbol
    self.binary = binary
    self.count = count
  }
}

public struct SampleReport: Equatable, Codable, Sendable {
  public let pid: Int32
  public let processName: String
  /// Heaviest first. The tool lists only frames seen at the top of a stack at least five times.
  public let topFrames: [SampleFrame]
  /// Every thread's samples together, which is what the top-frame counts add up to.
  public let totalSamples: Int
  public let rawText: String
  public init(
    pid: Int32, processName: String, topFrames: [SampleFrame], totalSamples: Int, rawText: String
  ) {
    self.pid = pid
    self.processName = processName
    self.topFrames = topFrames
    self.totalSamples = totalSamples
    self.rawText = rawText
  }
}
