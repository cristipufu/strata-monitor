import CSystem
import Foundation
import StrataCore

package enum NativeProcessInventory {
  package static func read() -> ProcessInventory {
    var count = 0
    var paths: UnsafeMutablePointer<CChar>?
    var status = SBScanStatus()
    guard let buffer = sb_processes(&count, &paths, &status) else {
      return ProcessInventory(processes: [], summary: scanSummary(status))
    }
    let capturedAt = ProcessInfo.processInfo.systemUptime
    defer {
      sb_free(buffer)
      sb_free(paths)
    }
    let processes = UnsafeBufferPointer(start: buffer, count: count).map { sample($0, paths: paths) }
    return ProcessInventory(processes: processes, summary: scanSummary(status), capturedAt: capturedAt)
  }
  package static func displayName(path: String, shortName: String) -> String {
    guard let slash = path.lastIndex(of: "/") else { return path.isEmpty ? shortName : path }
    let name = path[path.index(after: slash)...]
    return name.isEmpty ? shortName : String(name)
  }
  private static func sample(_ raw: SBProcess, paths: UnsafePointer<CChar>?) -> ProcessSample {
    let path = paths.map { path(at: raw.path_offset, length: raw.path_length, in: $0) } ?? ""
    var shortName = raw.name
    return ProcessSample(
      id: ProcessIdentity(
        pid: raw.pid, startSeconds: raw.start_seconds, startMicroseconds: raw.start_microseconds),
      parentPID: raw.parent_pid, userID: raw.uid,
      name: displayName(path: path, shortName: cString(&shortName)),
      path: path,
      cpuTimeNanoseconds: raw.usage_valid ? raw.cpu_ns : nil,
      residentBytes: raw.usage_valid ? raw.resident : nil,
      footprintBytes: raw.rusage_valid ? raw.footprint : nil,
      threads: raw.usage_valid ? Int(raw.threads) : nil,
      diskReadBytes: raw.rusage_valid ? raw.disk_read : nil,
      diskWrittenBytes: raw.rusage_valid ? raw.disk_written : nil,
      runState: runState(raw.run_state), isTranslated: raw.translated,
      activity: raw.rusage_valid ? activity(raw) : nil)
  }
  private static func activity(_ raw: SBProcess) -> ProcessActivityCounters {
    ProcessActivityCounters(
      energyNanojoules: raw.energy_nj, wakeups: raw.wakeups, instructions: raw.instructions,
      cycles: raw.cycles, performanceCoreNanoseconds: raw.performance_cpu_ns,
      peakFootprintBytes: raw.peak_footprint)
  }
  private static func path(at offset: UInt32, length: UInt32, in paths: UnsafePointer<CChar>) -> String {
    String(
      decoding: UnsafeRawBufferPointer(start: paths + Int(offset), count: Int(length)), as: UTF8.self)
  }
  private static func cString<Field>(_ field: UnsafePointer<Field>) -> String {
    let capacity = MemoryLayout<Field>.size
    return UnsafeRawPointer(field).withMemoryRebound(to: CChar.self, capacity: capacity) { text in
      String(
        decoding: UnsafeRawBufferPointer(start: text, count: strnlen(text, capacity)), as: UTF8.self)
    }
  }
  package static func runState(_ kernelState: Int32) -> ProcessRunState? {
    switch kernelState {
    case Int32(SIDL): .starting
    case Int32(SRUN), Int32(SSLEEP): .running
    case Int32(SSTOP): .stopped
    case Int32(SZOMB): .zombie
    default: nil
    }
  }
}

package enum NativeProcessIdentity {
  package static func isCurrent(_ identity: ProcessIdentity) -> Bool {
    sb_process_identity(identity.pid, identity.startSeconds, identity.startMicroseconds)
  }
  package static func isRunning(_ pid: Int32) -> Bool {
    var seconds: UInt64 = 0
    var microseconds: UInt64 = 0
    return sb_process_start_time(pid, &seconds, &microseconds)
  }
  package static func owner(of pid: Int32) -> uid_t? { record(of: pid)?.owner }
  /// Identity and effective owner from one read of the kernel's record, so neither can change
  /// between the two.
  package static func record(of pid: Int32) -> (identity: ProcessIdentity, owner: uid_t)? {
    var query: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    // A pid with no process answers success with an empty record.
    guard pid > 0, sysctl(&query, 4, &info, &size, nil, 0) == 0,
      size == MemoryLayout<kinfo_proc>.stride
    else { return nil }
    let identity = ProcessIdentity(
      pid: pid, startSeconds: UInt64(info.kp_proc.p_starttime.tv_sec),
      startMicroseconds: UInt64(info.kp_proc.p_starttime.tv_usec))
    return (identity, info.kp_eproc.e_ucred.cr_uid)
  }
  // libproc's PROC_PIDPATHINFO_MAXSIZE, a macro Swift does not import.
  private static let pathCapacity = Int(MAXPATHLEN) * 4
  package static func name(of pid: Int32) -> String {
    var path = [CChar](repeating: 0, count: pathCapacity)
    let pathLength = proc_pidpath(pid, &path, UInt32(path.count))
    if pathLength > 0 {
      return NativeProcessInventory.displayName(
        path: string(path, length: pathLength), shortName: "")
    }
    var shortName = [CChar](repeating: 0, count: 2 * Int(MAXCOMLEN) + 1)
    let nameLength = proc_name(pid, &shortName, UInt32(shortName.count))
    return nameLength > 0 ? string(shortName, length: nameLength) : ""
  }
  private static func string(_ buffer: [CChar], length: Int32) -> String {
    let bytes = buffer.prefix(Int(length)).prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return String(decoding: bytes, as: UTF8.self)
  }
}
