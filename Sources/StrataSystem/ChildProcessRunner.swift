import Darwin
import Dispatch
import Foundation
import Synchronization

struct ChildProcessOutput: Sendable {
  let output: Data
  let diagnostics: String
}

struct ChildProcessRunner: Sendable {
  let limits: SystemToolLimits
  let timeout: Duration
  let terminationSignal: Int32
  let didLaunch: @Sendable (Int32) -> Void
  init(
    limits: SystemToolLimits, timeout: Duration, terminationSignal: Int32 = SIGTERM,
    didLaunch: @escaping @Sendable (Int32) -> Void = { _ in }
  ) {
    self.limits = limits
    self.timeout = timeout
    self.terminationSignal = terminationSignal
    self.didLaunch = didLaunch
  }

  func run(_ command: SystemToolCommand) async throws -> ChildProcessOutput {
    try Task.checkCancellation()
    let execution = ChildProcessExecution(
      command: command, limits: limits, timeout: timeout, terminationSignal: terminationSignal,
      didLaunch: didLaunch)
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { execution.start(resuming: $0) }
    } onCancel: {
      execution.stop(because: CancellationError())
    }
  }
}

/// Both pipes are drained while the child runs, so a full pipe never blocks it.
/// The run completes only after the child has exited and both pipes reached
/// end of file, so no child outlives its caller.
final class ChildProcessExecution: Sendable {
  private enum Stream { case output, diagnostics }
  private let process = Process()
  private let outputPipe = Pipe()
  private let diagnosticPipe = Pipe()
  private let queue = DispatchQueue(label: "dev.stratabar.system-tool")
  private let limits: SystemToolLimits
  private let timeout: Duration
  private let terminationSignal: Int32
  private let didLaunch: @Sendable (Int32) -> Void
  private let state = Mutex(ChildProcessState())

  init(
    command: SystemToolCommand, limits: SystemToolLimits, timeout: Duration,
    terminationSignal: Int32, didLaunch: @escaping @Sendable (Int32) -> Void
  ) {
    self.limits = limits
    self.timeout = timeout
    self.terminationSignal = terminationSignal
    self.didLaunch = didLaunch
    process.executableURL = URL(fileURLWithPath: command.executablePath)
    process.arguments = command.arguments
    process.environment = ["LC_ALL": "C"]
    process.currentDirectoryURL = URL(fileURLWithPath: "/")
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = outputPipe
    process.standardError = diagnosticPipe
    process.terminationHandler = { [weak self] child in
      self?.recordExit(reason: child.terminationReason, status: child.terminationStatus)
    }
  }

  func start(resuming continuation: CheckedContinuation<ChildProcessOutput, any Error>) {
    let launch = state.withLock { state -> Result<Int32, any Error> in
      if let failure = state.failure { return .failure(failure) }
      do {
        try process.run()
      } catch {
        return .failure(SystemToolError.launchFailed(error.localizedDescription))
      }
      state.continuation = continuation
      state.channels = [read(outputPipe, as: .output), read(diagnosticPipe, as: .diagnostics)]
      state.openStreams = state.channels.count
      return .success(process.processIdentifier)
    }
    switch launch {
    case .failure(let error):
      continuation.resume(throwing: error)
    case .success(let pid):
      didLaunch(pid)
      queue.asyncAfter(deadline: .now() + timeout.dispatchInterval) { [weak self] in
        self?.stop(because: SystemToolError.timedOut)
      }
    }
  }

  func stop(because reason: any Error) {
    let mustEscalate = state.withLock { state in
      if state.failure == nil { state.failure = reason }
      guard state.isRunning, !state.stopping else { return false }
      state.stopping = true
      signalChild(terminationSignal, in: state)
      return true
    }
    guard mustEscalate else { return }
    queue.asyncAfter(deadline: .now() + limits.terminationGrace.dispatchInterval) {
      [weak self] in self?.forceStop()
    }
  }

  private func forceStop() {
    let channels = state.withLock { state -> [DispatchIO] in
      guard state.isRunning else { return [] }
      signalChild(SIGKILL, in: state)
      return state.channels
    }
    for channel in channels { channel.close(flags: .stop) }
  }

  /// Foundation reaps the child just before the termination handler records the
  /// exit, so a signal can race a PID reuse only inside that brief window.
  private func signalChild(_ signal: Int32, in state: borrowing ChildProcessState) {
    if state.exit == nil { kill(process.processIdentifier, signal) }
  }

  private func read(_ pipe: Pipe, as stream: Stream) -> DispatchIO {
    let handle = pipe.fileHandleForReading
    let channel = DispatchIO(type: .stream, fileDescriptor: handle.fileDescriptor, queue: queue) {
      _ in withExtendedLifetime(handle) {}
    }
    channel.setLimit(lowWater: 1)
    channel.read(offset: 0, length: .max, queue: queue) { [weak self] done, data, _ in
      if let data, !data.isEmpty { self?.receive(data, on: stream) }
      if done { self?.endStream() }
    }
    return channel
  }

  private func receive(_ data: DispatchData, on stream: Stream) {
    let exceeded = state.withLock { state in
      guard state.failure == nil else { return false }
      switch stream {
      case .output:
        guard data.count <= limits.outputBytes - state.output.count else { return true }
        state.output.append(data, upTo: data.count)
      case .diagnostics:
        state.diagnostics.append(data, upTo: limits.diagnosticBytes - state.diagnostics.count)
      }
      return false
    }
    if exceeded { stop(because: SystemToolError.outputLimitExceeded(limit: limits.outputBytes)) }
  }

  private func endStream() {
    state.withLock { state in
      state.openStreams -= 1
      return state.takeCompletion()
    }?.resume()
  }

  private func recordExit(reason: Process.TerminationReason, status: Int32) {
    state.withLock { state in
      state.exit = ChildProcessExit(reason: reason, status: status)
      return state.takeCompletion()
    }?.resume()
  }
}

private struct ChildProcessExit {
  let reason: Process.TerminationReason
  let status: Int32
}

private struct ChildProcessCompletion {
  let continuation: CheckedContinuation<ChildProcessOutput, any Error>
  let result: Result<ChildProcessOutput, any Error>
  func resume() { continuation.resume(with: result) }
}

private struct ChildProcessState {
  var continuation: CheckedContinuation<ChildProcessOutput, any Error>?
  var channels: [DispatchIO] = []
  var openStreams = 0
  var output = Data()
  var diagnostics = Data()
  var exit: ChildProcessExit?
  var failure: (any Error)?
  var stopping = false

  var isRunning: Bool { continuation != nil }

  mutating func takeCompletion() -> ChildProcessCompletion? {
    guard let exit, openStreams == 0, let continuation else { return nil }
    self.continuation = nil
    for channel in channels { channel.close() }
    channels.removeAll()
    return ChildProcessCompletion(continuation: continuation, result: result(of: exit))
  }

  private func result(of exit: ChildProcessExit) -> Result<ChildProcessOutput, any Error> {
    if let failure { return .failure(failure) }
    let message = String(decoding: diagnostics, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    switch (exit.reason, exit.status) {
    case (.exit, 0):
      return .success(ChildProcessOutput(output: output, diagnostics: message))
    case (.exit, let status):
      return .failure(SystemToolError.exited(status: status, diagnostics: message))
    case (_, let signal):
      return .failure(SystemToolError.terminated(signal: signal))
    }
  }
}

extension Data {
  fileprivate mutating func append(_ data: DispatchData, upTo limit: Int) {
    var remaining = Swift.max(0, limit)
    data.enumerateBytes { bytes, _, stop in
      let piece = UnsafeBufferPointer(rebasing: bytes.prefix(remaining))
      append(piece)
      remaining -= piece.count
      stop = remaining == 0
    }
  }
}

extension Duration {
  fileprivate var dispatchInterval: DispatchTimeInterval {
    let nanoseconds = self / .nanoseconds(1)
    return nanoseconds < Double(Int.max) ? .nanoseconds(Int(Swift.max(0, nanoseconds))) : .never
  }
}
