import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
  fputs("Usage: CheckStoppedApp.swift /path/to/application.app\n", stderr)
  exit(EXIT_FAILURE)
}
let applicationURL = URL(fileURLWithPath: CommandLine.arguments[1]).resolvingSymlinksInPath()
let isRunning = NSWorkspace.shared.runningApplications.contains {
  $0.bundleURL?.resolvingSymlinksInPath() == applicationURL && !$0.isTerminated
}
guard !isRunning else {
  fputs("Quit Strata Monitor before replacing its packaged build.\n", stderr)
  exit(EXIT_FAILURE)
}
