import StrataCore
import SwiftUI

// The last hour or day of one reading from the history kept on this Mac. Gaps, such as sleep,
// break the line instead of being bridged.
struct LongHistoryChart: View {
  enum Span: Int, CaseIterable, Identifiable {
    case hour = 3600
    case day = 86_400
    var id: Self { self }
    var title: LocalizedStringKey { self == .hour ? "Last hour" : "Last 24 hours" }
  }
  @ObservedObject var recorder: HistoryRecorder
  let metric: HistoryMetric
  var color: Color = Design.mint
  var formatsRate = false
  @State private var span = Span.hour
  @State private var points: [HistorySummaryPoint] = []
  private static let refresh: Duration = .seconds(10)

  var body: some View {
    SurfaceCard {
      VStack(alignment: .leading, spacing: Design.Spacing.medium) {
        Picker("History", selection: $span) {
          ForEach(Span.allCases) { Text($0.title).tag($0) }
        }.pickerStyle(.segmented).labelsHidden()
        HistoryLineCanvas(
          points: points, metric: metric, span: TimeInterval(span.rawValue), color: color,
          ceiling: ceiling
        ).frame(height: 60)
        HStack {
          Text(peakText).footnoteStyle()
          Spacer()
          Text("Now").footnoteStyle()
        }
      }
    }
    .task(id: span) {
      while !Task.isCancelled {
        points = await recorder.points(last: TimeInterval(span.rawValue))
        do { try await Task.sleep(for: Self.refresh) } catch { return }
      }
    }
  }
  private var maximum: Double? { points.compactMap { $0[metric]?.maximum }.max() }
  private var ceiling: Double {
    formatsRate ? Sparkline.roundedCeiling(max(1000, maximum ?? 0)) : 1
  }
  private var peakText: String {
    guard let maximum else { return String(localized: "Collecting history…") }
    let value = formatsRate ? ValueFormat.rate(maximum) : ValueFormat.percent(maximum)
    return String(localized: "Peak \(value)")
  }
}

private struct HistoryLineCanvas: View {
  let points: [HistorySummaryPoint]
  let metric: HistoryMetric
  let span: TimeInterval
  let color: Color
  let ceiling: Double
  var body: some View {
    Canvas { context, size in
      let end = Date()
      let start = end.addingTimeInterval(-span)
      var line = Path()
      var previous: HistorySummaryPoint?
      for point in points {
        guard let value = point[metric]?.mean, value.isFinite else {
          previous = nil
          continue
        }
        let x = size.width * max(0, min(1, point.time.timeIntervalSince(start) / span))
        let y = size.height - min(1, max(0, value / ceiling)) * (size.height - 4) - 2
        let joins = previous.map { point.time.timeIntervalSince($0.end) <= 2.5 * point.duration } ?? false
        if joins { line.addLine(to: CGPoint(x: x, y: y)) } else { line.move(to: CGPoint(x: x, y: y)) }
        previous = point
      }
      context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
    }
    .accessibilityLabel("History")
  }
}
