import AppKit
import UserNotifications
import ServiceManagement

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
        build(Snapshot())
        if CommandLine.arguments.contains("--test-notify") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.testNotification() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { exit(0) }
            return
        }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
    }
    @objc func refresh() {
        DispatchQueue.global(qos: .utility).async {
            let s = scan()
            var fetched: (limits: [Limit], error: String?)?
            if Date().timeIntervalSince(self.lastFetch) > 100 { fetched = fetchLimits() }
            DispatchQueue.main.async {
                if let f = fetched { self.lastFetch = Date(); self.limits = f.limits; self.limitError = f.error }
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
        add(m, NSView(frame: NSRect(x: 0, y: 0, width: menuWidth, height: 8)))
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
    let d = App(); let fl = fetchLimits(); d.limits = fl.limits; d.limitError = fl.error; d.build(scan())
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
let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
