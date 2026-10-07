import SwiftUI
import Charts

enum ReportRange: String, CaseIterable, Identifiable {
    case day, week, month
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

private struct LimitPoint: Identifiable {
    let t: Date, v: Double, name: String, window: String
    var id: String { "\(window)-\(t.timeIntervalSince1970)" }
}
private struct PeakBar: Identifiable {
    let end: Date, peak: Double
    var id: TimeInterval { end.timeIntervalSince1970 }
}

/// Day / week / month reports: token usage, limit utilisation over time, and the peak reached in each limit window.
struct ReportsView: View {
    @ObservedObject var store: Store
    @ObservedObject var settings = Settings.shared
    @StateObject private var rangeBox = Box(ReportRange.day)
    private var range: ReportRange { rangeBox.value }

    // MARK: derived data

    private var now: Date { Clock.now }
    private var start: Date {
        let cal = Calendar.current
        switch range {
        case .day: return cal.startOfDay(for: now)
        case .week: return now.addingTimeInterval(-7 * 86400)
        case .month: return now.addingTimeInterval(-30 * 86400)
        }
    }
    private var end: Date { range == .day ? Calendar.current.date(byAdding: .day, value: 1, to: start)! : now }

    /// (time, tokens) bars: hourly for the day view, daily otherwise.
    private var tokenBars: [(Date, Int)] {
        let s = store.snapshot
        switch range {
        case .day: return (0..<24).map { (start.addingTimeInterval(Double($0) * 3600), s.hourly[$0]) }
        case .week: return Array(zip(s.dailyDates.suffix(7), s.daily.suffix(7)))
        case .month: return Array(zip(s.dailyDates.suffix(30), s.daily.suffix(30)))
        }
    }

    private var samples: [Sample] { store.samples.filter { $0.t >= start } }

    /// Limit readings, bucketed (max per bucket) so long ranges stay readable; windows are kept separate so the line
    /// doesn't draw a diagonal across each reset.
    private var points: [LimitPoint] {
        let bucket: Double = range == .day ? 300 : (range == .week ? 3600 : 6 * 3600)
        var out: [String: LimitPoint] = [:]
        func add(_ name: String, _ t: Date, _ v: Double, _ reset: Date?) {
            let b = floor(t.timeIntervalSince1970 / bucket)
            let w = "\(name)\(Int((reset?.timeIntervalSince1970 ?? 0) / 600))"
            let key = "\(w)-\(b)"
            let when = Date(timeIntervalSince1970: b * bucket + bucket / 2)
            if let e = out[key], e.v >= v { return }
            out[key] = LimitPoint(t: min(when, now), v: v, name: name, window: w)
        }
        for s in samples { add("Session", s.t, s.session, s.sessionReset); add("Weekly", s.t, s.weekly, s.weeklyReset) }
        if settings.chatgptEnabled {
            for s in store.gptSamples where s.t >= start { for w in s.w { add(ChatGPT.seriesName(w.seconds), s.t, w.percent, w.reset) } }
        }
        return out.values.sorted { $0.t < $1.t }
    }

    /// Peak percentage reached in each limit window (sessions for day/week, weekly windows for month).
    private var peaks: [PeakBar] {
        var best: [Int: (Date, Double)] = [:]
        for s in samples {
            guard let r = range == .month ? s.weeklyReset : s.sessionReset else { continue }
            let v = range == .month ? s.weekly : s.session
            let k = Int(r.timeIntervalSince1970 / 600)
            if let e = best[k], e.1 >= v { continue }
            best[k] = (r, v)
        }
        return best.values.map { PeakBar(end: min($0.0, now), peak: $0.1) }.sorted { $0.end < $1.end }
    }

    /// Claude keeps its orange and grey; each ChatGPT window gets a shade of ChatGPT green.
    /// (KeyValuePairs can't be built from an array, so the realistic combinations are listed explicitly.)
    private func styleScale(_ pts: [LimitPoint]) -> KeyValuePairs<String, Color> {
        let set = Set(pts.map(\.name))
        switch (set.contains("ChatGPT 5-hour"), set.contains("ChatGPT weekly"), set.contains("ChatGPT monthly")) {
        case (true, true, _): return ["Session": Color.brand, "Weekly": Color.primary.opacity(0.55), "ChatGPT 5-hour": Color.gpt, "ChatGPT weekly": Color.gpt.opacity(0.55)]
        case (true, false, _): return ["Session": Color.brand, "Weekly": Color.primary.opacity(0.55), "ChatGPT 5-hour": Color.gpt]
        case (false, true, _): return ["Session": Color.brand, "Weekly": Color.primary.opacity(0.55), "ChatGPT weekly": Color.gpt.opacity(0.55)]
        case (_, _, true): return ["Session": Color.brand, "Weekly": Color.primary.opacity(0.55), "ChatGPT monthly": Color.gpt]
        default: return ["Session": Color.brand, "Weekly": Color.primary.opacity(0.55)]
        }
    }

    private var peakLabel: String { range == .month ? "weekly windows" : "5-hour windows" }

    // MARK: view

    var body: some View {
        let bars = tokenBars, pts = points, pk = peaks
        let total = bars.reduce(0) { $0 + $1.1 }
        let warn = Double(settings.warnThreshold)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reports").font(AppFont.largeTitle.bold())
                        Text(rangeDescription).foregroundStyle(.secondary)
                    }
                    Spacer()
                    SegmentedChoice(options: ReportRange.allCases, label: { $0.title }, selection: $rangeBox.value)
                }

                HStack(spacing: 16) {
                    StatTile(title: "Tokens", value: fmt(total), sub: range == .day ? "today" : (range == .week ? "last 7 days" : "last 30 days"))
                    if range == .day {
                        let top = bars.max { $0.1 < $1.1 }
                        StatTile(title: "Busiest hour", value: (top?.1 ?? 0) > 0 ? top!.0.formatted(.dateTime.hour()) : "—", sub: top.map { fmt($0.1) + " tokens" } ?? "no usage yet")
                    } else {
                        let days = max(1, bars.count)
                        StatTile(title: "Daily average", value: fmt(total / days), sub: "tokens per day")
                    }
                    StatTile(title: "Peak \(range == .month ? "weekly" : "session")", value: pk.isEmpty ? "—" : "\(Int((pk.map(\.peak).max() ?? 0).rounded()))%", sub: "highest in range")
                    StatTile(title: "Over \(Int(warn))%", value: pk.isEmpty ? "—" : "\(pk.filter { $0.peak >= warn }.count)", sub: "of \(pk.count) \(pk.count == 1 ? String(peakLabel.dropLast()) : peakLabel)")
                }

                chartCard(title: "Token usage", subtitle: range == .day ? "Per hour" : "Per day") {
                    Chart(Array(bars.enumerated()), id: \.offset) { i, b in
                        BarMark(x: .value("Time", b.0, unit: range == .day ? .hour : .day), y: .value("Tokens", b.1))
                            .foregroundStyle(isCurrent(i, bars.count) ? Color.brand : Color.brand.opacity(0.7)).cornerRadius(3)
                    }
                    .chartXAxis { xAxis() }
                    .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Int.self) { Text(fmt(n)) } } } }
                    .frame(height: 200)
                }

                chartCard(title: "Limit utilisation", subtitle: settings.chatgptEnabled ? "Claude and ChatGPT usage against their limits" : "Session and weekly usage against the limit") {
                    if pts.count < 2 {
                        emptyNote
                    } else {
                        Chart {
                            ForEach(pts) { p in
                                LineMark(x: .value("Time", p.t), y: .value("Used", p.v), series: .value("Window", p.window))
                                    .foregroundStyle(by: .value("Limit", p.name)).lineStyle(StrokeStyle(lineWidth: 2.2))
                            }
                            RuleMark(y: .value("Limit", 100)).foregroundStyle(Color.danger.opacity(0.85)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                .annotation(position: .top, alignment: .leading) { Text("Limit").font(AppFont.caption2).foregroundStyle(Color.danger) }
                            RuleMark(y: .value("Warn", warn)).foregroundStyle(Color.orange.opacity(0.7)).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
                                .annotation(position: .top, alignment: .leading) { Text("Warn at \(Int(warn))%").font(AppFont.caption2).foregroundStyle(.orange) }
                        }
                        .chartForegroundStyleScale(styleScale(pts))
                        .chartXScale(domain: start...end)
                        .chartYScale(domain: 0...115)
                        .chartXAxis { xAxis() }
                        .chartYAxis { AxisMarks(values: [0, 25, 50, 75, 100]) { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Int.self) { Text("\(n)%") } } } }
                        .padding(.top, 14)
                        .frame(height: 240)
                    }
                }

                chartCard(title: "Peak per \(range == .month ? "week" : "session")", subtitle: "Highest usage reached in each \(range == .month ? "weekly" : "5-hour") window") {
                    if pk.isEmpty {
                        emptyNote
                    } else {
                        Chart {
                            ForEach(pk) { b in
                                BarMark(x: .value("Window ends", b.end), y: .value("Peak", b.peak), width: .fixed(range == .month ? 26 : (range == .week ? 12 : 22)))
                                    .foregroundStyle(b.peak >= Double(settings.criticalThreshold) ? Color.danger : (b.peak >= warn ? Color.orange : Color.brand)).cornerRadius(3)
                            }
                            RuleMark(y: .value("Limit", 100)).foregroundStyle(Color.danger.opacity(0.85)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        }
                        .chartXScale(domain: start...end)
                        .chartYScale(domain: 0...115)
                        .chartXAxis { xAxis() }
                        .chartYAxis { AxisMarks(values: [0, 50, 100]) { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Int.self) { Text("\(n)%") } } } }
                        .frame(height: 180)
                    }
                }
            }
            .padding(24)
        }
    }

    // MARK: helpers

    private var rangeDescription: String {
        switch range {
        case .day: return Clock.now.formatted(.dateTime.weekday(.wide).day().month(.wide))
        case .week: return "Last 7 days"
        case .month: return "Last 30 days"
        }
    }

    private func isCurrent(_ i: Int, _ n: Int) -> Bool {
        range == .day ? i == Calendar.current.component(.hour, from: Clock.now) : i == n - 1
    }

    private var emptyNote: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.line.uptrend.xyaxis").font(AppFont.title2).foregroundStyle(.secondary).accessibilityHidden(true)
            Text("Limit history is recorded while the app runs, so this fills in over time.").font(AppFont.callout).foregroundStyle(.secondary)
            if let first = store.samples.first {
                Text("Recording since \(first.t.formatted(date: .abbreviated, time: .shortened))").font(AppFont.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity).frame(height: 120)
    }

    @AxisContentBuilder
    private func xAxis() -> some AxisContent {
        switch range {
        case .day:
            AxisMarks(values: .stride(by: .hour, count: 6)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.hour()) }
        case .week:
            AxisMarks(values: .stride(by: .day)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.weekday(.abbreviated)) }
        case .month:
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.day().month(.abbreviated)) }
        }
    }

    private func chartCard<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppFont.headline)
                Text(subtitle).font(AppFont.caption).foregroundStyle(.secondary)
            }
            content()
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading).card()
        .accessibilityElement(children: .contain).accessibilityLabel("\(title) chart, \(subtitle)")
    }
}
