import StrataCore
import Testing

@Test func bluetoothMomentsCoalesceConnectedDevicesAndResetAfterUnavailableObservations() {
  var detector = MomentDetector()
  #expect(detector.observeBluetooth(connectedDevices: ["a": "Headphones"]) == nil)
  #expect(detector.observeBluetooth(connectedDevices: ["a": "Renamed headphones"]) == nil)
  #expect(
    detector.observeBluetooth(connectedDevices: ["a": "Headphones", "b": "Keyboard"])?.title
      == "Keyboard connected")
  #expect(
    detector.observeBluetooth(connectedDevices: ["a": "Headphones"])?.title
      == "Keyboard disconnected")
  #expect(
    detector.observeBluetooth(connectedDevices: ["b": "Keyboard"])?.title
      == "Bluetooth devices changed")
  #expect(detector.observeBluetooth(connectedDevices: [:])?.title == "Keyboard disconnected")
  #expect(
    detector.observeBluetooth(connectedDevices: ["a": "Headphones", "b": "Keyboard"])?.title
      == "2 devices connected")
  #expect(detector.observeBluetooth(connectedDevices: nil) == nil)
  #expect(detector.observeBluetooth(connectedDevices: [:]) == nil)
  detector.reset()
  #expect(detector.observeBluetooth(connectedDevices: ["a": "Headphones"]) == nil)
}
@Test func volumeMomentsCoalesceChangesWithoutStartupOrWakeReplay() {
  func volumes(_ names: [String: String]?) -> DeviceObservation {
    DeviceObservation(
      batteryFraction: nil, externalPower: nil, muted: nil, outputName: "Speakers",
      volumeNamesByID: names)
  }
  var detector = MomentDetector()
  #expect(detector.observe(volumes(["/": "Macintosh HD"])) == nil)
  #expect(
    detector.observe(volumes(["/": "Macintosh HD", "/Volumes/Work": "Work"]))?.title
      == "Work mounted")
  #expect(detector.observe(volumes(["/": "Macintosh HD"]))?.title == "Work disconnected")
  #expect(detector.observe(volumes(nil)) == nil)
  #expect(detector.observe(volumes(["/Volumes/A": "A", "/Volumes/B": "B"])) == nil)
  #expect(detector.observe(volumes([:]))?.title == "2 drives disconnected")
  detector.reset()
  #expect(detector.observe(volumes(["/": "Macintosh HD"])) == nil)
}

@Test func signalHysteresisPreventsBoundaryFlicker() {
  var policy = SignalStrengthPolicy()
  #expect(policy.update(rssi: -60) == .strong)
  for rssi in [-62, -63, -61, -64] { #expect(policy.update(rssi: rssi) == .strong) }
  #expect(policy.update(rssi: -67) == .fair)
  #expect(policy.update(rssi: -62) == .fair)
  #expect(policy.update(rssi: -58) == .strong)
  #expect(policy.update(rssi: -95) == .weak)
  #expect(policy.update(rssi: 0) == nil)
}

private func observation(
  _ fraction: Double, power: Bool = false, muted: Bool = false, output: String = "Speakers"
) -> DeviceObservation {
  DeviceObservation(
    batteryFraction: fraction, externalPower: power, muted: muted, outputName: output)
}

@Test func lowBatteryMomentsRequireCrossingAndRecovery() {
  var detector = MomentDetector()
  #expect(detector.observe(observation(0.5)) == nil)
  #expect(detector.observe(observation(0.15))?.priority == 3)
  #expect(detector.observe(observation(0.16)) == nil)
  #expect(detector.observe(observation(0.14)) == nil)
  #expect(detector.observe(observation(0.21))?.title == "Battery recovered")
  #expect(detector.observe(observation(0.14))?.title == "Battery is low")
}

@Test func firstObservationAndWakeDoNotReplayDeviceEvents() {
  var detector = MomentDetector()
  #expect(detector.observe(observation(0.1, power: true, muted: true)) == nil)
  #expect(detector.observe(observation(0.1, power: true, muted: true)) == nil)
  detector.reset()
  #expect(detector.observe(observation(0.8)) == nil)
  #expect(detector.observe(connection: .offline) == nil)
  #expect(detector.observe(connection: .connecting) == nil)
  #expect(detector.observe(connection: .wifi)?.title == "Network available")
  #expect(detector.observe(connection: .wired) == nil)
}

@Test func higherPriorityDeviceEventsWinWithoutUnboundedQueueing() {
  var detector = MomentDetector()
  _ = detector.observe(observation(0.5))
  let moment = detector.observe(observation(0.1, power: true, muted: true, output: "Headphones"))
  #expect(moment?.title == "Battery is low")
  #expect(detector.observe(observation(0.1, power: true, muted: true, output: "Headphones")) == nil)
}

@Test func unavailableAudioObservationDoesNotInventAnOutputChangeOrReplayRecovery() {
  var detector = MomentDetector()
  func observation(_ output: String?) -> DeviceObservation {
    DeviceObservation(batteryFraction: nil, externalPower: nil, muted: nil, outputName: output)
  }
  #expect(detector.observe(observation("Speaker")) == nil)
  #expect(detector.observe(observation(nil)) == nil)
  #expect(detector.observe(observation("Headphones")) == nil)
  #expect(detector.observe(observation("Monitor"))?.title == "Monitor")
}
