import StrataCore
import SwiftUI

struct CPUContent: View {
  @ObservedObject var model: AppModel
  let openExplorer: (ExplorerDestination) -> Void
  var body: some View {
    MetricHero(
      value: model.value(for: .cpu), caption: "of total CPU capacity",
      values: model.historyValues(for: .cpu), timestamps: model.history.points.map(\.uptime),
      color: Reading.cpu.tint
    ).help("A process can use up to 100% of each logical core.")
    MeasureLeaders(model: model, measure: .cpu, openExplorer: openExplorer)
    if let sample = model.sample, !sample.cores.isEmpty {
      SurfaceCard {
        VStack(alignment: .leading, spacing: Design.Spacing.medium) {
          SectionHeading("\(sample.cores.count) logical cores")
          HStack(alignment: .bottom, spacing: Design.Spacing.xSmall) {
            ForEach(Array(sample.cores.enumerated()), id: \.offset) { index, value in
              RoundedRectangle(cornerRadius: 3).fill(
                value == nil
                  ? Color.secondary.opacity(0.15) : Reading.cpu.tint.opacity(0.2 + (value ?? 0) * 0.8)
              )
              .frame(height: max(4, (value ?? 0) * 42))
              .frame(maxHeight: 42, alignment: .bottom)
              .help("Core \(index + 1): \(ValueFormat.percent(value))")
            }
          }.frame(height: 42)
          DetailRow(label: "Thermal pressure", value: sample.thermalPressure.rawValue.capitalized)
        }
      }
    }
    RecordedHistory(model: model, metric: .cpu, color: Reading.cpu.tint)
  }
}

struct GPUContent: View {
  @ObservedObject var model: AppModel
  let openExplorer: (ExplorerDestination) -> Void
  @State private var openedAt = Date.now
  // The GPU is read from the next reading on, so a missing value is a wait before it is a lack.
  private static let firstReadingWait: TimeInterval = 5
  var body: some View {
    if let gpu = model.sample?.gpu {
      MetricHero(
        value: model.value(for: .gpu),
        caption: gpu.model.map { "of the \($0) GPU's capacity" } ?? "of GPU capacity",
        values: model.historyValues(for: .gpu), timestamps: model.history.points.map(\.uptime),
        color: Reading.gpu.tint)
      MeasureLeaders(model: model, measure: .gpu, openExplorer: openExplorer)
      SurfaceCard {
        VStack(spacing: Design.Spacing.medium) {
          DetailRow(label: "Rendering", value: ValueFormat.percent(gpu.rendererUtilization))
          DetailRow(label: "Geometry", value: ValueFormat.percent(gpu.tilerUtilization))
          DetailRow(
            label: "Memory in use",
            value: gpu.inUseSystemMemoryBytes.map(ValueFormat.bytes) ?? ReadingValue.unavailable
          ).help("Shared with the rest of the Mac, so it counts toward Memory.")
        }
      }
      RecordedHistory(model: model, metric: .gpu, color: Reading.gpu.tint)
    } else if Date.now.timeIntervalSince(openedAt) < Self.firstReadingWait {
      LoadingState("Reading the GPU…")
    } else {
      EmptyState(
        symbol: Reading.gpu.symbol, title: "GPU readings unavailable",
        detail: "macOS reports no GPU statistics on this Mac.")
    }
  }
}

struct MemoryContent: View {
  @ObservedObject var model: AppModel
  let openExplorer: (ExplorerDestination) -> Void
  var body: some View {
    MetricHero(
      value: model.value(for: .memory),
      caption: model.sample?.memory.map {
        "used of \(ValueFormat.bytes($0.total)) · pressure \($0.pressure.rawValue)"
      } ?? "Waiting for memory data",
      values: model.historyValues(for: .memory), timestamps: model.history.points.map(\.uptime),
      color: Reading.memory.tint
    ).help("Used is active + wired + compressed memory.")
    MeasureLeaders(model: model, measure: .memory, openExplorer: openExplorer)
    if let memory = model.sample?.memory {
      SurfaceCard {
        VStack(spacing: Design.Spacing.medium) {
          DetailRow(label: "Active", value: ValueFormat.bytes(memory.active))
          DetailRow(label: "Wired", value: ValueFormat.bytes(memory.wired))
          DetailRow(label: "Compressed", value: ValueFormat.bytes(memory.compressed))
          DetailRow(label: "Inactive / cache", value: ValueFormat.bytes(memory.cached))
          DetailRow(
            label: "Swap used",
            value: memory.swap.map(ValueFormat.bytes) ?? ReadingValue.unavailable)
        }
      }
    }
    RecordedHistory(model: model, metric: .memoryUsed, color: Reading.memory.tint)
  }
}

struct DiskContent: View {
  @ObservedObject var model: AppModel
  let openExplorer: (ExplorerDestination) -> Void
  var body: some View {
    if let startup = model.devices?.volumes.first {
      MetricHero(
        value: ValueFormat.bytes(startup.available),
        caption: "available on \(startup.name) · \(ValueFormat.bytes(startup.total)) capacity",
        color: Reading.disk.tint, capacity: startup.usedFraction)
    } else if model.devices == nil {
      LoadingState("Reading volumes…")
    }
    MeasureLeaders(model: model, measure: .diskWrites, openExplorer: openExplorer)
    if let activity = model.sample?.observedDiskActivity {
      SurfaceCard {
        VStack(alignment: .leading, spacing: Design.Spacing.medium) {
          SectionHeading("Activity")
          DetailRow(label: "Reads", value: ValueFormat.rate(activity.read))
          rateSparkline(model.history.points.map(\.diskRead), color: Reading.disk.tint)
          DetailRow(label: "Writes", value: ValueFormat.rate(activity.written))
          rateSparkline(model.history.points.map(\.diskWritten), color: Design.violet)
        }
      }
    }
    volumes
    ExplorerLink(title: "Explore Open Files") { openExplorer(.resources(nil)) }
  }
  private func rateSparkline(_ values: [Double?], color: Color) -> some View {
    Sparkline(
      values: values, timestamps: model.history.points.map(\.uptime), color: color,
      maximum: max(1000, values.compactMap { $0 }.max() ?? 0), showsRate: true
    ).frame(height: 30)
  }
  @ViewBuilder private var volumes: some View {
    if let volumes = model.devices?.volumes {
      ItemsCard(title: "Volumes") {
        if volumes.isEmpty {
          Text("Mounted local volumes appear here.").font(Design.Typography.body)
            .foregroundStyle(.secondary)
        }
        ForEach(volumes) { volume in
          if volume.id != volumes.first?.id { Divider() }
          VStack(alignment: .leading, spacing: Design.Spacing.small) {
            HStack {
              Label(volume.name, systemImage: "internaldrive").font(Design.Typography.itemTitle)
              Spacer()
              Text("\(ValueFormat.bytes(volume.available)) of \(ValueFormat.bytes(volume.total))")
                .font(Design.Typography.footnote).monospacedDigit().foregroundStyle(.secondary)
            }
            ProgressView(value: volume.usedFraction).tint(Reading.disk.tint)
            if let identity = volume.fileSystem {
              Button("Find Open Files") {
                openExplorer(
                  .volume(
                    VolumeResourceScope(
                      identity: identity, name: volume.name, mountPath: volume.url.path)))
              }.buttonStyle(.link).font(Design.Typography.footnote)
            }
          }.padding(.vertical, Design.Spacing.xSmall)
        }
      }
    }
  }
}

struct NetworkContent: View {
  @ObservedObject var model: AppModel
  let openExplorer: (ExplorerDestination) -> Void
  var body: some View {
    MetricHero(
      value: model.value(for: .network),
      caption: "download · \(ValueFormat.rate(model.sample?.network?.sent)) upload",
      values: model.historyValues(for: .network), timestamps: model.history.points.map(\.uptime),
      color: Reading.network.tint,
      maximum: max(1000, model.history.points.compactMap(\.download).max() ?? 0), showsRate: true
    ).help("Physical Ethernet and Wi-Fi traffic; tunnels are left out so nothing counts twice.")
    NetworkLeaders(model: model, openExplorer: openExplorer)
      .help("Measured with Apple's nettop while this tab is open.")
    SurfaceCard {
      VStack(spacing: Design.Spacing.medium) {
        DetailRow(label: "Download", value: ValueFormat.rate(model.sample?.network?.received))
        DetailRow(label: "Upload", value: ValueFormat.rate(model.sample?.network?.sent))
        DetailRow(label: "Measured interfaces", value: measuredInterfaces)
      }
    }
    RecordedHistory(model: model, metric: .networkIn, color: Reading.network.tint, formatsRate: true)
    ItemsCard(title: "Find a port") { PortLookup(openExplorer: openExplorer) }
    ExplorerLink(title: "Explore Processes and Ports") { openExplorer(.ports) }
  }
  private var measuredInterfaces: String {
    ReadingValue.text(observing: model.sample?.interfaces) { interfaces in
      interfaces.isEmpty ? nil : interfaces.joined(separator: ", ")
    }
  }
}

struct MetricHero: View {
  let value: String
  let caption: String
  var values: [Double?] = []
  var timestamps: [TimeInterval] = []
  var color: Color = Design.mint
  var maximum: Double = 1
  var showsRate = false
  // A fill bar for amounts with a total, such as disk space, in place of a trend.
  var capacity: Double?
  var body: some View {
    VStack(alignment: .leading, spacing: Design.Spacing.small) {
      Text(value).font(Design.Typography.hero).monospacedDigit().lineLimit(1)
        .minimumScaleFactor(0.5)
      Text(caption).font(Design.Typography.secondary).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      if let capacity {
        ProgressView(value: capacity).tint(color).padding(.top, Design.Spacing.small)
      } else if !values.isEmpty {
        Sparkline(
          values: values, timestamps: timestamps, color: color, maximum: maximum,
          showsRate: showsRate
        ).frame(height: 70).padding(.top, Design.Spacing.medium)
        HStack {
          Text("60s ago")
          Spacer()
          Text("Now")
        }.font(Design.Typography.footnote.monospaced()).foregroundStyle(.tertiary)
      }
    }.padding(.bottom, Design.Spacing.xSmall)
  }
}

struct RecordedHistory: View {
  @ObservedObject var model: AppModel
  let metric: HistoryMetric
  let color: Color
  var formatsRate = false
  var body: some View {
    if let recorder = model.historyRecorder, recorder.isRecording {
      LongHistoryChart(recorder: recorder, metric: metric, color: color, formatsRate: formatsRate)
    }
  }
}

// Finds the process holding a port; the Explorer then offers to stop it with confirmation.
private struct PortLookup: View {
  let openExplorer: (ExplorerDestination) -> Void
  @State private var text = ""
  private var port: UInt16? { UInt16(text.trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 : nil } }
  var body: some View {
    HStack(spacing: Design.Spacing.small) {
      TextField("Port", text: $text, prompt: Text("What's using port…"))
        .textFieldStyle(.roundedBorder).onSubmit(lookUp)
        .accessibilityLabel("Port number")
      Button("Find", action: lookUp).disabled(port == nil)
    }
  }
  private func lookUp() {
    guard let port else { return }
    openExplorer(.port(port))
  }
}

// Processes ranked by their combined traffic since the previous reading.
private struct NetworkLeaders: View {
  @ObservedObject var model: AppModel
  let openExplorer: (ExplorerDestination) -> Void
  var body: some View {
    ProcessLeaders(
      title: "Sending and receiving the most", rows: rows, emptyText: emptyText,
      select: { openExplorer(.processes($0)) })
  }
  private var emptyText: Text {
    switch model.networkUsage {
    case .measuring: Text("Measuring traffic…")
    case .unavailable: Text(ReadingValue.unavailable)
    case .measured: Text("No process is sending or receiving right now.")
    }
  }
  private var rows: [LeaderRow] {
    let rates = model.networkUsage.rates
    return model.processes.compactMap { process in
      rates[process.id].flatMap { $0.received + $0.sent > 0 ? (process, $0) : nil }
    }
    .sorted { $0.1.received + $0.1.sent > $1.1.received + $1.1.sent }
    .prefix(LeaderMeasure.shownCount)
    .map { process, rate in
      LeaderRow(
        id: process.id, name: process.displayName,
        value: "↓ \(ValueFormat.rate(rate.received)) ↑ \(ValueFormat.rate(rate.sent))")
    }
  }
}
