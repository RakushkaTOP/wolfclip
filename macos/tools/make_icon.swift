// Renders the 1024px app icon: dark squircle with a stack of history cards.
import AppKit

func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: a)
}
func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Base squircle with soft drop shadow.
let base = rr(100, 100, 824, 824, 186)
NSGraphicsContext.saveGraphicsState()
let drop = NSShadow()
drop.shadowColor = hex(0x000000, 0.35); drop.shadowBlurRadius = 28; drop.shadowOffset = NSSize(width: 0, height: -12)
drop.set()
hex(0x1A1B1F).setFill(); base.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(starting: hex(0x34363D), ending: hex(0x111215))!.draw(in: base, angle: -90)
hex(0xFFFFFF, 0.09).setStroke(); base.lineWidth = 3; base.stroke()

// Cards behind (peeking above the front one).
hex(0x4A4D56).setFill(); rr(296, 400, 432, 330, 50).fill()
hex(0x7B7F8A).setFill(); rr(254, 340, 516, 330, 54).fill()

// Front card.
NSGraphicsContext.saveGraphicsState()
let cardShadow = NSShadow()
cardShadow.shadowColor = hex(0x000000, 0.45); cardShadow.shadowBlurRadius = 30; cardShadow.shadowOffset = NSSize(width: 0, height: -10)
cardShadow.set()
hex(0xF3F4F6).setFill(); rr(212, 236, 600, 370, 58).fill()
NSGraphicsContext.restoreGraphicsState()

// Text lines; the accent one is the "current" clip.
hex(0x4F8CFF).setFill(); rr(276, 489, 250, 38, 19).fill()
hex(0xC8CBD2).setFill()
rr(276, 423, 472, 30, 15).fill()
rr(276, 369, 400, 30, 15).fill()
rr(276, 315, 300, 30, 15).fill()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
