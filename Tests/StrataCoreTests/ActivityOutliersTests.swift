import Foundation
import StrataCore
import Testing

private func sampleProcess(
  _ pid: Int32, parent: Int32 = 1, user: UInt32 = 501, startSeconds: UInt64 = 100,
  startMicroseconds: UInt64 = 0, name: String = "worker", path: String = "/usr/bin/worker",
  cpu: Double? = 5, footprint: UInt64? = 50 << 20, runState: ProcessRunState = .running,
  workingDirectory: String? = nil, project: String? = nil, spawnsPerSecond: Double? = nil
) -> ProcessSample {
  var sample = ProcessSample(
    id: ProcessIdentity(
      pid: pid, startSeconds: startSeconds, startMicroseconds: startMicroseconds),
    parentPID: parent, userID: user, name: name, path: path, cpuTimeNanoseconds: nil,
    cpuPercent: cpu, residentBytes: footprint, footprintBytes: footprint, threads: 1,
    runState: runState)
  sample.workingDirectory = workingDirectory
  sample.project = project
  sample.spawnsPerSecond = spawnsPerSecond
  return sample
}

@Test func churnTrackerCountsDirectChildSpawnsAndPIDRollover() {
  var tracker = ProcessChurnTracker()
  let parent = sampleProcess(200, startSeconds: 90, name: "Python", path: "/Library/Python")
  let initialChild = sampleProcess(201, parent: 200, startSeconds: 100, name: "sh")
  let initialRates = tracker.observe([parent, initialChild], at: 10.0)
  #expect(initialRates.isEmpty)

  // Out-of-order snapshot must be ignored without poisoning the baseline.
  #expect(tracker.observe([parent], at: 9.5).isEmpty)

  // Next tick 1 second later: 1 new child under PID 200 (sequential fork/exec loop), plus a 400-PID jump.
  let nextChild = sampleProcess(202, parent: 200, startSeconds: 101, name: "sh")
  let highPID = sampleProcess(605, parent: 1, startSeconds: 101, startMicroseconds: 50, name: "other")
  let secondRates = tracker.observe([parent, nextChild, highPID], at: 11.0)
  let parentRate = secondRates[parent.id] ?? 0
  #expect(parentRate >= 390)

  // Also test wrap-around near macOS PID ceiling (99,900 -> 300).
  var wrapTracker = ProcessChurnTracker()
  let nearCeiling = sampleProcess(99_900, parent: 200, startSeconds: 200, name: "sh")
  _ = wrapTracker.observe([parent, nearCeiling], at: 20.0)
  let wrappedChild = sampleProcess(
    300, parent: 200, startSeconds: 201, name: "sh", runState: .starting)
  let wrappedRates = wrapTracker.observe([parent, wrappedChild], at: 21.0)
  #expect((wrappedRates[parent.id] ?? 0) >= 350)
}

@Test func oldHighPIDProcessDoesNotFabricateWrapAroundStorm() {
  var tracker = ProcessChurnTracker()
  // Old daemon started yesterday at PID 95,000; current frontier is PID 15,000.
  let oldDaemon = sampleProcess(95_000, startSeconds: 10, name: "daemon")
  let currentProcess = sampleProcess(15_000, startSeconds: 500, name: "zsh")
  _ = tracker.observe([oldDaemon, currentProcess], at: 10.0)

  let singleSpawn = sampleProcess(15_001, parent: 15_000, startSeconds: 501, name: "ls")
  let rates = tracker.observe([oldDaemon, currentProcess, singleSpawn], at: 11.0)
  #expect(rates[currentProcess.id] == 1.0)
}

@Test func outlierRankerGroupsOrphanedProcessesAndPrioritizesSpawnStorms() throws {
  let repo = "/Users/me/Documents/GitHub/strata"
  let orphans = (0..<9).map { index in
    sampleProcess(
      Int32(2000 + index), parent: 1, user: 501, startSeconds: 100, name: "Python",
      path: "/Library/Frameworks/Python.framework/Versions/3.13/Resources/Python.app/Contents/MacOS/Python",
      cpu: 1.5, footprint: 20 << 20, workingDirectory: repo, project: "strata",
      spawnsPerSecond: 45)
  }
  let normalApp = sampleProcess(
    500, parent: 1, user: 501, name: "Xcode",
    path: "/Applications/Xcode.app/Contents/MacOS/Xcode", cpu: 85, footprint: 2 << 30)

  let ranked = ActivityOutlierRanker.rank(
    orphans + [normalApp], currentUser: 501, homeDirectory: "/Users/me",
    now: Date(timeIntervalSince1970: 1_000), limit: 5)
  let top = try #require(ranked.first)
  #expect(top.kind == .spawnStorm)
  #expect(top.severity == .critical)
  #expect(top.title == "Python ×9")
  #expect(top.rootCount == 9)
  #expect(top.memberCount == 9)
  #expect(top.targetProcesses.count == 9)
  #expect(top.workingDirectory == repo)
  #expect(top.project == "strata")
  #expect(top.subtitle.contains("~/Documents/GitHub/strata"))
  #expect(top.subtitle.contains("Orphaned spawn loop"))
}

@Test func outlierRankerGroupsOrphanedRunnersEvenWithoutSpawnStorm() throws {
  let repo = "/Users/me/Documents/GitHub/strata"
  let orphans = (0..<3).map { index in
    sampleProcess(
      Int32(3000 + index), parent: 1, user: 501, startSeconds: 100, name: "bun",
      path: "/opt/homebrew/bin/bun", cpu: 8, footprint: 100 << 20, workingDirectory: repo,
      project: "strata")
  }
  let ranked = ActivityOutlierRanker.rank(
    orphans, currentUser: 501, homeDirectory: "/Users/me",
    now: Date(timeIntervalSince1970: 1_000), limit: 5)
  let top = try #require(ranked.first)
  #expect(top.kind == .orphanedGroup)
  #expect(top.title == "bun ×3")
  #expect(top.rootCount == 3)
  #expect(top.memberCount == 3)
  #expect(top.subtitle == "Orphaned (15m) · ~/Documents/GitHub/strata")
}

@Test func securityAgentIsAttributedToActiveSpawnStormOrBusyFolder() throws {
  let repo = "/Users/me/Documents/GitHub/strata"
  let falcon = sampleProcess(
    88, parent: 1, user: 0, name: "com.crowdstrike.falcon.Agent",
    path: "/Library/CS/falcond", cpu: 115, footprint: 300 << 20)
  let spawner = sampleProcess(
    501, parent: 1, user: 501, name: "Python", path: "/usr/bin/python3", cpu: 12,
    workingDirectory: repo, project: "strata", spawnsPerSecond: 120)

  let ranked = ActivityOutlierRanker.rank(
    [falcon, spawner], currentUser: 501, homeDirectory: "/Users/me", limit: 5)
  let falconOutlier = try #require(ranked.first { $0.kind == .securityAgentActivity })
  #expect(falconOutlier.workingDirectory == repo)
  #expect(falconOutlier.subtitle == "Scanning spawns in ~/Documents/GitHub/strata")

  let qualys = sampleProcess(
    89, parent: 1, user: 0, name: "qualys-cloud-agent",
    path: "/Applications/QualysCloudAgent.app/Contents/MacOS/qualys-cloud-agent", cpu: 14,
    footprint: 180 << 20)
  let qualysRanked = ActivityOutlierRanker.rank(
    [qualys], currentUser: 501, homeDirectory: "/Users/me", limit: 5)
  let qualysOutlier = try #require(qualysRanked.first)
  #expect(qualysOutlier.kind == .securityAgentActivity)
}

@Test func familyRootInheritsWorkingDirectoryFromBusyChildAndOrdersRootBeforeWrappedChild() throws {
  let repo = "/Users/me/Documents/GitHub/strata"
  // Parent has PID 90,000 while wrapped child has PID 101; targetProcesses must still put parent first.
  let parentA = sampleProcess(
    90_000, parent: 1, user: 501, name: "Terminal",
    path: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal", cpu: 1)
  let childA = sampleProcess(
    101, parent: 90_000, user: 501, name: "cargo", path: "/Users/me/.cargo/bin/cargo", cpu: 55,
    workingDirectory: repo, project: "strata")

  let ranked = ActivityOutlierRanker.rank(
    [parentA, childA], currentUser: 501, homeDirectory: "/Users/me", limit: 10)
  let familyRow = try #require(ranked.first { $0.id == parentA.id })
  #expect(familyRow.kind == .folderHotspot)
  #expect(familyRow.workingDirectory == repo)
  #expect(familyRow.project == "strata")
  #expect(familyRow.isFamilyTree)
  #expect(familyRow.memberCount == 2)
  #expect(familyRow.subtitle == "2 processes · ~/Documents/GitHub/strata")
  #expect(familyRow.targetProcesses.map(\.id) == [parentA.id, childA.id])
}

@Test func pausedProcessRemainsVisibleInOutliersWithPausedMetric() throws {
  let paused = sampleProcess(
    777, parent: 1, user: 501, name: "Python", path: "/usr/bin/python3", cpu: 0,
    footprint: 12 << 20, runState: .stopped, workingDirectory: "/Users/me/Documents/GitHub/strata",
    project: "strata")
  let ranked = ActivityOutlierRanker.rank(
    [paused], currentUser: 501, homeDirectory: "/Users/me", limit: 5)
  let row = try #require(ranked.first)
  #expect(row.isPaused)
  #expect(row.primaryMetric == "Paused")
}

@Test func terminalTabsUnwrapToIndependentWorkloadsWithoutBundlingIntoTerminalApp() throws {
  let ghostty = sampleProcess(
    65_000, parent: 1, user: 501, name: "ghostty",
    path: "/Applications/Ghostty.app/Contents/MacOS/ghostty", cpu: 5, footprint: 400 << 20)
  let login1 = sampleProcess(65_001, parent: 65_000, user: 501, name: "login", path: "/usr/bin/login", cpu: 0)
  let zsh1 = sampleProcess(
    65_002, parent: 65_001, user: 501, name: "zsh", path: "/bin/zsh", cpu: 0,
    workingDirectory: "/Users/me/Documents/GitHub/repo-a", project: "repo-a")
  let codex1 = sampleProcess(
    65_003, parent: 65_002, user: 501, name: "codex", path: "/opt/homebrew/bin/codex", cpu: 18,
    footprint: 900 << 20, workingDirectory: "/Users/me/Documents/GitHub/repo-a", project: "repo-a")
  let cargo1 = sampleProcess(
    65_004, parent: 65_003, user: 501, name: "cargo", path: "/Users/me/.cargo/bin/cargo", cpu: 45,
    footprint: 200 << 20, workingDirectory: "/Users/me/Documents/GitHub/repo-a", project: "repo-a")

  let login2 = sampleProcess(65_010, parent: 65_000, user: 501, name: "login", path: "/usr/bin/login", cpu: 0)
  let zsh2 = sampleProcess(
    65_011, parent: 65_010, user: 501, name: "zsh", path: "/bin/zsh", cpu: 0,
    workingDirectory: "/Users/me/Documents/GitHub/repo-b", project: "repo-b")
  let claude2 = sampleProcess(
    65_012, parent: 65_011, user: 501, name: "2.1.321",
    path: "/Users/me/.local/share/claude/versions/2.1.321", cpu: 12, footprint: 400 << 20,
    workingDirectory: "/Users/me/Documents/GitHub/repo-b", project: "repo-b")

  let ranked = ActivityOutlierRanker.rank(
    [ghostty, login1, zsh1, codex1, cargo1, login2, zsh2, claude2], currentUser: 501,
    homeDirectory: "/Users/me", limit: 10)

  let codexOutlier = try #require(ranked.first { $0.id == codex1.id })
  #expect(codexOutlier.kind == .folderHotspot)
  #expect(codexOutlier.workingDirectory == "/Users/me/Documents/GitHub/repo-a")
  #expect(codexOutlier.targetProcesses.map(\.id) == [codex1.id, cargo1.id])

  let claudeOutlier = try #require(ranked.first { $0.id == claude2.id })
  #expect(claudeOutlier.title == "claude (2.1.321)")
  #expect(claudeOutlier.workingDirectory == "/Users/me/Documents/GitHub/repo-b")

  let ghosttyOutlier = try #require(ranked.first { $0.id == ghostty.id })
  #expect(ghosttyOutlier.memberCount == 1)
  #expect(ghosttyOutlier.workingDirectory == nil)
  #expect(ghosttyOutlier.targetProcesses.map(\.id) == [ghostty.id])
}

@Test func launchdCrashpadAndIdleDaemonsAreNeverFalsePositiveOrphansOrStorms() {
  let launchd = sampleProcess(
    1, parent: 0, user: 0, name: "launchd", path: "/sbin/launchd", cpu: 4, spawnsPerSecond: 30)
  let openWait1 = sampleProcess(
    66_587, parent: 1, user: 501, startSeconds: 100, name: "open", path: "/usr/bin/open", cpu: 0,
    footprint: 3 << 20)
  let openWait2 = sampleProcess(
    66_588, parent: 1, user: 501, startSeconds: 100, name: "open", path: "/usr/bin/open", cpu: 0,
    footprint: 3 << 20)
  let crashpad1 = sampleProcess(
    99_656, parent: 1, user: 501, startSeconds: 100, name: "chrome_crashpad_handler",
    path: "/Users/me/Library/Caches/ms-playwright/Google Chrome for Testing.app/Contents/Helpers/chrome_crashpad_handler",
    cpu: 0, footprint: 2 << 20)
  let crashpad2 = sampleProcess(
    99_660, parent: 1, user: 501, startSeconds: 100, name: "chrome_crashpad_handler",
    path: "/Users/me/Library/Caches/ms-playwright/Google Chrome for Testing.app/Contents/Helpers/chrome_crashpad_handler",
    cpu: 0, footprint: 2 << 20)
  let codexDaemon = sampleProcess(
    4_492, parent: 1, user: 501, startSeconds: 100, name: "codex",
    path: "/Users/me/.codex/packages/app-server-daemon/bin/codex", cpu: 0, footprint: 150 << 20,
    workingDirectory: "/Users/me/Documents/GitHub/strata", project: "strata")
  let chrome = sampleProcess(
    92_616, parent: 1, user: 501, name: "Google Chrome",
    path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", cpu: 0.5,
    footprint: 500 << 20)
  let nativeMessagingHost = sampleProcess(
    92_700, parent: 92_616, user: 501, name: "chrome-native-host",
    path: "/Users/me/.claude/chrome/chrome-native-host", cpu: 0, footprint: 10 << 20,
    workingDirectory: "/Users/me/.claude/chrome", project: "chrome")

  let ranked = ActivityOutlierRanker.rank(
    [launchd, openWait1, openWait2, crashpad1, crashpad2, codexDaemon, chrome, nativeMessagingHost],
    currentUser: 501, homeDirectory: "/Users/me", now: Date(timeIntervalSince1970: 10_000),
    limit: 10)

  #expect(!ranked.contains { $0.id == launchd.id })
  #expect(!ranked.contains { $0.kind == .orphanedGroup })
  #expect(!ranked.contains { $0.kind == .spawnStorm })
  if let chromeRow = ranked.first(where: { $0.id == chrome.id }) {
    #expect(chromeRow.workingDirectory == nil)
    #expect(chromeRow.subtitle == "2 processes · /Applications/Google Chrome.app")
  }
}
