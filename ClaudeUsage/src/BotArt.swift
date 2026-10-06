import AppKit

// An original orange "bot" mascot, drawn with vector paths so it stays crisp at any size.
// To use your own artwork instead, drop a PNG at ClaudeUsage/assets/bot.png and rebuild – it replaces this drawing
// in the app icon and the menu bar.

private func botRect(_ r: NSRect, _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ rad: Double) -> NSBezierPath {
    NSBezierPath(roundedRect: NSRect(x: r.minX + r.width * x0, y: r.minY + r.height * y0, width: r.width * (x1 - x0), height: r.height * (y1 - y0)),
                 xRadius: r.width * rad, yRadius: r.width * rad)
}

/// Head/body, ears, antenna and feet (one shape).
func botBodyPath(in r: NSRect) -> NSBezierPath {
    let p = NSBezierPath()
    p.append(botRect(r, 0.12, 0.26, 0.88, 0.80, 0.14))                       // body
    p.append(botRect(r, 0.02, 0.44, 0.14, 0.62, 0.04))                       // ears
    p.append(botRect(r, 0.86, 0.44, 0.98, 0.62, 0.04))
    p.append(botRect(r, 0.46, 0.78, 0.54, 0.90, 0.02))                       // antenna
    p.append(NSBezierPath(ovalIn: NSRect(x: r.minX + r.width * 0.43, y: r.minY + r.height * 0.86, width: r.width * 0.14, height: r.height * 0.14)))
    p.append(botRect(r, 0.24, 0.10, 0.40, 0.27, 0.03))                       // feet
    p.append(botRect(r, 0.60, 0.10, 0.76, 0.27, 0.03))
    return p
}

func botEyesPath(in r: NSRect) -> NSBezierPath {
    let p = NSBezierPath()
    p.append(botRect(r, 0.29, 0.48, 0.43, 0.66, 0.04))
    p.append(botRect(r, 0.57, 0.48, 0.71, 0.66, 0.04))
    return p
}

/// Draws the bot. `eyes == nil` cuts the eyes out so whatever is behind shows through.
func drawBot(in r: NSRect, body: NSColor, eyes: NSColor?) {
    body.setFill(); botBodyPath(in: r).fill()
    let e = botEyesPath(in: r)
    if let eyes = eyes { eyes.setFill(); e.fill(); return }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current?.compositingOperation = .clear
    e.fill()
    NSGraphicsContext.restoreGraphicsState()
}
