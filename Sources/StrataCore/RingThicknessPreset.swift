public enum RingThicknessPreset: Int, CaseIterable, Sendable {
  case thin, light, regular, bold, heavy

  public var thickness: Double {
    switch self {
    case .thin: 1
    case .light: 1.4
    case .regular: 1.8
    case .bold: 2.4
    case .heavy: 3
    }
  }
  public var title: String {
    switch self {
    case .thin: "Thin"
    case .light: "Light"
    case .regular: "Regular"
    case .bold: "Bold"
    case .heavy: "Heavy"
    }
  }
  public static func nearest(to thickness: Double) -> Self {
    guard thickness.isFinite else { return .regular }
    return allCases.min { abs($0.thickness - thickness) < abs($1.thickness - thickness) }
      ?? .regular
  }
}
