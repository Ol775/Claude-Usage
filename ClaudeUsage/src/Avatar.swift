import AppKit

// MARK: - Profile photo (stored locally, never uploaded)

func supportDir() -> URL {
    let base = ProcessInfo.processInfo.environment["CUB_SUPPORT_DIR"].map { URL(fileURLWithPath: $0) }
        ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ClaudeUsage")
    // Migrate data from the app's previous name ("Claude Usage Bar") so history and photo carry over.
    let old = base.deletingLastPathComponent().appendingPathComponent("ClaudeUsage" + "Bar")
    if base.lastPathComponent == "ClaudeUsage", !FileManager.default.fileExists(atPath: base.path), FileManager.default.fileExists(atPath: old.path) {
        try? FileManager.default.moveItem(at: old, to: base)
    }
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base
}
func avatarURL() -> URL { supportDir().appendingPathComponent("avatar.png") }
var avatarImage: NSImage? = NSImage(contentsOf: avatarURL())

/// Centre-crops to a square, scales to 256px and saves. Returns false if the file isn't a usable image.
func saveAvatar(from url: URL) -> Bool {
    guard let src = NSImage(contentsOf: url), src.size.width > 0, src.size.height > 0 else { return false }
    let side = min(src.size.width, src.size.height)
    let crop = NSRect(x: (src.size.width - side) / 2, y: (src.size.height - side) / 2, width: side, height: side)
    let out = NSImage(size: NSSize(width: 256, height: 256))
    out.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    src.draw(in: NSRect(x: 0, y: 0, width: 256, height: 256), from: crop, operation: .copy, fraction: 1)
    out.unlockFocus()
    guard let tiff = out.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]),
          (try? png.write(to: avatarURL())) != nil else { return false }
    avatarImage = NSImage(data: png)
    stockAvatarIndex = nil
    return true
}
func removeAvatar() { try? FileManager.default.removeItem(at: avatarURL()); avatarImage = nil; stockAvatarIndex = nil }

/// Which robot stock avatar is the account picture (nil when a photo or nothing is set).
var stockAvatarIndex: Int? {
    get { UserDefaults.standard.object(forKey: "stockAvatar") as? Int }
    set { if let v = newValue { UserDefaults.standard.set(v, forKey: "stockAvatar") } else { UserDefaults.standard.removeObject(forKey: "stockAvatar") } }
}

/// Uses a robot stock image as the account picture.
func setStockAvatar(_ i: Int) {
    let img = stockAvatarImage(i)
    guard let tiff = img.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]),
          (try? png.write(to: avatarURL())) != nil else { return }
    avatarImage = NSImage(data: png)
    stockAvatarIndex = i
}

/// Circular avatar for AppKit views: the photo if there is one, else accent-coloured initials, or a grey "?" when signed out.
func drawAvatar(in rect: NSRect, account: Account) {
    let path = NSBezierPath(ovalIn: rect)
    if account.loggedIn, let img = avatarImage {
        NSGraphicsContext.saveGraphicsState(); path.addClip()
        img.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        NSColor.labelColor.withAlphaComponent(0.2).setStroke(); path.lineWidth = 1; path.stroke()
        return
    }
    if account.loggedIn {
        NSGradient(starting: claudeOrange.withAlphaComponent(0.85), ending: claudeOrange)!.draw(in: path, angle: -90)
    } else { NSColor.labelColor.withAlphaComponent(0.15).setFill(); path.fill() }
    let fg: NSColor = account.loggedIn ? .white : .secondaryLabelColor
    let t = NSAttributedString(string: account.loggedIn ? account.initials : "?", attributes: [.font: NSFont.systemFont(ofSize: rect.height * 0.38, weight: .semibold), .foregroundColor: fg])
    t.draw(at: NSPoint(x: rect.midX - t.size().width / 2, y: rect.midY - t.size().height / 2))
}
