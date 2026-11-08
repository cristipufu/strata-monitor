import CSystem
import Foundation
import StrataCore

package func nativeString<T>(_ value: T) -> String {
  var value = value
  return withUnsafeBytes(of: &value) { bytes in
    let prefix = bytes.prefix { $0 != 0 }
    return String(decoding: prefix, as: UTF8.self)
  }
}

package func scanSummary(_ status: SBScanStatus) -> ScanSummary {
  var summary = ScanSummary()
  summary.restricted = status.restricted
  summary.failed = status.error != 0 && status.error != ECANCELED
  summary.changedDuringScan = status.ended
  summary.truncated = status.truncated
  summary.unreadableHandles = Int(clamping: status.unreadable_descriptors)
  if summary.failed {
    summary.failureMessage =
      POSIXError(POSIXErrorCode(rawValue: status.error) ?? .EIO).localizedDescription
  }
  return summary
}

/// The C flag is atomic; the cancellation callback may run on any executor.
/// Its allocation stays alive through both the scan and its cancellation handler.
package final class NativeScanCancellation: @unchecked Sendable {
  package let handle: OpaquePointer
  package init() throws {
    guard let handle = sb_cancellation_create() else { throw POSIXError(.ENOMEM) }
    self.handle = handle
  }
  package func cancel() { sb_cancellation_cancel(handle) }
  deinit { sb_cancellation_destroy(handle) }
}
