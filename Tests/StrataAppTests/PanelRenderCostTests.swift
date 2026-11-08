import AppKit
import Foundation
import StrataCore
import Testing

@testable import StrataBar

@Test @MainActor func applicationIconsAreDrawnOnceAtTheirShownSize() throws {
  var lookups: [Int32] = []
  let fullSize = NSImage(size: NSSize(width: 1024, height: 1024), flipped: false) { rect in
    NSColor.systemTeal.setFill()
    rect.fill()
    return true
  }
  let icons = ProcessIconCache { pid in
    lookups.append(pid)
    return pid == 7 ? fullSize : nil
  }
  let app = ProcessIdentity(pid: 7, startSeconds: 100, startMicroseconds: 0)
  let image = try #require(icons.icon(for: app, side: 27, scale: 2))
  #expect(image.width == 54 && image.height == 54)
  #expect(icons.icon(for: app, side: 27, scale: 2) === image)
  let tool = ProcessIdentity(pid: 8, startSeconds: 100, startMicroseconds: 0)
  #expect(icons.icon(for: tool, side: 27, scale: 2) == nil)
  #expect(icons.icon(for: tool, side: 27, scale: 2) == nil)
  #expect(lookups == [7, 8], "A process without an icon is not looked up on every frame")
}

@Test @MainActor func aReusedProcessIDGetsItsOwnApplicationIcon() {
  var lookups = 0
  let icons = ProcessIconCache { _ in
    lookups += 1
    return NSImage(size: NSSize(width: 16, height: 16))
  }
  _ = icons.icon(for: ProcessIdentity(pid: 7, startSeconds: 100, startMicroseconds: 0), side: 27, scale: 2)
  _ = icons.icon(for: ProcessIdentity(pid: 7, startSeconds: 200, startMicroseconds: 0), side: 27, scale: 2)
  #expect(lookups == 2)
}

@Test @MainActor func processFamiliesFollowEachNewReading() async throws {
  let sampler = GatedSampler()
  let model = AppModel(
    defaults: try #require(UserDefaults(suiteName: "StrataBar.Tests.\(UUID())")), collector: sampler)
  model.setDemand("popover", active: true)
  model.start()
  try await waitUntil { await sampler.requests.count >= 1 }
  let shell = process(pid: 40, parent: 1, name: "zsh")
  await sampler.complete(with: reading(uptime: 10, [shell, process(pid: 41, parent: 40, name: "bun")]))
  try await waitUntil { model.sample?.uptime == 10 }
  #expect(model.processFamilyRoots.map(\.members.count) == [2])
  #expect(model.processFamilies.parent(of: identity(41))?.id == shell.id)

  let clock = ContinuousClock()
  let deadline = clock.now + .seconds(8)
  while await sampler.requests.count < 2 && clock.now < deadline {
    try await Task.sleep(for: .milliseconds(20))
  }
  await sampler.complete(with: reading(uptime: 12, [shell]))
  try await waitUntil { model.sample?.uptime == 12 }
  #expect(model.processFamilyRoots.map(\.members.count) == [1])
  #expect(model.processFamilies.parent(of: identity(41)) == nil)
  model.stop()
}

private func identity(_ pid: Int32) -> ProcessIdentity {
  ProcessIdentity(pid: pid, startSeconds: UInt64(pid), startMicroseconds: 0)
}

private func process(pid: Int32, parent: Int32, name: String) -> ProcessSample {
  ProcessSample(
    id: identity(pid), parentPID: parent, userID: 501, name: name, path: "/bin/\(name)",
    cpuTimeNanoseconds: 0, cpuPercent: 1, residentBytes: 1, footprintBytes: 1, threads: 1)
}

private func reading(uptime: TimeInterval, _ processes: [ProcessSample]) -> SystemSample {
  SystemSample(
    uptime: uptime, cpu: 0.25, cores: [0.25], memory: nil, network: nil, interfaces: [],
    processes: processes)
}
