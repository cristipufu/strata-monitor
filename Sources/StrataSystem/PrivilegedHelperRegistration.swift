import CSystem
import Foundation
import ServiceManagement
import StrataHelperInterface

public enum PrivilegedHelperStatus: String, Sendable, Equatable {
  case notRegistered, enabled, requiresApproval, notFound
  init(_ status: SMAppService.Status) {
    switch status {
    case .notRegistered: self = .notRegistered
    case .enabled: self = .enabled
    case .requiresApproval: self = .requiresApproval
    case .notFound: self = .notFound
    @unknown default: self = .notFound
    }
  }
  public var title: String {
    switch self {
    case .notRegistered: "Off"
    case .enabled: "On"
    case .requiresApproval: "Needs approval in Login Items & Extensions"
    case .notFound: "Not available in this copy of Strata Monitor"
    }
  }
}

public enum PrivilegedHelperRegistrationError: LocalizedError, Sendable, Equatable {
  case notAllowed, invalidSignature, notFound, failed(String)
  public var errorDescription: String? {
    switch self {
    case .notAllowed:
      "Not allowed. Turn on Strata Monitor in System Settings › General › Login Items & Extensions."
    case .invalidSignature:
      "This copy of Strata Monitor isn't signed and notarized, so macOS won't run its helper."
    case .notFound: "This copy of Strata Monitor doesn't include the helper."
    case .failed(let message): message
    }
  }
}

/// The system service behind `PrivilegedHelperRegistration`; tests substitute a fake.
public protocol LaunchDaemonControlling: Sendable {
  var status: SMAppService.Status { get }
  func register() throws
  func unregister() async throws
  func openSystemSettingsLoginItems()
}

public struct SystemLaunchDaemon: LaunchDaemonControlling {
  private let plistName: String
  public init(plistName: String = HelperContract.launchDaemonPlistName) {
    self.plistName = plistName
  }
  // SMAppService isn't Sendable; a new instance per call is cheap and holds no state.
  private var service: SMAppService { SMAppService.daemon(plistName: plistName) }
  public var status: SMAppService.Status { service.status }
  public func register() throws { try service.register() }
  public func unregister() async throws { try await service.unregister() }
  public func openSystemSettingsLoginItems() { SMAppService.openSystemSettingsLoginItems() }
}

public protocol PrivilegedHelperRegistering: Sendable {
  func status() -> PrivilegedHelperStatus
  func register() throws(PrivilegedHelperRegistrationError) -> PrivilegedHelperStatus
  func unregister() async throws(PrivilegedHelperRegistrationError)
  func reregister() async throws(PrivilegedHelperRegistrationError) -> PrivilegedHelperStatus
  func openLoginItemsSettings()
}

public struct PrivilegedHelperRegistration: PrivilegedHelperRegistering {
  private let daemon: any LaunchDaemonControlling
  public init(daemon: any LaunchDaemonControlling = SystemLaunchDaemon()) {
    self.daemon = daemon
  }
  public func status() -> PrivilegedHelperStatus { PrivilegedHelperStatus(daemon.status) }

  public func register() throws(PrivilegedHelperRegistrationError) -> PrivilegedHelperStatus {
    do {
      try daemon.register()
    } catch {
      let mapped = Self.registrationError(error)
      // A daemon awaiting approval may also report a generic error; its status is what counts.
      guard mapped != .notAllowed, [.enabled, .requiresApproval].contains(status()) else {
        throw mapped
      }
    }
    return status()
  }
  public func unregister() async throws(PrivilegedHelperRegistrationError) {
    do {
      try await daemon.unregister()
    } catch where Self.code(of: error) == kSMErrorJobNotFound {
      // Already unregistered.
    } catch {
      throw Self.registrationError(error)
    }
  }
  /// The SDK asks for unregister before register when the bundled executable changed.
  public func reregister() async throws(PrivilegedHelperRegistrationError)
    -> PrivilegedHelperStatus
  {
    try await unregister()
    return try register()
  }
  public func openLoginItemsSettings() { daemon.openSystemSettingsLoginItems() }

  private static func code(of error: any Error) -> Int? {
    let error = error as NSError
    return [SMAppServiceErrorDomain, NSOSStatusErrorDomain].contains(error.domain)
      ? error.code : nil
  }
  private static func registrationError(_ error: any Error) -> PrivilegedHelperRegistrationError {
    switch code(of: error) {
    case kSMErrorLaunchDeniedByUser: .notAllowed
    case kSMErrorInvalidSignature: .invalidSignature
    case kSMErrorJobPlistNotFound, kSMErrorToolNotValid, kSMErrorJobNotFound: .notFound
    default: .failed(error.localizedDescription)
    }
  }
}

// Only an administrator can approve the helper, and it serves full readings only to them.
public enum AccountMembership {
  public static func isAdministrator(_ userID: UInt32 = getuid()) -> Bool {
    sb_user_is_administrator(userID)
  }
}
