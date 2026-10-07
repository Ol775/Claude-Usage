import SwiftUI
import Charts
import ServiceManagement

// MARK: - Usage

struct UsageView: View {
    @ObservedObject var store: Store
    @StateObject private var daysBox = Box(30)
    @StateObject private var rangeBox = Box(0)
    private var days: Int { daysBox.value }
    private var modelRange: Int { rangeBox.value }

    private func short(_ m: String) -> String { m.replacingOccurrences(of: "claude-", with: "") }
    private func axis() -> some AxisContent {
        AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Int.self) { Text(fmt(n)) } } }
    }

    var body: some View {
        let s = store.snapshot
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Usage").font(.largeTitle.bold())

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Daily tokens").font(.headline); Spacer()
                        Picker("", selection: $daysBox.value) { Text("14 days").tag(14); Text("30 days").tag(30) }
                            .pickerStyle(.segmented).labelsHidden().frame(width: 170)
                    }
                    let n = min(days, s.daily.count)
                    let data = Array(zip(s.dailyDates.suffix(n), s.daily.suffix(n)))
                    Chart(Array(data.enumerated()), id: \.offset) { i, d in
                        BarMark(x: .value("Day", d.0, unit: .day), y: .value("Tokens", d.1))
                            .foregroundStyle(i == data.count - 1 ? Color.brand : Color.brand.opacity(0.7)).cornerRadius(3)
                    }
                    .chartYAxis { axis() }
                    .frame(height: 220)
                    Text("Input + output + cache-write tokens from Claude Code on this Mac.").font(.caption).foregroundStyle(.secondary)
                }
                .padding(18).card()
        .accessibilityElement(children: .contain).accessibilityLabel("Daily tokens chart")

                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Today by hour").font(.headline)
                        Chart(Array(s.hourly.enumerated()), id: \.offset) { h, v in
                            BarMark(x: .value("Hour", h), y: .value("Tokens", v))
                                .foregroundStyle(h == Calendar.current.component(.hour, from: Clock.now) ? Color.brand : Color.brand.opacity(0.7)).cornerRadius(2)
                        }
                        .chartXScale(domain: -1...24)
                        .chartXAxis { AxisMarks(values: [0, 6, 12, 18]) { v in AxisGridLine(); AxisValueLabel { if let h = v.as(Int.self) { Text(String(format: "%02d:00", h)) } } } }
                        .chartYAxis { axis() }
                        .frame(height: 180)
                    }
                    .padding(18).frame(maxWidth: .infinity).card()
        .accessibilityElement(children: .contain).accessibilityLabel("Today by hour chart")

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("By model").font(.headline); Spacer()
                            Picker("", selection: $rangeBox.value) { Text("Today").tag(0); Text("7 days").tag(1) }
                                .pickerStyle(.segmented).labelsHidden().frame(width: 130)
                        }
                        let models = (modelRange == 0 ? s.byModelToday : s.byModelWeek).map { ($0.key, $0.value.billable) }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
                        if models.isEmpty {
                            Text("No usage yet").foregroundStyle(.secondary).frame(height: 180)
                        } else {
                            Chart(models, id: \.0) { m in
                                BarMark(x: .value("Tokens", m.1), y: .value("Model", short(m.0)), height: .fixed(18)).foregroundStyle(Color.brand).cornerRadius(3)
                                    .annotation(position: .top, alignment: .leading, spacing: 3) {
                                        (Text(short(m.0)).foregroundColor(.secondary) + Text("  \(fmt(m.1))").fontWeight(.semibold)).font(.caption)
                                    }
                            }
                            .chartXAxis(.hidden)
                            .chartYAxis(.hidden)
                            .frame(height: max(120, CGFloat(models.count) * 48))
                        }
                    }
                    .padding(18).frame(maxWidth: .infinity).card()
        .accessibilityElement(children: .contain).accessibilityLabel("Tokens by model chart")
                }

                let projects = s.byProjectWeek.map { ($0.key, $0.value.billable) }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.prefix(8)
                VStack(alignment: .leading, spacing: 12) {
                    Text("By project (7 days)").font(.headline)
                    if projects.isEmpty {
                        Text("No usage yet").foregroundStyle(.secondary).frame(height: 80)
                    } else {
                        Chart(Array(projects), id: \.0) { m in
                            BarMark(x: .value("Tokens", m.1), y: .value("Project", m.0), height: .fixed(16)).foregroundStyle(Color.brand).cornerRadius(3)
                                .annotation(position: .top, alignment: .leading, spacing: 3) {
                                    (Text(m.0).foregroundColor(.secondary) + Text("  \(fmt(m.1))").fontWeight(.semibold)).font(.caption)
                                }
                        }
                        .chartXAxis(.hidden).chartYAxis(.hidden)
                        .frame(height: max(100, CGFloat(projects.count) * 44))
                    }
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading).card()
        .accessibilityElement(children: .contain).accessibilityLabel("Tokens by project chart")

                let busyHour = s.hourOfDay30.enumerated().max { $0.element < $1.element }
                let busyDay = s.weekday30.enumerated().max { $0.element < $1.element }
                let active = s.daily.filter { $0 > 0 }.count
                HStack(spacing: 16) {
                    StatTile(title: "Busiest hour", value: (busyHour?.element ?? 0) > 0 ? String(format: "%02d:00", busyHour!.offset) : "—", sub: "over the last 30 days")
                    StatTile(title: "Busiest day", value: (busyDay?.element ?? 0) > 0 ? Calendar.current.weekdaySymbols[busyDay!.offset] : "—", sub: "over the last 30 days")
                    StatTile(title: "Active days", value: "\(active)", sub: "of the last 30")
                    StatTile(title: "Avg active day", value: active > 0 ? fmt(s.daily.reduce(0, +) / active) : "—", sub: "tokens")
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Token breakdown").font(.headline)
                    Grid(alignment: .trailing, horizontalSpacing: 24, verticalSpacing: 10) {
                        GridRow {
                            Text("").gridColumnAlignment(.leading)
                            ForEach(["Input", "Output", "Cache write", "Cache read"], id: \.self) { Text($0).foregroundStyle(.secondary).font(.subheadline) }
                        }
                        Divider()
                        ForEach([("Today", s.today), ("Last 7 days", s.week), ("This month", s.month)], id: \.0) { row in
                            GridRow {
                                Text(row.0).fontWeight(.medium).gridColumnAlignment(.leading)
                                Text(fmt(row.1.input)); Text(fmt(row.1.output)); Text(fmt(row.1.cacheWrite)); Text(fmt(row.1.cacheRead))
                            }.monospacedDigit()
                        }
                    }
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading).card()
            }
            .padding(24)
        }
    }
}
