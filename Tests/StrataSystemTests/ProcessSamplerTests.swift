import Foundation
import StrataCore
import Testing

@testable import StrataSystem

/// Modeled on the report `/usr/bin/sample <pid> <seconds> -file <path>` writes on macOS 26.
private let sampleFixture = """
  Analysis of sampling Demo (pid 4242) every 1 millisecond
  Process:         Demo [4242]
  Path:            /Applications/Demo.app/Contents/MacOS/Demo
  Load Address:    0x100abc000
  Identifier:      com.example.demo
  Code Type:       ARM64E
  Parent Process:  launchd [1]
  Target Type:     live task
  ----

  Call graph:
      900 Thread_100   DispatchQueue_1: com.apple.main-thread  (serial)
      + 900 start  (in dyld) + 6992  [0x180cc54e4]
      +   900 main  (in Demo) + 204  [0x10091658c]  main.swift:20
      +     600 -[NSApplication run]  (in AppKit) + 480  [0x18500a0e0]
      +     300 closure #1 in Model.refresh()  (in Demo) + 52  [0x100920034]
      900 Thread_101: com.example.worker
      + 900 ???  (in Demo)  load address 0x100abc000 + 0x740  [0x100abc740]
      + ! 900 std::__1::vector<int, std::__1::allocator<int>>::push_back(int&&)  (in libc++.1.dylib) + 8
      12 Thread_<multiple>   DispatchQueue_9: com.example.queue  (serial)
        12 __workq_kernreturn  (in libsystem_kernel.dylib) + 8  [0x18104d6a8]

  Total number in stack (recursive counted multiple, when >=5):
          8       start_wqthread  (in libsystem_pthread.dylib) + 8  [0x18108bc10]

  Sort by top of stack, same collapsed (when >= 5):
          mach_msg2_trap  (in libsystem_kernel.dylib)        600
          closure #1 in Model.refresh()  (in Demo)        300
          std::__1::vector<int, std::__1::allocator<int>>::push_back(int&&)  (in libc++.1.dylib)        900
          ???  (in Demo)  load address 0x100abc000 + 0x740        7
          __workq_kernreturn  (in libsystem_kernel.dylib)        12
          symbol-without-binary        5
          not a frame line
          (in Orphan)        5

  Binary Images:
         0x100abc000 -        0x100abca03 +com.example.demo (1.0) <00000000-0000-0000-0000-000000000000> /Applications/Demo.app/Contents/MacOS/Demo
  """

@Suite struct SampleReportParserTests {
  @Test func reportNamesTheSampledProcess() throws {
    let report = try #require(SampleReportParser.parse(sampleFixture))
    #expect(report.pid == 4242 && report.processName == "Demo")
    #expect(report.rawText == sampleFixture)
  }

  @Test func totalCountsEveryThreadRoot() throws {
    let report = try #require(SampleReportParser.parse(sampleFixture))
    #expect(report.totalSamples == 1_812)
  }

  @Test func topOfStackFramesKeepSymbolBinaryAndCount() throws {
    let frames = try #require(SampleReportParser.parse(sampleFixture)).topFrames
    #expect(
      frames == [
        SampleFrame(symbol: "mach_msg2_trap", binary: "libsystem_kernel.dylib", count: 600),
        SampleFrame(symbol: "closure #1 in Model.refresh()", binary: "Demo", count: 300),
        SampleFrame(
          symbol: "std::__1::vector<int, std::__1::allocator<int>>::push_back(int&&)",
          binary: "libc++.1.dylib", count: 900),
        SampleFrame(symbol: "???", binary: "Demo", count: 7),
        SampleFrame(symbol: "__workq_kernreturn", binary: "libsystem_kernel.dylib", count: 12),
        SampleFrame(symbol: "symbol-without-binary", binary: nil, count: 5),
      ])
  }

  @Test func truncatedReportKeepsWhatArrived() throws {
    let cut = sampleFixture.prefix { $0 != "?" }
    let report = try #require(SampleReportParser.parse(String(cut)))
    #expect(report.topFrames.isEmpty)
    #expect(report.totalSamples == 1_800)
  }

  @Test(arguments: [
    "", "Process:", "Process:         Demo", "Process:         Demo [x]",
    "Process:         Demo [0]", "Call graph:\n    5 Thread_1\n",
  ])
  func reportWithoutAProcessHeaderIsRejected(_ text: String) {
    #expect(SampleReportParser.parse(text) == nil)
  }

  @Test func processNamesMayContainBrackets() {
    let header = SampleReportParser.processHeader("Process:  Helper [GPU] [77]")
    #expect(header?.name == "Helper [GPU]" && header?.pid == 77)
  }

  @Test func absurdCountsNeverOverflow() throws {
    let text = """
      Process:         Demo [5]
      Call graph:
          \(Int.max) Thread_1
          \(Int.max) Thread_2
          99999999999999999999999 Thread_3
      """
    #expect(try #require(SampleReportParser.parse(text)).totalSamples == .max)
  }
}

@Suite struct ProcessSamplerTests {
  private func sampler(_ result: Result<Data, SystemToolError>) -> ProcessSampler {
    ProcessSampler(tool: ScriptedSystemTool([.sample(pid: 4242, seconds: 3): result]))
  }

  @Test func samplesTheRequestedProcessForTheRequestedTime() async throws {
    let tool = ScriptedSystemTool(.sample(pid: 4242, seconds: 3), output: sampleFixture)
    let report = try await ProcessSampler(tool: tool).sample(pid: 4242, seconds: 3)
    #expect(report.topFrames.count == 6)
    #expect(tool.invocations == [.sample(pid: 4242, seconds: 3)])
  }

  @Test func otherUsersProcessesAreNotPermitted() async {
    let refusal = SystemToolError.exited(
      status: 255,
      diagnostics: "sample[1]: sample cannot examine process 1 (launchd) because you do not "
        + "have appropriate privileges to examine it; try running with `sudo`.")
    await #expect(throws: ProcessSamplingError.notPermitted) {
      try await sampler(.failure(refusal)).sample(pid: 4242, seconds: 3)
    }
  }

  @Test func endedProcessesAreReportedAsEnded() async {
    let ended = SystemToolError.exited(
      status: 255,
      diagnostics: "sample[1]: sample cannot examine process 4242 (with name like '4242') "
        + "because it no longer appears to be running.")
    await #expect(throws: ProcessSamplingError.processEnded) {
      try await sampler(.failure(ended)).sample(pid: 4242, seconds: 3)
    }
  }

  @Test(arguments: [
    SystemToolError.exited(status: 1, diagnostics: "unexpected"), .timedOut,
    .outputLimitExceeded(limit: 10), .reportUnavailable,
  ])
  func otherFailuresReachTheCallerUnchanged(_ failure: SystemToolError) async {
    await #expect(throws: failure) {
      try await sampler(.failure(failure)).sample(pid: 4242, seconds: 3)
    }
  }

  @Test func unreadableReportIsRejected() async {
    await #expect(throws: ProcessSamplingError.unrecognizedReport) {
      try await sampler(.success(Data("Sampling completed".utf8))).sample(pid: 4242, seconds: 3)
    }
  }

  @Test func reportAboutAnotherProcessIsRejected() async {
    let other = sampleFixture.replacingOccurrences(of: "Demo [4242]", with: "Demo [4343]")
    await #expect(throws: ProcessSamplingError.differentProcess) {
      try await sampler(.success(Data(other.utf8))).sample(pid: 4242, seconds: 3)
    }
  }
}
