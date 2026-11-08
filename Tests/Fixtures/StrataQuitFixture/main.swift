import AppKit
import Foundation

@MainActor final class QuitFixtureDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if CommandLine.arguments.count > 1 {
      let marker = URL(fileURLWithPath: CommandLine.arguments[1])
      try? Data("quit-requested".utf8).write(to: marker, options: .atomic)
    }
    return CommandLine.arguments.contains("--veto") ? .terminateCancel : .terminateNow
  }
}

let application = NSApplication.shared
let delegate = QuitFixtureDelegate()
application.delegate = delegate
application.setActivationPolicy(.prohibited)
application.run()
