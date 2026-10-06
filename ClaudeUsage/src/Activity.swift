import Foundation

// MARK: - API-equivalent pricing ($ per million tokens)
// Source: Anthropic's published first-party API prices. Cache writes (5-minute) cost 1.25x the input price.
// This is what the usage WOULD cost on pay-as-you-go API billing – it is not what a Claude subscription charges.

struct Pricing {
    let input: Double, output: Double, cacheRead: Double
    var cacheWrite: Double { input * 1.25 }

    /// Longest-prefix match so dated snapshot ids ("claude-haiku-4-5-20251001") resolve too.
    static let table: [(String, Pricing)] = [
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
    func markSignedIn() { if recordingSince == nil { recordingSince = Date() } }
}
