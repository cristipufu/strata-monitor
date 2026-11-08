import StrataCore
import SwiftUI

enum Design {
  static let panelWidth: CGFloat = 412
  enum Spacing {
    static let xxSmall: CGFloat = 2
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let xLarge: CGFloat = 24
  }
  enum Radius {
    static let panel: CGFloat = 26
    static let card: CGFloat = 18
    static let tile: CGFloat = 15
    static let banner: CGFloat = 12
    static let icon: CGFloat = 8
  }
  enum Typography {
    static let displayTitle = Font.system(.largeTitle, design: .rounded, weight: .semibold)
    static let lead = Font.title3
    static let pageTitle = Font.system(size: 20, weight: .semibold, design: .rounded)
    static let hero = Font.system(size: 43, weight: .light, design: .rounded)
    static let metric = Font.system(size: 27, weight: .medium, design: .rounded)
    // A rate carries its unit, so it needs a smaller face to fit a tile at a steady size.
    static let rateMetric = Font.system(size: 19, weight: .medium, design: .rounded)
    static let cardTitle = Font.headline
    static let itemTitle = Font.callout.weight(.medium)
    static let body = Font.callout
    static let secondary = Font.subheadline
    static let control = Font.subheadline.weight(.medium)
    static let footnote = Font.footnote
    static let label = Font.footnote.weight(.medium)
    static let sectionHeading = Font.system(size: 9, weight: .semibold)
    static let inlineSymbol = Font.system(size: 8, weight: .semibold)
    static let controlSymbol = Font.system(size: 12, weight: .medium)
    static let tileSymbol = Font.system(size: 14, weight: .medium)
    static let stateSymbol = Font.system(size: 30, weight: .light)
  }
  enum Symbol {
    static let explorer = "arrow.up.right"
    static let systemSettings = "arrow.up.forward.app"
    static let strataSettings = "gearshape"
  }
  static let mint = adaptiveColor(
    name: "StrataMint", light: NSColor(srgbRed: 0, green: 0.40, blue: 0.32, alpha: 1),
    dark: NSColor(srgbRed: 0.32, green: 0.94, blue: 0.76, alpha: 1))
  static let violet = adaptiveColor(
    name: "StrataViolet", light: NSColor(srgbRed: 0.42, green: 0.28, blue: 0.78, alpha: 1),
    dark: NSColor(srgbRed: 0.64, green: 0.53, blue: 0.96, alpha: 1))
  static let yellow = adaptiveColor(
    name: "StrataYellow", light: NSColor(srgbRed: 0.60, green: 0.42, blue: 0, alpha: 1),
    dark: NSColor(srgbRed: 0.99, green: 0.79, blue: 0.10, alpha: 1))
  static let orange = adaptiveColor(
    name: "StrataOrange", light: NSColor(srgbRed: 0.72, green: 0.31, blue: 0.03, alpha: 1),
    dark: NSColor(srgbRed: 1, green: 0.58, blue: 0.16, alpha: 1))
  private static func adaptiveColor(name: String, light: NSColor, dark: NSColor) -> Color {
    Color(
      nsColor: NSColor(name: NSColor.Name(name)) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
      })
  }
  static func accent(_ choice: Accent) -> Color {
    switch choice {
    case .automatic, .mint: mint
    case .monochrome: .primary
    case .blue: .blue
    case .teal: .teal
    case .violet: violet
    case .pink: .pink
    case .orange: orange
    case .red: .red
    }
  }
  // Matches the panel's AppKit frame animation so content and window edges land together.
  static func animation(reduced: Bool) -> Animation {
    reduced
      ? .easeOut(duration: MotionPolicy.reducedTransition)
      : .easeInOut(duration: MotionPolicy.transition)
  }
  // Readings inside windows change without motion. Every animation frame re-lays out and
  // redraws the whole window on the CPU, which made an open panel cost ten times more.
}

struct SurfaceCard<Content: View>: View {
  @ViewBuilder let content: Content
  var body: some View {
    content.padding(Design.Spacing.large).frame(maxWidth: .infinity, alignment: .leading)
      .surfaceBackground()
  }
}

private struct SurfaceBackground: ViewModifier {
  let cornerRadius: CGFloat
  @Environment(\.colorScheme) private var scheme
  func body(content: Content) -> some View {
    content
      .background(
        .white.opacity(scheme == .dark ? 0.055 : 0.48),
        in: RoundedRectangle(cornerRadius: cornerRadius)
      )
      .overlay(
        RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(
          .white.opacity(scheme == .dark ? 0.09 : 0.62), lineWidth: 0.7))
  }
}

extension View {
  func surfaceBackground(cornerRadius: CGFloat = Design.Radius.card) -> some View {
    modifier(SurfaceBackground(cornerRadius: cornerRadius))
  }
  func footnoteStyle() -> some View {
    font(Design.Typography.footnote).foregroundStyle(.secondary)
  }
}

struct SectionHeading: View {
  private let title: String
  init(_ title: String) { self.title = title }
  var body: some View {
    Text(title).font(Design.Typography.sectionHeading).tracking(1.1).textCase(.uppercase)
      .foregroundStyle(.secondary)
  }
}

struct SwitchRow: View {
  let title: String
  @Binding var isOn: Bool
  var body: some View {
    HStack {
      Text(title).font(Design.Typography.itemTitle)
      Spacer(minLength: Design.Spacing.medium)
      Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
    }
  }
}

struct DetailRow: View {
  let label: String
  let value: String
  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(label).foregroundStyle(.secondary)
      Spacer(minLength: Design.Spacing.medium)
      Text(value).monospacedDigit().multilineTextAlignment(.trailing).textSelection(.enabled)
    }.font(Design.Typography.body)
  }
}

struct LoadingState: View {
  private let title: String
  init(_ title: String) { self.title = title }
  var body: some View {
    ProgressView(title).controlSize(.small).frame(maxWidth: .infinity)
      .padding(.vertical, Design.Spacing.xLarge)
  }
}

struct EmptyState: View {
  let symbol: String
  let title: String
  let detail: String
  var body: some View {
    VStack(spacing: Design.Spacing.small) {
      Image(systemName: symbol).font(Design.Typography.stateSymbol).foregroundStyle(.secondary)
      Text(title).font(Design.Typography.cardTitle)
      Text(detail).font(Design.Typography.body).foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }.frame(maxWidth: .infinity).padding(Design.Spacing.xLarge)
  }
}

struct PermissionPrompt: View {
  enum Action {
    case request(String, @MainActor () -> Void)
    case openPrivacySettings(SystemSettings.PrivacyPane)
  }
  let explanation: String
  let action: Action
  var body: some View {
    VStack(alignment: .leading, spacing: Design.Spacing.small) {
      Text(explanation).font(Design.Typography.body).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      switch action {
      case .request(let title, let request):
        Button(title, action: request).buttonStyle(.glass)
      case .openPrivacySettings(let pane):
        Button {
          SystemSettings.openPrivacy(pane)
        } label: {
          Label("Open Privacy & Security…", systemImage: Design.Symbol.systemSettings)
        }.buttonStyle(.glass)
      }
    }
  }
}

struct Sparkline: View {
  let values: [Double?]
  var timestamps: [TimeInterval] = []
  var color: Color = Design.mint
  var maximum: Double = 1
  var showsRate = false
  var body: some View {
    let ceiling = showsRate ? Self.roundedCeiling(maximum) : max(0.001, maximum)
    SparklineCanvas(values: values, timestamps: timestamps, color: color, ceiling: ceiling)
      .accessibilityLabel("Recent history")
      .accessibilityValue(
        showsRate
          ? ValueFormat.rate(values.last.flatMap { $0 })
          : ValueFormat.percent(values.last.flatMap { $0 }))
  }
  // Rates rescale only when they cross a 1–2–5 step, not with every new peak.
  nonisolated static func roundedCeiling(_ value: Double) -> Double {
    guard value.isFinite, value > 0 else { return 1 }
    let magnitude = pow(10, floor(log10(value)))
    let step = [1.0, 2, 5, 10].first { $0 * magnitude >= value } ?? 10
    return step * magnitude
  }
}

private struct SparklineCanvas: View {
  let values: [Double?]
  let timestamps: [TimeInterval]
  let color: Color
  let ceiling: Double
  var body: some View {
    Canvas { context, size in
      var line = Path()
      var drawing = false
      for (index, value) in values.enumerated() {
        guard let value, value.isFinite else {
          drawing = false
          continue
        }
        guard timestamps.indices.contains(index), let latest = timestamps.last,
          let position = HistoryLayout.horizontalPosition(at: timestamps[index], latest: latest)
        else {
          drawing = false
          continue
        }
        let x = size.width * position
        let y = size.height - min(1, max(0, value / ceiling)) * (size.height - 4) - 2
        let point = CGPoint(x: x, y: y)
        if drawing {
          line.addLine(to: point)
        } else {
          line.move(to: point)
          drawing = true
        }
      }
      context.stroke(
        line, with: .color(color),
        style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
    }
  }
}
