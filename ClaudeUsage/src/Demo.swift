import Foundation

/// Made-up data for screenshots (`CUB_DEMO=1`). Nothing here is read from, or written to, the user's real history.
enum Demo {
    static var enabled: Bool { ProcessInfo.processInfo.environment["CUB_DEMO"] == "1" }

    static let account: Account = { var a = Account(); a.loggedIn = true; a.email = "alex.morgan@example.com"; a.plan = "Max"; return a }()

    private static let models: [(String, Double)] = [("claude-opus-5-5", 0.52), ("claude-sonnet-5-5", 0.36), ("claude-haiku-4-5-20251001", 0.12)]
    private static let projects: [(String, Double)] = [("Portfolio-Site", 0.30), ("Home-Automation", 0.22), ("Budget-Tracker", 0.18), ("Docs", 0.16), ("Home", 0.14)]

    /// Stable pseudo-random value in 0...1 for a seed.
    private static func rnd(_ i: Int, _ salt: Int) -> Double {
        let x = sin(Double(i &* 7919 &+ salt &* 104729)) * 43758.5453
        return x - floor(x)
    }

    private static func dayRecord(daysAgo i: Int, weekday: Int, today: Bool) -> DayRecord {
        let weekend = weekday == 1 || weekday == 7
        var level = (weekend ? 0.25 : 1.0) * (0.35 + 0.9 * rnd(i, 1))
        if rnd(i, 2) > 0.93 { level *= 0.1 }                    // the odd quiet day
        if i < 21 { level *= 1.2 }                              // a bit busier lately
        let billable = Int(level * 5_200_000)
        var r = DayRecord()
        r.output = Int(Double(billable) * 0.18); r.input = Int(Double(billable) * 0.07); r.cacheWrite = billable - r.output - r.input
        r.cacheRead = billable * 9
        r.prompts = Int(level * 70) + 2; r.responses = Int(level * 520) + 6; r.toolCalls = Int(level * 410) + 4
        r.sessions = max(1, Int(level * 5.5))
        for (m, share) in models {
            let tokens = Int(Double(billable) * share)
            r.models[m] = tokens
            let u = Usage(input: Int(Double(r.input) * share), output: Int(Double(r.output) * share), cacheWrite: Int(Double(r.cacheWrite) * share), cacheRead: Int(Double(r.cacheRead) * share))
            if let c = Pricing.cost(model: m, u) { r.modelCost[m] = c; r.cost += c }
        }
        for (p, share) in projects { r.projects[p] = Int(Double(billable) * share * (0.6 + 0.8 * rnd(i, p.count))) }
        return r
    }

    static func snapshot(now: Date = Date()) -> Snapshot {
        let cal = Calendar.current
        let startToday = cal.startOfDay(for: now)
        var s = Snapshot()
        var days: [String: DayRecord] = [:]
        for i in 0..<365 {
            let d = cal.date(byAdding: .day, value: -i, to: startToday)!
            days[dayKey(d)] = dayRecord(daysAgo: i, weekday: cal.component(.weekday, from: d), today: i == 0)
        }
        s.days = days
        let start30 = cal.date(byAdding: .day, value: -29, to: startToday)!
        s.dailyDates = (0..<30).map { cal.date(byAdding: .day, value: $0, to: start30)! }
        s.daily = s.dailyDates.map { days[dayKey($0)]?.billable ?? 0 }
        for d in s.dailyDates {
            let rec = days[dayKey(d)]!, wd = cal.component(.weekday, from: d) - 1
            s.weekday30[wd] += rec.billable
        }
        for h in 0..<24 { s.hourOfDay30[h] = Int(Double(s.daily.reduce(0, +)) / 30 * max(0, exp(-pow(Double(h) - 13.5, 2) / 18)) * 0.5) }
        func usage(_ r: DayRecord) -> Usage { Usage(input: r.input, output: r.output, cacheWrite: r.cacheWrite, cacheRead: r.cacheRead) }
        s.today = usage(days[dayKey(now)]!)
        for i in 0..<7 {
            let r = days[dayKey(cal.date(byAdding: .day, value: -i, to: startToday)!)]!
            s.week.add(usage(r))
            for (m, t) in r.models { s.byModelWeek[m, default: Usage()].add(Usage(output: t)) }
            for (p, t) in r.projects { s.byProjectWeek[p, default: Usage()].add(Usage(output: t)) }
        }
        for (k, v) in days where dayDate(k).map({ $0 >= cal.date(from: cal.dateComponents([.year, .month], from: now))! }) == true { s.month.add(usage(v)) }
        for (m, t) in days[dayKey(now)]!.models { s.byModelToday[m] = Usage(output: t) }
        s.messagesToday = days[dayKey(now)]!.responses
        let nowHour = cal.component(.hour, from: now), today = s.today.billable
        let weights = (0..<24).map { $0 <= nowHour ? max(0.02, exp(-pow(Double($0) - 12.5, 2) / 14)) : 0 }
        let total = weights.reduce(0, +)
        s.hourly = weights.map { Int(Double(today) * $0 / max(total, 0.001)) }
        s.updated = now
        return s
    }

    /// A week of limit readings every 20 minutes: session fills and resets every 5 hours, weekly climbs steadily.
    static func samples(now: Date = Date(), sessionIn: TimeInterval = 2 * 3600 + 10 * 60, weeklyIn: TimeInterval = 2 * 86400 + 6 * 3600, sessionTarget: Double = 58, weeklyTarget: Double = 46, seed: Int = 0) -> [Sample] {
        let sessionReset = now.addingTimeInterval(sessionIn)
        let weeklyReset = now.addingTimeInterval(weeklyIn)
        let step: TimeInterval = 20 * 60, cal = Calendar.current
        var out: [Sample] = []
        var t = now.addingTimeInterval(-7 * 86400)
        var weekly = 52.0                                                    // the end of last week's window
        var window = 0, sess = 0.0
        while t <= now {
            let h = Double(cal.component(.hour, from: t)) + Double(cal.component(.minute, from: t)) / 60
            let wd = cal.component(.weekday, from: t)
            let active = max(0, exp(-pow(h - 13, 2) / 22)) * ((wd == 1 || wd == 7) ? 0.3 : 1.0) * (0.6 + 0.8 * rnd(Int(t.timeIntervalSince1970 / step), 9 + seed))
            let w = Int(floor(sessionReset.timeIntervalSince(t) / (5 * 3600)))
            if w != window { window = w; sess = 0 }
            sess = min(97, sess + active * 4.5)
            if t >= weeklyReset.addingTimeInterval(-7 * 86400) && out.last.map({ $0.t < weeklyReset.addingTimeInterval(-7 * 86400) }) == true { weekly = 0 }
            weekly = min(99, weekly + active * 0.55)
            let thisWeekly = t < weeklyReset.addingTimeInterval(-7 * 86400) ? weeklyReset.addingTimeInterval(-7 * 86400) : weeklyReset
            out.append(Sample(t: t, session: sess, sessionReset: sessionReset.addingTimeInterval(-Double(window) * 5 * 3600), weekly: weekly, weeklyReset: thisWeekly))
            t = t.addingTimeInterval(step)
        }
        // land exactly on the headline numbers
        if let last = out.last, last.session > 0 {
            let ks = sessionTarget / last.session
            for i in out.indices where out[i].sessionReset == out.last!.sessionReset { out[i].session = min(100, out[i].session * ks) }
        }
        if let lw = out.last?.weekly, lw > 0 {
            let start = weeklyReset.addingTimeInterval(-7 * 86400)
            let kw = weeklyTarget / lw
            for i in out.indices where out[i].t >= start { out[i].weekly = min(100, out[i].weekly * kw) }
        }
        return out
    }

    static func limits(now: Date = Date()) -> [Limit] {
        [Limit(name: "Current session", percent: 58, resets: now.addingTimeInterval(2 * 3600 + 10 * 60)),
         Limit(name: "Weekly – all models", percent: 46, resets: now.addingTimeInterval(2 * 86400 + 6 * 3600)),
         Limit(name: "Weekly – Opus", percent: 31, resets: now.addingTimeInterval(2 * 86400 + 6 * 3600)),
         Limit(name: "Weekly – Sonnet", percent: 22, resets: now.addingTimeInterval(2 * 86400 + 6 * 3600))]
    }
}
