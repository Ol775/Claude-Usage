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

// MARK: - Stock robot avatars (original artwork, used as account pictures)

enum BotEyes { case square, round, happy, visor, sleepy, wide }
enum BotTop { case antenna, twin, halo, none }

struct BotStyle {
    let name: String
    let bgTop: NSColor, bgBottom: NSColor
    let body: NSColor, face: NSColor
    let eyes: BotEyes, top: BotTop, smile: Bool
}

private func c(_ r: Double, _ g: Double, _ b: Double) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }

let stockBots: [BotStyle] = [
    BotStyle(name: "Claude",  bgTop: c(0.20, 0.20, 0.23), bgBottom: c(0.07, 0.07, 0.09), body: c(1.00, 0.55, 0.33), face: c(0.12, 0.12, 0.14), eyes: .square, top: .antenna, smile: false),
    BotStyle(name: "Sky",     bgTop: c(0.16, 0.28, 0.52), bgBottom: c(0.06, 0.10, 0.24), body: c(0.45, 0.72, 1.00), face: c(0.07, 0.12, 0.28), eyes: .round,  top: .antenna, smile: true),
    BotStyle(name: "Mint",    bgTop: c(0.12, 0.38, 0.30), bgBottom: c(0.04, 0.16, 0.14), body: c(0.40, 0.88, 0.62), face: c(0.05, 0.20, 0.16), eyes: .happy,  top: .antenna, smile: true),
    BotStyle(name: "Violet",  bgTop: c(0.32, 0.20, 0.55), bgBottom: c(0.12, 0.07, 0.26), body: c(0.74, 0.60, 1.00), face: c(0.14, 0.09, 0.30), eyes: .visor,  top: .twin,    smile: false),
    BotStyle(name: "Rose",    bgTop: c(0.55, 0.16, 0.34), bgBottom: c(0.24, 0.06, 0.15), body: c(1.00, 0.52, 0.70), face: c(0.28, 0.07, 0.17), eyes: .round,  top: .twin,    smile: true),
    BotStyle(name: "Sunny",   bgTop: c(0.55, 0.38, 0.12), bgBottom: c(0.26, 0.15, 0.04), body: c(1.00, 0.84, 0.30), face: c(0.28, 0.17, 0.05), eyes: .wide,   top: .none,    smile: true),
    BotStyle(name: "Night",   bgTop: c(0.10, 0.10, 0.11), bgBottom: c(0.00, 0.00, 0.00), body: c(0.82, 0.83, 0.86), face: c(1.00, 0.55, 0.33), eyes: .square, top: .halo,    smile: false),
    BotStyle(name: "Frost",   bgTop: c(0.86, 0.93, 1.00), bgBottom: c(0.66, 0.80, 0.96), body: c(1.00, 1.00, 1.00), face: c(0.16, 0.26, 0.48), eyes: .round,  top: .antenna, smile: true),
    BotStyle(name: "Ember",   bgTop: c(0.50, 0.12, 0.10), bgBottom: c(0.20, 0.04, 0.04), body: c(1.00, 0.42, 0.30), face: c(1.00, 0.88, 0.40), eyes: .visor,  top: .twin,    smile: false),
    BotStyle(name: "Lime",    bgTop: c(0.12, 0.40, 0.36), bgBottom: c(0.04, 0.17, 0.17), body: c(0.74, 0.94, 0.36), face: c(0.06, 0.22, 0.20), eyes: .sleepy, top: .antenna, smile: false),
    BotStyle(name: "Ocean",   bgTop: c(0.08, 0.34, 0.46), bgBottom: c(0.03, 0.12, 0.22), body: c(0.30, 0.85, 0.85), face: c(0.04, 0.16, 0.24), eyes: .happy,  top: .halo,    smile: true),
    BotStyle(name: "Peach",   bgTop: c(1.00, 0.90, 0.76), bgBottom: c(0.99, 0.74, 0.58), body: c(0.90, 0.42, 0.30), face: c(1.00, 0.94, 0.86), eyes: .round,  top: .antenna, smile: true),
]

/// Draws one stock robot on a square background (the avatar view clips it to a circle).
func drawStockBot(_ s: BotStyle, in r: NSRect) {
    NSGradient(starting: s.bgTop, ending: s.bgBottom)!.draw(in: r, angle: -90)
    let size = r.width * 0.72
    let b = NSRect(x: r.midX - size / 2, y: r.midY - size / 2 - r.height * 0.02, width: size, height: size)
    func pt(_ x: Double, _ y: Double) -> NSPoint { NSPoint(x: b.minX + b.width * x, y: b.minY + b.height * y) }
    func box(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ rad: Double) -> NSBezierPath {
        NSBezierPath(roundedRect: NSRect(x: b.minX + b.width * x0, y: b.minY + b.height * y0, width: b.width * (x1 - x0), height: b.height * (y1 - y0)), xRadius: b.width * rad, yRadius: b.width * rad)
    }
    func dot(_ x: Double, _ y: Double, _ rad: Double) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: pt(x, y).x - b.width * rad, y: pt(x, y).y - b.width * rad, width: b.width * rad * 2, height: b.width * rad * 2))
    }
    s.body.setFill()
    for p in [box(0.02, 0.44, 0.14, 0.62, 0.04), box(0.86, 0.44, 0.98, 0.62, 0.04), box(0.12, 0.26, 0.88, 0.80, 0.14), box(0.24, 0.10, 0.40, 0.27, 0.03), box(0.60, 0.10, 0.76, 0.27, 0.03)] { p.fill() }

    switch s.top {
    case .antenna: box(0.46, 0.78, 0.54, 0.90, 0.02).fill(); dot(0.5, 0.93, 0.07).fill()
    case .twin:
        for x in [0.30, 0.70] { box(x - 0.03, 0.78, x + 0.03, 0.89, 0.02).fill(); dot(x, 0.92, 0.055).fill() }
    case .halo:
        let halo = NSBezierPath(ovalIn: NSRect(x: pt(0.30, 0).x, y: pt(0, 0.84).y, width: b.width * 0.40, height: b.height * 0.11))
        halo.lineWidth = b.width * 0.035; s.body.setStroke(); halo.stroke()
    case .none: break
    }

    s.face.setFill(); s.face.setStroke()
    func stroke(_ p: NSBezierPath) { p.lineWidth = b.width * 0.04; p.lineCapStyle = .round; p.stroke() }
    func arc(_ x: Double, _ y: Double, _ rad: Double, _ a0: CGFloat, _ a1: CGFloat) -> NSBezierPath {
        let p = NSBezierPath(); p.appendArc(withCenter: pt(x, y), radius: b.width * rad, startAngle: a0, endAngle: a1); return p
    }
    switch s.eyes {
    case .square: box(0.29, 0.48, 0.43, 0.66, 0.04).fill(); box(0.57, 0.48, 0.71, 0.66, 0.04).fill()
    case .round: dot(0.36, 0.57, 0.075).fill(); dot(0.64, 0.57, 0.075).fill()
    case .wide:
        dot(0.36, 0.57, 0.105).fill(); dot(0.64, 0.57, 0.105).fill()
        s.body.setFill(); dot(0.38, 0.59, 0.035).fill(); dot(0.66, 0.59, 0.035).fill()
    case .happy: stroke(arc(0.36, 0.54, 0.075, 15, 165)); stroke(arc(0.64, 0.54, 0.075, 15, 165))
    case .visor: box(0.24, 0.48, 0.76, 0.64, 0.05).fill()
    case .sleepy: box(0.28, 0.555, 0.44, 0.585, 0.012).fill(); box(0.56, 0.555, 0.72, 0.585, 0.012).fill()
    }
    if s.smile { s.face.setStroke(); stroke(arc(0.5, 0.47, 0.11, 205, 335)) }
}

/// Renders (and caches) stock avatar `i` at 256x256.
private var stockCache: [Int: NSImage] = [:]
func stockAvatarImage(_ i: Int) -> NSImage {
    if let c = stockCache[i] { return c }
    let img = NSImage(size: NSSize(width: 256, height: 256), flipped: false) { rect in
        drawStockBot(stockBots[i % stockBots.count], in: rect); return true
    }
    stockCache[i] = img
    return img
}
