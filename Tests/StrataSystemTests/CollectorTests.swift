import CSystem
import Darwin
import Foundation
import IOKit
import StrataCore
import StrataInventory
import Testing

@testable import StrataSystem

@Suite(.serialized)
struct SystemIntegrationTests {

  @Test(arguments: [false, true]) @MainActor
  func normalApplicationQuitUsesCocoaAndRespectsAVeto(_ veto: Bool) async throws {
    let fixture = try await QuitFixtureApplication.launch(veto: veto)
    defer { fixture.cleanUp() }
    let service = ApplicationQuitService()
    let action = try service.prepare(fixture.process)
    try service.perform(action)
    try await fixture.waitForQuitRequest()
    let clock = ContinuousClock()
    let deadline = ContinuousClock.now + .seconds(3)
    if veto {
      try await Task.sleep(for: .milliseconds(100))
      #expect(!fixture.application.isTerminated)
      #expect(ProcessIdentityVerifier().isCurrent(fixture.process.id))
    } else {
      while !fixture.application.isTerminated, clock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
      }
      #expect(fixture.application.isTerminated)
    }
  }

  @Test func repeatedBatteryHealthReadsBalanceRegistrySendRights() {
    let source = IOServiceGetMatchingService(
      kIOMainPortDefault, IOServiceMatching("IOPMPowerSource"))
    guard source != 0 else { return }  // Desktop hardware may have no such service.
    defer { IOObjectRelease(source) }
    let reader = BatteryHealthReader()
    _ = reader.cycleCount()
    var before: mach_port_urefs_t = 0
    var after: mach_port_urefs_t = 0
    #expect(
      mach_port_get_refs(mach_task_self_, source, mach_port_right_t(MACH_PORT_RIGHT_SEND), &before)
        == KERN_SUCCESS)
    for _ in 0..<100 { _ = reader.cycleCount() }
    #expect(
      mach_port_get_refs(mach_task_self_, source, mach_port_right_t(MACH_PORT_RIGHT_SEND), &after)
        == KERN_SUCCESS)
    #expect(before == after)
  }

  @Test func emptyFirstArgumentCannotExposeChildEnvironment() async throws {
    let arguments = ["", "30"].map { value in value.withCString { strdup($0) } }
    let environment = [strdup("STRATA_ENV_ONLY=must-not-appear-as-an-argument")]
    defer { for pointer in arguments + environment { free(pointer) } }
    var argumentPointers = arguments + [nil]
    var environmentPointers = environment + [nil]
    var child: pid_t = 0
    let result = posix_spawn(
      &child, "/bin/sleep", nil, nil, &argumentPointers, &environmentPointers)
    try #require(result == 0)
    // Swift's test worker may block SIGTERM on the spawning thread. This
    // fixture owns the unreaped child, so SIGKILL guarantees bounded teardown.
    defer {
      kill(child, SIGKILL)
      waitpid(child, nil, 0)
    }
    let ownChild = try #require(
      await SystemCollector().sample(includeProcesses: true).processes.first { $0.id.pid == child })
    let details = try await ProcessDetailsCollector().inspect(ownChild)
    #expect(details.arguments == ["", "30"])
  }

  @Test func processDetailsUseLiveSigningArgumentsAndExecutableMappings() async throws {
    let own = try #require(
      await SystemCollector().sample(includeProcesses: true).processes.first {
        $0.id.pid == getpid()
      })
    let details = try await ProcessDetailsCollector().inspect(own)
    #expect(details.identity == own.id)
    #expect([.apple, .signed, .adHoc].contains(details.signing.kind))
    #expect(details.arguments?.isEmpty == false)
    #expect(details.executableMappings.contains(own.path))
  }

  @Test func changedExecutablePathCannotReceiveStaleDetails() async throws {
    let own = try #require(
      await SystemCollector().sample(includeProcesses: true).processes.first {
        $0.id.pid == getpid()
      })
    let changed = ProcessSample(
      id: own.id, parentPID: own.parentPID, userID: own.userID,
      name: own.name, path: "/this-is-not-the-current-executable", cpuTimeNanoseconds: nil,
      residentBytes: nil, footprintBytes: nil, threads: nil)
    do {
      _ = try await ProcessDetailsCollector().inspect(changed)
      Issue.record("Changed executable must not receive details")
    } catch { #expect(error is InspectionError) }
  }

  private func idleChild() throws -> Process {
    let child = Process()
    child.executableURL = URL(fileURLWithPath: "/bin/sleep")
    child.arguments = ["30"]
    child.standardInput = FileHandle.nullDevice
    child.standardOutput = FileHandle.nullDevice
    child.standardError = FileHandle.nullDevice
    try child.run()
    return child
  }
  private func stopChild(_ child: Process) {
    if child.isRunning { child.terminate() }
    child.waitUntilExit()
  }

  @Test(arguments: [ProcessSignal.terminate, .forceQuit])
  func processSignalsTargetOnlyThePreparedChild(_ signal: ProcessSignal) async throws {
    let child = try idleChild()
    defer { stopChild(child) }
    let sample = await SystemCollector().sample(includeProcesses: true)
    let target = try #require(sample.processes.first { $0.id.pid == child.processIdentifier })
    let control = ProcessControl()
    let action = try await control.prepare(target, signal: signal)
    try await control.perform(action)
    child.waitUntilExit()
    #expect(child.terminationReason == .uncaughtSignal)
    #expect(child.terminationStatus == (signal == .terminate ? SIGTERM : SIGKILL))
  }

  @Test func pausingAndResumingAChildChangesOnlyItsRunState() async throws {
    let child = try idleChild()
    defer { stopChild(child) }
    func current() async throws -> ProcessSample {
      try #require(
        await ProcessInventoryCollector().inventory().processes.first {
          $0.id.pid == child.processIdentifier
        })
    }
    let control = ProcessControl()
    try await control.perform(try await control.prepare(try await current(), signal: .pause))
    #expect(try await current().runState == .stopped)
    try await control.resumePaused(try await current().id)
    #expect(try await current().runState == .running)
    #expect(child.isRunning)
  }

  // The shell is spawned and reaped here rather than through Process, which loses track of a
  // child that was stopped and continued by other means.
  @Test func terminatingAPausedProcessThatHandlesTheSignalStillEndsIt() async throws {
    let script = "trap 'exit 0' TERM; while :; do sleep 0.2; done"
    let commandArguments = ["/bin/sh", "-c", script]
    var arguments = commandArguments.map { argument in
      argument.withCString { strdup($0) }
    }
    defer { arguments.forEach { free($0) } }
    arguments.append(nil)
    // The test runner's blocked signals and handlers must not carry over to the child.
    var attributes: posix_spawnattr_t?
    posix_spawnattr_init(&attributes)
    defer { posix_spawnattr_destroy(&attributes) }
    var noSignals = sigset_t()
    var allSignals = sigset_t()
    sigemptyset(&noSignals)
    sigfillset(&allSignals)
    posix_spawnattr_setsigmask(&attributes, &noSignals)
    posix_spawnattr_setsigdefault(&attributes, &allSignals)
    posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF))
    var pid: pid_t = 0
    let spawned = posix_spawn(&pid, "/bin/sh", nil, &attributes, &arguments, environ)
    #expect(spawned == 0)
    guard spawned == 0 else { return }
    var exited = false
    defer {
      if !exited {
        kill(pid, SIGKILL)
        var status: Int32 = 0
        waitpid(pid, &status, 0)
      }
    }
    func current() async throws -> ProcessSample {
      try #require(
        await ProcessInventoryCollector().inventory().processes.first { $0.id.pid == pid })
    }
    let control = ProcessControl()
    try await control.perform(try await control.prepare(try await current(), signal: .pause))
    try await control.perform(try await control.prepare(try await current(), signal: .terminate))
    let deadline = ContinuousClock.now + .seconds(10)
    var status: Int32 = 0
    while !exited && ContinuousClock.now < deadline {
      exited = waitpid(pid, &status, WNOHANG) == pid
      if !exited { try await Task.sleep(for: .milliseconds(50)) }
    }
    #expect(exited, "A paused process must run again to handle Terminate")
  }

  @Test func alteredAuditGenerationCannotSignalAnExistingChild() async throws {
    let child = try idleChild()
    defer { stopChild(child) }
    let sample = await SystemCollector().sample(includeProcesses: true)
    let target = try #require(sample.processes.first { $0.id.pid == child.processIdentifier })
    var token = SBActionToken()
    let result = sb_prepare_signal(
      target.id.pid, target.id.startSeconds, target.id.startMicroseconds, &token)
    #expect(result == 0)
    token.values.7 &+= 1
    #expect(sb_send_signal(&token, SIGTERM) == ESRCH)
    #expect(child.isRunning)
  }

  @Test func canceledProcessConfirmationCannotBeReplayed() async throws {
    let child = try idleChild()
    defer { stopChild(child) }
    let target = try #require(
      await SystemCollector().sample(includeProcesses: true).processes.first {
        $0.id.pid == child.processIdentifier
      })
    let control = ProcessControl()
    let action = try await control.prepare(target, signal: .forceQuit)
    await control.cancel(action.id)
    do {
      try await control.perform(action)
      Issue.record("A canceled confirmation must not send a signal")
    } catch { #expect(error as? ProcessActionError == .expired) }
    #expect(child.isRunning)
  }

  @Test func processCollectorUsesRealStableIdentities() async throws {
    let collector = SystemCollector()
    let sample = await collector.sample(includeProcesses: true)
    let own = try #require(sample.processes.first { $0.id.pid == getpid() })
    #expect(own.id.startSeconds > 0)
    #expect(own.residentBytes.map { $0 > 0 } == true)
    #expect(own.cpuPercent == nil)
    #expect(sb_process_identity(own.id.pid, own.id.startSeconds, own.id.startMicroseconds))
    #expect(!sb_process_identity(own.id.pid, own.id.startSeconds + 1, own.id.startMicroseconds))
    #expect(sample.memory?.total == ProcessInfo.processInfo.physicalMemory)
    #expect(sample.cores.count == ProcessInfo.processInfo.activeProcessorCount)
    #expect(sample.cores.allSatisfy { $0 == nil })
    #expect(sample.cpu == nil)
  }

  @Test func everyProcessIsListedAndOnlyReadableOnesAreMeasured() async throws {
    let earlier = try ownResourceCounters()
    let inventory = await ProcessInventoryCollector().inventory()
    let later = try ownResourceCounters()
    let launchd = try #require(inventory.processes.first { $0.id.pid == 1 })
    #expect(launchd.userID == 0 && launchd.name == "launchd")
    #expect(launchd.cpuTimeNanoseconds == nil && launchd.footprintBytes == nil)
    #expect(launchd.activity == nil, "Another user's counters are unavailable, not zero")
    let kernel = try #require(inventory.processes.first { $0.id.pid == 0 })
    #expect(kernel.runState == .running)
    #expect(inventory.summary.restricted)

    let own = try #require(inventory.processes.first { $0.id.pid == getpid() })
    let activity = try #require(own.activity)
    #expect((earlier.ri_instructions...later.ri_instructions).contains(activity.instructions))
    #expect((earlier.ri_cycles...later.ri_cycles).contains(activity.cycles))
    #expect(activity.peakFootprintBytes >= (own.footprintBytes ?? 0))
    let cpu = try #require(own.cpuTimeNanoseconds)
    #expect(activity.performanceCoreNanoseconds <= cpu + 50_000_000)
    #expect(own.runState == .running && !own.isTranslated)
  }

  @Test func anotherUsersProcessIsInspectedWithoutItsPrivateDetails() async throws {
    let launchd = try #require(
      await ProcessInventoryCollector().inventory().processes.first { $0.id.pid == 1 })
    let details = try await ProcessDetailsCollector().inspect(launchd)
    #expect(details.arguments == nil && details.argumentsIssue != nil)
    #expect(details.executableMappings.isEmpty)
  }

  @Test func kernelRunStatesMapToStoppedAndExitedProcesses() {
    #expect(NativeProcessInventory.runState(Int32(SSTOP)) == .stopped)
    #expect(NativeProcessInventory.runState(Int32(SZOMB)) == .zombie)
    #expect(NativeProcessInventory.runState(Int32(SSLEEP)) == .running)
    #expect(NativeProcessInventory.runState(Int32(SIDL)) == .starting)
    #expect(NativeProcessInventory.runState(99) == nil)
  }

  @Test func processActivityBecomesPowerAndWakeupRates() async throws {
    let collector = SystemCollector()
    let first = await collector.sample(includeProcesses: true)
    let initialEnergy = try #require(
      first.processes.first { $0.id.pid == getpid() }?.activity?.energyNanojoules)
    spinForCPUTime(0.2)
    let sample = await collector.sample(includeProcesses: true)
    let own = try #require(sample.processes.first { $0.id.pid == getpid() })
    #expect((own.cpuPercent ?? 0) > 1)
    let finalEnergy = try #require(own.activity?.energyNanojoules)
    let watts = try #require(own.watts)
    #expect(watts.isFinite && (0..<200).contains(watts))
    #expect((watts > 0) == (finalEnergy > initialEnergy))
    #expect(own.wakeupsPerSecond.map { $0 >= 0 } == true)
    #expect(own.performanceCoreShare.map { (0...1).contains($0) } == true)
  }

  @Test func resourceCollectorFindsAnActualLoopbackListener() async throws {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    #expect(fd >= 0)
    defer { close(fd) }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    let bound = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    #expect(bound == 0)
    #expect(listen(fd, 1) == 0)
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    _ = withUnsafeMutablePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
    }
    let port = UInt16(bigEndian: address.sin_port)
    let sample = await SystemCollector().sample(includeProcesses: true)
    let own = try #require(sample.processes.first { $0.id.pid == getpid() })
    let report = try await ResourceCollector().inspect([own], socketsOnly: true)
    #expect(
      report.resources.contains {
        $0.isListener && $0.localPort == port && $0.localAddress == "127.0.0.1"
      })
  }

  @Test func obsoleteIdentityCannotBeInspected() async throws {
    let fake = ProcessSample(
      id: ProcessIdentity(pid: getpid(), startSeconds: 1, startMicroseconds: 0),
      parentPID: 0, userID: getuid(), name: "old", path: "", cpuTimeNanoseconds: nil,
      residentBytes: nil, footprintBytes: nil, threads: nil)
    let report = try await ResourceCollector().inspect([fake])
    #expect(report.resources.isEmpty)
    #expect(report.summary.changedDuringScan)
  }

  @Test func nativeScansReportInvalidTargetsAndHonorCancellation() throws {
    var count = 0
    var status = SBScanStatus()
    let invalid = sb_resources(-1, &count, false, &status, nil)
    #expect(invalid == nil && status.error == EINVAL)
    let cancellation = try NativeScanCancellation()
    cancellation.cancel()
    let canceled = sb_resources(getpid(), &count, false, &status, cancellation.handle)
    #expect(canceled == nil && status.error == ECANCELED)
  }

  @Test func udpBoundPortAppearsWithoutBeingCalledAListener() async throws {
    let descriptor = socket(AF_INET6, SOCK_DGRAM, 0)
    try #require(descriptor >= 0)
    defer { close(descriptor) }
    var address = sockaddr_in6()
    address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
    address.sin6_family = sa_family_t(AF_INET6)
    address.sin6_addr = in6addr_loopback
    let bound = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in6>.size))
      }
    }
    #expect(bound == 0)
    var size = socklen_t(MemoryLayout<sockaddr_in6>.size)
    _ = withUnsafeMutablePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &size) }
    }
    let own = try #require(
      await SystemCollector().sample(includeProcesses: true).processes.first {
        $0.id.pid == getpid()
      })
    let report = try await ResourceCollector().inspect([own], socketsOnly: true)
    let udp = try #require(report.resources.first { $0.descriptor == descriptor })
    #expect(udp.localPort == UInt16(bigEndian: address.sin6_port))
    #expect(udp.localAddress == "::1" && udp.ownsLocalPort && !udp.isListener)
    #expect(udp.state == "Bound datagram")
    #expect(report.resources.allSatisfy { [.tcp, .udp, .unixSocket].contains($0.kind) })
  }

  @Test func repeatedAggregateSamplingBalancesMachSendRights() {
    let host = mach_host_self()
    defer { mach_port_deallocate(mach_task_self_, host) }
    var before: mach_port_urefs_t = 0
    var after: mach_port_urefs_t = 0
    #expect(
      mach_port_get_refs(mach_task_self_, host, mach_port_right_t(MACH_PORT_RIGHT_SEND), &before)
        == KERN_SUCCESS)
    for _ in 0..<200 { _ = sb_system_counters() }
    #expect(
      mach_port_get_refs(mach_task_self_, host, mach_port_right_t(MACH_PORT_RIGHT_SEND), &after)
        == KERN_SUCCESS)
    #expect(before == after)
  }

  @Test func fileInspectionPreservesLiteralUnicodePaths() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(
      "Strata-\(UUID())-λ '$() file"
    ).resolvingSymlinksInPath()
    let descriptor = open(file.path, O_CREAT | O_EXCL | O_RDWR, mode_t(0o600))
    try #require(descriptor >= 0)
    defer {
      close(descriptor)
      try? FileManager.default.removeItem(at: file)
    }
    let sample = await SystemCollector().sample(includeProcesses: true)
    let own = try #require(sample.processes.first { $0.id.pid == getpid() })
    let report = try await ResourceCollector().inspect([own])
    let resource = try #require(report.resources.first { $0.descriptor == descriptor })
    #expect(resource.kind == .file)
    #expect(URL(fileURLWithPath: resource.path).lastPathComponent == file.lastPathComponent)
    #expect(
      URL(fileURLWithPath: resource.path).resolvingSymlinksInPath()
        == file.resolvingSymlinksInPath())
    let fileSystem = try #require(FileSystemIdentityReader().identity(at: file))
    #expect(resource.fileSystem == fileSystem)
    let scope = VolumeResourceScope(
      identity: fileSystem, name: "Fixture", mountPath: "/unrelated-path")
    #expect(scope.contains(resource))
  }

  @Test func filesystemIdentityFollowsSymlinksAndCannotInventAnUnavailableMount() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let alias = directory.appendingPathComponent("alias")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: directory)
    let descriptor = open(alias.path, O_RDONLY)
    try #require(descriptor >= 0)
    defer { close(descriptor) }
    let deviceDescriptor = open("/dev/null", O_RDONLY)
    try #require(deviceDescriptor >= 0)
    defer { close(deviceDescriptor) }
    let own = try #require(
      await SystemCollector().sample(includeProcesses: true).processes.first {
        $0.id.pid == getpid()
      })
    let report = try await ResourceCollector().inspect([own])
    let resource = try #require(report.resources.first { $0.descriptor == descriptor })
    let reader = FileSystemIdentityReader()
    let expected = try #require(reader.identity(at: directory))
    #expect(resource.fileSystem == expected)
    let device = try #require(report.resources.first { $0.descriptor == deviceDescriptor })
    let deviceFileSystem = try #require(reader.identity(at: URL(fileURLWithPath: "/dev/null")))
    #expect(device.kind == .device && device.fileSystem == deviceFileSystem)
    #expect(deviceFileSystem != expected)
    let scope = VolumeResourceScope(identity: expected, name: "Fixture", mountPath: "/")
    #expect(scope.contains(resource) && !scope.contains(device))
    #expect(reader.identity(at: alias) == expected)
    #expect(reader.identity(at: directory.appendingPathComponent("missing")) == nil)
    #expect(reader.identity(at: URL(string: "https://example.invalid")!) == nil)
  }

  @Test func cancellationStopsResourceInspection() async throws {
    let sample = await SystemCollector().sample(includeProcesses: true)
    let own = try #require(sample.processes.first { $0.id.pid == getpid() })
    let task = Task { try await ResourceCollector().inspect(Array(repeating: own, count: 1000)) }
    task.cancel()
    do {
      _ = try await task.value
      Issue.record("A canceled inspection must not return a report")
    } catch { #expect(error is CancellationError) }
  }

  @Test func processCPUTimeAgreesWithIndependentResourceAccounting() async throws {
    let collector = SystemCollector()
    let first = await collector.sample(includeProcesses: true)
    let start = try #require(first.processes.first { $0.id.pid == getpid() }?.cpuTimeNanoseconds)
    var before = rusage()
    var after = rusage()
    #expect(getrusage(RUSAGE_SELF, &before) == 0)
    // Deliberately use CPU until it is measurable, however busy the machine is.
    spinForCPUTime(0.3)
    let last = await collector.sample(includeProcesses: true)
    #expect(getrusage(RUSAGE_SELF, &after) == 0)
    let end = try #require(last.processes.first { $0.id.pid == getpid() }?.cpuTimeNanoseconds)
    let reference = cpuSeconds(after) - cpuSeconds(before)
    let collected = Double(end - start) / 1_000_000_000
    #expect(reference > 0.1)
    #expect(
      abs(collected - reference) < 0.1,
      "Collected \(collected)s versus getrusage \(reference)s; include the machine timebase")
  }

}

private func ownResourceCounters() throws -> rusage_info_v6 {
  var counters = rusage_info_v6()
  let result = withUnsafeMutablePointer(to: &counters) { pointer in
    pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
      proc_pid_rusage(getpid(), RUSAGE_INFO_V6, $0)
    }
  }
  try #require(result == 0)
  return counters
}

private func cpuSeconds(_ value: rusage) -> Double {
  Double(value.ru_utime.tv_sec + value.ru_stime.tv_sec) + Double(
    value.ru_utime.tv_usec + value.ru_stime.tv_usec) / 1_000_000
}

// A wall-clock spin can get almost no CPU on a saturated machine; this waits for CPU time itself.
private func spinForCPUTime(_ seconds: Double, wallLimit: Duration = .seconds(20)) {
  var usage = rusage()
  _ = getrusage(RUSAGE_SELF, &usage)
  let target = cpuSeconds(usage) + seconds
  let limit = ContinuousClock.now + wallLimit
  var spin = 0.0
  repeat {
    for _ in 0..<10_000 { spin += sin(spin) }
    _ = getrusage(RUSAGE_SELF, &usage)
  } while cpuSeconds(usage) < target && ContinuousClock.now < limit
  precondition(spin.isFinite)
}
