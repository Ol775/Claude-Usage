import AppKit
let custom: NSImage? = CommandLine.arguments.count > 2 ? NSImage(contentsOfFile: CommandLine.arguments[2]) : nil

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let inset = s * 0.085, body = NSRect(x: inset, y: inset, width: s - 2*inset, height: s - 2*inset)
    let path = NSBezierPath(roundedRect: body, xRadius: s * 0.225, yRadius: s * 0.225)
    NSGradient(starting: NSColor(srgbRed: 1.00, green: 0.60, blue: 0.38, alpha: 1),
               ending: NSColor(srgbRed: 0.80, green: 0.34, blue: 0.16, alpha: 1))!.draw(in: path, angle: -90)
    // the bot (or custom artwork from assets/bot.png), centred on the tile
    let side = s * 0.60, area = NSRect(x: (s - side) / 2, y: (s - side) / 2 - s * 0.015, width: side, height: side)
    if let c = custom { c.draw(in: area, from: .zero, operation: .sourceOver, fraction: 1) }
    else { drawBot(in: area, body: .white, eyes: NSColor(srgbRed: 0.83, green: 0.36, blue: 0.17, alpha: 1)) }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
let dir = CommandLine.arguments[1]
for (base, scale, px) in [(16,1,16),(16,2,32),(32,1,32),(32,2,64),(128,1,128),(128,2,256),(256,1,256),(256,2,512),(512,1,512),(512,2,1024)] {
    let suffix = scale == 2 ? "@2x" : ""
    try! render(px).write(to: URL(fileURLWithPath: "\(dir)/icon_\(base)x\(base)\(suffix).png"))
}
