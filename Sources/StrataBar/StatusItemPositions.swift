import Foundation

@MainActor enum StatusItemPositions {
  static func preserve(
    _ names: [String], in defaults: UserDefaults, during operation: () throws -> Void
  ) rethrows {
    let positions = Set(names).map { name in
      let key = "NSStatusItem Preferred Position \(name)"
      let value = (defaults.object(forKey: key) as? NSNumber).flatMap {
        $0.doubleValue.isFinite && $0.doubleValue >= 0 ? $0 : nil
      }
      return (key, value)
    }
    defer {
      for (key, value) in positions { defaults.set(value, forKey: key) }
    }
    try operation()
  }
}
