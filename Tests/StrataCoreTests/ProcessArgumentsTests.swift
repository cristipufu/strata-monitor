import Foundation
import StrataCore
import Testing

private func argumentData(_ count: Int32, body: [UInt8]) -> Data {
  var count = count
  var data = withUnsafeBytes(of: &count) { Data($0) }
  data.append(contentsOf: body)
  return data
}
private func alignedArguments(_ path: String, _ arguments: [String], environment: [String] = [])
  -> [UInt8]
{
  var body = Array((path + "\0").utf8)
  while body.count % 8 != 0 { body.append(0) }
  for value in arguments + environment { body.append(contentsOf: (value + "\0").utf8) }
  return body
}

@Test func argumentsPreserveEmptyValuesAndStopBeforeEnvironment() {
  let bytes = alignedArguments(
    "/bin/worker", ["worker", "", "--name", "λ"], environment: ["SECRET_TOKEN=do-not-export"])
  #expect(ProcessArguments.parse(argumentData(4, body: bytes)) == ["worker", "", "--name", "λ"])
}

@Test func emptyFirstArgumentIsNotMistakenForPathAlignment() {
  for path in ["/a", "/worker", "/bin/worker", "/a/longer/worker/path"] {
    let bytes = alignedArguments(path, ["", "30"], environment: ["SECRET=never-an-argument"])
    #expect(ProcessArguments.parse(argumentData(2, body: bytes)) == ["", "30"])
  }
}

@Test func malformedArgumentBlocksAreUnavailable() {
  #expect(ProcessArguments.parse(Data()) == nil)
  #expect(ProcessArguments.parse(argumentData(-1, body: [])) == nil)
  #expect(ProcessArguments.parse(argumentData(4097, body: [])) == nil)
  #expect(
    ProcessArguments.parse(argumentData(2, body: Array("/worker\0worker\0truncated".utf8))) == nil)
  #expect(ProcessArguments.parse(argumentData(0, body: [])) == [])
}
