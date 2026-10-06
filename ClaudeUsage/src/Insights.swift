import SwiftUI
import Charts

private enum InsightRange: Int, CaseIterable, Identifiable {
    case week = 7, month = 30, quarter = 90, year = 365
    var id: Int { rawValue }
    var title: String { self == .week ? "7 days" : (self == .month ? "30 days" : (self == .quarter ? "90 days" : "Year")) }
}

private struct DayRow: Identifiable {
    let date: Date, rec: DayRecord
    var id: TimeInterval { date.timeIntervalSince1970 }
    var tokens: Int { rec.billable }
}

private enum DayClass { case heavy, normal, light, idle }

private struct Cell: Identifiable {
    let x: Int, row: Int, tokens: Int, level: Int, date: Date
    var id: String { "\(x)-\(row)" }
}

/// Long-term insights built from the permanently saved daily activity (Claude Code logs + what the app has recorded).
struct InsightsView: View {
    @ObservedObject var store: Store
    @StateObject private var rangeBox = Box(30)
    private var range: InsightRange { InsightRange(rawValue: rangeBox.value) ?? .month }

    private let cal = Calendar.current
    private func short(_ m: String) -> String { m.replacingOccurrences(of: "claude-", with: "") }

    // MARK: derived

    private func rows(_ n: Int) -> [DayRow] {
        let today = cal.startOfDay(for: Date()), days = store.snapshot.days
        return (0..<n).reversed().map { i in
            let d = cal.date(byAdding: .day, value: -i, to: today)!
            return DayRow(date: d, rec: days[dayKey(d)] ?? DayRecord())
        }
    }

    private func sessionPeaks(since: Date, weekly: Bool) -> [Double] {
        var best: [Int: Double] = [:]
        for s in store.samples where s.t >= since {
            guard let r = weekly ? s.weeklyReset : s.sessionReset else { continue }
            let k = Int(r.timeIntervalSince1970 / 600)
            best[k] = max(best[k] ?? 0, weekly ? s.weekly : s.session)
        }
        return Array(best.values)
    }

    var body: some View {
        let n = range.rawValue
        let data = rows(n)
        let active = data.filter { $0.tokens > 0 }
        let total = data.reduce(0) { $0 + $1.tokens }
        let cost = data.reduce(0.0) { $0 + $1.rec.cost }
        let prompts = data.reduce(0) { $0 + $1.rec.prompts }
        let responses = data.reduce(0) { $0 + $1.rec.responses }
        let tools = data.reduce(0) { $0 + $1.rec.toolCalls }
        let sessions = data.reduce(0) { $0 + $1.rec.sessions }
        let weeks = max(1, Double(n) / 7)
        let avgActive = active.isEmpty ? 0 : Double(total) / Double(active.count)
        let heavyCut = avgActive * 1.5, lightCut = avgActive * 0.5
        let cls: (DayRow) -> DayClass = { r in
            if r.tokens == 0 { return .idle }
            return Double(r.tokens) >= heavyCut ? .heavy : (Double(r.tokens) <= lightCut ? .light : .normal)
        }
        let heavy = active.filter { cls($0) == .heavy }.sorted { $0.tokens > $1.tokens }
        let light = active.filter { cls($0) == .light }.sorted { $0.tokens < $1.tokens }
        let start = data.first?.date ?? Date()
        let sPeaks = sessionPeaks(since: start, weekly: false), wPeaks = sessionPeaks(since: start, weekly: true)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Insights").font(.largeTitle.bold())
                        Text("Your habits, costs and trends – built from saved daily activity").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $rangeBox.value) { ForEach(InsightRange.allCases) { Text($0.title).tag($0.rawValue) } }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 300)
                }

                if total == 0 && prompts == 0 {
                    VStack(spacing: 8) {
                        Image(systemName: "lightbulb").font(.largeTitle).foregroundStyle(.secondary)
                        Text("No activity in this range yet").font(.headline)
                        Text("Use Claude Code and your insights will appear here.").foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(40).card()
                } else {
                    // Claude Code activity
                    section("Claude Code activity") {
                        HStack(spacing: 16) {
                            StatTile(title: "Messages sent", value: fmt(prompts), sub: "\(per(prompts, n)) per day")
                            StatTile(title: "Responses", value: fmt(responses), sub: "\(per(responses, n)) per day")
                            StatTile(title: "Tool calls", value: fmt(tools), sub: responses > 0 ? String(format: "%.1f per response", Double(tools) / Double(responses)) : "—")
                            StatTile(title: "Sessions", value: fmt(sessions), sub: "\(String(format: "%.1f", Double(sessions) / weeks)) per week")
                        }
                    }

                    // Cost
                    section("API-equivalent cost") {
                        HStack(spacing: 16) {
                            StatTile(title: "Total", value: money(cost), sub: "\(fmt(total)) tokens")
                            StatTile(title: "Per day", value: money(cost / Double(n)), sub: active.isEmpty ? "—" : "\(money(cost / Double(active.count))) per active day")
                            StatTile(title: "Per week", value: money(cost / weeks), sub: "average")
                            StatTile(title: "Per session", value: sessions > 0 ? money(cost / Double(sessions)) : "—", sub: "average")
                        }
                        Text("What this usage would cost at pay-as-you-go API prices (cache reads included). Your Claude plan isn’t billed this way – it’s a guide to the value you’re getting.")
                            .font(.caption).foregroundStyle(.secondary)
                        if !store.snapshot.unpricedModels.isEmpty {
                            Text("No price known for: \(store.snapshot.unpricedModels.sorted().joined(separator: ", ")) – excluded from cost.")
                                .font(.caption).foregroundStyle(Color.danger)
                        }
                    }

                    // Heavy / light days
                    section("Heavy and light days", subtitle: "Heavy: at least 1.5× your average active day. Light: half of it or less.") {
                        Chart(data) { r in
                            BarMark(x: .value("Day", r.date, unit: .day), y: .value("Tokens", r.tokens))
                                .foregroundStyle(color(cls(r)))
                            if avgActive > 0 {
                                RuleMark(y: .value("Average", avgActive)).foregroundStyle(Color.secondary.opacity(0.7)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                    .annotation(position: .top, alignment: .leading) { Text("avg active day \(fmt(Int(avgActive)))").font(.caption2).foregroundStyle(.secondary) }
                            }
                        }
                        .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let x = v.as(Int.self) { Text(fmt(x)) } } } }
                        .padding(.top, 14).frame(height: 220)
                        HStack(spacing: 18) {
                            legend(Color.brand, "Heavy · \(plural(heavy.count, "day"))")
                            legend(Color.brand.opacity(0.55), "Normal · \(plural(active.count - heavy.count - light.count, "day"))")
                            legend(Color.secondary.opacity(0.55), "Light · \(plural(light.count, "day"))")
                            legend(Color.secondary.opacity(0.2), "Idle · \(plural(n - active.count, "day"))")
                        }.font(.caption)
                    }

                    HStack(alignment: .top, spacing: 16) {
                        dayList("Heaviest days", Array(heavy.prefix(5)))
                        dayList("Lightest active days", Array(light.prefix(5)))
                    }

                    // Averages
                    section("Sessions and averages") {
                        HStack(spacing: 16) {
                            StatTile(title: "Sessions per day", value: String(format: "%.1f", Double(sessions) / Double(n)), sub: active.isEmpty ? "—" : String(format: "%.1f per active day", Double(sessions) / Double(active.count)))
                            StatTile(title: "Sessions per week", value: String(format: "%.1f", Double(sessions) / weeks), sub: "average")
                            StatTile(title: "Tokens per session", value: sessions > 0 ? fmt(total / sessions) : "—", sub: "average")
                            StatTile(title: "Tokens per week", value: fmt(Int(Double(total) / weeks)), sub: "\(fmt(total / n)) per day")
                        }
                        HStack(spacing: 16) {
                            StatTile(title: "Avg session peak", value: sPeaks.isEmpty ? "—" : "\(Int((sPeaks.reduce(0, +) / Double(sPeaks.count)).rounded()))%", sub: sPeaks.isEmpty ? "recorded as you use the app" : "of the 5-hour limit · \(sPeaks.count) session\(sPeaks.count == 1 ? "" : "s")")
                            StatTile(title: "Highest session", value: sPeaks.isEmpty ? "—" : "\(Int((sPeaks.max() ?? 0).rounded()))%", sub: "of the 5-hour limit")
                            StatTile(title: "Avg weekly peak", value: wPeaks.isEmpty ? "—" : "\(Int((wPeaks.reduce(0, +) / Double(wPeaks.count)).rounded()))%", sub: wPeaks.isEmpty ? "recorded as you use the app" : "of the weekly limit")
                            StatTile(title: "Active days", value: "\(active.count)", sub: "of \(n)")
                        }
                    }

                    // Models
                    modelSection(data, total: total)

                    // Projects
                    projectSection(data, total: total)
                }

                yearSection()
                recordingCard()
            }
            .padding(24)
        }
    }

    // MARK: sections

    private func modelSection(_ data: [DayRow], total: Int) -> some View {
        var tokens: [String: Int] = [:], costs: [String: Double] = [:]
        for r in data { for (m, t) in r.rec.models { tokens[m, default: 0] += t }; for (m, c) in r.rec.modelCost { costs[m, default: 0] += c } }
        let models = tokens.filter { $0.value > 0 }.sorted { $0.value > $1.value }
        return section("Model usage") {
            if models.isEmpty { Text("No model usage yet").foregroundStyle(.secondary) } else {
                Chart(models, id: \.key) { m in
                    BarMark(x: .value("Tokens", m.value), y: .value("Model", short(m.key)), height: .fixed(18)).foregroundStyle(Color.brand).cornerRadius(3)
                        .annotation(position: .top, alignment: .leading, spacing: 3) {
                            (Text(short(m.key)).foregroundColor(.secondary) + Text("  \(fmt(m.value))").fontWeight(.semibold)).font(.caption)
                        }
                }
                .chartXAxis(.hidden).chartYAxis(.hidden)
                .frame(height: max(100, CGFloat(models.count) * 46))
                Grid(alignment: .trailing, horizontalSpacing: 24, verticalSpacing: 8) {
                    GridRow {
                        Text("Model").gridColumnAlignment(.leading)
                        Text("Tokens"); Text("Share"); Text("API cost")
                    }.font(.subheadline).foregroundStyle(.secondary)
                    Divider()
                    ForEach(models, id: \.key) { m in
                        GridRow {
                            Text(short(m.key)).fontWeight(.medium).gridColumnAlignment(.leading)
                            Text(fmt(m.value))
                            Text(total > 0 ? String(format: "%.0f%%", Double(m.value) / Double(total) * 100) : "—")
                            Text(costs[m.key].map(money) ?? "—")
                        }.monospacedDigit()
                    }
                }
            }
        }
    }

    private func projectSection(_ data: [DayRow], total: Int) -> some View {
        var tokens: [String: Int] = [:]
        for r in data { for (p, t) in r.rec.projects { tokens[p, default: 0] += t } }
        let projects = Array(tokens.filter { $0.value > 0 }.sorted { $0.value > $1.value }.prefix(10))
        return section("Project usage", subtitle: "Tokens by Claude Code project folder") {
            if projects.isEmpty { Text("No project usage yet").foregroundStyle(.secondary) } else {
                Chart(projects, id: \.key) { p in
                    BarMark(x: .value("Tokens", p.value), y: .value("Project", p.key), height: .fixed(16)).foregroundStyle(Color.brand).cornerRadius(3)
                        .annotation(position: .top, alignment: .leading, spacing: 3) {
                            (Text(p.key).foregroundColor(.secondary) + Text("  \(fmt(p.value))" + (total > 0 ? String(format: " · %.0f%%", Double(p.value) / Double(total) * 100) : ""))
                                .fontWeight(.semibold)).font(.caption)
                        }
                }
                .chartXAxis(.hidden).chartYAxis(.hidden)
                .frame(height: max(100, CGFloat(projects.count) * 44))
            }
        }
    }

    private func yearSection() -> some View {
        let today = cal.startOfDay(for: Date()), days = store.snapshot.days
        let yearStart = cal.date(byAdding: .day, value: -364, to: today)!
        // Grid starts on the first day of the week containing yearStart, following the user's calendar.
        let offset = (cal.component(.weekday, from: yearStart) - cal.firstWeekday + 7) % 7
        let gridStart = cal.date(byAdding: .day, value: -offset, to: yearStart)!
        let all: [(Date, Int)] = (0...(364 + offset)).compactMap { i in
            let d = cal.date(byAdding: .day, value: i, to: gridStart)!
            return d > today ? nil : (d, days[dayKey(d)]?.billable ?? 0)
        }
        let nonzero = all.map(\.1).filter { $0 > 0 }.sorted()
        func q(_ f: Double) -> Int { nonzero.isEmpty ? 0 : nonzero[min(nonzero.count - 1, Int(Double(nonzero.count) * f))] }
        let q1 = q(0.25), q2 = q(0.5), q3 = q(0.75)
        var cells: [Cell] = [], monthMarks: [(Int, String)] = []
        let monthName = DateFormatter(); monthName.dateFormat = "MMM"
        for (i, item) in all.enumerated() {
            let (d, t) = item
            let x = i / 7, row = i % 7
            let level = t == 0 ? 0 : (t <= q1 ? 1 : (t <= q2 ? 2 : (t <= q3 ? 3 : 4)))
            cells.append(Cell(x: x, row: row, tokens: t, level: level, date: d))
            if cal.component(.day, from: d) <= 7, row == 0 || cal.component(.day, from: d) == 1, !monthMarks.contains(where: { $0.0 == x }),
               monthMarks.last.map({ x - $0.0 >= 3 }) ?? true { monthMarks.append((x, monthName.string(from: d))) }
        }
        let weeksCount = (cells.last?.x ?? 52) + 1
        // monthly totals for the last 12 months
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: today))!
        let months: [(Date, Int)] = (0..<12).reversed().map { i in
            let m = cal.date(byAdding: .month, value: -i, to: monthStart)!
            let next = cal.date(byAdding: .month, value: 1, to: m)!
            var sum = 0, d = m
            while d < next && d <= today { sum += days[dayKey(d)]?.billable ?? 0; d = cal.date(byAdding: .day, value: 1, to: d)! }
            return (m, sum)
        }
        let yearTotal = all.reduce(0) { $0 + $1.1 }
        let yearCost = all.reduce(0.0) { $0 + (days[dayKey($1.0)]?.cost ?? 0) }
        return section("Yearly usage", subtitle: "\(fmt(yearTotal)) tokens · \(money(yearCost)) API-equivalent over the last 12 months") {
            Chart(cells) { c in
                RectangleMark(xStart: .value("Week", Double(c.x) + 0.07), xEnd: .value("Week", Double(c.x) + 0.93),
                              yStart: .value("Day", Double(6 - c.row) + 0.07), yEnd: .value("Day", Double(6 - c.row) + 0.93))
                    .foregroundStyle(c.level == 0 ? Color.secondary.opacity(0.15) : Color.brand.opacity(0.22 + 0.2 * Double(c.level)))
                    .cornerRadius(2)
            }
            .chartXScale(domain: 0...Double(weeksCount))
            .chartYScale(domain: 0...7)
            .chartYAxis(.hidden)
            .chartXAxis { AxisMarks(values: monthMarks.map { Double($0.0) }) { v in
                AxisValueLabel { if let w = v.as(Double.self), let m = monthMarks.first(where: { Double($0.0) == w }) { Text(m.1) } } } }
            .frame(height: 150)
            HStack(spacing: 5) {
                Text("Less").font(.caption2).foregroundStyle(.secondary)
                ForEach(0..<5) { l in RoundedRectangle(cornerRadius: 2).fill(l == 0 ? Color.secondary.opacity(0.15) : Color.brand.opacity(0.22 + 0.2 * Double(l))).frame(width: 12, height: 12) }
                Text("More").font(.caption2).foregroundStyle(.secondary)
            }
            Divider().padding(.vertical, 4)
            Text("By month").font(.subheadline.weight(.semibold))
            Chart(Array(months.enumerated()), id: \.offset) { i, m in
                BarMark(x: .value("Month", m.0, unit: .month), y: .value("Tokens", m.1))
                    .foregroundStyle(i == months.count - 1 ? Color.brand : Color.brand.opacity(0.7)).cornerRadius(3)
            }
            .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
            .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let x = v.as(Int.self) { Text(fmt(x)) } } } }
            .frame(height: 170)
        }
    }

    private func recordingCard() -> some View {
        let stored = store.snapshot.days.count
        let since = ActivityStore.shared.recordingSince
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: "externaldrive.badge.checkmark").font(.title3).foregroundStyle(Color.brand)
            VStack(alignment: .leading, spacing: 4) {
                Text("Activity is saved on this Mac").font(.headline)
                Text((stored == 1 ? "1 day of activity is stored" : "\(stored) days of activity are stored") + (since.map { " · recording since \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "") +
                     ". They keep these insights and the yearly view going even after Claude Code clears its own logs, and your usual week is used to sharpen the weekly-limit forecast.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(18).card()
    }

    // MARK: pieces

    private func per(_ v: Int, _ n: Int) -> String { String(format: "%.1f", Double(v) / Double(max(1, n))) }

    private func color(_ c: DayClass) -> Color {
        switch c {
        case .heavy: return Color.brand
        case .normal: return Color.brand.opacity(0.55)
        case .light: return Color.secondary.opacity(0.55)
        case .idle: return Color.secondary.opacity(0.2)
        }
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 6) { RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 12, height: 12); Text(t).foregroundStyle(.secondary) }
    }

    private func dayList(_ title: String, _ rows: [DayRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            if rows.isEmpty { Text("None in this range").foregroundStyle(.secondary).font(.callout) }
            ForEach(rows) { r in
                HStack {
                    Text(r.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))).fontWeight(.medium)
                    Spacer()
                    Text(fmt(r.tokens)).monospacedDigit().foregroundStyle(Color.brand).fontWeight(.semibold)
                    Text(money(r.rec.cost)).monospacedDigit().foregroundStyle(.secondary).frame(width: 64, alignment: .trailing)
                }
                .font(.callout)
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .topLeading).card()
    }

    private func section<Content: View>(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let s = subtitle { Text(s).font(.caption).foregroundStyle(.secondary) }
            }
            content()
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading).card()
    }
}
