import AppKit
import StrataCore
import SwiftUI

struct ExplorerRowAction {
  let title: String
  let perform: () -> Void
}

// Table menus and inspector context menus render these same lists, so each
// process, resource and file offers identical actions wherever it appears.
@MainActor struct ExplorerRowActions {
  let copy: @MainActor (String) -> Void
  let reveal: @MainActor (URL) -> Void
  var currentPID = ProcessInfo.processInfo.processIdentifier
  var currentUser = getuid()
  static let system = ExplorerRowActions(
    copy: Clipboard.copy, reveal: { NSWorkspace.shared.activateFileViewerSelecting([$0]) })

  func process(_ process: ProcessSample) -> [ExplorerRowAction] {
    [copyPID(process.id)] + file(process.path)
  }
  func resource(
    _ resource: ProcessResource, inspectOwner: ((ProcessIdentity) -> Void)? = nil
  ) -> [ExplorerRowAction] {
    var actions: [ExplorerRowAction] = []
    if let inspectOwner {
      actions.append(ExplorerRowAction(title: String(localized: "Inspect Owner")) { inspectOwner(resource.owner) })
    }
    actions.append(copyPID(resource.owner))
    actions += file(resource.path)
    // A resource without a local port reports its path as its endpoint.
    if resource.endpoint != resource.path {
      actions.append(ExplorerRowAction(title: String(localized: "Copy Endpoint")) { copy(resource.endpoint) })
    }
    if let remote = resource.remoteEndpoint {
      actions.append(ExplorerRowAction(title: String(localized: "Copy Remote Endpoint")) { copy(remote) })
    }
    return actions
  }
  // Ends a listener's process through the confirmed Terminate flow. Another user's listener
  // offers nothing, because Strata Monitor cannot signal it.
  func freePort(
    _ resource: ProcessResource, owner: ProcessSample?,
    terminate: @escaping @MainActor (ProcessSample) -> Void
  ) -> [ExplorerRowAction] {
    guard resource.ownsLocalPort, let owner, owner.id == resource.owner,
      ProcessActionPolicy.allows(
        .terminate, for: owner, currentPID: currentPID, currentUser: currentUser)
    else { return [] }
    return [
      ExplorerRowAction(title: String(localized: "Stop Process Using Port \(String(resource.localPort))…")) {
        terminate(owner)
      }
    ]
  }
  func file(_ path: String) -> [ExplorerRowAction] {
    guard !path.isEmpty else { return [] }
    let copyPath = ExplorerRowAction(title: String(localized: "Copy Path")) { copy(path) }
    guard path.hasPrefix("/") else { return [copyPath] }
    return [
      copyPath,
      ExplorerRowAction(title: String(localized: "Reveal in Finder")) { reveal(URL(fileURLWithPath: path)) },
    ]
  }
  private func copyPID(_ identity: ProcessIdentity) -> ExplorerRowAction {
    ExplorerRowAction(title: String(localized: "Copy PID")) { copy(String(identity.pid)) }
  }
}

struct ExplorerActionButtons: View {
  let actions: [ExplorerRowAction]
  var body: some View {
    ForEach(actions, id: \.title) { action in
      Button(action.title, action: action.perform)
    }
  }
}

@MainActor final class ExplorerMenuActions: NSObject {
  private var actions: [ExplorerRowAction] = []
  func install(_ actions: [ExplorerRowAction], in menu: NSMenu) {
    self.actions = actions
    menu.removeAllItems()
    for (index, action) in actions.enumerated() {
      let item = menu.addItem(
        withTitle: action.title, action: #selector(performAction(_:)), keyEquivalent: "")
      item.target = self
      item.tag = index
    }
  }
  @objc private func performAction(_ item: NSMenuItem) {
    guard actions.indices.contains(item.tag) else { return }
    actions[item.tag].perform()
  }
}

@MainActor enum Clipboard {
  static func copy(_ value: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
  }
}
