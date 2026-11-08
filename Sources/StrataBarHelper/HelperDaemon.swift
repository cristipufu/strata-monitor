import Foundation
import StrataHelperInterface
import os

enum HelperDaemon {
  static func run() -> Never {
    let log = Logger(subsystem: HelperContract.machServiceName, category: "lifecycle")
    guard
      let callerRequirement = HelperCodeSigning.peerRequirement(
        signingIdentifier: HelperContract.appSigningIdentifier)
    else {
      log.error("The helper has no team signature, so it cannot verify Strata Monitor. Exiting.")
      exit(EX_CONFIG)
    }
    let core = HelperCore.live()
    let delegate = HelperListenerDelegate(core: core)
    let listener = NSXPCListener(machServiceName: HelperContract.machServiceName)
    listener.setConnectionCodeSigningRequirement(callerRequirement)
    listener.delegate = delegate
    listener.activate()
    let idleExit = IdleExitTimer(activity: core.activity) {
      log.info("No requests for \(core.activity.idleLimit, privacy: .public) seconds. Exiting.")
      exit(EXIT_SUCCESS)
    }
    idleExit.start()
    withExtendedLifetime((listener, delegate, idleExit)) { dispatchMain() }
  }
}
