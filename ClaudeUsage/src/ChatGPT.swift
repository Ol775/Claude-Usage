import Foundation

/// ChatGPT usage limits, read through OpenAI's Codex CLI sign-in (`codex login`). Opt-in: nothing is read until the user connects.
struct ChatGPTState {
    var signedIn = false
    var email = ""
    var plan = ""                       // "Free", "Plus", "Pro" …
    var limits: [Limit] = []
    var error: String?
    var planName: String { plan.isEmpty ? "ChatGPT" : "ChatGPT \(plan)" }
    var isFree: Bool { plan.lowercased() == "free" }
}

enum ChatGPT {
    static var codexHome: URL {
        if let h = ProcessInfo.processInfo.environment["CODEX_HOME"], !h.isEmpty { return URL(fileURLWithPath: h) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }
    static var authFile: URL { codexHome.appendingPathComponent("auth.json") }

    static func codexBinary() -> String? {
        let home = NSHomeDirectory()
        return ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "\(home)/.local/bin/codex", "\(home)/.npm-global/bin/codex", "\(home)/.bun/bin/codex"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// True when Codex has a ChatGPT sign-in saved (the file is only checked for its shape here, never copied).
    static var hasLogin: Bool {
        guard let d = try? Data(contentsOf: authFile), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let t = j["tokens"] as? [String: Any], t["access_token"] is String else { return false }
        return true
    }

    @discardableResult
    static func runCodex(_ args: [String]) -> (ok: Bool, out: Data) {
        guard let bin = codexBinary() else { return (false, Data()) }
        let p = Process(); p.executableURL = URL(fileURLWithPath: bin); p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(NSHomeDirectory())/.local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        p.environment = env
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        do { try p.run() } catch { return (false, Data()) }
        let out = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return (p.terminationStatus == 0, out)
    }

    /// "5-hour", "weekly", "monthly" from a window length.
    static func windowName(seconds: Double) -> String {
        let h = seconds / 3600
        if h <= 6 { return "\(Int(h.rounded()))-hour" }
        if h <= 26 { return "daily" }
        if abs(h - 168) < 12 { return "weekly" }
        if h >= 24 * 28 && h <= 24 * 31 { return "monthly" }
        return "\(Int((h / 24).rounded()))-day"
    }

    /// Turns one `rate_limit` object from the usage response into limits.
    static func parseWindows(_ rl: [String: Any]?, prefix: String, now: Date = Date()) -> [Limit] {
        guard let rl = rl else { return [] }
        var out: [Limit] = []
        for key in ["primary_window", "secondary_window"] {
            guard let w = rl[key] as? [String: Any], let used = (w["used_percent"] as? NSNumber)?.doubleValue else { continue }
            let secs = (w["limit_window_seconds"] as? NSNumber)?.doubleValue ?? 0
            var reset: Date?
            if let at = (w["reset_at"] as? NSNumber)?.doubleValue, at > 1_000_000_000 { reset = Date(timeIntervalSince1970: at) }
            else if let after = (w["reset_after_seconds"] as? NSNumber)?.doubleValue { reset = now.addingTimeInterval(after) }
            let name = secs > 0 ? windowName(seconds: secs) : (key == "primary_window" ? "usage" : "extra")
            out.append(Limit(name: "\(prefix) \(name)", percent: used, resets: reset, seconds: secs))
        }
        return out
    }

    static func parse(_ json: [String: Any], now: Date = Date()) -> ChatGPTState {
        var s = ChatGPTState(signedIn: true)
        s.email = json["email"] as? String ?? ""
        s.plan = (json["plan_type"] as? String).map { $0.replacingOccurrences(of: "_", with: " ").capitalized } ?? ""
        s.limits = parseWindows(json["rate_limit"] as? [String: Any], prefix: "ChatGPT", now: now)
        s.limits += parseWindows(json["code_review_rate_limit"] as? [String: Any], prefix: "Code review", now: now)
        if let extra = json["additional_rate_limits"] as? [[String: Any]] {
            for e in extra {
                let label = (e["limit_name"] as? String) ?? (e["name"] as? String) ?? "Extra"
                s.limits += parseWindows(e["rate_limit"] as? [String: Any], prefix: label, now: now)
            }
        }
        if s.isFree {            // Codex only reports meaningful limits on paid plans
            s.limits = []
            s.error = "Free ChatGPT plans aren’t supported. Usage limits are shown for paid plans (Plus, Pro, Business or Enterprise)."
        } else if s.limits.isEmpty { s.error = "No limit data returned" }
        return s
    }

    /// Blocking – call from a background queue. Uses Codex's saved access token read-only; it never refreshes or rewrites it.
    static func fetch() -> ChatGPTState {
        guard codexBinary() != nil || hasLogin else {
            var s = ChatGPTState(); s.error = "Codex isn’t installed. Install it (brew install codex), then connect ChatGPT."; return s
        }
        guard let d = try? Data(contentsOf: authFile), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let t = j["tokens"] as? [String: Any], let token = t["access_token"] as? String
        else { var s = ChatGPTState(); s.error = "Not signed in to ChatGPT"; return s }
        var req = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!, timeoutInterval: 15)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let acct = t["account_id"] as? String { req.setValue(acct, forHTTPHeaderField: "ChatGPT-Account-Id") }
        req.setValue("codex_cli_rs", forHTTPHeaderField: "User-Agent")
        let sem = DispatchSemaphore(value: 0)
        var body: Data?; var status = 0
        URLSession.shared.dataTask(with: req) { d, r, _ in body = d; status = (r as? HTTPURLResponse)?.statusCode ?? 0; sem.signal() }.resume()
        sem.wait()
        var s = ChatGPTState(signedIn: true)
        if status == 401 || status == 403 { s.error = "ChatGPT login expired – run any Codex command to refresh it"; return s }
        guard status == 200, let b = body, let json = try? JSONSerialization.jsonObject(with: b) as? [String: Any] else {
            s.error = "ChatGPT usage unavailable (HTTP \(status))"; return s
        }
        return parse(json)
    }

    static func demoSamples(now: Date = Date()) -> [GPTSample] {
        Demo.samples(now: now, sessionIn: 3 * 3600 + 25 * 60, weeklyIn: 4 * 86400 + 2 * 3600, sessionTarget: 34, weeklyTarget: 18, seed: 5).map {
            GPTSample(t: $0.t, w: [GPTWin(seconds: 18000, percent: $0.session, reset: $0.sessionReset), GPTWin(seconds: 604800, percent: $0.weekly, reset: $0.weeklyReset)])
        }
    }

    static var demo: ChatGPTState {
        let now = Date()
        var s = ChatGPTState(signedIn: true); s.email = "alex.morgan@example.com"; s.plan = "Plus"
        s.limits = [Limit(name: "ChatGPT 5-hour", percent: 34, resets: now.addingTimeInterval(3 * 3600 + 25 * 60), seconds: 18000),
                    Limit(name: "ChatGPT weekly", percent: 18, resets: now.addingTimeInterval(4 * 86400 + 2 * 3600), seconds: 604800)]
        return s
    }
}

// MARK: - History of ChatGPT readings (for the charts)

struct GPTWin: Codable { var seconds: Double; var percent: Double; var reset: Date? }
struct GPTSample: Codable { var t: Date; var w: [GPTWin] }

extension ChatGPT {
    /// "ChatGPT 5-hour" etc. for a window length, matching the limit names.
    static func seriesName(_ seconds: Double) -> String { "ChatGPT " + windowName(seconds: seconds) }
    static func isSession(_ seconds: Double) -> Bool { seconds > 0 && seconds <= 6 * 3600 }
    static func isWeekly(_ seconds: Double) -> Bool { abs(seconds - 7 * 86400) < 12 * 3600 }
}

final class GPTHistory {
    static let shared = GPTHistory()
    private(set) var samples: [GPTSample] = []
    private let url = supportDir().appendingPathComponent("chatgpt-history.json")

    init() {
        if let d = try? Data(contentsOf: url) {
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            samples = (try? dec.decode([GPTSample].self, from: d)) ?? []
        }
    }

    @discardableResult
    func record(_ limits: [Limit], now: Date = Date()) -> Bool {
        let wins = limits.filter { $0.name.hasPrefix("ChatGPT ") && $0.seconds > 0 }.map { GPTWin(seconds: $0.seconds, percent: $0.percent, reset: $0.resets) }
        guard !wins.isEmpty else { return false }
        if let last = samples.last, now.timeIntervalSince(last.t) < 170, last.w.map(\.percent) == wins.map(\.percent) { return false }
        samples.append(GPTSample(t: now, w: wins))
        samples.removeAll { now.timeIntervalSince($0.t) > 90 * 86400 }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let d = try? enc.encode(samples) { try? d.write(to: url, options: .atomic) }
        return true
    }
}
