import AppKit

struct Limit { let name: String; let percent: Double; let resets: Date?; var seconds: Double = 0 }     // seconds: window length (ChatGPT only)

func parseDate(_ t: String) -> Date? {
    let clean = t.replacingOccurrences(of: "\\.\\d+", with: "", options: .regularExpression)
    return ISO8601DateFormatter().date(from: clean)
}

/// Turns the oauth usage response into limits. Unknown or missing sections are skipped, so a changed response degrades
/// to "fewer limits" rather than a crash.
func parseClaudeLimits(_ json: [String: Any]) -> [Limit] {
    var result: [Limit] = []
    for (key, name) in [("five_hour", "Current session"), ("seven_day", "Weekly – all models"),
                        ("seven_day_opus", "Weekly – Opus"), ("seven_day_sonnet", "Weekly – Sonnet")] {
        guard let o = json[key] as? [String: Any], let u = (o["utilization"] as? NSNumber)?.doubleValue else { continue }
        result.append(Limit(name: name, percent: u, resets: (o["resets_at"] as? String).flatMap(parseDate)))
    }
    // Fallback: the response also carries a `limits` list ({kind, percent, resets_at}). If the classic sections ever disappear,
    // the same limits are read from there, so a reshuffled response still shows your numbers.
    if let list = json["limits"] as? [[String: Any]] {
        for item in list {
            guard let kind = (item["kind"] as? String)?.lowercased(), let pct = (item["percent"] as? NSNumber)?.doubleValue else { continue }
            let name: String? = kind == "session" ? "Current session" : kind == "weekly_all" ? "Weekly – all models"
                : kind.contains("opus") ? "Weekly – Opus" : kind.contains("sonnet") ? "Weekly – Sonnet" : nil
            guard let n = name, !result.contains(where: { $0.name == n }) else { continue }
            result.append(Limit(name: n, percent: pct, resets: (item["resets_at"] as? String).flatMap(parseDate)))
        }
    }
    return result
}

/// Reads Claude Code's own login from the keychain and asks Anthropic for the same
/// session / weekly usage numbers that Claude Code's /usage view shows.
func fetchLimits() -> (limits: [Limit], error: String?) {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
    let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
    do { try p.run() } catch { return ([], "Can't read Claude Code login") }
    DispatchQueue.global().asyncAfter(deadline: .now() + 10) { if p.isRunning { p.terminate() } }   // never hang on a keychain prompt
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
    let result = parseClaudeLimits(json)
    return (result, result.isEmpty ? "Usage response not recognised – Claude may have changed it" : nil)
}

func untilText(_ d: Date?) -> String {
    guard let d = d else { return "" }
    let secs = Int(Clock.until(d))
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
    return trustedExecutable(["/opt/homebrew/bin/claude", "/usr/local/bin/claude", "\(home)/.local/bin/claude", "\(home)/.claude/local/claude"])
}

/// The first of `paths` that is an executable we are willing to run. Package-manager and system folders come first; a
/// program in your own folders is only used if you own it and nobody else can write to it (or the folder it links to),
/// so another program can't just drop a fake `claude` there.
func trustedExecutable(_ paths: [String]) -> String? {
    let fm = FileManager.default, me = getuid()
    for p in paths where fm.isExecutableFile(atPath: p) {
        let real = URL(fileURLWithPath: p).resolvingSymlinksInPath().path
        guard let a = try? fm.attributesOfItem(atPath: real), let owner = (a[.ownerAccountID] as? NSNumber)?.uint32Value,
              let mode = (a[.posixPermissions] as? NSNumber)?.intValue else { continue }
        if (owner == me || owner == 0), mode & 0o022 == 0 { return p }          // owned by you or root, not group/world-writable
    }
    return nil
}

@discardableResult
func runClaude(_ args: [String]) -> (ok: Bool, out: Data) {
    guard let bin = claudeBinary() else { return (false, Data()) }
    let p = Process(); p.executableURL = URL(fileURLWithPath: bin); p.arguments = args
    var env = ProcessInfo.processInfo.environment
    env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:\(NSHomeDirectory())/.local/bin"      // fixed order: your own folder last
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

