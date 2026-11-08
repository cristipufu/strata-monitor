import AppKit
import SwiftUI

// Renders one image without starting monitoring, then exits.
@MainActor func render(_ path: String, _ write: (URL) throws -> Void) -> Never {
  do {
    try write(URL(fileURLWithPath: path))
    print("Rendered \(path)")
    exit(EXIT_SUCCESS)
  } catch {
    fputs("Rendering failed: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
  }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
switch PreviewConfiguration(arguments: CommandLine.arguments).surface {
case .glyphs(let path): render(path, GlyphStudyRenderer.write)
case .unfoldAnimation(let path): render(path, MenuBarAnimation.writeUnfold)
case .momentsAnimation(let path): render(path, MenuBarAnimation.writeMoments)
default: break
}
let delegate = ApplicationDelegate()
app.delegate = delegate
app.run()
