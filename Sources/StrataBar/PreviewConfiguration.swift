import StrataCore

enum PreviewSurface: Equatable {
  case glyphs(String)
  case unfoldAnimation(String)
  case momentsAnimation(String)
  case explorer
  case reading(Reading)
  case unfoldedStrip
}
struct PreviewConfiguration {
  let surface: PreviewSurface?
  let appearance: Appearance?
  let selectsOwnProcess: Bool
  let processGrouping: ProcessGrouping
  // Made-up readings for screenshots, so nothing about this Mac is shown.
  let usesDemoData: Bool
  var isEnabled: Bool { surface != nil }
  init(arguments: [String]) {
    if let path = Self.value(after: "--render-glyphs", in: arguments), !path.isEmpty {
      surface = .glyphs(path)
    } else if let path = Self.value(after: "--render-unfold", in: arguments), !path.isEmpty {
      surface = .unfoldAnimation(path)
    } else if let path = Self.value(after: "--render-moments", in: arguments), !path.isEmpty {
      surface = .momentsAnimation(path)
    } else if let value = Self.value(after: "--preview-page", in: arguments),
      let reading = Reading(rawValue: value)
    {
      surface = .reading(reading)
    } else if arguments.contains("--preview-strip") {
      surface = .unfoldedStrip
    } else if arguments.contains("--preview") {
      surface = .explorer
    } else {
      surface = nil
    }
    appearance =
      surface == nil
      ? nil : Self.value(after: "--appearance", in: arguments).flatMap(Appearance.init(rawValue:))
    selectsOwnProcess = surface == .explorer && arguments.contains("--preview-self")
    processGrouping =
      surface == .explorer && arguments.contains("--preview-families") ? .families : .individual
    usesDemoData = surface != nil && arguments.contains("--demo")
  }
  private static func value(after flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
      return nil
    }
    return arguments[index + 1]
  }
}
