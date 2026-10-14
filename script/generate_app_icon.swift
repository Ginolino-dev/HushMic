#!/usr/bin/env swift
import AppKit
import Foundation

// Editable vector geometry, rendered at each native macOS icon size.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Sources/MicMinder/Resources")
let preview = root.appendingPathComponent("design/MicMinder-icon.png")
let temporary = FileManager.default.temporaryDirectory
  .appendingPathComponent("MicMinder-icon-" + UUID().uuidString)
let iconset = temporary.appendingPathComponent("MicMinder.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: preview.deletingLastPathComponent(), withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporary) }

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
  NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
}

func render(side: Int) throws -> Data {
  guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
    isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
  ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    throw NSError(domain: "MicMinder.Icon", code: 1)
  }
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context
  context.imageInterpolation = .high
  let scale = NSAffineTransform()
  scale.scale(by: CGFloat(side) / 1024)
  scale.concat()

  let tile = NSBezierPath(
    roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896),
    xRadius: 196, yRadius: 196
  )
  NSGradient(starting: color(9, 113, 111), ending: color(33, 191, 178))!
    .draw(in: tile, angle: 90)

  NSColor.white.setFill()
  NSBezierPath(
    roundedRect: NSRect(x: 350, y: 405, width: 170, height: 330),
    xRadius: 85, yRadius: 85
  ).fill()

  let cradle = NSBezierPath()
  cradle.lineWidth = 36
  cradle.lineCapStyle = .round
  cradle.lineJoinStyle = .round
  cradle.move(to: NSPoint(x: 288, y: 528))
  cradle.line(to: NSPoint(x: 288, y: 428))
  cradle.curve(to: NSPoint(x: 435, y: 296),
               controlPoint1: NSPoint(x: 288, y: 346),
               controlPoint2: NSPoint(x: 351, y: 296))
  cradle.curve(to: NSPoint(x: 582, y: 428),
               controlPoint1: NSPoint(x: 519, y: 296),
               controlPoint2: NSPoint(x: 582, y: 346))
  cradle.line(to: NSPoint(x: 582, y: 528))
  NSColor.white.setStroke()
  cradle.stroke()

  let stand = NSBezierPath()
  stand.lineWidth = 36
  stand.lineCapStyle = .round
  stand.move(to: NSPoint(x: 435, y: 296))
  stand.line(to: NSPoint(x: 435, y: 215))
  stand.move(to: NSPoint(x: 356, y: 215))
  stand.line(to: NSPoint(x: 514, y: 215))
  stand.stroke()

  let badge = NSBezierPath(ovalIn: NSRect(x: 597, y: 225, width: 250, height: 250))
  color(6, 78, 79).setFill()
  badge.fill()
  color(91, 218, 204).setStroke()
  badge.lineWidth = 8
  badge.stroke()
  NSColor.white.setFill()
  for x in [CGFloat(669), CGFloat(741)] {
    NSBezierPath(
      roundedRect: NSRect(x: x, y: 295, width: 34, height: 110),
      xRadius: 9, yRadius: 9
    ).fill()
  }

  NSGraphicsContext.restoreGraphicsState()
  guard let png = bitmap.representation(using: .png, properties: [:]) else {
    throw NSError(domain: "MicMinder.Icon", code: 2)
  }
  return png
}

for size in [16, 32, 128, 256, 512] {
  try render(side: size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
  try render(side: size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
try render(side: 1024).write(to: preview)
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o",
                     resources.appendingPathComponent("MicMinder.icns").path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
  throw NSError(domain: "MicMinder.Icon", code: Int(process.terminationStatus))
}
print("Generated MicMinder.icns and design/MicMinder-icon.png")
