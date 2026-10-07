import SwiftUI
import Charts
import ServiceManagement

// MARK: - Projection chart

struct Pt: Identifiable { let t: Date; let v: Double; var id: TimeInterval { t.timeIntervalSince1970 } }

/// A small coloured dot followed by the text, for chart legends.
struct LegendLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) { configuration.icon.font(AppFont.system(size: 7)); configuration.title.foregroundStyle(.secondary) }
    }
}


struct ProjectionCard: View {
    @ObservedObject var store: Store
    @StateObject private var kindBox = Box(LimitKind.session)
    var kind: LimitKind { kindBox.value }

    var limit: Limit? { store.limits.first { $0.kind == kind } }

    // ChatGPT on the same chart: its 5-hour window goes on the Session view, its weekly window on the Weekly view.
    var gptLimit: Limit? {
        guard Settings.shared.chatgptEnabled else { return nil }
        return store.chatgpt.limits.first { $0.name.hasPrefix("ChatGPT ") && (kind == .session ? ChatGPT.isSession($0.seconds) : ChatGPT.isWeekly($0.seconds)) }
    }
    private func gptWindow(_ s: GPTSample) -> GPTWin? { s.w.first { kind == .session ? ChatGPT.isSession($0.seconds) : ChatGPT.isWeekly($0.seconds) } }
    /// One line per ChatGPT window, so the line doesn't join across a reset.
    private func gptSeries(from start: Date, now: Date) -> [(id: String, pts: [Pt])] {
        var groups: [Int: [Pt]] = [:]
        for s in store.gptSamples where s.t >= start && s.t <= now {
            guard let w = gptWindow(s), let r = w.reset else { continue }
            groups[Int(r.timeIntervalSince1970 / 600), default: []].append(Pt(t: s.t, v: w.percent))
        }
        return groups.keys.sorted().map { (id: "gpt\($0)", pts: groups[$0]!) }
    }
    private func gptForecast(_ l: Limit, now: Date) -> Forecast {
        // reuse the Claude predictor on ChatGPT's own readings (no token history to blend in, so it uses the window average / recent pace)
        let pseudo = Limit(name: kind == .session ? "Current session" : "Weekly – all models", percent: l.percent, resets: l.resets)
        let samples = store.gptSamples.compactMap { s -> Sample? in
            guard let w = gptWindow(s) else { return nil }
            return Sample(t: s.t, session: kind == .session ? w.percent : 0, sessionReset: kind == .session ? w.reset : nil,
                          weekly: kind == .weekly ? w.percent : 0, weeklyReset: kind == .weekly ? w.reset : nil)
        }
        return Predictor.forecast(pseudo, samples: samples, activity: [:], now: now)
    }
    /// The dashed projection, cut off at the chart's right edge.
    private func gptProjection(_ f: Forecast, l: Limit, now: Date, chartEnd: Date) -> (Date, Double)? {
        guard let own = l.resets else { return nil }
        var end = own, v = l.percent
        switch f {
        case .hits(let at, _, _): end = at; v = 100
        case .safe(let p, let rate): guard rate > 0 else { return nil }; v = min(p, 115)
        default: return nil
        }
        if end > chartEnd {
            let frac = chartEnd.timeIntervalSince(now) / max(end.timeIntervalSince(now), 1)
            v = l.percent + (v - l.percent) * frac; end = chartEnd
        }
        return end > now ? (end, v) : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Limit forecast").font(AppFont.headline)
                Spacer()
                Picker("", selection: $kindBox.value) {
                    Text("Session").tag(LimitKind.session)
                    Text("Weekly").tag(LimitKind.weekly)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 180)
            }
            if let l = limit, let resets = l.resets {
                let start = resets.addingTimeInterval(-l.window)
                let now = Clock.now
                let pts = points(l, resets: resets, now: now)
                let f = Predictor.forecast(l, samples: store.samples, activity: store.snapshot.days, now: now)
                let proj = projection(f, l: l, resets: resets, now: now)
                let gl = gptLimit
                let gSeries = gl == nil ? [] : gptSeries(from: start, now: now)
                let gf = gl.map { gptForecast($0, now: now) }
                let gproj = gl.flatMap { g in gf.flatMap { gptProjection($0, l: g, now: now, chartEnd: resets) } }
                if gl != nil {
                    HStack(spacing: 14) {
                        Label("Claude", systemImage: "circle.fill").foregroundStyle(Color.brand)
                        Label("ChatGPT", systemImage: "circle.fill").foregroundStyle(Color.gpt)
                    }.labelStyle(LegendLabel()).font(AppFont.caption)
                }
                Chart {
                    ForEach(gSeries, id: \.id) { s in
                        ForEach(s.pts) { p in
                            LineMark(x: .value("Time", p.t), y: .value("Used", p.v), series: .value("S", s.id))
                                .foregroundStyle(Color.gpt).lineStyle(StrokeStyle(lineWidth: 2.2))
                        }
                    }
                    if let g = gl, let (gend, gv) = gproj {
                        LineMark(x: .value("Time", now), y: .value("Used", g.percent), series: .value("S", "gptproj"))
                            .foregroundStyle(Color.gpt).lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                        LineMark(x: .value("Time", gend), y: .value("Used", gv), series: .value("S", "gptproj"))
                            .foregroundStyle(Color.gpt).lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    }
                    if let g = gl, g.resets.map({ $0 > start && $0 <= resets }) == true {
                        PointMark(x: .value("Time", now), y: .value("Used", g.percent)).foregroundStyle(Color.gpt).symbolSize(60)
                    }
                    ForEach(pts) { p in
                        AreaMark(x: .value("Time", p.t), y: .value("Used", p.v))
                            .foregroundStyle(LinearGradient(colors: [Color.brand.opacity(0.35), Color.brand.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Time", p.t), y: .value("Used", p.v), series: .value("S", "actual"))
                            .foregroundStyle(Color.brand).lineStyle(StrokeStyle(lineWidth: 2.5))
                    }
                    if let (end, v) = proj {
                        LineMark(x: .value("Time", now), y: .value("Used", l.percent), series: .value("S", "proj"))
                            .foregroundStyle(Color.brand).lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                        LineMark(x: .value("Time", end), y: .value("Used", v), series: .value("S", "proj"))
                            .foregroundStyle(Color.brand).lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                        PointMark(x: .value("Time", end), y: .value("Used", v)).foregroundStyle(v >= 100 ? Color.danger : Color.brand)
                    }
                    RuleMark(y: .value("Limit", 100)).foregroundStyle(Color.danger.opacity(0.8)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, alignment: .leading) { Text("Limit").font(AppFont.caption2).foregroundStyle(Color.danger) }
                    RuleMark(x: .value("Reset", resets)).foregroundStyle(Color.secondary.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                        .annotation(position: .top, alignment: .trailing) { Text("Resets").font(AppFont.caption2).foregroundStyle(.secondary) }
                    PointMark(x: .value("Time", now), y: .value("Used", l.percent)).foregroundStyle(Color.brand).symbolSize(70)
                }
                .chartXScale(domain: start...resets)
                .chartYScale(domain: 0...115)
                .chartYAxis {
                    AxisMarks(values: [0, 25, 50, 75, 100]) { v in
                        AxisGridLine(); AxisValueLabel { if let n = v.as(Int.self) { Text("\(n)%") } }
                    }
                }
                .padding(.top, 16)
                .frame(height: 246)
                Text(gl == nil ? Predictor.describe(f) : "Claude: " + Predictor.describe(f)).font(AppFont.callout).foregroundStyle(.secondary)
                if let g = gl, let gf = gf { Text("ChatGPT: " + Predictor.describe(gf)).font(AppFont.callout).foregroundStyle(Color.gpt).help(g.name) }
                if store.samples.count < 3 {
                    Text("The line fills in as the app runs – predictions improve after a few minutes of data.")
                        .font(AppFont.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("No data for this limit yet.").foregroundStyle(.secondary).frame(height: 120)
            }
        }
        .padding(18).card()
        .accessibilityElement(children: .contain).accessibilityLabel("Limit forecast chart")
    }

    private func points(_ l: Limit, resets: Date, now: Date) -> [Pt] {
        let start = resets.addingTimeInterval(-l.window)
        var out: [Pt] = [Pt(t: start, v: 0)]
        for s in store.samples {
            let r = l.kind == .session ? s.sessionReset : s.weeklyReset
            guard let rr = r, abs(rr.timeIntervalSince(resets)) < 300, s.t >= start else { continue }
            out.append(Pt(t: s.t, v: l.kind == .session ? s.session : s.weekly))
        }
        if let last = out.last, now.timeIntervalSince(last.t) > 30 { out.append(Pt(t: now, v: l.percent)) }
        return out
    }

    private func projection(_ f: Forecast, l: Limit, resets: Date, now: Date) -> (Date, Double)? {
        switch f {
        case .hits(let at, _, _): return (at, 100)
        case .safe(let p, let rate): return rate > 0 ? (resets, min(p, 115)) : nil
        default: return nil
        }
    }
}
