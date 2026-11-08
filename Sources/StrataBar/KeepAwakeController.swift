import Combine
import Foundation
import IOKit.pwr_mgt

@MainActor
final class KeepAwakeController: ObservableObject {
  @Published private(set) var expiresAt: Date?
  @Published private(set) var error: String?
  private var assertion: IOPMAssertionID = 0
  private var expirationTask: Task<Void, Never>?
  var isEnabled: Bool { assertion != 0 }

  func enable(minutes: Int = 30) {
    disable()
    error = nil
    var identifier: IOPMAssertionID = 0
    let result = IOPMAssertionCreateWithName(
      kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
      IOPMAssertionLevel(kIOPMAssertionLevelOn),
      "Strata Monitor Keep Awake" as CFString, &identifier)
    guard result == kIOReturnSuccess else {
      error = "Keep Awake could not start (\(result))."
      return
    }
    assertion = identifier
    let duration = max(1, min(480, minutes))
    expiresAt = Date().addingTimeInterval(Double(duration * 60))
    expirationTask = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(duration * 60)) } catch { return }
      self?.disable()
    }
  }
  func disable() {
    expirationTask?.cancel()
    expirationTask = nil
    if assertion != 0 {
      IOPMAssertionRelease(assertion)
      assertion = 0
    }
    expiresAt = nil
  }
  deinit {
    expirationTask?.cancel()
    if assertion != 0 { IOPMAssertionRelease(assertion) }
  }
}
