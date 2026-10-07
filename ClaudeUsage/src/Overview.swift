import SwiftUI
import Charts
import ServiceManagement

// MARK: - Overview

struct OverviewView: View {
    @ObservedObject var store: Store
    @ObservedObject var settings = Settings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.account.loggedIn ? "Hi, \(store.account.name.split(separator: " ").first.map(String.init) ?? "there")" : "Overview")
                            .font(.largeTitle.bold())
                        HStack(spacing: 6) {
                            if store.stale { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                            Text(store.stale ? (store.staleReason ?? "Couldn’t reach Anthropic – showing the last reading")
                                 : (store.lastUpdated.map { "Updated \($0.formatted(date: .omitted, time: .shortened))" } ?? "Loading…"))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button { store.actions.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }.keyboardShortcut("r", modifiers: .command).help("Refresh (⌘R)")
                }

                if store.limits.isEmpty {
                    if store.account.loggedIn {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.circle").font(.title2).foregroundStyle(.secondary)
                            Text(store.limitError ?? "Loading limits…")
                            Spacer()
                        }
                        .padding(18).card()
                    } else {
                        OnboardingCard(store: store)
                    }
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(Array(store.limits.enumerated()).filter { $0.element.kind != .other }, id: \.offset) { _, l in
                            LimitCard(limit: l, samples: store.samples, activity: store.snapshot.days)
                        }
                    }
                    let extra = store.limits.filter { $0.kind == .other }
                    if !extra.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(extra.enumerated()), id: \.offset) { _, l in
                                HStack {
                                    Text(l.name).frame(width: 150, alignment: .leading)
                                    GeometryReader { g in      // drawn by hand: the system progress bar ignores our dynamic colour in dark mode and turns blue
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(Color.primary.opacity(0.12))
                                            Capsule().fill(Color.brand).frame(width: g.size.width * CGFloat(min(max(l.percent, 0), 100) / 100))
                                        }
                                    }.frame(height: 6)
                                    Text("\(Int(l.percent.rounded()))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                                }
                            }
                        }
                        .padding(18).card()
                    }
                }

                if settings.chatgptEnabled && !store.chatgpt.isFree { ChatGPTSection(store: store) }      // a free plan is unsupported: only Settings → Account mentions it
                if !store.limits.isEmpty { ProjectionCard(store: store) }

                HStack(spacing: 16) {
                    StatTile(title: "Today", value: fmt(store.snapshot.today.billable), sub: plural(store.snapshot.messagesToday, "response"))
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

/// ChatGPT limits (through Codex's sign-in): same look as the Claude cards, without a forecast.
struct ChatGPTSection: View {
    @ObservedObject var store: Store
    var body: some View {
        let g = store.chatgpt
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("ChatGPT").font(.title3.bold())
                Text("EXPERIMENTAL").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.orange)
                    .padding(.horizontal, 7).padding(.vertical, 3).background(Capsule().fill(Color.orange.opacity(0.18)))
                    .help("ChatGPT usage is experimental: the paid-plan limits have only been verified with sample data.")
                Text("Codex limits").font(.caption).foregroundStyle(.secondary)
                if !g.plan.isEmpty {
                    Text("\(g.plan.uppercased()) PLAN").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.brand)
                        .padding(.horizontal, 7).padding(.vertical, 3).background(Capsule().fill(Color.brand.opacity(0.18)))
                }
                Spacer()
            }
            if g.limits.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: g.isFree ? "lock.fill" : "bubble.left.and.bubble.right").font(.title2).foregroundStyle(.secondary)
                    Text(store.chatgptBusy ? "Waiting for your browser…" : (g.error ?? "Loading ChatGPT limits…")).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if !g.signedIn && !store.chatgptBusy { Button("Connect") { store.actions.connectChatGPT() }.buttonStyle(.borderedProminent) }
                }
                .padding(18).card()
            } else {
                let rows = stride(from: 0, to: g.limits.count, by: 2).map { Array(g.limits[$0..<min($0 + 2, g.limits.count)]) }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, l in PlainLimitCard(limit: l) }
                        if row.count == 1 { Color.clear.frame(maxWidth: .infinity) }
                    }
                }
                if let e = g.error { Text(e).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}

struct PlainLimitCard: View {
    let limit: Limit
    var body: some View {
        HStack(spacing: 18) {
            Ring(percent: limit.percent, color: limit.percent >= 95 ? .danger : .brand).frame(width: 104, height: 104)
            VStack(alignment: .leading, spacing: 6) {
                Text(limit.name).font(.headline)
                Text(untilText(limit.resets)).font(.subheadline).foregroundStyle(.secondary)
                Label(limit.percent >= 95 ? "Almost at the limit" : "\(Int((100 - limit.percent).rounded()))% left", systemImage: limit.percent >= 95 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.callout).foregroundStyle(limit.percent >= 95 ? Color.danger : Color.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(18).frame(maxWidth: .infinity).card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(limit.name), \(Int(limit.percent.rounded())) percent used")
        .accessibilityValue("\(untilText(limit.resets)). \(limit.percent >= 95 ? "Almost at the limit" : "\(Int((100 - limit.percent).rounded())) percent left")")
    }
}

struct LimitCard: View {
    let limit: Limit
    let samples: [Sample]
    var activity: [String: DayRecord] = [:]

    var forecast: Forecast { Predictor.forecast(limit, samples: samples, activity: activity) }
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(limit.name), \(Int(limit.percent.rounded())) percent used")
        .accessibilityValue("\(untilText(limit.resets)). \(Predictor.describe(forecast))")
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
        .accessibilityElement(children: .combine)
    }
}

/// First-run help for someone who hasn't set Claude Code up yet: what's needed, what's done, and the next click.
struct OnboardingCard: View {
    @ObservedObject var store: Store
    private var hasClaude: Bool { claudeBinary() != nil }

    private func step(_ done: Bool, _ title: String, _ detail: String, @ViewBuilder action: () -> some View = { EmptyView() }) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(done ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            action()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome to Claude Usage").font(.title2.bold())
                Text(store.limitError == nil || store.limitError == "Sign in to see your limits"
                     ? "Two quick steps and your limits appear here and in the menu bar."
                     : (store.limitError ?? ""))
                    .foregroundStyle(.secondary)
            }
            step(hasClaude, "1. Get Claude Code", "Claude Usage reads the same login and logs as Claude Code, so it needs to be installed on this Mac.") {
                if !hasClaude {
                    Button("Get Claude Code") { if let u = URL(string: "https://claude.com/claude-code") { NSWorkspace.shared.open(u) } }
                }
            }
            step(store.account.loggedIn, "2. Sign in", "Uses Claude’s official sign-in in your browser. Claude Usage never sees your password.") {
                if store.loginBusy { ProgressView().controlSize(.small) }
                else { Button("Sign In") { store.actions.signIn() }.buttonStyle(.borderedProminent).disabled(!hasClaude) }
            }
            Text("Optional and experimental: add ChatGPT (Codex) usage later in Settings → Account. Everything stays on your Mac.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(20).card()
    }
}
