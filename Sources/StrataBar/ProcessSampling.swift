import AppKit
import StrataCore
import StrataSystem
import SwiftUI

// Samples one of the person's own processes with Apple's `sample` tool. The process's identity
// is checked before and after, so a report never describes a different process with a reused pid.
@MainActor final class ProcessSamplingController: ObservableObject {
  enum State {
    case idle
    case sampling(ProcessIdentity)
    case finished(ProcessIdentity, SampleReport)
    case failed(ProcessIdentity, String)
  }
  static let seconds = 3
  @Published private(set) var state = State.idle
  private let sampler: any ProcessSampling
  private let identities: any ProcessIdentityVerifying
  private var task: Task<Void, Never>?

  init(
    sampler: any ProcessSampling = ProcessSampler(),
    identities: any ProcessIdentityVerifying = ProcessIdentityVerifier()
  ) {
    self.sampler = sampler
    self.identities = identities
  }

  static func canSample(_ process: ProcessSample) -> Bool {
    process.userID == getuid() && process.id.pid != ProcessInfo.processInfo.processIdentifier
  }

  func sample(_ process: ProcessSample) {
    guard Self.canSample(process) else { return }
    cancel()
    let identity = process.id
    state = .sampling(identity)
    task = Task { [sampler, identities] in
      let outcome: State
      do {
        guard identities.isCurrent(identity) else { throw ProcessSamplingError.processEnded }
        let report = try await sampler.sample(pid: identity.pid, seconds: Self.seconds)
        guard identities.isCurrent(identity) else { throw ProcessSamplingError.processEnded }
        outcome = .finished(identity, report)
      } catch is CancellationError {
        return
      } catch {
        outcome = .failed(identity, Self.explanation(error))
      }
      guard !Task.isCancelled else { return }
      state = outcome
    }
  }

  func cancel() {
    task?.cancel()
    task = nil
    state = .idle
  }

  func save(_ report: SampleReport, of identity: ProcessIdentity) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "\(report.processName) sample.txt"
    panel.allowedContentTypes = [.plainText]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try report.rawText.write(to: url, atomically: true, encoding: .utf8)
    } catch {
      state = .failed(identity, error.localizedDescription)
    }
  }

  private static func explanation(_ error: any Error) -> String {
    switch error as? ProcessSamplingError {
    case .notPermitted?: String(localized: "macOS did not allow sampling this process.")
    case .processEnded?, .differentProcess?: String(localized: "The process ended while it was sampled.")
    case .unrecognizedReport?: String(localized: "The sample report could not be read.")
    case nil: error.localizedDescription
    }
  }
}

struct ProcessSampleSection: View {
  @ObservedObject var controller: ProcessSamplingController
  let process: ProcessSample
  private static let shownFrames = 8
  var body: some View {
    VStack(alignment: .leading, spacing: Design.Spacing.medium) {
      SectionHeading("Sample")
      switch controller.state {
      case .sampling(let identity) where identity == process.id:
        LoadingState("Sampling for \(ProcessSamplingController.seconds) seconds…")
      case .finished(let identity, let report) where identity == process.id:
        frames(report)
        HStack {
          Button("Sample Again") { controller.sample(process) }
          Button("Save Full Report…") { controller.save(report, of: identity) }
        }
      case .failed(let identity, let message) where identity == process.id:
        Text(message).font(Design.Typography.body).foregroundStyle(.secondary)
        Button("Try Again") { controller.sample(process) }
      default:
        Button("Sample for \(ProcessSamplingController.seconds) Seconds") { controller.sample(process) }
        Text("Shows where the process spends its time, using Apple's sample tool.").footnoteStyle()
      }
    }
  }
  private func frames(_ report: SampleReport) -> some View {
    VStack(alignment: .leading, spacing: Design.Spacing.small) {
      ForEach(Array(report.topFrames.prefix(Self.shownFrames).enumerated()), id: \.offset) {
        _, frame in
        DetailRow(
          label: frame.binary.map { "\(frame.symbol) · \($0)" } ?? frame.symbol,
          value: report.totalSamples > 0
            ? ValueFormat.percent(Double(frame.count) / Double(report.totalSamples))
            : String(frame.count))
      }
      Text("Share of samples where each function was running.").footnoteStyle()
    }
  }
}
