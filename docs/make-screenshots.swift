// Frames window screenshots App Store style: caption on top, rounded window with a shadow, soft gradient behind.
// Usage: make-screenshots <out-dir> <title> <subtitle> <window.png> <style: dark|light> [more groups of 5 args…]
// Build: d=$(mktemp -d) && cp docs/make-screenshots.swift $d/main.swift && swiftc $d/main.swift -o $d/ms
import AppKit

let args = Array(CommandLine.arguments.dropFirst())
let outDir = args[0]
let W = 2400, H = 1500
func c(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }

var i = 1, n = 1
while i + 4 < args.count {
    let (title, sub, file, style) = (args[i], args[i + 1], args[i + 2], args[i + 3]); let out = args[i + 4]
    i += 5; n += 1
    guard let shot = NSImage(contentsOfFile: file) else { print("missing \(file)"); continue }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let light = style == "light"
    let bgTop = light ? c(1.00, 0.93, 0.88) : c(0.19, 0.13, 0.11), bgBottom = light ? c(0.99, 0.80, 0.68) : c(0.05, 0.05, 0.07)
    NSGradient(starting: bgTop, ending: bgBottom)!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -70)
    let ink = light ? c(0.17, 0.10, 0.07) : NSColor.white
    let para = NSMutableParagraphStyle(); para.alignment = .center
    NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 92, weight: .bold), .foregroundColor: ink, .paragraphStyle: para])
        .draw(in: NSRect(x: 0, y: H - 190, width: W, height: 120))
    NSAttributedString(string: sub, attributes: [.font: NSFont.systemFont(ofSize: 40, weight: .regular), .foregroundColor: ink.withAlphaComponent(0.7), .paragraphStyle: para])
        .draw(in: NSRect(x: 0, y: H - 260, width: W, height: 60))
    // the window, scaled to fit under the caption and cropped to a tidy height at the bottom edge
    let maxW = 1780.0, maxH = 1130.0
    let pw = Double(shot.representations.first?.pixelsWide ?? Int(shot.size.width)), ph = Double(shot.representations.first?.pixelsHigh ?? Int(shot.size.height))   // size is in points; use pixels
    let scale = maxW / pw
    let w = pw * scale, h = ph * scale
    let frame = NSRect(x: (Double(W) - w) / 2, y: Double(H) - 330 - min(h, maxH), width: w, height: min(h, maxH))
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow(); sh.shadowColor = .black.withAlphaComponent(light ? 0.28 : 0.6); sh.shadowBlurRadius = 60; sh.shadowOffset = NSSize(width: 0, height: -24); sh.set()
    NSBezierPath(roundedRect: frame, xRadius: 26, yRadius: 26).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: frame, xRadius: 26, yRadius: 26).addClip()
    shot.draw(in: NSRect(x: frame.minX, y: frame.maxY - h, width: w, height: h), from: .zero, operation: .sourceOver, fraction: 1)   // top-aligned, bottom cropped
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(out)"))
}
