import Foundation

struct RunEvents {
  var runsStarted = 0, runsEnded = 0, testsStarted = 0, testsEnded = 0
  init(data: Data, recordKind: String) throws {
    for line in data.split(separator: 10) {
      guard let record = try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
        record["kind"] as? String == recordKind, let payload = record["payload"] as? [String: Any]
      else { continue }
      switch payload["kind"] as? String {
      case "runStarted": runsStarted += 1
      case "runEnded": runsEnded += 1
      case "testStarted": testsStarted += 1
      case "testEnded": testsEnded += 1
      default: break
      }
    }
  }
  var isComplete: Bool { runsStarted == runsEnded && testsStarted == testsEnded }
}

do {
  guard CommandLine.arguments.count == 3 else { throw CocoaError(.fileReadInvalidFileName) }
  let events = try RunEvents(
    data: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])), recordKind: "event")
  let native = try RunEvents(
    data: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])),
    recordKind: "nativeEvent")
  guard events.isComplete && native.isComplete else {
    FileHandle.standardError.write(
      Data(
        "Incomplete test execution: \(events.runsStarted) Swift runs started, \(events.runsEnded) finished; \(events.testsStarted + native.testsStarted) tests/suites started, \(events.testsEnded + native.testsEnded) finished.\n"
          .utf8))
    exit(1)
  }
  guard events.testsEnded + native.testsEnded > 0 else {
    FileHandle.standardError.write(Data("No tests executed.\n".utf8))
    exit(1)
  }
  print("Verified complete test execution (Swift Testing and native XCTest events).")
} catch {
  FileHandle.standardError.write(
    Data("Could not verify test results: \(error.localizedDescription)\n".utf8))
  exit(1)
}
