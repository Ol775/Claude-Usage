import Foundation

struct Usage {
    var input = 0, output = 0, cacheWrite = 0, cacheRead = 0
    var billable: Int { input + output + cacheWrite }   // excludes cheap cache reads
    var total: Int { billable + cacheRead }
    mutating func add(_ o: Usage) { input += o.input; output += o.output; cacheWrite += o.cacheWrite; cacheRead += o.cacheRead }
}

struct Snapshot {
    var today = Usage(), week = Usage(), month = Usage()
    var byModelToday: [String: Usage] = [:], byModelWeek: [String: Usage] = [:]
    var messagesToday = 0
    var daily = [Int](repeating: 0, count: 30)      // oldest first; last element is today
    var dailyDates: [Date] = []
    var hourly = [Int](repeating: 0, count: 24)
    var byProjectWeek: [String: Usage] = [:]
    var hourOfDay30 = [Int](repeating: 0, count: 24)    // tokens by hour of day over 30 days
    var weekday30 = [Int](repeating: 0, count: 7)       // tokens by weekday (0 = Sunday) over 30 days
    var days: [String: DayRecord] = [:]                 // permanent daily activity (up to a year, plus anything saved earlier)
    var unpricedModels: Set<String> = []
    var updated = Date()
}

/// "1 response", "2 responses".
func plural(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }

func fmt(_ n: Int) -> String {
    switch n {
    case 1_000_000...: return String(format: "%.1fM", Double(n) / 1e6)
    case 1_000...: return String(format: "%.1fK", Double(n) / 1e3)
    default: return "\(n)"
    }
}

// MARK: - Log scanning (cached per file so a refresh only re-reads files that changed)

/// One parsed log line. Claude Code writes each content block of an assistant message as its own line, so usage is
/// de-duplicated by message id later, while tool calls (unique ids) and prompts (unique uuids) are counted across lines.
struct Rec {
    let date: Date, model: String, key: String, project: String, session: String
    let u: Usage
    let toolIds: [String]
    let promptId: String?       // set for a real user prompt
}

final class LogCache {
    static let shared = LogCache()
    var files: [String: (mtime: Date, size: Int, recs: [Rec])] = [:]
}

/// "-Users-me-Projects-MacApps" -> "Projects-MacApps"; the home folder itself -> "Home".
func projectName(for url: URL) -> String {
    var name = url.deletingLastPathComponent().lastPathComponent
    let home = "-Users-" + NSUserName().replacingOccurrences(of: ".", with: "-")
    if name.hasPrefix(home) { name = String(name.dropFirst(home.count)) }
    name = name.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return name.isEmpty ? "Home" : name
}

private func parseLog(_ url: URL, oldest: Date) -> [Rec] {
    let project = projectName(for: url)
    guard let data = try? Data(contentsOf: url) else { return [] }
    let usageNeedle = Data("\"usage\"".utf8), toolNeedle = Data("\"tool_use\"".utf8), userNeedle = Data("\"type\":\"user\"".utf8)
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let iso2 = ISO8601DateFormatter()
    var out: [Rec] = []
    for line in data.split(separator: 10) {
        let hasUsage = line.range(of: usageNeedle) != nil
        let hasTool = line.range(of: toolNeedle) != nil
        let isUser = !hasUsage && line.range(of: userNeedle) != nil
        guard hasUsage || hasTool || isUser,                       // cheap pre-filter before JSON parsing
              let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let ts = obj["timestamp"] as? String,
              let date = iso.date(from: ts) ?? iso2.date(from: ts), date >= oldest,
              let msg = obj["message"] as? [String: Any] else { continue }
        let session = obj["sessionId"] as? String ?? ""

        if obj["type"] as? String == "user" {
            // A real prompt: not a tool result, not meta, not a sub-agent's internal prompt.
            if obj["isMeta"] as? Bool == true || obj["isSidechain"] as? Bool == true { continue }
            var isPrompt = false
            if msg["content"] is String { isPrompt = true }
            else if let parts = msg["content"] as? [[String: Any]] {
                isPrompt = parts.contains { $0["type"] as? String == "text" } && !parts.contains { $0["type"] as? String == "tool_result" }
            }
            if isPrompt, let id = obj["uuid"] as? String {
                out.append(Rec(date: date, model: "", key: "", project: project, session: session, u: Usage(), toolIds: [], promptId: id))
            }
            continue
        }

        var tools: [String] = []
        if let parts = msg["content"] as? [[String: Any]] {
            tools = parts.compactMap { $0["type"] as? String == "tool_use" ? ($0["id"] as? String) : nil }
        }
        let usage = msg["usage"] as? [String: Any]
        guard usage != nil || !tools.isEmpty else { continue }
        let u = usage ?? [:]
        let use = Usage(input: u["input_tokens"] as? Int ?? 0, output: u["output_tokens"] as? Int ?? 0,
                        cacheWrite: u["cache_creation_input_tokens"] as? Int ?? 0, cacheRead: u["cache_read_input_tokens"] as? Int ?? 0)
        let key = usage == nil ? "" : "\(msg["id"] as? String ?? "")|\(obj["requestId"] as? String ?? "")"
        out.append(Rec(date: date, model: msg["model"] as? String ?? "unknown", key: key, project: project, session: session, u: use, toolIds: tools, promptId: nil))
    }
    return out
}

func scan() -> Snapshot {
    var snap = Snapshot()
    let now = Date(), cal = Calendar.current
    let startToday = cal.startOfDay(for: now)
    let start30 = cal.date(byAdding: .day, value: -29, to: startToday)!
    let start7d = now.addingTimeInterval(-7 * 86400)
    let startMonth = cal.date(from: cal.dateComponents([.year, .month], from: now))!
    let oldest = cal.date(byAdding: .day, value: -364, to: startToday)!          // read up to a year of logs
    snap.dailyDates = (0..<30).map { cal.date(byAdding: .day, value: $0, to: start30)! }

    let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else {
        snap.days = ActivityStore.shared.merge([:]); return snap
    }
    let cache = LogCache.shared
    var live = Set<String>()
    var all: [Rec] = []
    for case let url as URL in en where url.pathExtension == "jsonl" {
        guard let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let mtime = v.contentModificationDate, mtime >= oldest else { continue }
        let size = v.fileSize ?? 0, path = url.path
        live.insert(path)
        if let c = cache.files[path], c.mtime == mtime, c.size == size { all += c.recs; continue }
        let recs = parseLog(url, oldest: oldest)
        cache.files[path] = (mtime, size, recs)
        all += recs
    }
    for p in cache.files.keys where !live.contains(p) { cache.files[p] = nil }

    var seen = Set<String>(), seenTools = Set<String>(), seenPrompts = Set<String>()
    var perDay: [String: DayRecord] = [:]
    var sessionsPerDay: [String: Set<String>] = [:]
    for r in all {
        let d = r.date, dk = dayKey(d)
        var rec = perDay[dk] ?? DayRecord()
        defer { perDay[dk] = rec }
        if !r.session.isEmpty { sessionsPerDay[dk, default: []].insert(r.session) }

        if let pid = r.promptId { if seenPrompts.insert(pid).inserted { rec.prompts += 1 }; continue }
        for t in r.toolIds where seenTools.insert(t).inserted { rec.toolCalls += 1 }
        if r.key.isEmpty || r.key == "|" && r.u.total == 0 { continue }          // tool-only line: usage is counted on the message's first line
        if r.key != "|" { if seen.contains(r.key) { continue }; seen.insert(r.key) }

        let use = r.u
        rec.input += use.input; rec.output += use.output; rec.cacheWrite += use.cacheWrite; rec.cacheRead += use.cacheRead
        rec.responses += 1
        rec.models[r.model, default: 0] += use.billable
        rec.projects[r.project, default: 0] += use.billable
        if let c = Pricing.cost(model: r.model, use) { rec.cost += c; rec.modelCost[r.model, default: 0] += c }
        else if r.model != "<synthetic>" && use.total > 0 { snap.unpricedModels.insert(r.model) }

        if d >= startMonth { snap.month.add(use) }
        if d >= start7d { snap.week.add(use); snap.byModelWeek[r.model, default: Usage()].add(use); snap.byProjectWeek[r.project, default: Usage()].add(use) }
        if d >= start30 {
            snap.hourOfDay30[min(23, cal.component(.hour, from: d))] += use.billable
            snap.weekday30[max(0, min(6, cal.component(.weekday, from: d) - 1))] += use.billable
            let i = cal.dateComponents([.day], from: start30, to: cal.startOfDay(for: d)).day ?? -1
            if (0..<30).contains(i) { snap.daily[i] += use.billable }
        }
        if d >= startToday {
            snap.hourly[min(23, cal.component(.hour, from: d))] += use.billable
            snap.today.add(use); snap.messagesToday += 1
            snap.byModelToday[r.model, default: Usage()].add(use)
        }
    }
    for (k, s) in sessionsPerDay { perDay[k]?.sessions = s.count }
    snap.days = ActivityStore.shared.merge(perDay)
    return snap
}
