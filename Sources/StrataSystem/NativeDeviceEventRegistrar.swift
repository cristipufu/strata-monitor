import AppKit
import CSystem
import CoreAudio
import Foundation
import IOKit.ps

/// Cancellation is serialized. Captures contain immutable SDK handles and listener blocks whose
/// bodies only invoke a Sendable callback. The exact original HAL block is retained until removal.
private final class NativeDeviceEventRegistration: DeviceEventRegistration, @unchecked Sendable {
  private let lock = NSLock()
  private var cancellation: (() -> DeviceEventFailure?)?
  init(cancel: @escaping () -> DeviceEventFailure?) { cancellation = cancel }
  func cancel() -> DeviceEventFailure? {
    let action = lock.withLock {
      let action = cancellation
      cancellation = nil
      return action
    }
    return action?()
  }
  deinit { _ = cancel() }
}

struct NativeDeviceEventRegistrar: DeviceEventRegistering {
  private let workspaceCenter: NotificationCenter
  private let defaultCenter: NotificationCenter
  private let queue = DispatchQueue(label: "dev.strata.bar.device-events", qos: .utility)
  init(workspaceCenter: NotificationCenter, defaultCenter: NotificationCenter) {
    self.workspaceCenter = workspaceCenter
    self.defaultCenter = defaultCenter
  }
  func register(_ channel: DeviceEventChannel, change: @escaping @Sendable () -> Void) throws
    -> any DeviceEventRegistration
  {
    switch channel {
    case .power: return try registerPower(change)
    case .lowPowerMode:
      return notification(.NSProcessInfoPowerStateDidChange, center: defaultCenter, change: change)
    case .volumeMounted:
      return notification(NSWorkspace.didMountNotification, center: workspaceCenter, change: change)
    case .volumeUnmounted:
      return notification(
        NSWorkspace.didUnmountNotification, center: workspaceCenter, change: change)
    case .volumeRenamed:
      return notification(
        NSWorkspace.didRenameVolumeNotification, center: workspaceCenter, change: change)
    case .displays:
      return notification(
        NSApplication.didChangeScreenParametersNotification, center: defaultCenter, change: change)
    default: return try registerAudio(channel, change: change)
    }
  }
  private func notification(
    _ name: Notification.Name, center: NotificationCenter, change: @escaping @Sendable () -> Void
  ) -> any DeviceEventRegistration {
    let observer = center.addObserver(forName: name, object: nil, queue: nil) { _ in change() }
    return NativeDeviceEventRegistration {
      center.removeObserver(observer)
      return nil
    }
  }
  private func registerPower(_ change: @escaping @Sendable () -> Void) throws
    -> any DeviceEventRegistration
  {
    var token: Int32 = 0
    let status = sb_observe_dispatch_notification(
      kIOPSNotifyPowerSource, { change() }, &token)
    guard status == 0 else {
      throw DeviceEventFailure(
        channel: "power", operation: "register", status: Int32(bitPattern: status))
    }
    let registeredToken = token
    return NativeDeviceEventRegistration {
      let result = sb_cancel_dispatch_notification(registeredToken)
      return result == 0
        ? nil
        : DeviceEventFailure(
          channel: "power", operation: "remove", status: Int32(bitPattern: result))
    }
  }
  private func registerAudio(_ channel: DeviceEventChannel, change: @escaping @Sendable () -> Void)
    throws -> any DeviceEventRegistration
  {
    let (object, selector, scope) = try audioProperty(channel)
    var property = AudioObjectPropertyAddress(
      mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    let listener: AudioObjectPropertyListenerBlock = { _, _ in change() }
    let status = AudioObjectAddPropertyListenerBlock(object, &property, queue, listener)
    guard status == noErr else {
      throw DeviceEventFailure(
        channel: String(describing: channel), operation: "register", status: status)
    }
    let originalProperty = property
    return NativeDeviceEventRegistration {
      var address = originalProperty
      let result = AudioObjectRemovePropertyListenerBlock(object, &address, queue, listener)
      return result == noErr
        ? nil
        : DeviceEventFailure(
          channel: String(describing: channel), operation: "remove", status: result)
    }
  }
  private func audioProperty(_ channel: DeviceEventChannel) throws -> (
    UInt32, AudioObjectPropertySelector, AudioObjectPropertyScope
  ) {
    let global = kAudioObjectPropertyScopeGlobal
    let output = kAudioDevicePropertyScopeOutput
    switch channel {
    case .audioDevices:
      return (AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices, global)
    case .defaultAudioOutput:
      return (
        AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, global
      )
    case .audioVolume(let id): return (id, kAudioDevicePropertyVolumeScalar, output)
    case .audioMute(let id): return (id, kAudioDevicePropertyMute, output)
    case .audioName(let id): return (id, kAudioObjectPropertyName, global)
    case .audioIdentity(let id): return (id, kAudioDevicePropertyDeviceUID, global)
    default:
      throw DeviceEventFailure(
        channel: String(describing: channel), operation: "register",
        status: kAudioHardwareUnknownPropertyError)
    }
  }
}
