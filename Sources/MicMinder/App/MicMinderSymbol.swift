import AppKit
// A custom note and pause mark. Template rendering follows the menu bar's appearance.
enum MicMinderSymbol {
  static func image(size: CGFloat = 18) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    NSColor.black.setFill()
    let scale = size / 24
    let transform = AffineTransform(scale: scale)
    let note = NSBezierPath()
    note.move(to: NSPoint(x: 7, y: 6))
    note.line(to: NSPoint(x: 7, y: 20))
    note.line(to: NSPoint(x: 19, y: 23))
    note.line(to: NSPoint(x: 19, y: 17))
    note.line(to: NSPoint(x: 10, y: 15))
    note.line(to: NSPoint(x: 10, y: 6))
    note.close()
    note.transform(using: transform); note.fill()
    let head = NSBezierPath(ovalIn: NSRect(x: 1 * scale, y: 1 * scale, width: 9 * scale, height: 7 * scale))
    head.fill()
    for x in [13.0, 19.0] {
      NSBezierPath(roundedRect: NSRect(x: x * scale, y: 4 * scale, width: 3.5 * scale, height: 9 * scale), xRadius: scale, yRadius: scale).fill()
    }
    image.unlockFocus()
    image.isTemplate = true
    image.accessibilityDescription = "MicMinder"
    return image
  }
}
