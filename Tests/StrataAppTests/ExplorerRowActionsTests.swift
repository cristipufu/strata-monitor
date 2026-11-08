import Foundation
import StrataCore
import Testing

@testable import StrataBar

@MainActor private final class RecordedEffects {
  var copied: [String] = []
  var revealed: [URL] = []
  var inspected: [ProcessIdentity] = []
  lazy var actions = ExplorerRowActions(
    copy: { [unowned self] in self.copied.append($0) },
    reveal: { [unowned self] in self.revealed.append($0) })
  func perform(_ actions: [ExplorerRowAction]) {
    for action in actions { action.perform() }
  }
}

@Test @MainActor func processActionsCopyItsIdentityAndRevealItsExecutable() {
  let effects = RecordedEffects()
  let path = "/Applications/Example.app/Contents/MacOS/Example"
  let actions = effects.actions.process(actionProcess(42, path: path))
  #expect(actions.map(\.title) == ["Copy PID", "Copy Path", "Reveal in Finder"])
  effects.perform(actions)
  #expect(effects.copied == ["42", path])
  #expect(effects.revealed == [URL(fileURLWithPath: path)])
  #expect(effects.actions.process(actionProcess(7, path: "")).map(\.title) == ["Copy PID"])
}

@Test @MainActor func fileActionsRevealOnlyAbsolutePaths() {
  let effects = RecordedEffects()
  #expect(effects.actions.file("").isEmpty)
  #expect(effects.actions.file("anon_inode").map(\.title) == ["Copy Path"])
  #expect(effects.actions.file("/tmp/log").map(\.title) == ["Copy Path", "Reveal in Finder"])
}

@Test @MainActor func fileResourcesOfferTheirPathOnceAndCanInspectTheirOwner() {
  let effects = RecordedEffects()
  let resource = actionResource(path: "/tmp/log")
  let actions = effects.actions.resource(resource) { effects.inspected.append($0) }
  #expect(actions.map(\.title) == ["Inspect Owner", "Copy PID", "Copy Path", "Reveal in Finder"])
  effects.perform(actions)
  #expect(effects.inspected == [resource.owner])
  #expect(effects.copied == ["12", "/tmp/log"])
  #expect(effects.actions.resource(resource).map(\.title).first == "Copy PID")
}

@Test @MainActor func connectionResourcesCopyBothEndpoints() {
  let effects = RecordedEffects()
  let connection = actionResource(
    kind: .tcp, localAddress: "127.0.0.1", localPort: 8080, remoteAddress: "fe80::1",
    remotePort: 443)
  let actions = effects.actions.resource(connection)
  #expect(actions.map(\.title) == ["Copy PID", "Copy Endpoint", "Copy Remote Endpoint"])
  effects.perform(actions)
  #expect(effects.copied == ["12", "127.0.0.1:8080", "[fe80::1]:443"])
  #expect(effects.revealed.isEmpty)
}

@Test @MainActor func aListeningPortOffersToStopOnlyAnOwnerStrataBarMaySignal() {
  let effects = RecordedEffects()
  var terminated: [Int32] = []
  let listener = ProcessResource(
    owner: ProcessIdentity(pid: 12, startSeconds: 1, startMicroseconds: 0), processName: "Example",
    descriptor: 3, kind: .tcp, path: "", localAddress: "127.0.0.1", localPort: 3000,
    state: "Listening")
  func actions(owner: ProcessSample?, resource: ProcessResource = listener) -> [ExplorerRowAction] {
    var rowActions = effects.actions
    rowActions.currentPID = 30
    rowActions.currentUser = 501
    return rowActions.freePort(resource, owner: owner) { terminated.append($0.id.pid) }
  }
  let owner = actionProcess(12, path: "")
  let stop = actions(owner: owner)
  #expect(stop.map(\.title) == ["Stop Process Using Port 3000…"])
  stop.first?.perform()
  #expect(terminated == [12])
  #expect(actions(owner: nil).isEmpty)
  #expect(actions(owner: actionProcess(13, path: "")).isEmpty, "A different process never stands in")
  #expect(actions(owner: owner, resource: actionResource(kind: .file, path: "/tmp/a")).isEmpty)
}

private func actionProcess(_ pid: Int32, path: String) -> ProcessSample {
  ProcessSample(
    id: ProcessIdentity(pid: pid, startSeconds: 1, startMicroseconds: 0), parentPID: 1,
    userID: 501, name: "Example", path: path, cpuTimeNanoseconds: nil, residentBytes: nil,
    footprintBytes: nil, threads: nil)
}

private func actionResource(
  kind: ResourceKind = .file, path: String = "", localAddress: String = "",
  localPort: UInt16 = 0, remoteAddress: String = "", remotePort: UInt16 = 0
) -> ProcessResource {
  ProcessResource(
    owner: ProcessIdentity(pid: 12, startSeconds: 1, startMicroseconds: 0), processName: "Example",
    descriptor: 3, kind: kind, path: path, localAddress: localAddress,
    remoteAddress: remoteAddress, localPort: localPort, remotePort: remotePort)
}
