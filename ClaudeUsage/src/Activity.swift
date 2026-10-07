import Foundation

// MARK: - API-equivalent pricing ($ per million tokens)
// Source: Anthropic's published first-party API prices. Cache writes (5-minute) cost 1.25x the input price.
// This is what the usage WOULD cost on pay-as-you-go API billing – it is not what a Claude subscription charges.

struct Pricing {
    let input: Double, output: Double, cacheRead: Double
    var cacheWrite: Double { input * 1.25 }

    /// Longest-prefix match so dated snapshot ids ("claude-haiku-4-5-20251001") resolve too.
    static let builtIn: [(String, Pricing)] = [
        ("claude-fable-5-1", Pricing(input: 10, output: 50, cacheRead: 0.25)),
        ("claude-mythos-5-1", Pricing(input: 10, output: 50, cacheRead: 0.25)),
        ("claude-fable-5", Pricing(input: 10, output: 50, cacheRead: 1.00)),
        ("claude-mythos-5", Pricing(input: 10, output: 50, cacheRead: 1.00)),
        ("claude-opus-5-5", Pricing(input: 4, output: 20, cacheRead: 0.20)),
        ("claude-opus-5", Pricing(input: 5, output: 25, cacheRead: 0.50)),
        ("claude-opus-4", Pricing(input: 5, output: 25, cacheRead: 0.50)),
        ("claude-sonnet-5", Pricing(input: 2, output: 10, cacheRead: 0.20)),
        ("claude-sonnet-4", Pricing(input: 3, output: 15, cacheRead: 0.30)),
        ("claude-haiku-4", Pricing(input: 1, output: 5, cacheRead: 0.10)),
    ]

    // Prices can be refreshed without a new app release: pricing.json in the repo is fetched at most once a day,
    // checked for sane values, cached next to the history, and merged over the built-in table.
    private static let lock = NSLock()
    private static var override: [(String, Pricing)] = []
    static var table: [(String, Pricing)] {
        lock.lock(); defer { lock.unlock() }
        return override + builtIn.filter { b in !override.contains { $0.0 == b.0 } }
    }
    static var cacheURL: URL { supportDir().appendingPathComponent("pricing.json") }

    /// Reads `{"models":[{"prefix","input","output","cacheRead"}]}`; nil if anything looks wrong (prices must be 0–1000 $/M).
    static func parse(_ json: [String: Any]) -> [(String, Pricing)]? {
        guard let models = json["models"] as? [[String: Any]], !models.isEmpty else { return nil }
        var out: [(String, Pricing)] = []
        for m in models {
            guard let prefix = m["prefix"] as? String, prefix.hasPrefix("claude-"), prefix.filter({ $0 == "-" }).count >= 2,     // e.g. "claude-opus-5", never a bare "claude-"
                  let i = (m["input"] as? NSNumber)?.doubleValue, let o = (m["output"] as? NSNumber)?.doubleValue,
                  let c = (m["cacheRead"] as? NSNumber)?.doubleValue,
                  [i, o, c].allSatisfy({ $0 >= 0 && $0 <= 1000 }), i > 0, o > 0 else { return nil }
            out.append((prefix, Pricing(input: i, output: o, cacheRead: c)))
        }
        return out
    }

    static func loadCached() {
        guard let d = try? Data(contentsOf: cacheURL), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let t = parse(j) else { return }
        lock.lock(); override = t; lock.unlock()
    }

    /// Blocking; call from a background queue. Checks GitHub at most once a day.
    static func refreshIfStale(force: Bool = false) {
        let key = "pricingCheckedAt"
        if !force, Clock.now.timeIntervalSince(UserDefaults.standard.object(forKey: key) as? Date ?? .distantPast) < 86400 { return }
        UserDefaults.standard.set(Clock.now, forKey: key)
        guard let text = Updater.fetch("ClaudeUsage/pricing.json"), let d = text.data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let t = parse(j) else { return }
        lock.lock(); override = t; lock.unlock()
        try? d.write(to: cacheURL, options: .atomic)
    }

    static func forModel(_ model: String) -> Pricing? {
        table.filter { model.hasPrefix($0.0) }.max { $0.0.count < $1.0.count }?.1
    }

    static func cost(model: String, _ u: Usage) -> Double? {
        guard let p = forModel(model) else { return nil }
        return (Double(u.input) * p.input + Double(u.output) * p.output + Double(u.cacheWrite) * p.cacheWrite + Double(u.cacheRead) * p.cacheRead) / 1_000_000
    }
}

func money(_ v: Double) -> String {
    v >= 100 ? String(format: "$%.0f", v) : (v >= 1 ? String(format: "$%.2f", v) : String(format: "$%.3f", v))
}

// MARK: - Permanent daily activity (kept even after Claude Code prunes its own logs)

/// "2026-10-06" in the local calendar. Thread-safe (no shared formatter).
func dayKey(_ d: Date) -> String {
    let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
}
func dayDate(_ key: String) -> Date? {
    let p = key.split(separator: "-").compactMap { Int($0) }
    guard p.count == 3 else { return nil }
    return Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
}

struct DayRecord: Codable {
    var input = 0, output = 0, cacheWrite = 0, cacheRead = 0
    var prompts = 0, responses = 0, toolCalls = 0, sessions = 0
    var cost = 0.0
    var models: [String: Int] = [:]          // billable tokens per model
    var modelCost: [String: Double] = [:]
    var projects: [String: Int] = [:]        // billable tokens per project
    var billable: Int { input + output + cacheWrite }
}

/// Daily aggregates saved to disk. Days still present in Claude Code's logs are refreshed from them each scan;
/// older days are kept as saved, so history (and the yearly view and forecasts) outlives the logs.
final class ActivityStore {
    static let shared = ActivityStore()
    private(set) var days: [String: DayRecord] = [:]
    private let url = supportDir().appendingPathComponent("activity.json")
    private let lock = NSLock()

    init() {
        if let d = try? Data(contentsOf: url) { days = (try? JSONDecoder().decode([String: DayRecord].self, from: d)) ?? [:] }
    }

    @discardableResult
    func merge(_ scanned: [String: DayRecord]) -> [String: DayRecord] {
        lock.lock(); defer { lock.unlock() }
        var changed = false
        for (k, v) in scanned {
            if let old = days[k], old.billable == v.billable, old.toolCalls == v.toolCalls, old.prompts == v.prompts, old.responses == v.responses { continue }
            days[k] = v; changed = true
        }
        if changed, let d = try? JSONEncoder().encode(days) { try? d.write(to: url, options: .atomic) }
        return days
    }

    /// When the user first appeared signed in – shown in Insights as "recording since".
    var recordingSince: Date? {
        get { UserDefaults.standard.object(forKey: "recordingSince") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "recordingSince") }
    }
    func markSignedIn() { if recordingSince == nil { recordingSince = Clock.now } }
}
