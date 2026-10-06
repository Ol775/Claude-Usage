import Foundation

// MARK: - History of limit readings (used for charts and predictions)

struct Sample: Codable {
    var t: Date
    var session: Double
    var sessionReset: Date?
    var weekly: Double
    var weeklyReset: Date?
}

enum LimitKind { case session, weekly, other }

extension Limit {
    var kind: LimitKind {
        if name == "Current session" { return .session }
        if name == "Weekly – all models" { return .weekly }
        return .other
    }
    var window: TimeInterval { kind == .session ? 5 * 3600 : 7 * 86400 }
}

final class History {
    static let shared = History()
    private(set) var samples: [Sample] = []
    private let url = supportDir().appendingPathComponent("history.json")

    init() {
        if let d = try? Data(contentsOf: url) {
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            samples = (try? dec.decode([Sample].self, from: d)) ?? []
        }
    }

    /// Records the current readings. Returns true if a sample was stored.
    @discardableResult
    func record(_ limits: [Limit], now: Date = Date()) -> Bool {
        guard let s = limits.first(where: { $0.kind == .session }), let w = limits.first(where: { $0.kind == .weekly }) else { return false }
        let new = Sample(t: now, session: s.percent, sessionReset: s.resets, weekly: w.percent, weeklyReset: w.resets)
        if let last = samples.last, now.timeIntervalSince(last.t) < 170,
           last.session == new.session, last.weekly == new.weekly { return false }
        samples.append(new)
        samples.removeAll { now.timeIntervalSince($0.t) > 14 * 86400 }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let d = try? enc.encode(samples) { try? d.write(to: url, options: .atomic) }
        return true
    }
}

// MARK: - Forecasting

enum Forecast {
    case none(String)                                       // not enough data yet
    case reached
    case hits(at: Date, perHour: Double, recent: Bool)      // will hit 100% before the window resets
    case safe(projected: Double, perHour: Double)           // will not hit 100% before reset
}

enum Predictor {
    /// Estimates when `percent` reaches 100 by extrapolating the burn rate.
    /// Uses the recent pace from stored samples when there are enough, otherwise the average since the window began.
    static func forecast(_ l: Limit, samples: [Sample], now: Date = Date()) -> Forecast {
        guard l.kind != .other else { return .none("") }
        if l.percent >= 100 { return .reached }
        guard let resets = l.resets, resets > now else { return .none("Waiting for the limit to reset") }

        let start = resets.addingTimeInterval(-l.window)
        let elapsedH = max(now.timeIntervalSince(start), 0) / 3600
        let remainingH = resets.timeIntervalSince(now) / 3600

        // Recent pace from samples inside this window.
        let span: TimeInterval = l.kind == .session ? 3600 : 12 * 3600
        let minSpan: TimeInterval = l.kind == .session ? 600 : 3600
        let inWindow = samples.filter { s in
            let r = l.kind == .session ? s.sessionReset : s.weeklyReset
            return r.map { abs($0.timeIntervalSince(resets)) < 300 } ?? false && now.timeIntervalSince(s.t) <= span
        }
        var rate: Double?
        var recent = false
        if let first = inWindow.first, let last = inWindow.last, last.t.timeIntervalSince(first.t) >= minSpan {
            let p0 = l.kind == .session ? first.session : first.weekly
            let p1 = l.kind == .session ? last.session : last.weekly
            rate = max(0, (p1 - p0) / (last.t.timeIntervalSince(first.t) / 3600)); recent = true
        } else if elapsedH >= 0.1 {
            rate = l.percent / elapsedH
        }
        guard let perHour = rate else { return .none("Not enough data yet") }
        if perHour < 0.01 { return .safe(projected: l.percent, perHour: 0) }
        let hoursToHit = (100 - l.percent) / perHour
        if hoursToHit < remainingH { return .hits(at: now.addingTimeInterval(hoursToHit * 3600), perHour: perHour, recent: recent) }
        return .safe(projected: l.percent + perHour * remainingH, perHour: perHour)
    }

    static func describe(_ f: Forecast, now: Date = Date()) -> String {
        let t = DateFormatter(); t.dateFormat = "h:mm a"
        switch f {
        case .none(let why): return why
        case .reached: return "Limit reached"
        case .hits(let at, _, _):
            let secs = Int(at.timeIntervalSince(now))
            let rel = secs >= 86400 ? "\(secs / 86400)d \((secs % 86400) / 3600)h" : (secs >= 3600 ? "\(secs / 3600)h \((secs % 3600) / 60)m" : "\(max(1, secs / 60))m")
            let when = Calendar.current.isDate(at, inSameDayAs: now) ? t.string(from: at) : { let d = DateFormatter(); d.dateFormat = "EEE h:mm a"; return d.string(from: at) }()
            return "On pace to hit the limit at \(when) (in \(rel))"
        case .safe(let p, let r):
            return r == 0 ? "Idle – on pace for \(Int(p.rounded()))% at reset" : "On pace for \(min(Int(p.rounded()), 99))% at reset – safe"
        }
    }
}
