import StrataCore
import SwiftUI

struct PopoverView: View {
  @ObservedObject var model: AppModel
  let openExplorer: (ExplorerDestination) -> Void
  let openSettings: () -> Void
  let preferHeight: (CGFloat) -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var headerHeight: CGFloat = 0
  @State private var footerHeight: CGFloat = 0
  @State private var contentHeight: CGFloat = 0
  @State private var scrollPosition = ScrollPosition(edge: .top)
  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 0) {
        header.padding(.horizontal, Design.Spacing.large).padding(.top, Design.Spacing.large)
          .padding(.bottom, Design.Spacing.medium)
        if let message = model.errorMessage {
          OperationErrorBanner(message: message) { model.errorMessage = nil }
            .padding(.horizontal, Design.Spacing.large).padding(.bottom, Design.Spacing.medium)
        }
        navigation.padding(.horizontal, Design.Spacing.large).padding(.bottom, Design.Spacing.small)
      }
      .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
        headerHeight = height
        reportPreferredHeight()
      }
      ScrollView {
        // Overlapping pages keep a page change from briefly stacking both pages' heights.
        ZStack(alignment: .top) {
          ReadingContent(model: model, reading: model.page, openExplorer: openExplorer)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Design.Spacing.large).padding(.top, Design.Spacing.small)
            .padding(.bottom, Design.Spacing.large)
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { [page = model.page] height in
              guard page == model.page else { return }
              contentHeight = height
              reportPreferredHeight()
            }
            .id(model.page)
            .transition(.opacity.combined(with: reduceMotion ? .identity : .offset(y: 5)))
        }
      }
      .scrollIndicators(.automatic)
      .scrollPosition($scrollPosition)
      .onChange(of: model.page) { scrollPosition.scrollTo(edge: .top) }
      VStack(spacing: 0) {
        Divider().opacity(0.5)
        footer.padding(.horizontal, Design.Spacing.large).padding(.vertical, Design.Spacing.medium)
      }
      .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
        footerHeight = height
        reportPreferredHeight()
      }
    }
    .frame(width: Design.panelWidth)
    .background {
      LinearGradient(
        colors: [Design.mint.opacity(0.075), .clear, Design.violet.opacity(0.035)],
        startPoint: .topLeading, endPoint: .bottomTrailing
      ).clipShape(.rect(cornerRadius: Design.Radius.panel))
    }
    .glassEffect(.regular, in: .rect(cornerRadius: Design.Radius.panel))
    .animation(Design.animation(reduced: reduceMotion), value: model.page)
  }
  // The parts above and below the content never depend on the window's own height,
  // so resizing the window cannot feed back into this measurement.
  private func reportPreferredHeight() {
    guard headerHeight > 0, footerHeight > 0, contentHeight > 0 else { return }
    preferHeight(headerHeight + contentHeight + footerHeight)
  }
  private var header: some View {
    HStack(spacing: Design.Spacing.medium) {
      StrataGlyph(model: model, size: 25, animatesReadings: false).padding(Design.Spacing.xSmall)
      VStack(alignment: .leading, spacing: Design.Spacing.xxSmall) {
        Text("strata").font(Design.Typography.pageTitle).tracking(-0.7)
        Group {
          if let moment = model.moment {
            Text(verbatim: moment.title)
          } else {
            Text("A live look inside your Mac")
          }
        }
        .footnoteStyle().lineLimit(2)
        .fixedSize(horizontal: false, vertical: true).contentTransition(.opacity)
      }
      Spacer(minLength: Design.Spacing.small)
      HStack(spacing: Design.Spacing.xSmall) {
        Circle().fill(Design.mint).frame(width: 5, height: 5).shadow(
          color: Design.mint.opacity(0.6), radius: 3)
        Text("Live").font(Design.Typography.label)
      }.padding(.horizontal, Design.Spacing.small).padding(.vertical, Design.Spacing.xSmall)
        .background(Design.mint.opacity(0.09), in: Capsule()).fixedSize()
      Button(action: openSettings) {
        Image(systemName: Design.Symbol.strataSettings).font(Design.Typography.controlSymbol)
      }
      .buttonStyle(.plain).foregroundStyle(.secondary).help("Settings")
      .padding(.leading, Design.Spacing.xSmall)
    }
  }
  // Icon-only tabs fit the panel in every language; each page names itself below.
  private var navigation: some View {
    HStack(spacing: Design.Spacing.xxSmall) {
      ForEach(Reading.allCases) { reading in
        let selected = model.page == reading
        Button {
          model.page = reading
        } label: {
          Image(systemName: reading.symbol).font(Design.Typography.controlSymbol)
            .frame(maxWidth: .infinity).frame(height: 29)
            .foregroundStyle(selected ? Design.accent(model.profile.accent) : .secondary)
            .background(
              selected ? Design.accent(model.profile.accent).opacity(0.12) : .clear,
              in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain).help(reading.title).accessibilityLabel(reading.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
      }
    }
  }
  private var footer: some View {
    ViewThatFits(in: .horizontal) {
      HStack {
        profileMenu
        Spacer(minLength: Design.Spacing.medium)
        explorerButton
      }
      VStack(alignment: .leading, spacing: Design.Spacing.small) {
        profileMenu
        explorerButton
      }
    }.foregroundStyle(.secondary)
  }
  private var profileMenu: some View {
    Menu {
      ForEach(model.preferences.profiles) { profile in
        Button(profile.name) { model.selectedProfile = profile.id }
      }
    } label: {
      HStack(spacing: Design.Spacing.small) {
        HStack(spacing: -2) {
          ForEach([Design.mint, Design.violet, Color.cyan].indices, id: \.self) { index in
            Circle().fill([Design.mint, Design.violet, Color.cyan][index]).frame(
              width: 6, height: 6)
          }
        }
        Text(model.profile.name).font(Design.Typography.control)
      }
    }
    .menuStyle(.borderlessButton).fixedSize()
  }
  private var explorerButton: some View {
    Button {
      openExplorer(.resume)
    } label: {
      HStack(spacing: Design.Spacing.small) {
        Image(systemName: "square.stack.3d.up")
        Text("Open Explorer")
        Image(systemName: Design.Symbol.explorer).font(Design.Typography.inlineSymbol)
      }.font(Design.Typography.control).padding(.horizontal, Design.Spacing.xSmall)
    }
    .buttonStyle(.glass).controlSize(.small).fixedSize()
  }
}

struct ReadingContent: View {
  @ObservedObject var model: AppModel
  let reading: Reading
  let openExplorer: (ExplorerDestination) -> Void
  // Explorer names the page in its window title, and none of its readings have a settings pane.
  var showsHeading = true
  var body: some View {
    VStack(alignment: .leading, spacing: Design.Spacing.large) {
      if reading == .overview {
        OverviewContent(model: model, openExplorer: openExplorer)
      } else {
        if showsHeading { heading }
        switch reading {
        case .cpu: CPUContent(model: model, openExplorer: openExplorer)
        case .gpu: GPUContent(model: model, openExplorer: openExplorer)
        case .memory: MemoryContent(model: model, openExplorer: openExplorer)
        case .disk: DiskContent(model: model, openExplorer: openExplorer)
        case .network: NetworkContent(model: model, openExplorer: openExplorer)
        case .battery: BatteryContent(model: model, openExplorer: openExplorer)
        case .wifi: WiFiContent(model: model, controller: model.wifi)
        case .bluetooth: BluetoothContent(controller: model.bluetooth)
        case .sound: SoundContent(model: model)
        case .display: DisplayContent(controller: model.displays, power: model.power)
        case .overview: EmptyView()
        }
      }
    }
  }
  private var heading: some View {
    HStack {
      Label(reading.title, systemImage: reading.symbol).font(Design.Typography.pageTitle)
      Spacer()
      if [.wifi, .bluetooth, .sound, .battery, .display].contains(reading) {
        Button {
          SystemSettings.open(reading)
        } label: {
          Image(systemName: Design.Symbol.systemSettings).font(Design.Typography.controlSymbol)
        }
        .buttonStyle(.plain).help("Open \(reading.title) settings")
      }
    }
  }
}

struct OverviewContent: View {
  @ObservedObject var model: AppModel
  let openExplorer: (ExplorerDestination) -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: Design.Spacing.large) {
      if let recorder = model.historyRecorder {
        DiagnosisCard(recorder: recorder, openExplorer: openExplorer)
      }
      HStack(alignment: .top, spacing: Design.Spacing.small) {
        ForEach([Reading.cpu, .memory, .network]) { reading in
          PulseTile(model: model, reading: reading, color: reading.tint)
        }
      }.fixedSize(horizontal: false, vertical: true)
      MeasureLeaders(model: model, measure: .cpu, openExplorer: openExplorer)
      HStack(alignment: .top, spacing: Design.Spacing.small) {
        ForEach([Reading.disk, .battery, .wifi, .sound]) { reading in
          Button {
            model.page = reading
          } label: {
            VStack(alignment: .leading, spacing: Design.Spacing.small) {
              Image(systemName: reading.symbol).font(Design.Typography.tileSymbol)
                .foregroundStyle(reading == .battery ? Design.mint : .primary)
                .frame(height: 18)
              Text(reading.title).font(Design.Typography.label)
              Text(model.value(for: reading)).footnoteStyle().lineLimit(3)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(Design.Spacing.medium)
            .surfaceBackground(cornerRadius: Design.Radius.tile)
          }.buttonStyle(.plain)
        }
      }.fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct PulseTile: View {
  @ObservedObject var model: AppModel
  let reading: Reading
  let color: Color
  var body: some View {
    Button {
      model.page = reading
    } label: {
      VStack(alignment: .leading, spacing: Design.Spacing.small) {
        HStack(spacing: Design.Spacing.xSmall) {
          Image(systemName: reading.symbol).foregroundStyle(color)
          Text(reading.title).foregroundStyle(.secondary).lineLimit(2)
        }.font(Design.Typography.label).fixedSize(horizontal: false, vertical: true)
        Text(
          reading == .memory
            ? ValueFormat.percent(model.fraction(for: .memory)) : model.value(for: reading)
        )
        .font(reading == .network ? Design.Typography.rateMetric : Design.Typography.metric)
        .tracking(-0.7).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
        Spacer(minLength: 0)
        Sparkline(
          values: model.historyValues(for: reading), timestamps: model.history.points.map(\.uptime),
          color: color,
          maximum: reading == .network
            ? max(1000, model.history.points.compactMap(\.download).max() ?? 0) : 1,
          showsRate: reading == .network
        ).frame(height: 24)
      }.padding(Design.Spacing.medium)
        .frame(maxWidth: .infinity, minHeight: 110, maxHeight: .infinity, alignment: .topLeading)
        .background {
          RoundedRectangle(cornerRadius: Design.Radius.tile).fill(color.opacity(0.075))
            .overlay(alignment: .topLeading) {
              LinearGradient(
                colors: [.white.opacity(0.12), .clear], startPoint: .topLeading,
                endPoint: .bottomTrailing)
            }.clipShape(.rect(cornerRadius: Design.Radius.tile))
        }
        .overlay(
          RoundedRectangle(cornerRadius: Design.Radius.tile).strokeBorder(
            color.opacity(0.16), lineWidth: 0.7))
    }.buttonStyle(.plain).accessibilityLabel(reading.title).accessibilityValue(
      model.accessibleValue(for: reading))
  }
}

struct ProcessAppIcon: View {
  let identity: ProcessIdentity
  let side: CGFloat
  var icons = ProcessIconCache.shared
  @Environment(\.displayScale) private var scale
  var body: some View {
    Group {
      if let icon = icons.icon(for: identity, side: side, scale: scale) {
        Image(decorative: icon, scale: scale)
      } else {
        placeholder
      }
    }.frame(width: side, height: side)
  }
  private var placeholder: some View {
    Image(systemName: "terminal.fill").font(Design.Typography.controlSymbol)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, maxHeight: .infinity).background(
        .primary.opacity(0.05), in: .rect(cornerRadius: Design.Radius.icon))
  }
}
