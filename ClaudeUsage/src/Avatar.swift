import AppKit

// MARK: - Profile photo (stored locally, never uploaded)

/// Developer overrides (CUB_* environment variables and the install/auto-update flags) only work in test copies
/// (any bundle id other than the shipped "local.claudeusage"), so something that controls the launch environment
/// can't redirect the real app's data folders or trigger installs.
enum Dev {
    static let production = Bundle.main.bundleIdentifier == "local.claudeusage"
    static func env(_ key: String) -> String? { production ? nil : ProcessInfo.processInfo.environment[key] }
    static func flag(_ name: String) -> Bool { !production && CommandLine.arguments.contains(name) }
}

/// The current time. In a test copy, `CUB_FROZEN_NOW` (seconds since 1970) freezes it so screenshots don't depend on the time of day;
/// the shipped app always uses the real clock.
enum Clock {
    private static let frozen: Date? = Dev.env("CUB_FROZEN_NOW").flatMap(Double.init).map { Date(timeIntervalSince1970: $0) }
    static var now: Date { frozen ?? Date() }
    /// Seconds from now until `d` (negative if in the past) – the frozen-clock version of `d.timeIntervalSinceNow`.
    static func until(_ d: Date) -> TimeInterval { d.timeIntervalSince(now) }
}

func supportDir() -> URL {
    let base = Dev.env("CUB_SUPPORT_DIR").map { URL(fileURLWithPath: $0) }
        ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ClaudeUsage")
    // Migrate data from the app's previous name ("Claude Usage Bar") so history and photo carry over.
    let old = base.deletingLastPathComponent().appendingPathComponent("ClaudeUsage" + "Bar")
    if base.lastPathComponent == "ClaudeUsage", !FileManager.default.fileExists(atPath: base.path), FileManager.default.fileExists(atPath: old.path) {
        try? FileManager.default.moveItem(at: old, to: base)
    }
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])   // private to you: it holds usage history
    try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: base.path)
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
