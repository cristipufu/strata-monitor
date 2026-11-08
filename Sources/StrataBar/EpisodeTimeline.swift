import StrataCore
import SwiftUI

// What happened while you weren't looking: sustained CPU, power, memory growth and wakeups,
// newest first, from the history kept on this Mac.
struct EpisodeTimeline: View {
  @ObservedObject var model: AppModel
  let select: (ProcessIdentity) -> Void
  var body: some View {
    if let recorder = model.historyRecorder, recorder.isRecording {
      EpisodeList(recorder: recorder, model: model, select: select)
    } else {
      EmptyState(
        symbol: "clock.arrow.circlepath", title: String(localized: "History is off"),
        detail: String(localized: "Turn on Keep history in Settings › General to see what your Mac was busy with."))
    }
  }
}

private struct EpisodeList: View {
  @ObservedObject var recorder: HistoryRecorder
  @ObservedObject var model: AppModel
  let select: (ProcessIdentity) -> Void
  var body: some View {
    let episodes = recorder.episodes.sorted { $0.start > $1.start }
    if episodes.isEmpty {
      EmptyState(
        symbol: "checkmark.circle", title: String(localized: "Nothing unusual yet"),
        detail: String(localized: "Processes that stay busy, draw power, grow in memory or wake the Mac often appear here."))
    } else {
      let running = Set(model.processes.map(\.id))
      List(episodes) { episode in
        let isRunning = episode.process.map { running.contains($0.identity) } ?? false
        Button { episode.process.map { select($0.identity) } } label: {
          EpisodeRow(episode: episode, isRunning: isRunning)
        }.buttonStyle(.plain).disabled(!isRunning)
      }
    }
  }
}

private struct EpisodeRow: View {
  let episode: Episode
  let isRunning: Bool
  var body: some View {
    HStack(spacing: Design.Spacing.medium) {
      Image(systemName: Self.symbol(episode.kind)).font(Design.Typography.tileSymbol)
        .foregroundStyle(Design.mint).frame(width: 22)
      VStack(alignment: .leading, spacing: Design.Spacing.xxSmall) {
        Text(title).font(Design.Typography.itemTitle)
        Text(detail).footnoteStyle()
      }
      Spacer(minLength: Design.Spacing.medium)
      if !isRunning && episode.process != nil {
        Text("Ended").footnoteStyle()
      }
    }.padding(.vertical, Design.Spacing.xSmall)
  }
  private var title: String {
    let subject =
      episode.process.map { label in label.project.map { "\(label.name) · \($0)" } ?? label.name }
      ?? String(localized: "Your Mac")
    return "\(subject) — \(Self.measure(episode))"
  }
  private var detail: String {
    let start = episode.start.formatted(date: .abbreviated, time: .shortened)
    guard let end = episode.end else { return String(localized: "\(start) · ongoing") }
    let duration = Duration.seconds(max(60, end.timeIntervalSince(episode.start))).formatted(
      .units(allowed: [.hours, .minutes], width: .abbreviated))
    return "\(start) · \(duration)"
  }
  private static func measure(_ episode: Episode) -> String {
    switch episode.kind {
    case .cpu: String(localized: "\(Int(episode.average))% CPU, peak \(Int(episode.peak))%")
    case .watts: String(localized: "\(ValueFormat.watts(episode.average)), peak \(ValueFormat.watts(episode.peak))")
    case .memoryGrowth: String(localized: "grew \(ValueFormat.bytes(UInt64(max(0, episode.peak))))")
    case .wakeups: String(localized: "\(ValueFormat.perSecond(episode.average)) wakeups")
    case .systemCPU: String(localized: "CPU \(ValueFormat.percent(episode.average)) busy")
    case .memoryPressure: String(localized: "memory pressure high")
    }
  }
  private static func symbol(_ kind: EpisodeKind) -> String {
    switch kind {
    case .cpu, .systemCPU: "flame"
    case .watts: "bolt"
    case .memoryGrowth, .memoryPressure: "memorychip"
    case .wakeups: "alarm"
    }
  }
}
