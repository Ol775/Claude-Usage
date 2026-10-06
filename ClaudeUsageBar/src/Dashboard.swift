import SwiftUI
import Charts
import ServiceManagement

// MARK: - State shared between the app delegate (AppKit) and the dashboard (SwiftUI)

struct Actions {
    var signIn: () -> Void = {}
    var signOut: () -> Void = {}
    var cancelSignIn: () -> Void = {}
    var choosePhoto: () -> Void = {}
    var removePhoto: () -> Void = {}
    var refresh: () -> Void = {}
    var testNotify: () -> Void = {}
    var openNotificationSettings: () -> Void = {}
}

enum DashTab: String, CaseIterable, Identifiable {
    case overview, usage, account, settings
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.50percent"
        case .usage: return "chart.bar.xaxis"
        case .account: return "person.crop.circle"
        case .settings: return "gearshape"
        }
    }
}

final class Store: ObservableObject {
    static let shared = Store()
    @Published var tab: DashTab = .overview
    @Published var snapshot = Snapshot()
    @Published var limits: [Limit] = []
    @Published var limitError: String?
    @Published var stale = false
    @Published var account = Account()
    @Published var samples: [Sample] = []
    @Published var loginBusy = false
    @Published var photo: NSImage? = avatarImage
    @Published var lastUpdated: Date?
    var actions = Actions()
}

/// Local UI state without @State (the SDK's @State macro needs a compiler plugin that command-line builds don't have).
final class Box<T>: ObservableObject {
    @Published var value: T
    init(_ v: T) { value = v }
}

extension Color {
    static var brand: Color { Color(nsColor: claudeOrange) }
    static var danger: Color { Color(nsColor: alertRed) }
}

extension View {
    func card() -> some View {
        background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
    }
}

// MARK: - Shell

struct DashboardView: View {
    @ObservedObject var store: Store
    @ObservedObject var settings = Settings.shared

    var body: some View {
        NavigationSplitView {
            List(DashTab.allCases, selection: Binding(get: { store.tab }, set: { if let v = $0 { store.tab = v } })) { tab in
                Label { Text(tab.title) } icon: { Image(systemName: tab.icon).foregroundStyle(Color.brand) }.tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 230)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude Usage Bar").font(.caption.weight(.semibold))
                    Text("\(AppInfo.display) · build \(AppInfo.build)").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
        } detail: {
            Group {
                switch store.tab {
                case .overview: OverviewView(store: store)
                case .usage: UsageView(store: store)
                case .account: AccountPage(store: store)
                case .settings: SettingsPage(store: store, settings: settings)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .tint(.brand)
        .frame(minWidth: 860, minHeight: 600)
    }
}

// MARK: - Overview

struct OverviewView: View {
    @ObservedObject var store: Store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.account.loggedIn ? "Hi, \(store.account.name.split(separator: " ").first.map(String.init) ?? "there")" : "Overview")
                            .font(.largeTitle.bold())
                        HStack(spacing: 6) {
                            if store.stale { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                            Text(store.stale ? "Couldn’t reach Anthropic – showing the last good reading"
                                 : (store.lastUpdated.map { "Updated \($0.formatted(date: .omitted, time: .shortened))" } ?? "Loading…"))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button { store.actions.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                }

                if store.limits.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.exclamationmark").font(.title2).foregroundStyle(.secondary)
                        Text(store.limitError ?? "Loading limits…")
                        Spacer()
                        if !store.account.loggedIn {
                            Button("Open Account") { store.tab = .account }.buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(18).card()
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(Array(store.limits.enumerated()).filter { $0.element.kind != .other }, id: \.offset) { _, l in
                            LimitCard(limit: l, samples: store.samples)
                        }
                    }
                    let extra = store.limits.filter { $0.kind == .other }
                    if !extra.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(extra.enumerated()), id: \.offset) { _, l in
                                HStack {
                                    Text(l.name).frame(width: 150, alignment: .leading)
                                    ProgressView(value: min(max(l.percent, 0), 100), total: 100).tint(.brand)
                                    Text("\(Int(l.percent.rounded()))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                                }
                            }
                        }
                        .padding(18).card()
                    }
                    ProjectionCard(store: store)
                }

                HStack(spacing: 16) {
                    StatTile(title: "Today", value: fmt(store.snapshot.today.billable), sub: "\(store.snapshot.messagesToday) responses")
                    StatTile(title: "Last 7 days", value: fmt(store.snapshot.week.billable), sub: "tokens")
                    StatTile(title: "This month", value: fmt(store.snapshot.month.billable), sub: "tokens")
                    StatTile(title: "Cache reads (7d)", value: fmt(store.snapshot.week.cacheRead), sub: "not counted above")
                }
            }
            .padding(24)
        }
    }
}

struct Ring: View {
    let percent: Double
    let color: Color
    var body: some View {
        ZStack {
            Circle().stroke(Color(nsColor: .quaternaryLabelColor), lineWidth: 11)
            if percent > 0 {
                Circle().trim(from: 0, to: CGFloat(min(max(percent, 0), 100) / 100))
                    .stroke(color, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 0) {
                Text("\(Int(percent.rounded()))%").font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                Text("used").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

struct LimitCard: View {
    let limit: Limit
    let samples: [Sample]

    var forecast: Forecast { Predictor.forecast(limit, samples: samples) }
    var hot: Bool {
        if limit.percent >= 95 { return true }
        if case .hits = forecast { return true }
        if case .reached = forecast { return true }
        return false
    }
    var icon: String {
        switch forecast {
        case .hits, .reached: return "exclamationmark.triangle.fill"
        case .safe: return "checkmark.circle.fill"
        case .none: return "clock"
        }
    }

    var body: some View {
        HStack(spacing: 18) {
            Ring(percent: limit.percent, color: limit.percent >= 95 ? .danger : .brand).frame(width: 104, height: 104)
            VStack(alignment: .leading, spacing: 6) {
                Text(limit.name).font(.headline)
                Text(untilText(limit.resets)).font(.subheadline).foregroundStyle(.secondary)
                Label(Predictor.describe(forecast), systemImage: icon)
                    .font(.callout).foregroundStyle(hot ? Color.danger : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18).frame(maxWidth: .infinity).card()
    }
}

struct StatTile: View {
    let title: String, value: String, sub: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(value).font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(Color.brand).monospacedDigit()
            Text(sub).font(.caption).foregroundStyle(.secondary)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
    }
}

// MARK: - Projection chart

struct Pt: Identifiable { let t: Date; let v: Double; var id: TimeInterval { t.timeIntervalSince1970 } }

struct ProjectionCard: View {
    @ObservedObject var store: Store
    @StateObject private var kindBox = Box(LimitKind.session)
    var kind: LimitKind { kindBox.value }

    var limit: Limit? { store.limits.first { $0.kind == kind } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Limit forecast").font(.headline)
                Spacer()
                Picker("", selection: $kindBox.value) {
                    Text("Session").tag(LimitKind.session)
                    Text("Weekly").tag(LimitKind.weekly)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 180)
            }
            if let l = limit, let resets = l.resets {
                let start = resets.addingTimeInterval(-l.window)
                let now = Date()
                let pts = points(l, resets: resets, now: now)
                let f = Predictor.forecast(l, samples: store.samples, now: now)
                let proj = projection(f, l: l, resets: resets, now: now)
                Chart {
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
                        .annotation(position: .top, alignment: .leading) { Text("Limit").font(.caption2).foregroundStyle(Color.danger) }
                    RuleMark(x: .value("Reset", resets)).foregroundStyle(Color.secondary.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                        .annotation(position: .top, alignment: .trailing) { Text("Resets").font(.caption2).foregroundStyle(.secondary) }
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
                Text(Predictor.describe(f)).font(.callout).foregroundStyle(.secondary)
                if store.samples.count < 3 {
                    Text("The line fills in as the app runs – predictions improve after a few minutes of data.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("No data for this limit yet.").foregroundStyle(.secondary).frame(height: 120)
            }
        }
        .padding(18).card()
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

                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Today by hour").font(.headline)
                        Chart(Array(s.hourly.enumerated()), id: \.offset) { h, v in
                            BarMark(x: .value("Hour", h), y: .value("Tokens", v))
                                .foregroundStyle(h == Calendar.current.component(.hour, from: Date()) ? Color.brand : Color.brand.opacity(0.7)).cornerRadius(2)
                        }
                        .chartXScale(domain: -1...24)
                        .chartXAxis { AxisMarks(values: [0, 6, 12, 18]) { v in AxisGridLine(); AxisValueLabel { if let h = v.as(Int.self) { Text(String(format: "%02d:00", h)) } } } }
                        .chartYAxis { axis() }
                        .frame(height: 180)
                    }
                    .padding(18).frame(maxWidth: .infinity).card()

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

// MARK: - Account

struct AvatarCircle: View {
    let account: Account
    let photo: NSImage?
    let size: CGFloat
    var body: some View {
        ZStack {
            if account.loggedIn, let p = photo {
                Image(nsImage: p).resizable().scaledToFill()
            } else if account.loggedIn {
                Circle().fill(LinearGradient(colors: [Color.brand.opacity(0.8), Color.brand], startPoint: .top, endPoint: .bottom))
                Text(account.initials).font(.system(size: size * 0.38, weight: .semibold)).foregroundColor(.white)
            } else {
                Circle().fill(Color.secondary.opacity(0.2))
                Text("?").font(.system(size: size * 0.38, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .overlay(Circle().stroke(Color(nsColor: .separatorColor), lineWidth: 1))
    }
}

struct AccountPage: View {
    @ObservedObject var store: Store
    var body: some View {
        let a = store.account
        VStack(spacing: 14) {
            Spacer()
            AvatarCircle(account: a, photo: store.photo, size: 110)
                .onTapGesture { if a.loggedIn { store.actions.choosePhoto() } }
            Text(a.loggedIn ? a.name : "Not signed in").font(.title.bold())
            if a.loggedIn {
                Text(a.email).foregroundStyle(.secondary)
                if !a.plan.isEmpty {
                    Text("Claude \(a.plan) plan").font(.caption.weight(.semibold)).foregroundStyle(Color.brand)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Color.brand.opacity(0.15)))
                }
                HStack {
                    Button(store.photo == nil ? "Choose photo…" : "Change photo…") { store.actions.choosePhoto() }
                    if store.photo != nil { Button("Remove photo") { store.actions.removePhoto() } }
                }.padding(.top, 6)
                Button { store.actions.signOut() } label: { Text("Sign out").foregroundStyle(Color.danger) }
            } else {
                Text("Connect your Claude account to see your session and weekly limits, when they reset, and get alerts before you hit them.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 380)
                if store.loginBusy {
                    ProgressView().controlSize(.small)
                    Text("Finish signing in in your browser window").font(.callout).foregroundStyle(.secondary)
                    Button("Cancel") { store.actions.cancelSignIn() }
                } else {
                    Button { store.actions.signIn() } label: { Text("Sign in with Claude").frame(width: 200) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                }
            }
            Text("Sign-in uses Claude’s official login (through Claude Code). Your photo stays on this Mac.")
                .font(.caption).foregroundStyle(.secondary).padding(.top, 10)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}

// MARK: - Settings

struct SettingsPage: View {
    @ObservedObject var store: Store
    @ObservedObject var settings: Settings
    @StateObject private var loginBox = Box(SMAppService.mainApp.status == .enabled)

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Mode", selection: $settings.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Colour theme")
                    HStack(spacing: 14) {
                        ForEach(AccentTheme.allCases) { t in
                            Button { settings.theme = t } label: {
                                VStack(spacing: 5) {
                                    Circle().fill(Color(nsColor: NSColor(name: nil) { a in a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? t.colors.0 : t.colors.1 }))
                                        .frame(width: 30, height: 30)
                                        .overlay(Circle().stroke(Color.primary.opacity(settings.theme == t ? 0.9 : 0), lineWidth: 2).padding(-4))
                                    Text(t.label).font(.caption2).foregroundStyle(settings.theme == t ? .primary : .secondary)
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            Section("General") {
                Toggle("Show in Dock", isOn: $settings.showInDock)
                Toggle("Launch at login", isOn: Binding(
                    get: { loginBox.value },
                    set: { on in
                        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                        catch { NSSound.beep() }
                        loginBox.value = SMAppService.mainApp.status == .enabled
                    }))
            }
            Section("Notifications") {
                Toggle("Alert at 80%, 95% and 100% of a limit", isOn: $settings.notificationsOn)
                Toggle("Warn when on pace to hit a limit early", isOn: $settings.predictiveAlerts)
                HStack {
                    Button("Send test notification") { store.actions.testNotify() }
                    Button("Open notification settings") { store.actions.openNotificationSettings() }
                }
            }
            Section("About") {
                LabeledContent("Version", value: "\(AppInfo.version) \(AppInfo.stage)")
                LabeledContent("Build", value: AppInfo.build)
                Text("Early alpha – expect rough edges. Limit numbers come from the same source as Claude Code’s /usage.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
