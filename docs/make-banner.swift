// Renders docs/banner.png (1280x640, GitHub social preview + README header) from the app's own bot artwork.
// Build: d=$(mktemp -d) && cp docs/make-banner.swift $d/main.swift && swiftc $d/main.swift ClaudeUsage/src/BotArt.swift -o $d/mb && $d/mb docs/banner.png
import AppKit

let W = 1280, H = 640
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func c(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
let orange = c(1.00, 0.55, 0.33)

// background
NSGradient(starting: c(0.13, 0.13, 0.15), ending: c(0.05, 0.05, 0.07))!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -60)
let glow = NSGradient(colors: [orange.withAlphaComponent(0.22), orange.withAlphaComponent(0)])!
glow.draw(fromCenter: NSPoint(x: 250, y: 420), radius: 0, toCenter: NSPoint(x: 250, y: 420), radius: 420, options: [])

// app icon tile
let tile = NSRect(x: 90, y: 250, width: 240, height: 240)
let tp = NSBezierPath(roundedRect: tile, xRadius: 54, yRadius: 54)
NSGraphicsContext.saveGraphicsState()
let sh = NSShadow(); sh.shadowColor = .black.withAlphaComponent(0.5); sh.shadowBlurRadius = 30; sh.shadowOffset = NSSize(width: 0, height: -10); sh.set()
NSGradient(starting: c(0.20, 0.20, 0.23), ending: c(0.07, 0.07, 0.09))!.draw(in: tp, angle: -90)
NSGraphicsContext.restoreGraphicsState()
drawBot(in: NSRect(x: tile.minX + 48, y: tile.minY + 44, width: 144, height: 144), body: orange, eyes: c(0.12, 0.12, 0.14))

func text(_ s: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]).draw(at: NSPoint(x: x, y: y))
}
text("Claude Usage", 90, 150, size: 84, weight: .bold, color: .white)
text("Session and weekly limits in your Mac’s menu bar", 94, 98, size: 30, weight: .regular, color: c(1, 1, 1, 0.72))
text("Forecasts · Reports · Insights · Unofficial", 94, 56, size: 22, weight: .medium, color: orange)

// a mock menu bar card on the right
let card = NSRect(x: 700, y: 140, width: 480, height: 360)
let cp = NSBezierPath(roundedRect: card, xRadius: 28, yRadius: 28)
c(1, 1, 1, 0.06).setFill(); cp.fill()
c(1, 1, 1, 0.12).setStroke(); cp.lineWidth = 1.5; cp.stroke()
func bar(_ label: String, _ pct: Double, _ reset: String, y: CGFloat) {
    text(label, card.minX + 36, y + 62, size: 26, weight: .semibold, color: .white)
    let p = "\(Int(pct * 100))%"
    let w = NSAttributedString(string: p, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 26, weight: .bold)]).size().width
    NSAttributedString(string: p, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 26, weight: .bold), .foregroundColor: orange]).draw(at: NSPoint(x: card.maxX - 36 - w, y: y + 62))
    let track = NSRect(x: card.minX + 36, y: y + 32, width: card.width - 72, height: 16)
    c(1, 1, 1, 0.12).setFill(); NSBezierPath(roundedRect: track, xRadius: 8, yRadius: 8).fill()
    orange.setFill(); NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.minY, width: track.width * pct, height: 16), xRadius: 8, yRadius: 8).fill()
    text(reset, card.minX + 36, y, size: 20, weight: .regular, color: c(1, 1, 1, 0.6))
}
bar("Current session", 0.42, "Resets in 2 hr 10 min", y: card.minY + 215)
bar("Weekly limit", 0.27, "Resets Friday 09:00 · on pace, safe", y: card.minY + 90)
text("D 42%  ·  W 27%", card.minX + 36, card.minY + 28, size: 22, weight: .medium, color: c(1, 1, 1, 0.5))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
