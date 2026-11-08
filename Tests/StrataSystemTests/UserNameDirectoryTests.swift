import Darwin
import Foundation
import Synchronization
import Testing

@testable import StrataSystem

private final class FixedUserNames: UserNameLookup {
  private let names: [UInt32: String]
  private let lookups = Mutex(0)
  init(_ names: [UInt32: String]) { self.names = names }
  var lookupCount: Int { lookups.withLock { $0 } }
  func userName(for userID: UInt32) -> String? {
    lookups.withLock { $0 += 1 }
    return names[userID]
  }
}

@Suite struct UserNameDirectoryTests {
  @Test func namesAreLookedUpOncePerUser() async {
    let lookup = FixedUserNames([0: "root", 88: "_windowserver"])
    let directory = UserNameDirectory(lookup: lookup)
    #expect(await directory.name(for: 0) == "root")
    #expect(await directory.name(for: 0) == "root")
    #expect(await directory.names(for: [0, 88, 4242]) == [0: "root", 88: "_windowserver"])
    #expect(lookup.lookupCount == 3)
  }

  @Test func unknownUsersAreRememberedAsUnknown() async {
    let lookup = FixedUserNames([:])
    let directory = UserNameDirectory(lookup: lookup)
    #expect(await directory.name(for: 4242) == nil)
    #expect(await directory.name(for: 4242) == nil)
    #expect(lookup.lookupCount == 1)
  }

  @Test func cacheStaysWithinItsCapacity() async {
    let lookup = FixedUserNames([1: "daemon", 2: "two", 3: "three"])
    let directory = UserNameDirectory(lookup: lookup, capacity: 2)
    for userID: UInt32 in [1, 2, 3, 1] { _ = await directory.name(for: userID) }
    #expect(lookup.lookupCount == 4)
  }

  @Test func passwordDatabaseResolvesKnownAccountsOnly() {
    let lookup = PasswordDatabaseLookup()
    #expect(lookup.userName(for: 0) == "root")
    #expect(lookup.userName(for: getuid()) == NSUserName())
    #expect(lookup.userName(for: 3_999_999_999) == nil)
  }
}
