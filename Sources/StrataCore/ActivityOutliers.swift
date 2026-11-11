import Foundation

/// Tracks newly spawned processes and PID rollover between consecutive snapshots so fork/exec
/// storms are attributed to their parent process even when children exit in milliseconds.
public struct ProcessChurnTracker: Sendable {
  private static let maximumPID: Int32 = 99_999
  private static let wrapHighWatermark: Int32 = 70_000
  private static let wrapLowWatermark: Int32 = 30_000
  private static let minimumElapsed: TimeInterval = 0.25
  private var previousIdentities: Set<ProcessIdentity> = []
  private var previousFrontierPID: Int32 = 0
  private var previousTime: TimeInterval?
  private let maximumInterval: TimeInterval

  public init(maximumInterval: TimeInterval = 45) {
    self.maximumInterval = maximumInterval
  }

  public mutating func reset() {
    previousIdentities.removeAll(keepingCapacity: true)
    previousFrontierPID = 0
    previousTime = nil
  }

  public mutating func observe(_ processes: [ProcessSample], at time: TimeInterval)
    -> [ProcessIdentity: Double]
  {
    guard time.isFinite, time >= 0 else { return [:] }
    if let lastTime = previousTime, time <= lastTime { return [:] }
    let currentIdentities = Set(processes.map(\.id))
    let frontierPID = Self.newestPID(in: processes)
    guard let lastTime = previousTime, time - lastTime <= maximumInterval else {
      previousIdentities = currentIdentities
      previousFrontierPID = frontierPID
      previousTime = time
      return [:]
    }
    let elapsed = max(Self.minimumElapsed, time - lastTime)
    var newChildrenByParent: [Int32: Int] = [:]
    var transientChildrenByParent: [Int32: Int] = [:]
    var newProcesses: [ProcessSample] = []

    for process in processes where process.parentPID > 0 {
      let isNew = !previousIdentities.contains(process.id)
      let isTransient = process.runState == .starting || process.runState == .zombie
      if isNew {
        if process.parentPID > 1 {
          newChildrenByParent[process.parentPID, default: 0] += 1
        }
        newProcesses.append(process)
      }
      if isTransient && process.parentPID > 1 {
        transientChildrenByParent[process.parentPID, default: 0] += 1
      }
    }

    let newestNewPID = Self.newestPID(in: newProcesses)
    let pidAdvance = Self.pidAdvance(from: previousFrontierPID, to: newestNewPID)
    previousIdentities = currentIdentities
    if newestNewPID > 0 {
      previousFrontierPID = newestNewPID
    } else if frontierPID > 0 {
      previousFrontierPID = frontierPID
    }
    previousTime = time

    let totalNewCount = newProcesses.count
    let unseenSpawns = max(0, pidAdvance - totalNewCount)
    let activeWeights = Self.spawnerWeights(
      processes: processes, newByParent: newChildrenByParent,
      transientByParent: transientChildrenByParent, hasUnseenBurst: unseenSpawns >= 35)
    let totalWeight = activeWeights.values.reduce(0, +)

    var rates: [ProcessIdentity: Double] = [:]
    for process in processes where process.id.pid > 1 {
      let directNew = newChildrenByParent[process.id.pid] ?? 0
      let weight = activeWeights[process.id] ?? 0
      guard directNew > 0 || weight > 0 else { continue }
      let attributedUnseen =
        totalWeight > 0 && weight > 0 && unseenSpawns >= 35
        ? Double(unseenSpawns) * (Double(weight) / Double(totalWeight)) : 0
      let rate = (Double(directNew) + attributedUnseen) / elapsed
      if rate > 0 { rates[process.id] = rate }
    }
    return rates
  }

  private static func newestPID(in processes: [ProcessSample]) -> Int32 {
    processes.max { lhs, rhs in
      let leftStart = lhs.id.startMicrosecondsSinceEpoch
      let rightStart = rhs.id.startMicrosecondsSinceEpoch
      return leftStart == rightStart ? lhs.id.pid < rhs.id.pid : leftStart < rightStart
    }?.id.pid ?? 0
  }

  private static func pidAdvance(from previous: Int32, to currentNewMax: Int32) -> Int {
    guard previous > 0, currentNewMax > 0 else { return 0 }
    if currentNewMax >= previous { return Int(currentNewMax - previous) }
    if previous >= wrapHighWatermark && currentNewMax <= wrapLowWatermark {
      return Int(maximumPID - previous + currentNewMax)
    }
    return 0
  }

  private static func spawnerWeights(
    processes: [ProcessSample], newByParent: [Int32: Int], transientByParent: [Int32: Int],
    hasUnseenBurst: Bool
  ) -> [ProcessIdentity: Int] {
    var weights: [ProcessIdentity: Int] = [:]
    for process in processes where process.id.pid > 1 {
      let pid = process.id.pid
      let transient = transientByParent[pid] ?? 0
      let directNew = newByParent[pid] ?? 0
      let isContainer = ActivityOutlierRanker.isSessionContainer(process)
      let isActive = (process.cpuPercent ?? 0) >= 1.0 || process.cpuPercent == nil
      // A sequential fork/exec loop has at most 1 child alive at the snapshot instant; when the
      // kernel PID counter jumps ahead by >= 35, an active non-container parent caught with a new
      // or transient child shares the unseen-spawn attribution proportionally.
      if transient > 0 || directNew >= 3
        || (hasUnseenBurst && !isContainer && directNew >= 1 && isActive)
      {
        weights[process.id] = transient * 4 + directNew
      }
    }
    return weights
  }
}

public struct ActivityOutlier: Identifiable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable, CaseIterable {
    case spawnStorm
    case orphanedGroup
    case securityAgentActivity
    case folderHotspot
    case highCPU
    case highMemory
    case highPower
    case highDisk
  }

  public enum Severity: Int, Comparable, Codable, Sendable {
    case normal = 0
    case elevated = 1
    case critical = 2
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
  }

  public let id: ProcessIdentity
  public let kind: Kind
  public let severity: Severity
  public let title: String
  public let subtitle: String
  public let primaryMetric: String
  public let workingDirectory: String?
  public let displayDirectory: String?
  public let project: String?
  public let rootCount: Int
  public let memberCount: Int
  public let isFamilyTree: Bool
  public let isPaused: Bool
  public let targetProcesses: [ProcessSample]
  public let score: Double

  public init(
    id: ProcessIdentity, kind: Kind, severity: Severity, title: String, subtitle: String,
    primaryMetric: String, workingDirectory: String? = nil, displayDirectory: String? = nil,
    project: String? = nil, rootCount: Int = 1, memberCount: Int = 1,
    isFamilyTree: Bool = false, isPaused: Bool = false, targetProcesses: [ProcessSample],
    score: Double
  ) {
    self.id = id
    self.kind = kind
    self.severity = severity
    self.title = title
    self.subtitle = subtitle
    self.primaryMetric = primaryMetric
    self.workingDirectory = workingDirectory
    self.displayDirectory = displayDirectory
    self.project = project
    self.rootCount = rootCount
    self.memberCount = memberCount
    self.isFamilyTree = isFamilyTree
    self.isPaused = isPaused
    self.targetProcesses = targetProcesses
    self.score = score
  }
}

public enum ActivityOutlierRanker {
  private static let securityAgentNames: Set<String> = [
    "com.crowdstrike.falcon.Agent", "Falcon", "QualysCloudAgent", "qualys-cloud-agent",
    "qualys-scan-util", "syspolicyd", "endpointsecurityd", "fseventsd", "mds_stores", "mds",
  ]
  private static let terminalEmulatorNames: Set<String> = [
    "ghostty", "Terminal", "iTerm2", "iTermServer", "Warp", "Alacritty", "kitty", "wezterm-gui",
    "Hyper", "Rio", "Tabby",
  ]
  private static let sessionWrapperNames: Set<String> = [
    "login", "sshd", "tmux", "screen", "zellij", "ghostback", "nohup", "script", "zsh", "bash",
    "fish", "sh", "dash", "ksh", "tcsh", "csh", "nu",
  ]
  private static let daemonOrServiceNames: Set<String> = [
    "tmux", "screen", "zellij", "mosh-server", "ghostback", "ssh-agent", "gpg-agent", "scdaemon",
    "dirmngr", "watchman", "sccache", "fsmonitor--daemon", "git-credential-osxkeychain",
    "chrome_crashpad_handler", "crashpad_handler", "opencode", "opencode.exe", "adb",
    "rust-analyzer", "sourcekit-lsp", "tsserver", "eslint_d", "prettierd", "kotlin-daemon",
    "gradle", "open", "caffeinate",
  ]
  private static let routineDesktopDaemonNames: Set<String> = [
    "loginwindow", "WindowManager", "Dock", "ControlCenter", "SystemUIServer", "Finder",
    "Spotlight", "UserEventAgent", "cfprefsd", "distnoted", "lsd", "tccd", "trustd", "secd",
  ]

  static func isSessionContainer(_ process: ProcessSample) -> Bool {
    terminalEmulatorNames.contains(process.name) || sessionWrapperNames.contains(process.name)
  }

  public static func rank(
    _ processes: [ProcessSample], families: ProcessFamilies? = nil, currentUser: UInt32,
    currentPID: Int32 = getpid(), homeDirectory: String = NSHomeDirectory(), now: Date = Date(),
    limit: Int = 10
  ) -> [ActivityOutlier] {
    guard !processes.isEmpty, limit > 0 else { return [] }
    let resolvedFamilies = families ?? ProcessFamilies(processes)
    let candidates = buildCandidates(
      from: resolvedFamilies, allProcesses: processes, currentUser: currentUser,
      currentPID: currentPID, homeDirectory: homeDirectory)
    let activeStorm = candidates.first { $0.isSpawnStorm }
    let busiestFolderWork = candidates
      .filter { $0.workingDirectory != nil && !$0.isSecurityAgent && ($0.cpu ?? 0) >= 5 }
      .max { ($0.cpu ?? 0) < ($1.cpu ?? 0) }

    let sorted = candidates
      .compactMap {
        classify(
          $0, now: now, homeDirectory: homeDirectory, activeStorm: activeStorm,
          busiestFolderWork: busiestFolderWork)
      }
      .sorted {
        if $0.severity != $1.severity { return $0.severity > $1.severity }
        if $0.score != $1.score { return $0.score > $1.score }
        return $0.id.pid < $1.id.pid
      }

    var seenXPCNames: Set<String> = []
    var deduplicated: [ActivityOutlier] = []
    for outlier in sorted {
      if let primary = outlier.targetProcesses.first, primary.path.contains(".xpc/") {
        guard seenXPCNames.insert(primary.name).inserted else { continue }
      }
      deduplicated.append(outlier)
      if deduplicated.count >= limit { break }
    }
    return deduplicated
  }

  public static func displayPath(_ path: String, homeDirectory: String = NSHomeDirectory()) -> String
  {
    let cleaned = stripCryptexPrefix(path)
    let trimmedHome = normalizedHome(homeDirectory)
    guard !trimmedHome.isEmpty, trimmedHome != "/" else { return cleaned }
    if cleaned == trimmedHome { return "~" }
    if cleaned.hasPrefix(trimmedHome + "/") {
      return "~" + cleaned.dropFirst(trimmedHome.count)
    }
    return cleaned
  }

  public static func compactBundlePath(_ path: String, homeDirectory: String = NSHomeDirectory())
    -> String
  {
    let displayed = displayPath(path, homeDirectory: homeDirectory)
    if let appRange = displayed.range(of: ".app/") {
      return String(displayed[..<appRange.upperBound].dropLast())
    }
    if let xpcRange = displayed.range(of: ".xpc/") {
      let prefix = String(displayed[..<xpcRange.upperBound].dropLast())
      if let frameworkRange = prefix.range(of: ".framework/") {
        return String(prefix[..<frameworkRange.upperBound].dropLast())
      }
      return prefix
    }
    if let appexRange = displayed.range(of: ".appex/") {
      return String(displayed[..<appexRange.upperBound].dropLast())
    }
    return displayed
  }

  private static func stripCryptexPrefix(_ path: String) -> String {
    for prefix in [
      "/System/Volumes/Preboot/Cryptexes/Incoming/OS",
      "/System/Volumes/Preboot/Cryptexes/OS",
      "/System/Volumes/Preboot/Cryptexes/App",
    ] where path.hasPrefix(prefix + "/") {
      return String(path.dropFirst(prefix.count))
    }
    return path
  }

  private static func normalizedHome(_ homeDirectory: String) -> String {
    homeDirectory.count > 1 && homeDirectory.hasSuffix("/")
      ? String(homeDirectory.dropLast()) : homeDirectory
  }

  private struct Candidate {
    let primary: ProcessSample
    let roots: [ProcessSample]
    let members: [ProcessSample]
    var workingDirectory: String?
    var displayDirectory: String?
    let project: String?
    let cpu: Double?
    let hasMissingCPU: Bool
    let isCPUReadable: Bool
    let footprintBytes: UInt64?
    let watts: Double?
    let diskWriteBytesPerSecond: Double?
    let spawnsPerSecond: Double
    let transientChildrenCount: Int
    let isOrphanedCLI: Bool
    let isSecurityAgent: Bool
    let isPaused: Bool

    var isSpawnStorm: Bool {
      !isPaused && primary.id.pid > 1
        && (spawnsPerSecond >= 12 || transientChildrenCount >= 4)
    }
  }

  private static func buildCandidates(
    from families: ProcessFamilies, allProcesses: [ProcessSample], currentUser: UInt32,
    currentPID: Int32, homeDirectory: String
  ) -> [Candidate] {
    var transientByParent: [Int32: Int] = [:]
    for process in allProcesses where process.parentPID > 1 {
      if process.runState == .starting || process.runState == .zombie {
        transientByParent[process.parentPID, default: 0] += 1
      }
    }

    var workloadFamilies: [ProcessFamily] = []
    for rootFamily in families.roots {
      workloadFamilies.append(
        contentsOf: unwrapWorkloads(of: rootFamily.root, in: families))
    }

    var orphanGroups: [OrphanKey: [ProcessFamily]] = [:]
    var standaloneFamilies: [ProcessFamily] = []

    for family in workloadFamilies {
      let root = family.root
      if root.id.pid <= 1 || root.id.pid == currentPID || root.name == "Strata Monitor"
        || root.name == "StrataBarHelper"
      {
        continue
      }
      if let key = orphanKey(for: root, currentUser: currentUser, homeDirectory: homeDirectory) {
        orphanGroups[key, default: []].append(family)
      } else {
        standaloneFamilies.append(family)
      }
    }

    var result: [Candidate] = []
    for (_, grouped) in orphanGroups {
      let sorted = grouped.sorted { $0.root.id.pid < $1.root.id.pid }
      guard let first = sorted.first else { continue }
      let roots = sorted.map(\.root)
      let members = sorted.flatMap(\.members)
      result.append(
        makeCandidate(
          primary: first.root, roots: roots, members: members,
          transientByParent: transientByParent, currentUser: currentUser,
          homeDirectory: homeDirectory))
    }
    for family in standaloneFamilies {
      result.append(
        makeCandidate(
          primary: family.root, roots: [family.root], members: family.members,
          transientByParent: transientByParent, currentUser: currentUser,
          homeDirectory: homeDirectory))
    }
    return result
  }

  /// Unwraps terminal emulators, login hosts, and interactive shells so each terminal tab's
  /// active command tree is ranked and acted on independently without killing the terminal app.
  private static func unwrapWorkloads(
    of node: ProcessSample, in families: ProcessFamilies
  ) -> [ProcessFamily] {
    let children = families.directChildren(of: node.id)
    if terminalEmulatorNames.contains(node.name) {
      guard !children.isEmpty else {
        return [ProcessFamily(root: node, members: [node])]
      }
      // If a terminal spawns a non-session tool directly (e.g. a single direct child command
      // without login/shell wrappers), keep it grouped unless the child is a session wrapper.
      let hasSessionChildren = children.contains { isSessionContainer($0) }
      if !hasSessionChildren && children.count == 1, let subtree = families.subtree(of: node.id) {
        return [subtree]
      }
      var result = [ProcessFamily(root: node, members: [node])]
      for child in children {
        result.append(contentsOf: unwrapWorkloads(of: child, in: families))
      }
      return result
    }
    if sessionWrapperNames.contains(node.name) {
      guard !children.isEmpty else {
        return [ProcessFamily(root: node, members: [node])]
      }
      var result: [ProcessFamily] = []
      if (node.cpuPercent ?? 0) >= 10 || (node.spawnsPerSecond ?? 0) >= 12
        || node.runState == .stopped
      {
        result.append(ProcessFamily(root: node, members: [node]))
      }
      for child in children {
        result.append(contentsOf: unwrapWorkloads(of: child, in: families))
      }
      return result
    }
    if let subtree = families.subtree(of: node.id) {
      return [subtree]
    }
    return [ProcessFamily(root: node, members: [node])]
  }

  private struct OrphanKey: Hashable {
    let name: String
    let scope: String
  }

  private static func orphanKey(
    for root: ProcessSample, currentUser: UInt32, homeDirectory: String
  ) -> OrphanKey? {
    guard isLegitimateOrphanedCLI(root, currentUser: currentUser, homeDirectory: homeDirectory),
      let folder = root.workingDirectory
    else { return nil }
    return OrphanKey(name: root.name, scope: folder)
  }

  private static func isLegitimateOrphanedCLI(
    _ process: ProcessSample, currentUser: UInt32, homeDirectory: String
  ) -> Bool {
    guard process.parentPID == 1, process.userID == currentUser else { return false }
    guard let folder = process.workingDirectory,
      isProjectOrWorkspaceDirectory(folder, homeDirectory: homeDirectory)
    else { return false }
    let lowerName = process.name.lowercased()
    if daemonOrServiceNames.contains(lowerName) || daemonOrServiceNames.contains(process.name) {
      return false
    }
    let path = process.path
    let lowerPath = path.lowercased()
    if lowerPath.contains("daemon") || lowerPath.contains("launchagent")
      || lowerPath.contains("crashpad") || lowerPath.contains(".xpc/")
      || lowerPath.contains(".appex/")
    {
      return false
    }
    if path.hasPrefix("/System/") || path.hasPrefix("/Library/Apple/")
      || path.hasPrefix("/usr/libexec/") || path.hasPrefix("/usr/sbin/")
    {
      return false
    }
    if path.contains(".app/") {
      return path.contains("Python.framework")
        || path.hasSuffix("Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing")
    }
    return true
  }

  private static func isProjectOrWorkspaceDirectory(_ directory: String, homeDirectory: String)
    -> Bool
  {
    guard !directory.isEmpty, directory != "/" else { return false }
    let trimmedHome = normalizedHome(homeDirectory)
    if directory == trimmedHome { return false }
    if directory.hasPrefix(trimmedHome + "/.") {
      // Hidden dot-folders inside ~ (like ~/.claude/chrome or ~/.vscode) are tool config
      // directories unless they are explicit worktree checkouts.
      return directory.contains("/worktrees/")
    }
    return true
  }

  private static func makeCandidate(
    primary: ProcessSample, roots: [ProcessSample], members: [ProcessSample],
    transientByParent: [Int32: Int], currentUser: UInt32, homeDirectory: String
  ) -> Candidate {
    let workingDirectory = resolveWorkingDirectory(
      primary: primary, members: members, homeDirectory: homeDirectory)
    let project =
      workingDirectory != nil
      ? (primary.project ?? dominantValue(in: members.compactMap(\.project))) : nil
    let displayDir = workingDirectory.map { displayPath($0, homeDirectory: homeDirectory) }

    let cpuValues = members.compactMap(\.cpuPercent).filter { $0.isFinite && $0 >= 0 }
    let cpu = cpuValues.isEmpty ? nil : cpuValues.reduce(0, +)
    let hasMissingCPU =
      members.contains { $0.cpuPercent.map { !$0.isFinite || $0 < 0 } ?? true } || cpu == nil
    let isCPUReadable = members.contains { $0.cpuTimeNanoseconds != nil || $0.isEstimated }

    let footprints = members.compactMap(\.footprintBytes)
    var footprintTotal: UInt64? = footprints.isEmpty ? nil : 0
    for value in footprints {
      if let current = footprintTotal {
        let sum = current.addingReportingOverflow(value)
        footprintTotal = sum.overflow ? nil : sum.partialValue
      }
    }

    let wattsValues = members.compactMap(\.watts).filter { $0.isFinite && $0 >= 0 }
    let watts = wattsValues.isEmpty ? nil : wattsValues.reduce(0, +)

    let diskValues = members.compactMap(\.diskWrittenBytesPerSecond).filter {
      $0.isFinite && $0 >= 0
    }
    let diskWrite = diskValues.isEmpty ? nil : diskValues.reduce(0, +)

    let spawns = members.compactMap(\.spawnsPerSecond).filter { $0.isFinite && $0 > 0 }
      .reduce(0, +)
    let memberPIDs = Set(members.map(\.id.pid))
    let transientFromParents = memberPIDs.reduce(0) { $0 + (transientByParent[$1] ?? 0) }
    let transientInMembers = members.filter { $0.runState == .starting || $0.runState == .zombie }
      .count
    let transientCount = max(transientFromParents, transientInMembers)

    let isOrphaned = isLegitimateOrphanedCLI(
      primary, currentUser: currentUser, homeDirectory: homeDirectory)
    let isSecurity =
      securityAgentNames.contains(primary.name)
      || primary.path.contains("com.crowdstrike.falcon")
      || primary.path.localizedCaseInsensitiveContains("qualys")
    let isPaused =
      primary.userID == currentUser && !roots.isEmpty
      && roots.allSatisfy { $0.runState == .stopped }

    return Candidate(
      primary: primary, roots: roots, members: members, workingDirectory: workingDirectory,
      displayDirectory: displayDir, project: project, cpu: cpu, hasMissingCPU: hasMissingCPU,
      isCPUReadable: isCPUReadable, footprintBytes: footprintTotal, watts: watts,
      diskWriteBytesPerSecond: diskWrite, spawnsPerSecond: spawns,
      transientChildrenCount: transientCount, isOrphanedCLI: isOrphaned,
      isSecurityAgent: isSecurity, isPaused: isPaused)
  }

  private static func resolveWorkingDirectory(
    primary: ProcessSample, members: [ProcessSample], homeDirectory: String
  ) -> String? {
    if let own = primary.workingDirectory, !own.isEmpty {
      return own
    }
    let isInstalledGUIApp =
      primary.path.hasPrefix("/Applications/") || primary.path.hasPrefix("/System/Applications/")
    let eligibleChildren = members.filter { member in
      guard let dir = member.workingDirectory,
        isProjectOrWorkspaceDirectory(dir, homeDirectory: homeDirectory)
      else { return false }
      if isInstalledGUIApp {
        return (member.cpuPercent ?? 0) >= 5.0
      }
      return true
    }
    return dominantValue(in: eligibleChildren.compactMap(\.workingDirectory))
  }

  private static func dominantValue(in values: [String]) -> String? {
    guard !values.isEmpty else { return nil }
    var counts: [String: Int] = [:]
    for value in values where !value.isEmpty { counts[value, default: 0] += 1 }
    return counts.max {
      $0.value == $1.value ? $0.key.count > $1.key.count : $0.value < $1.value
    }?.key
  }

  private static func classify(
    _ candidate: Candidate, now: Date, homeDirectory: String, activeStorm: Candidate?,
    busiestFolderWork: Candidate?
  ) -> ActivityOutlier? {
    let cpu = candidate.cpu ?? 0
    let footprintBytes = candidate.footprintBytes ?? 0
    let footprintGB = Double(footprintBytes) / Double(1 << 30)
    let watts = candidate.watts ?? 0
    let diskMBps = (candidate.diskWriteBytesPerSecond ?? 0) / 1_000_000
    let ageSeconds = max(0, now.timeIntervalSince(candidate.primary.id.startDate))

    if !candidate.isPaused && routineDesktopDaemonNames.contains(candidate.primary.name) {
      guard cpu >= 40.0 || footprintBytes >= (1_500 << 20) else { return nil }
    }

    let title = formatTitle(candidate)
    let compactPath = compactBundlePath(
      candidate.primary.path.isEmpty ? candidate.primary.name : candidate.primary.path,
      homeDirectory: homeDirectory)
    let location = candidate.displayDirectory ?? candidate.project ?? compactPath

    if candidate.isSpawnStorm {
      let severity: ActivityOutlier.Severity =
        (candidate.spawnsPerSecond >= 25 || candidate.transientChildrenCount >= 8)
        ? .critical : .elevated
      let score =
        2_000 + candidate.spawnsPerSecond * 10 + Double(candidate.transientChildrenCount) * 25
        + cpu
      let spawnLabel =
        candidate.spawnsPerSecond >= 1
        ? ValueFormat.perSecond(candidate.spawnsPerSecond.rounded())
        : String(localized: "\(candidate.transientChildrenCount) spawning")
      let subtitle =
        candidate.isOrphanedCLI
        ? String(localized: "Orphaned spawn loop (\(formatAge(ageSeconds))) · \(location)")
        : String(localized: "Spawn loop · \(location)")
      return makeOutlier(
        candidate, kind: .spawnStorm, severity: severity, title: title, subtitle: subtitle,
        primaryMetric: spawnLabel, score: score)
    }

    if candidate.isOrphanedCLI,
      candidate.isPaused || candidate.roots.count >= 3
        || (candidate.roots.count == 2 && (cpu >= 2.0 || footprintBytes >= 256 << 20))
        || (ageSeconds >= 300 && (cpu >= 15.0 || footprintBytes >= 1_024 << 20))
    {
      let severity: ActivityOutlier.Severity =
        candidate.isPaused
        ? .normal : ((candidate.roots.count >= 3 || cpu >= 25) ? .elevated : .normal)
      let baseScore = Double(candidate.roots.count) * 40 + cpu * 2.5 + footprintGB * 25
      let score = candidate.isPaused ? max(500, baseScore) : baseScore
      let metric = formatPrimaryMetric(candidate, kind: .orphanedGroup)
      let subtitle = String(localized: "Orphaned (\(formatAge(ageSeconds))) · \(location)")
      return makeOutlier(
        candidate, kind: .orphanedGroup, severity: severity, title: title, subtitle: subtitle,
        primaryMetric: metric, score: score)
    }

    if candidate.isSecurityAgent, cpu >= 25 {
      let severity: ActivityOutlier.Severity = cpu >= 80 ? .elevated : .normal
      let score = cpu * 2.5
      let subtitle: String
      var attributed = candidate
      if let storm = activeStorm, storm.primary.id != candidate.primary.id {
        let source = storm.displayDirectory ?? storm.primary.displayName
        subtitle = String(localized: "Scanning spawns in \(source)")
        if attributed.workingDirectory == nil {
          attributed.workingDirectory = storm.workingDirectory
          attributed.displayDirectory = storm.displayDirectory
        }
      } else if let work = busiestFolderWork, let folder = work.displayDirectory {
        subtitle = String(localized: "Active alongside \(work.primary.name) in \(folder)")
        if attributed.workingDirectory == nil {
          attributed.workingDirectory = work.workingDirectory
          attributed.displayDirectory = work.displayDirectory
        }
      } else {
        subtitle = location
      }
      return makeOutlier(
        attributed, kind: .securityAgentActivity, severity: severity, title: title,
        subtitle: subtitle, primaryMetric: formatCPU(candidate), score: score)
    }

    guard
      candidate.isPaused || cpu >= 0.1 || footprintBytes >= 50 << 20 || watts >= 0.1
        || diskMBps >= 0.1
    else {
      return nil
    }

    let cpuScore = cpu * 2.0
    let memoryScore = footprintGB * 15.0
    let powerScore = watts * 8.0
    let diskScore = diskMBps * 1.5

    let kind: ActivityOutlier.Kind
    if candidate.isSecurityAgent {
      kind = .securityAgentActivity
    } else if candidate.workingDirectory != nil && candidate.members.count > 1 && cpu >= 10 {
      kind = .folderHotspot
    } else if candidate.isPaused || cpu >= 10 || (cpu >= 1 && cpuScore >= memoryScore) {
      kind = .highCPU
    } else if diskMBps >= 5 && diskScore >= memoryScore {
      kind = .highDisk
    } else if watts >= 2 && powerScore >= memoryScore {
      kind = .highPower
    } else if footprintBytes >= 50 << 20 {
      kind = .highMemory
    } else {
      kind = .highCPU
    }

    let severity: ActivityOutlier.Severity =
      candidate.isPaused ? .normal : (cpu >= 150 ? .elevated : .normal)
    let folderBonus = candidate.workingDirectory != nil && cpu >= 10 ? 35.0 : 0
    let rawScore = cpuScore + memoryScore + powerScore + diskScore + folderBonus
    let score = candidate.isPaused ? max(450, rawScore) : rawScore
    let subtitle = formatStandardSubtitle(candidate, homeDirectory: homeDirectory)
    return makeOutlier(
      candidate, kind: kind, severity: severity, title: title, subtitle: subtitle,
      primaryMetric: formatPrimaryMetric(candidate, kind: kind), score: score)
  }

  private static func makeOutlier(
    _ candidate: Candidate, kind: ActivityOutlier.Kind, severity: ActivityOutlier.Severity,
    title: String, subtitle: String, primaryMetric: String, score: Double
  ) -> ActivityOutlier {
    // Roots come before descendants so pausing or stopping a spawner tree freezes the parent
    // before any child exit can wake waitpid() in the parent.
    let rootIDs = Set(candidate.roots.map(\.id))
    let descendants = candidate.members.filter { !rootIDs.contains($0.id) }.sorted {
      $0.id.pid < $1.id.pid
    }
    let targets = candidate.roots + descendants
    return ActivityOutlier(
      id: candidate.primary.id, kind: kind, severity: severity, title: title,
      subtitle: subtitle, primaryMetric: primaryMetric,
      workingDirectory: candidate.workingDirectory, displayDirectory: candidate.displayDirectory,
      project: candidate.project, rootCount: candidate.roots.count,
      memberCount: candidate.members.count,
      isFamilyTree: candidate.roots.count == 1 && candidate.members.count > 1,
      isPaused: candidate.isPaused, targetProcesses: targets, score: score)
  }

  private static func formatTitle(_ candidate: Candidate) -> String {
    let baseName = readableProcessName(candidate.primary)
    if candidate.roots.count > 1 {
      return "\(baseName) ×\(candidate.roots.count)"
    }
    if candidate.displayDirectory != nil {
      return baseName
    }
    return baseName == candidate.primary.name ? candidate.primary.displayName : baseName
  }

  private static func readableProcessName(_ process: ProcessSample) -> String {
    let name = process.name
    if !name.isEmpty && name.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" }) {
      let lowerPath = process.path.lowercased()
      if lowerPath.contains("/claude/") { return "claude (\(name))" }
    }
    return name
  }

  private static func formatStandardSubtitle(_ candidate: Candidate, homeDirectory: String) -> String
  {
    if let folder = candidate.displayDirectory {
      if candidate.members.count > 1 && candidate.roots.count == 1 {
        return String(localized: "\(candidate.members.count) processes") + " · " + folder
      }
      return folder
    }
    let compactPath =
      candidate.primary.path.isEmpty
      ? "" : compactBundlePath(candidate.primary.path, homeDirectory: homeDirectory)
    if candidate.members.count > 1 {
      if !compactPath.isEmpty {
        return String(localized: "\(candidate.members.count) processes") + " · " + compactPath
      }
      return String(localized: "\(candidate.members.count) processes")
    }
    if !compactPath.isEmpty {
      return compactPath
    }
    return candidate.primary.userName ?? String(candidate.primary.userID)
  }

  private static func formatCPU(_ candidate: Candidate) -> String {
    guard let cpu = candidate.cpu else {
      return candidate.isCPUReadable ? "0.0%" : "—"
    }
    return (candidate.hasMissingCPU ? "≥" : "") + ValueFormat.processCPU(cpu)
  }

  private static func formatPrimaryMetric(_ candidate: Candidate, kind: ActivityOutlier.Kind)
    -> String
  {
    if candidate.isPaused {
      return String(localized: "Paused")
    }
    switch kind {
    case .highDisk:
      if let disk = candidate.diskWriteBytesPerSecond, disk > 0 {
        return ValueFormat.rate(disk)
      }
    case .highPower:
      if let watts = candidate.watts, watts > 0 {
        return ValueFormat.watts(watts)
      }
    case .highMemory:
      if let footprint = candidate.footprintBytes, footprint > 0 {
        return ValueFormat.bytes(footprint)
      }
    default:
      break
    }
    if (candidate.cpu ?? 0) >= 0.1 || candidate.cpu != nil {
      return formatCPU(candidate)
    }
    if let footprint = candidate.footprintBytes, footprint > 0 {
      return ValueFormat.bytes(footprint)
    }
    if let watts = candidate.watts, watts > 0 {
      return ValueFormat.watts(watts)
    }
    return "—"
  }

  private static func formatAge(_ seconds: TimeInterval) -> String {
    let totalMinutes = Int(seconds / 60)
    if totalMinutes < 1 { return "<1m" }
    if totalMinutes < 60 { return "\(totalMinutes)m" }
    let hours = totalMinutes / 60
    if hours < 48 { return "\(hours)h" }
    return "\(hours / 24)d"
  }
}
