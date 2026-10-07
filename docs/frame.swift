import AppKit
// Makes the README gallery images. Capture a demo test copy's window first (CUB_DEMO=1, re-identified copy,
// `screencapture -x -o -l <window id>`; see ClaudeUsage/tests/README.md), then:
//   swiftc -O docs/frame.swift -o build/frame && build/frame window.png docs/screenshots/1-overview.png dark "Headline" "Subline"
// frame <window.png> <out.png> <dark|light> <headline> <subline>
// 2400×1500 gallery image: gradient background, centred headline and subline, the window below (clipped at the bottom, with a shadow).
let a = CommandLine.arguments
let win = NSImage(contentsOfFile: a[1])!, dark = a[3] == "dark"
let W: CGFloat = 2400, H: CGFloat = 1500
let img = NSImage(size: NSSize(width: W, height: H), flipped: true) { _ in
    let bg = dark ? NSGradient(colors: [NSColor(srgbRed: 0.18, green: 0.13, blue: 0.11, alpha: 1), NSColor(srgbRed: 0.07, green: 0.07, blue: 0.07, alpha: 1)])!
                  : NSGradient(colors: [NSColor(srgbRed: 0.99, green: 0.93, blue: 0.88, alpha: 1), NSColor(srgbRed: 0.98, green: 0.80, blue: 0.68, alpha: 1)])!
    bg.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: 60)
    func centred(_ s: String, _ f: NSFont, _ c: NSColor, _ y: CGFloat) {
        let t = NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: c, .kern: f.pointSize > 60 ? -f.pointSize * 0.01 : 0])
        t.draw(at: NSPoint(x: (W - t.size().width) / 2, y: y))
    }
    centred(a[4], .systemFont(ofSize: 104, weight: .bold), dark ? .white : NSColor(white: 0.12, alpha: 1), 62)
    centred(a[5], .systemFont(ofSize: 40, weight: .regular), dark ? NSColor(white: 1, alpha: 0.72) : NSColor(white: 0.25, alpha: 1), 200)
    let x: CGFloat = 310, y: CGFloat = 330, w: CGFloat = 1780, h = w * win.size.height / win.size.width
    let clip = NSRect(x: x, y: y, width: w, height: min(h, 1460 - y))
    let path = NSBezierPath(roundedRect: clip, xRadius: 26, yRadius: 26)
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.55 : 0.25); sh.shadowBlurRadius = 60; sh.shadowOffset = NSSize(width: 0, height: -20); sh.set()
    NSColor.black.setFill(); path.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState(); path.addClip()
    win.draw(in: NSRect(x: x, y: y, width: w, height: h), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
    NSGraphicsContext.restoreGraphicsState()
    NSColor(white: dark ? 1 : 0, alpha: 0.12).setStroke(); path.lineWidth = 2; path.stroke()
    return true
}
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
img.draw(in: NSRect(x: 0, y: 0, width: W, height: H)); NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))
