import AppKit
import UserNotifications
import ServiceManagement
import UniformTypeIdentifiers

let menuWidth: CGFloat = 340
let claudeOrange = NSColor(name: nil) { a in
    a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(srgbRed: 1.00, green: 0.55, blue: 0.33, alpha: 1)   // bright on dark glass
        : NSColor(srgbRed: 0.80, green: 0.31, blue: 0.10, alpha: 1)   // deep on light glass
}
let alertRed = NSColor(srgbRed: 1.0, green: 0.30, blue: 0.27, alpha: 1)

struct Usage { var input = 0, output = 0, cacheWrite = 0, cacheRead = 0
    var billable: Int { input + output + cacheWrite }   // excludes cheap cache reads
    var total: Int { billable + cacheRead }
    mutating func add(_ o: Usage) { input += o.input; output += o.output; cacheWrite += o.cacheWrite; cacheRead += o.cacheRead }
}

struct Snapshot { var today = Usage(), window5h = Usage(), week = Usage(), month = Usage()
    var byModelToday: [String: Usage] = [:]; var messagesToday = 0
    var daily = [Int](repeating: 0, count: 14); var hourly = [Int](repeating: 0, count: 24); var updated = Date() }

func fmt(_ n: Int) -> String {
    switch n { case 1_000_000...: return String(format: "%.1fM", Double(n)/1e6)
    case 1_000...: return String(format: "%.1fK", Double(n)/1e3)
    default: return "\(n)" }
}

func scan() -> Snapshot {
    var snap = Snapshot()
    let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return snap }
    let now = Date(), cal = Calendar.current
    let startToday = cal.startOfDay(for: now)
    let start5h = now.addingTimeInterval(-5*3600), start7d = now.addingTimeInterval(-7*86400)
    let startMonth = cal.date(from: cal.dateComponents([.year,.month], from: now))!
    let start14d = cal.date(byAdding: .day, value: -13, to: startToday)!
    let oldest = min(start7d, startMonth, start14d)
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let iso2 = ISO8601DateFormatter()
    var seen = Set<String>()
    for case let url as URL in en where url.pathExtension == "jsonl" {
        if let m = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, m < oldest { continue }
        guard let data = try? Data(contentsOf: url) else { continue }
        for line in data.split(separator: 10) {
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let msg = obj["message"] as? [String: Any], let u = msg["usage"] as? [String: Any],
                  let ts = obj["timestamp"] as? String,
                  let date = iso.date(from: ts) ?? iso2.date(from: ts), date >= oldest else { continue }
            let key = "\(msg["id"] as? String ?? "")|\(obj["requestId"] as? String ?? "")"
            if key != "|" { if seen.contains(key) { continue }; seen.insert(key) }
            let use = Usage(input: u["input_tokens"] as? Int ?? 0, output: u["output_tokens"] as? Int ?? 0,
                            cacheWrite: u["cache_creation_input_tokens"] as? Int ?? 0, cacheRead: u["cache_read_input_tokens"] as? Int ?? 0)
            if date >= startMonth { snap.month.add(use) }
            if date >= start7d { snap.week.add(use) }
            if date >= start5h { snap.window5h.add(use) }
            if date >= start14d {
                let d = cal.dateComponents([.day], from: start14d, to: cal.startOfDay(for: date)).day ?? 0
                if (0..<14).contains(d) { snap.daily[d] += use.billable }
            }
            if date >= startToday {
                snap.hourly[min(23, cal.component(.hour, from: date))] += use.billable
                snap.today.add(use); snap.messagesToday += 1
                snap.byModelToday[msg["model"] as? String ?? "unknown", default: Usage()].add(use)
            }
        }
    }
    return snap
}

final class ChartView: NSView {
    let values: [Int]; let title: String; let labels: [String]; let highlight: Int
    init(title: String, values: [Int], labels: [String], highlight: Int) {
        self.title = title; self.values = values; self.labels = labels; self.highlight = highlight
        super.init(frame: NSRect(x: 0, y: 0, width: menuWidth, height: 140))
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ r: NSRect) {
        let small: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.secondaryLabelColor]
        let mx = max(values.max() ?? 0, 1)
        NSAttributedString(string: title, attributes: [.font: NSFont.boldSystemFont(ofSize: 12), .foregroundColor: claudeOrange]).draw(at: NSPoint(x: 16, y: 118))
        let peak = NSAttributedString(string: "peak " + fmt(mx), attributes: small)
        peak.draw(at: NSPoint(x: bounds.width - 16 - peak.size().width, y: 119))
        let left: CGFloat = 16, bottom: CGFloat = 26, top: CGFloat = 108
        let w = bounds.width - 2*left, n = CGFloat(values.count), gap: CGFloat = 2
        let bw = (w - gap*(n-1)) / n
        for (i, v) in values.enumerated() {
            let h = v == 0 ? 1 : max(2, CGFloat(v)/CGFloat(mx) * (top - bottom))
            let rect = NSRect(x: left + CGFloat(i)*(bw+gap), y: bottom, width: bw, height: h)
            NSColor.labelColor.withAlphaComponent(0.10).setFill()
            NSBezierPath(roundedRect: NSRect(x: rect.minX, y: bottom, width: bw, height: top - bottom), xRadius: 2, yRadius: 2).fill()
            (i == highlight ? claudeOrange : claudeOrange.withAlphaComponent(0.7)).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
        }
        for (i, t) in labels.enumerated() where !t.isEmpty {
            let a = NSAttributedString(string: t, attributes: small)
            let cx = left + CGFloat(i)*(bw+gap) + bw/2
            a.draw(at: NSPoint(x: min(max(left, cx - a.size().width/2), bounds.width - left - a.size().width), y: 8))
        }
    }
}

final class RowView: NSView {
    init(left: String, right: String = "", sub: String = "", leftBold: Bool = true, size: CGFloat = 13, tint: NSColor = .labelColor) {
        let h: CGFloat = sub.isEmpty ? 28 : 48
        super.init(frame: NSRect(x: 0, y: 0, width: menuWidth, height: h))
        func label(_ t: String, _ f: NSFont, _ c: NSColor, _ a: NSTextAlignment) -> NSTextField {
            let l = NSTextField(labelWithString: t); l.font = f; l.textColor = c; l.alignment = a
            l.lineBreakMode = .byTruncatingTail; return l
        }
        let top: CGFloat = sub.isEmpty ? 5 : 26
        let l = label(left, leftBold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size), tint, .left)
        l.frame = NSRect(x: 16, y: top, width: menuWidth - 32 - (right.isEmpty ? 0 : 90), height: 17); addSubview(l)
        let r = label(right, .monospacedDigitSystemFont(ofSize: size, weight: leftBold ? .semibold : .regular), leftBold ? claudeOrange : .labelColor, .right)
        r.frame = NSRect(x: menuWidth - 16 - 90, y: top, width: 90, height: 17); addSubview(r)
        if !sub.isEmpty {
            let sl = label(sub, .systemFont(ofSize: 10.5), .secondaryLabelColor, .left)
            sl.frame = NSRect(x: 16, y: 7, width: menuWidth - 32, height: 14); addSubview(sl)
        }
    }
    required init?(coder: NSCoder) { fatalError() }
}

struct Limit { let name: String; let percent: Double; let resets: Date? }

func parseDate(_ t: String) -> Date? {
    let clean = t.replacingOccurrences(of: "\\.\\d+", with: "", options: .regularExpression)
    return ISO8601DateFormatter().date(from: clean)
}

/// Reads Claude Code's own login from the keychain and asks Anthropic for the same
/// session / weekly usage numbers that Claude Code's /usage view shows.
func fetchLimits() -> (limits: [Limit], error: String?) {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
    let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
    do { try p.run() } catch { return ([], "Can't read Claude Code login") }
    let out = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
    guard let cred = try? JSONSerialization.jsonObject(with: out) as? [String: Any],
          let oauth = cred["claudeAiOauth"] as? [String: Any], let token = oauth["accessToken"] as? String
    else { return ([], "Sign in to Claude Code to see limits") }
    var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, timeoutInterval: 15)
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
    req.setValue("claude-code/2.0", forHTTPHeaderField: "User-Agent")
    let sem = DispatchSemaphore(value: 0)
    var body: Data?; var status = 0
    URLSession.shared.dataTask(with: req) { d, r, _ in body = d; status = (r as? HTTPURLResponse)?.statusCode ?? 0; sem.signal() }.resume()
    sem.wait()
    if status == 401 { return ([], "Login expired – open Claude Code to refresh") }
    guard status == 200, let d = body, let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
    else { return ([], "Usage unavailable (HTTP \(status))") }
    var result: [Limit] = []
    for (key, name) in [("five_hour", "Current session"), ("seven_day", "Weekly – all models"),
                        ("seven_day_opus", "Weekly – Opus"), ("seven_day_sonnet", "Weekly – Sonnet")] {
        guard let o = json[key] as? [String: Any], let u = (o["utilization"] as? NSNumber)?.doubleValue else { continue }
        result.append(Limit(name: name, percent: u, resets: (o["resets_at"] as? String).flatMap(parseDate)))
    }
    return (result, result.isEmpty ? "No limit data returned" : nil)
}

func untilText(_ d: Date?) -> String {
    guard let d = d else { return "" }
    let secs = Int(d.timeIntervalSinceNow)
    guard secs > 0 else { return "resetting now" }
    let days = secs / 86400, h = (secs % 86400) / 3600, m = (secs % 3600) / 60
    let rel = days > 0 ? "\(days)d \(h)h" : (h > 0 ? "\(h)h \(m)m" : "\(m)m")
    let f = DateFormatter()
    f.dateFormat = Calendar.current.isDateInToday(d) ? "h:mm a" : "EEE d MMM, h:mm a"
    return "Resets in \(rel) · \(f.string(from: d))"
}

struct Account { var loggedIn = false; var email = ""; var plan = "" 
    var name: String {
        let local = email.split(separator: "@").first.map(String.init) ?? ""
        let parts = local.split(whereSeparator: { ".-_".contains($0) }).map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
        return parts.isEmpty ? "Claude account" : parts.joined(separator: " ")
    }
    var initials: String {
        let w = name.split(separator: " ")
        return w.isEmpty ? "?" : w.prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }
}

func claudeBinary() -> String? {
    let home = NSHomeDirectory()
    return ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude", "\(home)/.claude/local/claude"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }
}

@discardableResult
func runClaude(_ args: [String]) -> (ok: Bool, out: Data) {
    guard let bin = claudeBinary() else { return (false, Data()) }
    let p = Process(); p.executableURL = URL(fileURLWithPath: bin); p.arguments = args
    var env = ProcessInfo.processInfo.environment
    env["PATH"] = "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
    p.environment = env
    let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
    do { try p.run() } catch { return (false, Data()) }
    let out = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
    return (p.terminationStatus == 0, out)
}

/// Account info from Claude Code's own `claude auth status` (no token handling here).
func fetchAccount() -> Account {
    let r = runClaude(["auth", "status", "--json"])
    guard let d = try? JSONSerialization.jsonObject(with: r.out) as? [String: Any] else { return Account() }
    var a = Account()
    a.loggedIn = d["loggedIn"] as? Bool ?? false
    a.email = d["email"] as? String ?? ""
    a.plan = (d["subscriptionType"] as? String)?.capitalized ?? ""
    return a
}

final class AccountView: NSView {
    let account: Account
    init(_ a: Account) { account = a; super.init(frame: NSRect(x: 0, y: 0, width: menuWidth, height: 68)) }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ r: NSRect) {
        drawAvatar(in: NSRect(x: 16, y: 14, width: 40, height: 40), account: account)
        let title = account.loggedIn ? account.name : "Not signed in"
        NSAttributedString(string: title, attributes: [.font: NSFont.boldSystemFont(ofSize: 14), .foregroundColor: NSColor.labelColor]).draw(at: NSPoint(x: 66, y: 34))
        let sub = account.loggedIn ? [account.email, account.plan.isEmpty ? "" : "\(account.plan) plan"].filter { !$0.isEmpty }.joined(separator: " · ") : "Choose “Sign in with Claude…” below"
        NSAttributedString(string: sub, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]).draw(at: NSPoint(x: 66, y: 16))
        if account.loggedIn && !account.plan.isEmpty {
            let b = NSAttributedString(string: account.plan.uppercased(), attributes: [.font: NSFont.boldSystemFont(ofSize: 9), .foregroundColor: claudeOrange])
            let w = b.size().width + 14, rect = NSRect(x: menuWidth - 16 - w, y: 38, width: w, height: 17)
            claudeOrange.withAlphaComponent(0.18).setFill(); NSBezierPath(roundedRect: rect, xRadius: 8.5, yRadius: 8.5).fill()
            b.draw(at: NSPoint(x: rect.minX + 7, y: rect.minY + 3))
        }
    }
}

// MARK: profile photo (stored locally, never uploaded)
func avatarURL() -> URL {
    let base = ProcessInfo.processInfo.environment["CUB_SUPPORT_DIR"].map { URL(fileURLWithPath: $0) }
        ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ClaudeUsageBar")
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base.appendingPathComponent("avatar.png")
}
var avatarImage: NSImage? = NSImage(contentsOf: avatarURL())

/// Centre-crops to a square, scales to 256px and saves. Returns false if the file isn't a usable image.
func saveAvatar(from url: URL) -> Bool {
    guard let src = NSImage(contentsOf: url), src.size.width > 0, src.size.height > 0 else { return false }
    let side = min(src.size.width, src.size.height)
    let crop = NSRect(x: (src.size.width - side)/2, y: (src.size.height - side)/2, width: side, height: side)
    let out = NSImage(size: NSSize(width: 256, height: 256))
    out.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    src.draw(in: NSRect(x: 0, y: 0, width: 256, height: 256), from: crop, operation: .copy, fraction: 1)
    out.unlockFocus()
    guard let tiff = out.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]),
          (try? png.write(to: avatarURL())) != nil else { return false }
    avatarImage = NSImage(data: png)
    return true
}
func removeAvatar() { try? FileManager.default.removeItem(at: avatarURL()); avatarImage = nil }

/// Draws the circular avatar: photo if there is one, otherwise orange initials, or a grey "?" when signed out.
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
        NSGradient(starting: NSColor(srgbRed: 1.0, green: 0.62, blue: 0.40, alpha: 1), ending: NSColor(srgbRed: 0.80, green: 0.34, blue: 0.16, alpha: 1))!.draw(in: path, angle: -90)
    } else { NSColor.labelColor.withAlphaComponent(0.15).setFill(); path.fill() }
    let t = NSAttributedString(string: account.loggedIn ? account.initials : "?", attributes: [.font: NSFont.systemFont(ofSize: rect.height * 0.38, weight: .semibold), .foregroundColor: account.loggedIn ? NSColor.white : NSColor.secondaryLabelColor])
    t.draw(at: NSPoint(x: rect.midX - t.size().width/2, y: rect.midY - t.size().height/2))
}

final class AvatarView: NSView {
    var account = Account() { didSet { needsDisplay = true } }
    var onClick: () -> Void = {}
    override func draw(_ r: NSRect) { drawAvatar(in: bounds, account: account) }
    override func mouseDown(with event: NSEvent) { if account.loggedIn { onClick() } }
    override func resetCursorRects() { if account.loggedIn { addCursorRect(bounds, cursor: .pointingHand) } }
}

final class AccountWindow: NSObject {
    let window: NSWindow
    let avatar = AvatarView(), title = NSTextField(labelWithString: ""), detail = NSTextField(wrappingLabelWithString: "")
    let primary = NSButton(title: "", target: nil, action: nil), secondary = NSButton(title: "", target: nil, action: nil)
    let hint = NSTextField(labelWithString: "")
    let photoButton = NSButton(title: "", target: nil, action: nil), removeButton = NSButton(title: "", target: nil, action: nil)
    var onPhoto: () -> Void = {}, onRemovePhoto: () -> Void = {}
    var onSignIn: () -> Void = {}, onSignOut: () -> Void = {}, onCancel: () -> Void = {}
    var account = Account(), busy = false

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 360), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        window.title = "Claude Usage Bar"; window.titlebarAppearsTransparent = true; window.isReleasedWhenClosed = false
        let fx = NSVisualEffectView(frame: window.contentView!.bounds); fx.material = .underWindowBackground
        fx.blendingMode = .behindWindow; fx.state = .active; fx.autoresizingMask = [.width, .height]
        window.contentView = fx
        avatar.frame = NSRect(x: 146, y: 236, width: 88, height: 88)
        title.font = .boldSystemFont(ofSize: 20); title.alignment = .center; title.frame = NSRect(x: 20, y: 196, width: 340, height: 28)
        detail.font = .systemFont(ofSize: 13); detail.textColor = .secondaryLabelColor; detail.alignment = .center
        detail.frame = NSRect(x: 40, y: 124, width: 300, height: 62)
        primary.isBordered = false; primary.wantsLayer = true
        primary.layer?.backgroundColor = NSColor(srgbRed: 0.85, green: 0.42, blue: 0.22, alpha: 1).cgColor
        primary.layer?.cornerRadius = 10; primary.frame = NSRect(x: 70, y: 72, width: 240, height: 42)
        primary.target = self; primary.action = #selector(primaryTap)
        secondary.bezelStyle = .inline; secondary.isBordered = false; secondary.frame = NSRect(x: 110, y: 30, width: 160, height: 24)
        secondary.target = self; secondary.action = #selector(secondaryTap)
        hint.font = .systemFont(ofSize: 11); hint.textColor = .secondaryLabelColor; hint.alignment = .center; hint.frame = NSRect(x: 20, y: 8, width: 340, height: 16)
        for (b, y) in [(photoButton, CGFloat(98)), (removeButton, CGFloat(74))] {
            b.bezelStyle = .inline; b.isBordered = false; b.frame = NSRect(x: 110, y: y, width: 160, height: 22); b.target = self
        }
        photoButton.action = #selector(photoTap); removeButton.action = #selector(removeTap)
        avatar.onClick = { [weak self] in self?.onPhoto() }
        [avatar, title, detail, primary, secondary, hint, photoButton, removeButton].forEach { fx.addSubview($0) }
        update(account, busy: false)
    }
    func update(_ a: Account, busy b: Bool) {
        account = a; busy = b; avatar.account = a
        window.invalidateCursorRects(for: avatar)
        photoButton.isHidden = !a.loggedIn; removeButton.isHidden = !(a.loggedIn && avatarImage != nil)
        photoButton.attributedTitle = NSAttributedString(string: avatarImage == nil ? "Choose photo…" : "Change photo…", attributes: [.foregroundColor: claudeOrange, .font: NSFont.systemFont(ofSize: 12, weight: .medium)])
        removeButton.attributedTitle = NSAttributedString(string: "Remove photo", attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.systemFont(ofSize: 12)])
        removeButton.contentTintColor = .secondaryLabelColor
        if a.loggedIn {
            title.stringValue = a.name
            detail.stringValue = [a.email, a.plan.isEmpty ? "" : "Claude \(a.plan) plan"].filter { !$0.isEmpty }.joined(separator: "\n")
            primary.isHidden = true; hint.stringValue = "Signed in · usage updates every minute"
            setSecondary("Sign out", color: .secondaryLabelColor)
        } else {
            title.stringValue = "Sign in to Claude Usage Bar"
            detail.stringValue = "Connect your Claude account to see your session and weekly limits, when they reset, and get alerts before you hit them."
            primary.isHidden = false; primary.isEnabled = !b
            primary.attributedTitle = NSAttributedString(string: b ? "Waiting for browser…" : "Sign in with Claude", attributes: [.foregroundColor: NSColor.white, .font: NSFont.boldSystemFont(ofSize: 14)])
            primary.layer?.opacity = b ? 0.6 : 1
            hint.stringValue = b ? "Finish signing in in your browser window" : "Opens Claude’s own sign-in page in your browser"
            setSecondary(b ? "Cancel" : "", color: .secondaryLabelColor)
        }
    }
    func setSecondary(_ t: String, color: NSColor) {
        secondary.isHidden = t.isEmpty
        secondary.attributedTitle = NSAttributedString(string: t, attributes: [.foregroundColor: color, .font: NSFont.systemFont(ofSize: 12)])
    }
    func show() { window.center(); NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil) }
    @objc func photoTap() { onPhoto() }
    @objc func removeTap() { onRemovePhoto() }
    @objc func primaryTap() { onSignIn() }
    @objc func secondaryTap() { account.loggedIn ? onSignOut() : onCancel() }
}

final class UsageBarView: NSView {
    let limit: Limit
    init(_ limit: Limit) { self.limit = limit; super.init(frame: NSRect(x: 0, y: 0, width: menuWidth, height: 62)) }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ r: NSRect) {
        let frac = min(max(limit.percent / 100, 0), 1)
        let color = limit.percent >= 95 ? alertRed : claudeOrange
        NSAttributedString(string: limit.name, attributes: [.font: NSFont.boldSystemFont(ofSize: 13), .foregroundColor: NSColor.labelColor]).draw(at: NSPoint(x: 16, y: 40))
        let a = NSAttributedString(string: "\(Int(limit.percent.rounded()))%", attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold), .foregroundColor: color])
        a.draw(at: NSPoint(x: menuWidth - 16 - a.size().width, y: 40))
        let track = NSRect(x: 16, y: 28, width: menuWidth - 32, height: 8)
        NSColor.labelColor.withAlphaComponent(0.12).setFill(); NSBezierPath(roundedRect: track, xRadius: 4, yRadius: 4).fill()
        var f = track; f.size.width = max(8, track.width * CGFloat(frac))
        color.setFill(); NSBezierPath(roundedRect: f, xRadius: 4, yRadius: 4).fill()
        NSAttributedString(string: untilText(limit.resets), attributes: [.font: NSFont.systemFont(ofSize: 10.5), .foregroundColor: NSColor.secondaryLabelColor]).draw(at: NSPoint(x: 16, y: 9))
    }
}

final class App: NSObject, NSApplicationDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var timer: Timer?
    var account = Account()
    let accountWindow = AccountWindow()
    var loginProcess: Process?
    var shownLogin = false
    var limits: [Limit] = []
    var limitError: String?
    var lastFetch = Date.distantPast
    static var notificationsEnabled = true
    var notified: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "notified") ?? []) }
        set { UserDefaults.standard.set(Array(newValue.suffix(60)), forKey: "notified") }
    }
    func applicationDidFinishLaunching(_ n: Notification) {
        if App.notificationsEnabled { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in } }
        item.button?.attributedTitle = NSAttributedString(string: "◆ …", attributes: [.foregroundColor: claudeOrange])
        accountWindow.onSignIn = { [weak self] in self?.signIn() }
        accountWindow.onSignOut = { [weak self] in self?.signOut() }
        accountWindow.onCancel = { [weak self] in self?.cancelSignIn() }
        accountWindow.onPhoto = { [weak self] in self?.choosePhoto() }
        accountWindow.onRemovePhoto = { [weak self] in removeAvatar(); self?.photoChanged() }
        build(Snapshot())
        if CommandLine.arguments.contains("--test-notify") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.testNotification() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { exit(0) }
            return
        }
        if CommandLine.arguments.contains("--show-account") { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.showAccount() } }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
    }
    @objc func refresh() {
        DispatchQueue.global(qos: .utility).async {
            let s = scan()
            var fetched: (limits: [Limit], error: String?)?
            var acct: Account?
            if Date().timeIntervalSince(self.lastFetch) > 100 {
                acct = fetchAccount()
                fetched = acct!.loggedIn ? fetchLimits() : ([], "Sign in to see your limits")
            }
            DispatchQueue.main.async {
                if let f = fetched { self.lastFetch = Date(); self.limits = f.limits; self.limitError = f.error; self.account = acct ?? self.account
                    self.accountWindow.update(self.account, busy: self.loginProcess != nil)
                    if !self.account.loggedIn && !self.shownLogin { self.shownLogin = true; self.accountWindow.show() } }
                self.build(s)
            }
        }
    }
    func notify(_ title: String, _ body: String) {
        guard App.notificationsEnabled else { return }
        let c = UNMutableNotificationContent(); c.title = title; c.body = body; c.sound = .default
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { st in
            if st.authorizationStatus == .authorized || st.authorizationStatus == .provisional {
                center.add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
            } else {
                // Permission denied: fall back to a plain AppleScript notification (generic icon).
                let esc = { (x: String) in x.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
                let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                p.arguments = ["-e", "display notification \"\(esc(body))\" with title \"\(esc(title))\""]
                try? p.run()
            }
        }
    }
    func checkLimits() {
        var seen = notified
        for l in limits where l.name == "Current session" || l.name == "Weekly – all models" {
            let pct = Int(l.percent)
            for t in [80, 95, 100] where pct >= t {
                let key = "\(l.name)|\(l.resets.map { Int($0.timeIntervalSince1970 / 60) } ?? 0)|\(t)"
                if seen.contains(key) { continue }
                seen.insert(key)
                let when = untilText(l.resets).replacingOccurrences(of: "Resets", with: "resets")
                notify(t >= 100 ? "\(l.name) limit reached" : "\(l.name) at \(t)%", "Usage is \(pct)% – \(when)")
            }
        }
        notified = seen
    }
    func photoChanged() { accountWindow.update(account, busy: loginProcess != nil); build(lastSnapshot) }
    func choosePhoto() {
        let panel = NSOpenPanel()
        panel.title = "Choose a profile photo"; panel.message = "The photo stays on this Mac."
        panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if saveAvatar(from: url) { photoChanged() } else {
            let a = NSAlert(); a.messageText = "Couldn’t use that image"; a.informativeText = "Pick a JPEG, PNG or HEIC photo."; a.runModal()
        }
    }
    @objc func showAccount() { accountWindow.update(account, busy: loginProcess != nil); accountWindow.show() }
    @objc func signIn() {
        guard let bin = claudeBinary() else {
            let a = NSAlert(); a.messageText = "Claude Code not found"
            a.informativeText = "Sign-in uses Claude’s official login, which comes with Claude Code. Install it (claude.com/claude-code), then try again."
            NSApp.activate(ignoringOtherApps: true); a.runModal(); return
        }
        guard loginProcess == nil else { return }
        let p = Process(); p.executableURL = URL(fileURLWithPath: bin); p.arguments = ["auth", "login"]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        p.environment = env; p.standardOutput = Pipe(); p.standardError = Pipe()
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.loginProcess = nil; self.lastFetch = .distantPast; self.refresh()
                DispatchQueue.global().async {
                    let a = fetchAccount()
                    DispatchQueue.main.async {
                        self.accountWindow.update(a, busy: false)
                        if a.loggedIn { self.notify("Signed in to Claude", "Welcome, \(a.name). Your limits are now showing in the menu bar.") }
                    }
                }
            }
        }
        do { try p.run(); loginProcess = p; accountWindow.update(account, busy: true) } catch { NSSound.beep() }
    }
    @objc func cancelSignIn() { loginProcess?.terminate() }
    @objc func signOut() {
        let a = NSAlert(); a.messageText = "Sign out of Claude?"
        a.informativeText = "This also signs out Claude Code, because they share one Claude login."
        a.addButton(withTitle: "Sign out"); a.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }
        DispatchQueue.global().async {
            runClaude(["auth", "logout"])
            DispatchQueue.main.async { self.limits = []; self.account = Account(); self.accountWindow.update(self.account, busy: false); self.lastFetch = .distantPast; self.refresh() }
        }
    }
    @objc func toggleLogin() {
        let svc = SMAppService.mainApp
        do { if svc.status == .enabled { try svc.unregister() } else { try svc.register() } } catch { NSSound.beep() }
        build(lastSnapshot)
    }
    var lastSnapshot = Snapshot()
    @objc func testNotification() { notify("Claude Usage Bar", "Notifications are working.") }
    func add(_ m: NSMenu, _ v: NSView) { let i = NSMenuItem(); i.view = v; m.addItem(i) }
    func header(_ m: NSMenu, _ t: String) { add(m, RowView(left: t.uppercased(), leftBold: true, size: 10, tint: claudeOrange)) }
    func block(_ m: NSMenu, _ name: String, _ u: Usage) {
        add(m, RowView(left: name, right: fmt(u.billable),
                       sub: "in \(fmt(u.input)) · out \(fmt(u.output)) · cache write \(fmt(u.cacheWrite)) · cache read \(fmt(u.cacheRead))"))
    }
    func build(_ s: Snapshot) {
        lastSnapshot = s
        checkLimits()
        let t = NSMutableAttributedString(string: "◆ ", attributes: [.foregroundColor: claudeOrange])
        if let sess = limits.first(where: { $0.name == "Current session" }) {
            let hot = { (p: Double) in p >= 95 ? alertRed : NSColor.labelColor }
            t.append(NSAttributedString(string: "\(Int(sess.percent.rounded()))%", attributes: [.foregroundColor: hot(sess.percent)]))
            if let w = limits.first(where: { $0.name == "Weekly – all models" }) {
                t.append(NSAttributedString(string: " · \(Int(w.percent.rounded()))%", attributes: [.foregroundColor: hot(w.percent)]))
            }
        } else {
            t.append(NSAttributedString(string: fmt(s.today.billable)))
        }
        item.button?.attributedTitle = t
        let m = NSMenu()
        add(m, AccountView(account))
        m.addItem(.separator())
        if limits.isEmpty {
            add(m, RowView(left: limitError ?? "Loading limits…", leftBold: false, size: 12, tint: .secondaryLabelColor))
        } else {
            for l in limits { add(m, UsageBarView(l)) }
        }
        m.addItem(.separator())
        block(m, "Today", s.today)
        add(m, RowView(left: "\(s.messagesToday) responses today", leftBold: false, size: 11, tint: .secondaryLabelColor))
        m.addItem(.separator())
        let cal = Calendar.current, df = DateFormatter(); df.dateFormat = "d MMM"
        let start14 = cal.date(byAdding: .day, value: -13, to: cal.startOfDay(for: Date()))!
        let dl = (0..<14).map { i -> String in
            guard [0, 4, 8, 13].contains(i) else { return "" }
            return df.string(from: cal.date(byAdding: .day, value: i, to: start14)!) }
        let c1 = NSMenuItem(); c1.view = ChartView(title: "Last 14 days", values: s.daily, labels: dl, highlight: 13); m.addItem(c1)
        let hl = (0..<24).map { $0 % 6 == 0 ? String(format: "%02d", $0) : "" }
        let c2 = NSMenuItem(); c2.view = ChartView(title: "Today by hour", values: s.hourly, labels: hl, highlight: cal.component(.hour, from: Date())); m.addItem(c2)
        m.addItem(.separator())
        block(m, "Last 7 days", s.week)
        block(m, "This month", s.month)
        if !s.byModelToday.isEmpty {
            m.addItem(.separator()); header(m, "Today by model")
            for (k, v) in s.byModelToday.sorted(by: { $0.value.billable > $1.value.billable }) {
                add(m, RowView(left: k, right: fmt(v.billable), leftBold: false, size: 12))
            }
        }
        m.addItem(.separator())
        let f = DateFormatter(); f.timeStyle = .medium
        add(m, RowView(left: "Updated \(f.string(from: s.updated)) · totals exclude cache reads", leftBold: false, size: 10, tint: .secondaryLabelColor))
        let acc = NSMenuItem(title: account.loggedIn ? "Account…" : "Sign in with Claude…", action: #selector(showAccount), keyEquivalent: ",")
        acc.target = self; m.addItem(acc)
        let ll = NSMenuItem(title: "Launch at login", action: #selector(toggleLogin), keyEquivalent: ""); ll.target = self
        ll.state = SMAppService.mainApp.status == .enabled ? .on : .off; m.addItem(ll)
        let tn = NSMenuItem(title: "Send test notification", action: #selector(testNotification), keyEquivalent: ""); tn.target = self; m.addItem(tn)
        let r = NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r"); r.target = self; m.addItem(r)
        m.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = m
    }
}

if CommandLine.arguments.contains("--snapshot") {
    _ = NSApplication.shared
    App.notificationsEnabled = false
    let d = App(); d.account = fetchAccount(); let fl = fetchLimits(); d.limits = fl.limits; d.limitError = fl.error; d.build(scan())
    let views = (d.item.menu?.items ?? []).map { $0.view ?? NSView(frame: NSRect(x: 0, y: 0, width: menuWidth, height: 9)) }
    let H = views.reduce(0) { $0 + $1.frame.height }
    let host = NSView(frame: NSRect(x: 0, y: 0, width: menuWidth, height: H))
    host.wantsLayer = true; host.layer?.backgroundColor = NSColor(white: 0.16, alpha: 1).cgColor
    for i in d.item.menu?.items ?? [] { i.view = nil }
    var y = H
    for v in views { y -= v.frame.height; v.setFrameOrigin(NSPoint(x: 0, y: y)); host.addSubview(v) }
    host.appearance = NSAppearance(named: .darkAqua)
    let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
    host.cacheDisplay(in: host.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/menu_snapshot.png"))
    exit(0)
}
if CommandLine.arguments.contains("--snapshot-window") {
    _ = NSApplication.shared
    let w = AccountWindow()
    let states: [(Account, Bool)] = [(Account(), false), (Account(), true), (fetchAccount(), false)]
    var imgs: [NSBitmapImageRep] = []
    for (a, b) in states {
        w.update(a, busy: b); w.window.contentView!.appearance = NSAppearance(named: .darkAqua)
        let v = w.window.contentView!; let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
        v.cacheDisplay(in: v.bounds, to: rep); imgs.append(rep)
    }
    let out = NSImage(size: NSSize(width: 380*3, height: 360))
    out.lockFocus(); for (i, r) in imgs.enumerated() { r.draw(in: NSRect(x: CGFloat(i)*380, y: 0, width: 380, height: 360)) }; out.unlockFocus()
    try? NSBitmapImageRep(data: out.tiffRepresentation!)!.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/window_snapshot.png"))
    exit(0)
}
let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
