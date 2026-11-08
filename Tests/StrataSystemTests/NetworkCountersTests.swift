import CSystem
import Darwin
import Foundation
import StrataInventory
import Testing

@testable import StrataSystem

private let activeLink = UInt32(IFF_UP | IFF_RUNNING)

@Test func networkTrafficCountsOnlyActivePhysicalLinksThatCarriedBytes() {
  var counters = SBSystemCounters()
  sb_add_link_traffic(&counters, "en0", activeLink, 5_000_000_000_000, 700)
  sb_add_link_traffic(&counters, "en1", activeLink, 0, 0)
  sb_add_link_traffic(&counters, "en7", UInt32(IFF_UP), 900, 900)
  sb_add_link_traffic(&counters, "utun0", activeLink, 400, 400)
  sb_add_link_traffic(&counters, "bridge0", activeLink, 300, 300)
  sb_add_link_traffic(&counters, "lo0", activeLink, 200, 200)
  #expect(counters.received == 5_000_000_000_000 && counters.sent == 700)
  #expect(nativeString(counters.interfaces) == "en0")
}

@Test func liveNetworkCountersReachEveryInterfaceAfterLoopback() throws {
  let counters = sb_system_counters()
  #expect(counters.network_valid)
  let hasActiveEthernet = try activePhysicalLinkExists()
  #expect(!nativeString(counters.interfaces).isEmpty == hasActiveEthernet)
}

private func activePhysicalLinkExists() throws -> Bool {
  var list: UnsafeMutablePointer<ifaddrs>?
  guard getifaddrs(&list) == 0 else { throw POSIXError(.EIO) }
  defer { freeifaddrs(list) }
  return sequence(first: list, next: { $0?.pointee.ifa_next }).contains { entry in
    guard let entry else { return false }
    let flags = Int32(entry.pointee.ifa_flags)
    guard String(cString: entry.pointee.ifa_name).hasPrefix("en"),
      flags & IFF_UP != 0, flags & IFF_RUNNING != 0,
      let data = entry.pointee.ifa_data?.assumingMemoryBound(to: if_data.self)
    else { return false }
    return data.pointee.ifi_ibytes != 0 || data.pointee.ifi_obytes != 0
  }
}
