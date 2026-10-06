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
    var updated = Date()
}

func fmt(_ n: Int) -> String {
    switch n {
    case 1_000_000...: return String(format: "%.1fM", Double(n) / 1e6)
    case 1_000...: return String(format: "%.1fK", Double(n) / 1e3)
    default: return "\(n)"
    }
}

// MARK: - Log scanning (cached per file so a refresh only re-reads files that changed)

struct Rec { let date: Date; let model: String; let key: String; let u: Usage }

final class LogCache {
    static let shared = LogCache()
    var files: [String: (mtime: Date, size: Int, recs: [Rec])] = [:]
}

private func parseLog(_ url: URL, oldest: Date) -> [Rec] {
    guard let data = try? Data(contentsOf: url) else { return [] }
    let needle = Data("\"usage\"".utf8)
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let iso2 = ISO8601DateFormatter()
    var out: [Rec] = []
    for line in data.split(separator: 10) {
        guard line.range(of: needle) != nil,                       // cheap pre-filter before JSON parsing
              let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let msg = obj["message"] as? [String: Any], let u = msg["usage"] as? [String: Any],
              let ts = obj["timestamp"] as? String,
              let date = iso.date(from: ts) ?? iso2.date(from: ts), date >= oldest else { continue }
        let key = "\(msg["id"] as? String ?? "")|\(obj["requestId"] as? String ?? "")"
        let use = Usage(input: u["input_tokens"] as? Int ?? 0, output: u["output_tokens"] as? Int ?? 0,
                        cacheWrite: u["cache_creation_input_tokens"] as? Int ?? 0, cacheRead: u["cache_read_input_tokens"] as? Int ?? 0)
        out.append(Rec(date: date, model: msg["model"] as? String ?? "unknown", key: key, u: use))
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
    let oldest = min(start30, startMonth, start7d)
    snap.dailyDates = (0..<30).map { cal.date(byAdding: .day, value: $0, to: start30)! }

    let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else { return snap }
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

    var seen = Set<String>()
    for r in all {
        if r.key != "|" { if seen.contains(r.key) { continue }; seen.insert(r.key) }
        let d = r.date, use = r.u
        if d >= startMonth { snap.month.add(use) }
        if d >= start7d { snap.week.add(use); snap.byModelWeek[r.model, default: Usage()].add(use) }
        if d >= start30 {
            let i = cal.dateComponents([.day], from: start30, to: cal.startOfDay(for: d)).day ?? -1
            if (0..<30).contains(i) { snap.daily[i] += use.billable }
        }
        if d >= startToday {
            snap.hourly[min(23, cal.component(.hour, from: d))] += use.billable
            snap.today.add(use); snap.messagesToday += 1
            snap.byModelToday[r.model, default: Usage()].add(use)
        }
    }
    return snap
}
