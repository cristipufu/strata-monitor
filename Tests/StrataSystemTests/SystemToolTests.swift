import Darwin
import Foundation
import Synchronization
import Testing

@testable import StrataSystem

@Suite struct SystemToolCommandTests {
  @Test func everyInvocationRunsAnAbsoluteToolWithFixedArguments() {
    #expect(SystemToolCommand.processTable.executablePath == "/bin/ps")
    #expect(
      SystemToolCommand.processTable.arguments == [
        "-ax", "-o", "pid=,ppid=,uid=,time=,rss=,state=,comm=",
      ])
    #expect(SystemToolCommand.networkUsage.executablePath == "/usr/bin/nettop")
    #expect(
      SystemToolCommand.networkUsage.arguments == [
        "-P", "-L", "1", "-x", "-n", "-J", "bytes_in,bytes_out",
      ])
    let report = URL(fileURLWithPath: "/private/var/folders/x/report.txt")
    let sample = SystemToolCommand.sample(pid: 42, seconds: 3, reportFile: report)
    #expect(sample.executablePath == "/usr/bin/sample")
    #expect(sample.arguments == ["42", "3", "-file", "/private/var/folders/x/report.txt"])
  }

  @Test(arguments: [
    SystemToolInvocation.sample(pid: 0, seconds: 1), .sample(pid: -7, seconds: 1),
    .sample(pid: 1, seconds: 0), .sample(pid: 1, seconds: 31),
  ])
  func invalidSampleRequestsNeverLaunch(_ invocation: SystemToolInvocation) async {
    await #expect(throws: SystemToolError.invalidRequest) {
      try await SystemTool().run(invocation)
    }
  }

  @Test func processTableRunsTheRealPsEndToEnd() async throws {
    let table = try await ProcessTableReader(tool: SystemTool()).read()
    let own = try #require(table.records.first { $0.pid == getpid() })
    #expect(own.parentPID == getppid())
    #expect(own.userID == getuid())
    #expect(own.residentBytes > 0)
    #expect(table.records.contains { $0.pid == 1 && $0.userID == 0 })
  }
}

@Suite struct ChildProcessRunnerTests {
  private func runner(
    outputBytes: Int = 4 << 20, timeout: Duration = .seconds(10),
    terminationSignal: Int32 = SIGTERM, didLaunch: @escaping @Sendable (Int32) -> Void = { _ in }
  ) -> ChildProcessRunner {
    ChildProcessRunner(
      limits: SystemToolLimits(
        outputBytes: outputBytes, diagnosticBytes: 4096, timeout: timeout,
        terminationGrace: .milliseconds(300)),
      timeout: timeout, terminationSignal: terminationSignal, didLaunch: didLaunch)
  }
  private func command(_ path: String, _ arguments: String...) -> SystemToolCommand {
    SystemToolCommand(executablePath: path, arguments: arguments)
  }

  @Test func outputLargerThanAPipeBufferIsReadCompletely() async throws {
    let result = try await runner().run(command("/usr/bin/head", "-c", "2000000", "/dev/zero"))
    #expect(result.output.count == 2_000_000)
  }

  @Test func childRunsWithMinimalEnvironmentAndEmptyInput() async throws {
    let environment = try await runner().run(command("/usr/bin/env"))
    #expect(String(decoding: environment.output, as: UTF8.self) == "LC_ALL=C\n")
    let input = try await runner().run(command("/bin/cat"))
    #expect(input.output.isEmpty)
  }

  @Test func outputBeyondTheLimitStopsTheChild() async {
    await #expect(throws: SystemToolError.outputLimitExceeded(limit: 65_536)) {
      try await runner(outputBytes: 65_536).run(command("/usr/bin/yes"))
    }
  }

  @Test func failingToolReportsStatusAndDiagnostics() async throws {
    let error = await #expect(throws: SystemToolError.self) {
      try await runner().run(command("/bin/ls", "/strata-bar-missing-path"))
    }
    guard case .exited(let status, let diagnostics) = error else {
      Issue.record("Expected an exit status, got \(String(describing: error))")
      return
    }
    #expect(status != 0)
    #expect(diagnostics.contains("No such file or directory"))
  }

  @Test func missingExecutableFailsToLaunch() async {
    let error = await #expect(throws: SystemToolError.self) {
      try await runner().run(command("/strata-bar-missing-tool"))
    }
    guard case .launchFailed = error else {
      Issue.record("Expected a launch failure, got \(String(describing: error))")
      return
    }
  }

  @Test func childKilledFromOutsideReportsTheSignal() async {
    await #expect(throws: SystemToolError.terminated(signal: SIGKILL)) {
      try await runner { kill($0, SIGKILL) }.run(command("/bin/sleep", "30"))
    }
  }

  @Test func timeoutTerminatesAHungChild() async {
    let launched = LaunchedChild()
    let started = ContinuousClock.now
    await #expect(throws: SystemToolError.timedOut) {
      try await runner(timeout: .milliseconds(200), didLaunch: launched.record)
        .run(command("/bin/sleep", "30"))
    }
    #expect(ContinuousClock.now - started < .seconds(5))
    #expect(launched.hasExited)
  }

  /// sleep ignores SIGWINCH, which stands in for a child that ignores the polite request.
  @Test func childIgnoringTerminationIsKilledAfterTheGracePeriod() async {
    let launched = LaunchedChild()
    let stubborn = runner(
      timeout: .milliseconds(200), terminationSignal: SIGWINCH, didLaunch: launched.record)
    let started = ContinuousClock.now
    await #expect(throws: SystemToolError.timedOut) {
      try await stubborn.run(command("/bin/sleep", "30"))
    }
    #expect(ContinuousClock.now - started >= .milliseconds(500))
    #expect(launched.hasExited)
  }

  @Test func cancellationTerminatesTheChildPromptly() async throws {
    let launched = LaunchedChild()
    let task = Task {
      try await runner(didLaunch: launched.record).run(command("/bin/sleep", "30"))
    }
    while launched.pid == nil { try await Task.sleep(for: .milliseconds(5)) }
    let cancelled = ContinuousClock.now
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(ContinuousClock.now - cancelled < .seconds(2))
    #expect(launched.hasExited)
  }

  @Test func cancellationBeforeLaunchNeverStartsTheChild() async {
    let launched = LaunchedChild()
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await runner(didLaunch: launched.record).run(command("/bin/sleep", "30"))
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(launched.pid == nil)
  }
}

@Suite struct PrivateReportDirectoryTests {
  @Test func reportDirectoryIsPrivateBoundedAndRemoved() throws {
    let directory = try PrivateReportDirectory()
    let attributes = try FileManager.default.attributesOfItem(atPath: directory.url.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    #expect(throws: SystemToolError.reportUnavailable) { try directory.readReport(limit: 10) }
    try Data("0123456789".utf8).write(to: directory.reportFile)
    #expect(try directory.readReport(limit: 10) == Data("0123456789".utf8))
    #expect(throws: SystemToolError.outputLimitExceeded(limit: 9)) {
      try directory.readReport(limit: 9)
    }
    directory.remove()
    #expect(!FileManager.default.fileExists(atPath: directory.url.path))
  }
}

private final class LaunchedChild: Sendable {
  private let launchedPID = Mutex<Int32?>(nil)
  var pid: Int32? { launchedPID.withLock { $0 } }
  var hasExited: Bool {
    guard let pid else { return false }
    return kill(pid, 0) == -1 && errno == ESRCH
  }
  func record(_ pid: Int32) { launchedPID.withLock { $0 = pid } }
}
