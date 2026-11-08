import AppKit

// Draws the app icon: a gauge ring with a pulse inside, on the soft lavender tile the Strata
// apps share. Everything is drawn on a 1024-point grid and scaled for each size.
let destination = URL(fileURLWithPath: "build/StrataBar.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
  CGColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

let violet = color(129, 80, 207)
let deepViolet = color(84, 46, 168)
let mint = color(52, 211, 170)
let center = CGPoint(x: 512, y: 528)

func drawTile(in context: CGContext) {
  let tile = CGPath(
    roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 186,
    cornerHeight: 186, transform: nil)
  context.saveGState()
  context.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: color(60, 30, 120, 0.22))
  context.addPath(tile)
  context.setFillColor(color(236, 229, 251))
  context.fillPath()
  context.restoreGState()
  context.saveGState()
  context.addPath(tile)
  context.clip()
  let wash = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
    colors: [color(246, 242, 255), color(222, 210, 250)] as CFArray, locations: [0, 1])!
  context.drawLinearGradient(
    wash, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
  context.restoreGState()
  context.addPath(tile)
  context.setStrokeColor(color(255, 255, 255, 0.7))
  context.setLineWidth(3)
  context.strokePath()
}

func drawGauge(in context: CGContext) {
  let radius: CGFloat = 248
  let width: CGFloat = 88
  context.setLineWidth(width)
  context.setLineCap(.round)
  context.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
  context.setStrokeColor(color(129, 80, 207, 0.13))
  context.strokePath()
  // Four fifths of the way round, clockwise from the top, turning from violet to mint. Short
  // overlapping segments shade it, since the gradient must follow the arc.
  let start = CGFloat.pi / 2
  let sweep = CGFloat.pi * 2 * 0.8
  let segments = 160
  context.setLineCap(.butt)
  for index in 0..<segments {
    let fraction = CGFloat(index) / CGFloat(segments - 1)
    let from = start - sweep * CGFloat(index) / CGFloat(segments)
    let to = from - sweep / CGFloat(segments) - 0.01
    context.addArc(center: center, radius: radius, startAngle: from, endAngle: to, clockwise: true)
    context.setStrokeColor(blend(violet, mint, fraction))
    context.strokePath()
  }
  for (angle, cap) in [(start, violet), (start - sweep, mint)] {
    let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    context.setFillColor(cap)
    context.fillEllipse(
      in: CGRect(x: point.x - width / 2, y: point.y - width / 2, width: width, height: width))
  }
}

func blend(_ from: CGColor, _ to: CGColor, _ fraction: CGFloat) -> CGColor {
  let a = from.components ?? [0, 0, 0, 1]
  let b = to.components ?? [0, 0, 0, 1]
  return CGColor(
    srgbRed: a[0] + (b[0] - a[0]) * fraction, green: a[1] + (b[1] - a[1]) * fraction,
    blue: a[2] + (b[2] - a[2]) * fraction, alpha: 1)
}

func drawPulse(in context: CGContext) {
  let points: [CGPoint] = [
    CGPoint(x: 362, y: 528), CGPoint(x: 438, y: 528), CGPoint(x: 474, y: 600),
    CGPoint(x: 524, y: 420), CGPoint(x: 566, y: 572), CGPoint(x: 590, y: 528),
    CGPoint(x: 662, y: 528),
  ]
  context.addLines(between: points)
  context.setStrokeColor(deepViolet)
  context.setLineWidth(36)
  context.setLineCap(.round)
  context.setLineJoin(.round)
  context.strokePath()
}

func drawIcon(size: Int) throws -> Data {
  guard
    let context = CGContext(
      data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
  else { throw NSError(domain: "StrataMonitor.Icon", code: 1) }
  context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
  drawTile(in: context)
  drawGauge(in: context)
  drawPulse(in: context)
  guard let image = context.makeImage(),
    let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
  else { throw NSError(domain: "StrataMonitor.Icon", code: 2) }
  return data
}

for size in [16, 32, 128, 256, 512] {
  try drawIcon(size: size).write(to: destination.appendingPathComponent("icon_\(size)x\(size).png"))
  try drawIcon(size: size * 2).write(
    to: destination.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
