import AppKit

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

