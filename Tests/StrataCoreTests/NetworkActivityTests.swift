import StrataCore
import Testing

@Test func networkActivityDistinguishesIdleAndBothDirections() {
  let active = NetworkActivity.threshold
  #expect(NetworkActivity(nil) == .unavailable)
  #expect(NetworkActivity(NetworkRate(received: 0, sent: 0)) == .idle)
  #expect(NetworkActivity(NetworkRate(received: active, sent: 0)) == .receiving)
  #expect(NetworkActivity(NetworkRate(received: 0, sent: active)) == .sending)
  #expect(NetworkActivity(NetworkRate(received: active, sent: active)) == .bidirectional)
}

@Test func backgroundChatterStaysIdle() {
  let chatter = NetworkActivity.threshold - 1
  #expect(NetworkActivity(NetworkRate(received: chatter, sent: chatter)) == .idle)
}

@Test func recentNetworkAverageSmoothsASingleBurst() throws {
  let points = [(0.0, 0.0, 2.0), (40_000, 0, 4.0), (0, 0, 6.0)].map { received, sent, time in
    HistoryPoint(
      SystemSample(
        uptime: time, cpu: nil, cores: [], memory: nil,
        network: NetworkRate(received: received, sent: sent), interfaces: [], processes: []))
  }
  let average = try #require(NetworkRate.recentAverage(of: points))
  #expect(average.received == 20_000 && average.sent == 0)
  #expect(NetworkRate.recentAverage(of: []) == nil)
}

@Test(arguments: [Double.nan, Double.infinity, -Double.infinity, -1])
func invalidNetworkRatesNeverBecomePlausibleActivity(_ invalid: Double) {
  for rate in [NetworkRate(received: invalid, sent: 1), NetworkRate(received: 1, sent: invalid)] {
    #expect(NetworkActivity(rate) == .unavailable)
    #expect(rate.total == nil && rate.activityIntensity == nil)
  }
  let overflow = NetworkRate(received: .greatestFiniteMagnitude, sent: .greatestFiniteMagnitude)
  #expect(NetworkActivity(overflow) == .unavailable && overflow.activityIntensity == nil)
}

@Test func networkActivityIntensityIsBoundedMonotonicAndDirectionIndependent() throws {
  let rates = [0.0, 100, 1_000, 1_000_000, 100_000_000, 1_000_000_000]
  var previous = 0.0
  for value in rates {
    let intensity = try #require(NetworkRate(received: value, sent: 0).activityIntensity)
    #expect(intensity >= previous && intensity <= 1)
    #expect(intensity == NetworkRate(received: 0, sent: value).activityIntensity)
    #expect(intensity == NetworkRate(received: value / 2, sent: value / 2).activityIntensity)
    previous = intensity
  }
  #expect(NetworkRate(received: 0, sent: 0).activityIntensity == 0)
  #expect(previous == 1)
}
