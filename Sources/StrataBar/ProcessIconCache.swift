import AppKit
import StrataCore

// Application icons are drawn once at the size they are shown. Resampling a full-size icon
// on every frame of a reading animation cost more than the rest of the panel together.
@MainActor final class ProcessIconCache {
  static var shared = ProcessIconCache()
  private final class Entry {
    let image: CGImage?
    init(_ image: CGImage?) { self.image = image }
  }
  private let cache = NSCache<NSString, Entry>()
  private let applicationIcon: (Int32) -> NSImage?

  init(
    applicationIcon: @escaping (Int32) -> NSImage? = {
      NSRunningApplication(processIdentifier: $0)?.icon
    }
  ) {
    self.applicationIcon = applicationIcon
    cache.countLimit = 64
  }

  func icon(for identity: ProcessIdentity, side: CGFloat, scale: CGFloat) -> CGImage? {
    let key =
      "\(identity.pid):\(identity.startSeconds):\(identity.startMicroseconds):\(side)@\(scale)"
      as NSString
    if let entry = cache.object(forKey: key) { return entry.image }
    let image = applicationIcon(identity.pid).flatMap {
      Self.render($0, pixels: Int((side * scale).rounded(.up)))
    }
    cache.setObject(Entry(image), forKey: key)
    return image
  }

  static func render(_ icon: NSImage, pixels: Int) -> CGImage? {
    guard pixels > 0,
      let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
          | CGBitmapInfo.byteOrder32Little.rawValue)
    else { return nil }
    context.interpolationQuality = .high
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    icon.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return context.makeImage()
  }
}
