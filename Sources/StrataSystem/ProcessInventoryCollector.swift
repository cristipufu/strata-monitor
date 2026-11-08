import Foundation
import StrataCore
import StrataInventory

public protocol ProcessListing: Sendable {
  func inventory() async -> ProcessInventory
}
public actor ProcessInventoryCollector: ProcessListing {
  public init() {}
  public func inventory() -> ProcessInventory { NativeProcessInventory.read() }
}
