import Darwin
import Foundation
import StrataCore
import StrataHelperInterface
import Synchronization
import StrataInventory
import Testing

@testable import StrataBarHelper

@Test func snapshotIsReusedWithinTheWindowAndRescannedAfterIt() async {
  let clock = ManualClock()
  let scans = Counter()
  let cache = ProcessSnapshotCache(uptime: clock.uptime) {
    Data([UInt8(truncatingIfNeeded: scans.increment())])
  }
  let first = await cache.reply()
  clock.advance(by: 0.89)
  #expect(await cache.reply() == first)
  #expect(scans.count == 1)
  clock.advance(by: 0.02)
  #expect(await cache.reply() != first)
  #expect(scans.count == 2)
}

@Test func concurrentSnapshotRequestsShareOneScan() async {
  let clock = ManualClock()
  let scans = Counter()
  let running = Mutex((current: 0, maximum: 0))
  let cache = ProcessSnapshotCache(uptime: clock.uptime) {
    running.withLock {
      $0.current += 1
      $0.maximum = max($0.maximum, $0.current)
    }
    scans.increment()
    Thread.sleep(forTimeInterval: 0.05)
    running.withLock { $0.current -= 1 }
    return Data([1])
  }
  await withTaskGroup(of: Data.self) { group in
    for _ in 0..<8 { group.addTask { await cache.reply() } }
    for await reply in group { #expect(reply == Data([1])) }
  }
  #expect(scans.count == 1)
  #expect(running.withLock { $0.maximum } == 1)
}

@Test func rateLimiterRefusesBurstsAndRefillsOverTime() {
  let clock = ManualClock()
  let limiter = RequestRateLimiter(uptime: clock.uptime)
  let admitted = (0..<12).count { _ in limiter.admits(.query) }
  #expect(admitted == 10)
  #expect(limiter.admits(.resources), "Each request kind has its own budget")
  clock.advance(by: 0.5)
  #expect(limiter.admits(.query) && limiter.admits(.query))
  #expect(!limiter.admits(.query))
}

@Test func helperBecomesIdleOnlyAfterThirtyQuietSeconds() {
  let clock = ManualClock()
  let activity = HelperActivity(uptime: clock.uptime)
  clock.advance(by: 29.9)
  #expect(!activity.isIdle)
  clock.advance(by: 0.1)
  #expect(activity.isIdle, "No connection ever arrived")
  activity.connectionAccepted()
  #expect(!activity.isIdle)
  activity.requestStarted()
  clock.advance(by: 120)
  #expect(!activity.isIdle, "A request in flight keeps the helper running")
  activity.requestFinished()
  clock.advance(by: 29)
  #expect(!activity.isIdle)
  clock.advance(by: 1)
  #expect(activity.isIdle)
}

@Test func idleTimerExitsOnlyOnceIdle() async throws {
  let clock = ManualClock()
  let activity = HelperActivity(idleLimit: 1, uptime: clock.uptime)
  let exits = Counter()
  let timer = IdleExitTimer(
    activity: activity, checkInterval: .milliseconds(10),
    queue: DispatchQueue(label: "idle-exit-test")
  ) { exits.increment() }
  timer.start()
  try await Task.sleep(for: .milliseconds(60))
  #expect(exits.count == 0)
  clock.advance(by: 1)
  let deadline = ContinuousClock.now + .seconds(2)
  while exits.count == 0, ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(5))
  }
  #expect(exits.count > 0)
}

@Test func admissionRefusesRootCallersAndEndedProcesses() {
  let admission = CallerAdmission { $0 == 4242 }
  #expect(admission.admits(effectiveUserID: 501, processIdentifier: 4242))
  #expect(!admission.admits(effectiveUserID: 0, processIdentifier: 4242))
  #expect(!admission.admits(effectiveUserID: 501, processIdentifier: 4343))
  #expect(!admission.admits(effectiveUserID: 501, processIdentifier: 0))
  #expect(!admission.admits(effectiveUserID: 501, processIdentifier: -1))
  #expect(CallerAdmission.live.admits(effectiveUserID: getuid(), processIdentifier: getpid()))
}

@Test func handshakeReportsVersionsAndEffectiveUser() async throws {
  let service = HelperConnectionService(core: helperCore(effectiveUserID: 0), caller: testCaller)
  let recorder = ReplyRecorder()
  service.handshake(reply: recorder.reply)
  try await recorder.waitFor(1)
  let info = try HelperCoding.decode(HelperReply<HelperInfo>.self, from: recorder.all[0])
    .payload()
  #expect(info.matchesThisBuild && info.effectiveUserID == 0)
}

@Test func everyRequestRepliesExactlyOnceIncludingRefusals() async throws {
  let clock = ManualClock()
  let service = HelperConnectionService(core: helperCore(clock: clock), caller: testCaller)
  let recorder = ReplyRecorder()
  for _ in 0..<6 { service.handshake(reply: recorder.reply) }
  for _ in 0..<6 { service.processSnapshot(reply: recorder.reply) }
  for _ in 0..<12 { service.resources(Data("garbage".utf8), reply: recorder.reply) }
  try await recorder.waitFor(24)
  try await Task.sleep(for: .milliseconds(50))
  #expect(recorder.count == 24)
  // One inspection runs at a time per connection, so the rest of a burst is refused as busy.
  let failures = recorder.all.compactMap(decodedFailure)
  #expect(failures.count { $0 == .malformedReply } >= 1)
  #expect(failures.count { $0 == .rateLimited } + failures.count { $0 == .malformedReply } == 14)
}

@Test func aConnectionRunsOneInspectionAtATime() async throws {
  let service = HelperConnectionService(core: helperCore(), caller: testCaller)
  let recorder = ReplyRecorder()
  let own = try ownIdentity()
  let request = try HelperCoding.encode(ResourceRequest(identities: [own], socketsOnly: false))
  service.resources(request, reply: recorder.reply)
  service.resources(request, reply: recorder.reply)
  try await recorder.waitFor(2)
  #expect(recorder.all.compactMap(decodedFailure) == [.rateLimited])
  service.resources(request, reply: recorder.reply)
  try await recorder.waitFor(3)
  #expect(recorder.all.compactMap(decodedFailure).count == 1, "The slot frees once a reply is sent")
}

@Test func resourcesAreRefusedForAnIdentityWhoseStartTimeDiffers() async throws {
  let listener = try LoopbackListener()
  let service = HelperConnectionService(core: helperCore(), caller: testCaller)
  let stale = ProcessIdentityWire(pid: getpid(), startSeconds: 1, startMicroseconds: 0)
  let report = try await resourceReport(service, for: [stale], socketsOnly: true)
  #expect(report.resources.isEmpty)
  #expect(report.summary.changedDuringScan)

  let current = try ownIdentity()
  let live = try await resourceReport(service, for: [current], socketsOnly: true)
  #expect(live.resources.contains { $0.isListener && $0.localPort == listener.port })
  #expect(live.resources.allSatisfy { $0.owner.pid == getpid() })
  #expect(live.resources.allSatisfy { !$0.processName.isEmpty })
}

@Test func oversizedOrForeignResourceRequestsAreRefused() async throws {
  let service = HelperConnectionService(core: helperCore(), caller: testCaller)
  let recorder = ReplyRecorder()
  service.resources(
    Data(count: HelperContract.maximumRequestBytes + 1), reply: recorder.reply)
  try await recorder.waitFor(1)
  let foreign = try HelperCoding.encode(
    ResourceRequest(identities: [], socketsOnly: false, schemaVersion: 99))
  service.resources(foreign, reply: recorder.reply)
  try await recorder.waitFor(2)
  #expect(Set(recorder.all.compactMap(decodedFailure)) == [.payloadTooLarge, .unsupportedSchema])
}

@Test func anotherUsersOpenFilesStayHiddenFromAStandardUser() async throws {
  let own = try ownIdentity()
  let rootProcess = ProcessIdentityWire(pid: 1, startSeconds: 1, startMicroseconds: 0)
  let core = HelperCore(
    snapshots: ProcessSnapshotCache(uptime: ManualClock().uptime),
    resources: HelperResourceInspector(record: { pid in
      pid == 1
        ? (ProcessIdentity(pid: 1, startSeconds: 1, startMicroseconds: 0), 0)
        : NativeProcessIdentity.record(of: pid)
    }),
    activity: HelperActivity(uptime: ManualClock().uptime), uptime: ManualClock().uptime,
    effectiveUserID: { 0 })
  let standard = HelperConnectionService(core: core, caller: testCaller)
  let report = try await resourceReport(standard, for: [own, rootProcess], socketsOnly: false)
  #expect(report.summary.restricted)
  #expect(report.resources.allSatisfy { $0.owner.pid == getpid() })
  #expect(!report.resources.isEmpty, "The caller's own process stays inspectable")

  let ownOnly = try await resourceReport(standard, for: [own], socketsOnly: false)
  #expect(!ownOnly.summary.restricted)
}

@Test func onlyAdministratorsMayInspectOtherUsersProcesses() {
  let standard = CallerScope(userID: 501) { _ in false }.permission()
  #expect(standard.permits(owner: 501))
  #expect(!standard.permits(owner: 0))
  #expect(!standard.permits(owner: nil), "An ended or unknown owner is refused")
  #expect(CallerScope(userID: 502) { _ in true }.permission().permits(owner: 0))
  #expect(CallerScope.live(userID: getuid()).userID == getuid())
}

@Test func adminMembershipIsDecidedAgainForEveryRequest() {
  let membership = Membership()
  let scope = CallerScope(userID: 502) { _ in membership.isAdministrator }
  membership.isAdministrator = true
  #expect(scope.permission().permits(owner: 0))
  membership.isAdministrator = false
  #expect(!scope.permission().permits(owner: 0), "Leaving the admin group takes effect at once")
}

@Test func aProcessThatChangesOwnerDuringInspectionContributesNothing() async throws {
  let own = try ownIdentity()
  let reads = Counter()
  let identity = ProcessIdentity(
    pid: own.pid, startSeconds: own.startSeconds, startMicroseconds: own.startMicroseconds)
  // The first check sees the caller's process; by the next it runs a setuid program as root.
  let core = HelperCore(
    snapshots: ProcessSnapshotCache(uptime: ManualClock().uptime),
    resources: HelperResourceInspector(record: { _ in
      reads.increment()
      return (identity, reads.count <= 2 ? getuid() : 0)
    }),
    activity: HelperActivity(uptime: ManualClock().uptime), uptime: ManualClock().uptime,
    effectiveUserID: { 0 })
  let service = HelperConnectionService(core: core, caller: testCaller)
  let report = try await resourceReport(service, for: [own], socketsOnly: false)
  #expect(report.resources.isEmpty)
  #expect(report.summary.changedDuringScan)
}

@Test func longPathsAreShortenedAndAnOversizedSnapshotDropsPathsInsteadOfFailing() throws {
  let long = String(repeating: "\u{1}", count: 5000)
  #expect(SnapshotReply.prefix(long, bytes: 1024).utf8.count <= 1024)
  #expect(SnapshotReply.prefix("é" + long, bytes: 3).unicodeScalars.count <= 2)
  let processes = (1...4000).map { pid in
    var sample = fixtureSample(pid: Int32(pid), cpu: 1)
    sample.path = "/" + String(repeating: "\u{1}", count: 1000)
    return sample
  }
  let reply = SnapshotReply.encode(fixtureInventory(processes))
  let inventory = try HelperCoding.decode(HelperReply<ProcessInventory>.self, from: reply).payload()
  #expect(inventory.processes.count == 4000)
  #expect(inventory.summary.truncated && inventory.processes.allSatisfy(\.path.isEmpty))
}

private func ownIdentity() throws -> ProcessIdentityWire {
  var info = kinfo_proc()
  var size = MemoryLayout<kinfo_proc>.size
  var query: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
  try #require(sysctl(&query, 4, &info, &size, nil, 0) == 0)
  return ProcessIdentityWire(
    pid: getpid(), startSeconds: UInt64(info.kp_proc.p_starttime.tv_sec),
    startMicroseconds: UInt64(info.kp_proc.p_starttime.tv_usec))
}

private func resourceReport(
  _ service: HelperConnectionService, for identities: [ProcessIdentityWire], socketsOnly: Bool
) async throws -> ResourceReport {
  let recorder = ReplyRecorder()
  let request = try HelperCoding.encode(
    ResourceRequest(identities: identities, socketsOnly: socketsOnly))
  service.resources(request, reply: recorder.reply)
  try await recorder.waitFor(1)
  return try HelperCoding.decode(HelperReply<ResourceReport>.self, from: recorder.all[0]).payload()
}

final class LoopbackListener {
  let descriptor: Int32
  let port: UInt16
  init() throws {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    try #require(descriptor >= 0)
    self.descriptor = descriptor
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    let bound = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard bound == 0, listen(descriptor, 1) == 0 else {
      close(descriptor)
      throw POSIXError(.EADDRNOTAVAIL)
    }
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    _ = withUnsafeMutablePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
    }
    port = UInt16(bigEndian: address.sin_port)
  }
  deinit { close(descriptor) }
}

private final class Membership: @unchecked Sendable {
  private let lock = NSLock()
  private var member = false
  var isAdministrator: Bool {
    get { lock.withLock { member } }
    set { lock.withLock { member = newValue } }
  }
}
